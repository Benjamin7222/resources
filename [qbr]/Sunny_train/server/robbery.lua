-- ============================================================================
--  Sunny_train - Braquages (serveur)
--
--  - Publie la liste des convois braquables (GlobalState) : les clients ne
--    scannent que ces trains-là, à faible fréquence.
--  - Valide la tentative (distance, arme, vitesse, police, cooldowns, jobs).
--  - Immobilise le run, alerte le dispatch, surveille le braqueur, distribue
--    le butin côté serveur uniquement.
-- ============================================================================

local Robbery = {
    active = {},          -- [runId] = { robber, runId, origin, endsAt, prevState }
    trainCooldowns = {},  -- [trainKey] = os.time()
    lastGlobal = 0,
}
Sunny.Robbery = Robbery

local L = Sunny.L
local Srv, Security, Bridge, Utils = Sunny.Srv, Sunny.Security, Sunny.Bridge, Sunny.Utils
local cfg = Config.Robbery

--- Met à jour la liste publique des convois braquables.
function Robbery.Refresh()
    local list = {}
    if cfg.enabled then
        for id, run in pairs(Sunny.Runs.byId) do
            if run.netId and Sunny.Runs.IsRobbable(run) and not Robbery.active[id]
                and (run.state == 'ready' or run.state == 'enroute' or run.state == 'at_station') then
                list[#list + 1] = { runId = id, netId = run.netId, driver = run.src }
            end
        end
    end
    GlobalState.sunnyTrainRobbable = list
end

local function finish(entry, success)
    Robbery.active[entry.runId] = nil
    local run = Sunny.Runs.GetById(entry.runId)
    local robber = entry.robber

    if success then
        local mission = run and run.mission and Config.Missions[run.mission]
        local mult = mission and mission.robberyLoot or 1.0
        local cash = math.floor(math.random(cfg.loot.cash.min, cfg.loot.cash.max) * mult)
        if cash > 0 then Bridge.AddMoney(robber, cfg.loot.account, cash, 'sunny_train_robbery') end
        for _, it in ipairs(cfg.loot.items or {}) do
            if math.random(100) <= (it.chance or 100) then
                Bridge.AddItem(robber, it.name, math.random(it.min or 1, it.max or 1))
            end
        end
        -- Part de la cargaison du convoi (prélevée du wagon au départ).
        local share = cfg.cargoShare or 0
        if run and share > 0 then
            for _, c in ipairs(run.cargo or {}) do
                local n = math.floor(c.amount * share)
                if n > 0 then Bridge.AddItem(robber, c.item, n) end
            end
        end
        Srv.Notify(robber, L('rob_success', Utils.Money(cash)), 'success')
        if type(Config.Hooks.onRobbery) == 'function' and run then
            pcall(Config.Hooks.onRobbery, robber, Sunny.Runs.Summary(run.src), cash)
        end

        if run then
            run.robbed = true
            Sunny.Fleet.Wear(run.train, cfg.conditionDamage)
            if cfg.runOutcome == 'fail' then
                Sunny.Runs.Close(run, 'failed', L('run_failed', L('rob_run_failed')), Config.MissionSettings.robbedFailDelete)
            else
                run.state = entry.prevState
                TriggerClientEvent('sunny_train:client:robberyEnded', run.src, { success = true, message = L('rob_run_continues') })
            end
        end
    else
        if robber and GetPlayerName(robber) then Srv.Notify(robber, L('rob_aborted'), 'error') end
        if run then
            run.state = entry.prevState
            TriggerClientEvent('sunny_train:client:robberyEnded', run.src, { success = false, message = L('rob_aborted_driver') })
        end
    end
    TriggerClientEvent('sunny_train:client:robberyState', -1, entry.runId, nil)
    Robbery.Refresh()
end

--- Surveillance des braquages en cours (thread actif seulement si besoin).
local watching = false
local function watch()
    if watching then return end
    watching = true
    CreateThread(function()
        while next(Robbery.active) do
            local now = os.time()
            for _, entry in pairs(Robbery.active) do
                local ped = GetPlayerPed(entry.robber)
                if not ped or ped == 0 or GetEntityHealth(ped) <= 0 then
                    finish(entry, false)
                elseif #(GetEntityCoords(ped) - entry.origin) > cfg.cancelRadius then
                    finish(entry, false)
                elseif now >= entry.endsAt then
                    finish(entry, true)
                end
            end
            Wait(1000)
        end
        watching = false
    end)
end

local function policeCount()
    return #Bridge.GetPlayersWithJobs(cfg.policeJobs, true)
end

Srv.Register('robbery:start', function(src, payload)
    if not cfg.enabled then return Srv.Fail('rob_not_allowed') end
    local run = Sunny.Runs.GetById(tonumber(payload.runId) or -1)
    if not run or not run.netId or not Sunny.Runs.IsRobbable(run) or Robbery.active[run.id] then
        return Srv.Fail('rob_not_allowed')
    end
    if run.state ~= 'ready' and run.state ~= 'enroute' and run.state ~= 'at_station' then
        return Srv.Fail('rob_not_allowed')
    end
    if run.src == src then return Srv.Fail('rob_not_allowed') end

    local job = Bridge.GetJob(src)
    if job and (cfg.blacklistedJobs[job] or cfg.blacklistedJobs[job:lower()]) then return Srv.Fail('rob_not_allowed') end

    -- Distance au train (entité si résolue, sinon au conducteur).
    local robberPos = Security.PedCoords(src)
    local entity = Security.EntityFromNet(run.netId)
    local trainPos = entity ~= 0 and GetEntityCoords(entity) or Security.PedCoords(run.src)
    if not robberPos or not trainPos or #(robberPos - trainPos) > cfg.interactDistance + 25.0 then
        Security.Flag(src, 'too_far', 'robbery')
        return Srv.Fail('rob_not_allowed')
    end
    if entity ~= 0 and #(GetEntityVelocity(entity)) > cfg.maxTrainSpeed + 1.0 then
        return Srv.Fail('rob_too_fast')
    end
    if cfg.requireWeapon then
        local ped = GetPlayerPed(src)
        -- 0 = information non synchronisée : on s'en remet alors au contrôle client.
        if GetSelectedPedWeapon(ped) == GetHashKey('WEAPON_UNARMED') then return Srv.Fail('rob_need_weapon') end
    end

    local now = os.time()
    if now - Robbery.lastGlobal < cfg.globalCooldown or now < (Robbery.trainCooldowns[run.train] or 0) then
        return Srv.Fail('rob_cooldown')
    end
    if policeCount() < cfg.minPolice then return Srv.Fail('rob_min_police') end

    Robbery.lastGlobal = now
    Robbery.trainCooldowns[run.train] = now + cfg.trainCooldown
    local entry = {
        runId = run.id, robber = src, origin = robberPos,
        endsAt = now + cfg.duration, prevState = run.state,
    }
    Robbery.active[run.id] = entry
    run.state = 'robbery'
    Robbery.Refresh()
    watch()

    TriggerClientEvent('sunny_train:client:robberyStarted', run.src, { message = L('rob_started_driver'), duration = cfg.duration })
    TriggerClientEvent('sunny_train:client:robberyState', -1, run.id, { endsIn = cfg.duration })

    local nearest, nearestDist = nil, math.huge
    for _, st in pairs(Config.Stations) do
        local d = #(trainPos - st.coords)
        if d < nearestDist then nearest, nearestDist = st, d end
    end
    local trainLabel = Config.Trains[run.train].label
    Sunny.Dispatch.Send({
        title = L('dispatch_title'),
        message = L('dispatch_robbery', trainLabel, nearest and nearest.label or '?'),
        coords = trainPos,
        train = trainLabel,
        mission = run.mission and Config.Missions[run.mission].label or nil,
        route = Config.Routes[run.route].label,
    })

    return { ok = true, message = L('rob_started_robber', cfg.duration), data = { duration = cfg.duration, cancelRadius = cfg.cancelRadius } }
end, { rate = 3000 })

--- Appelé par Runs.Close : nettoie un braquage lié au run.
function Robbery.OnRunClosed(run)
    local entry = Robbery.active[run.id]
    if entry then
        Robbery.active[run.id] = nil
        if GetPlayerName(entry.robber) then Srv.Notify(entry.robber, L('rob_aborted'), 'error') end
        TriggerClientEvent('sunny_train:client:robberyState', -1, run.id, nil)
    end
    SetTimeout(0, Robbery.Refresh)
end

AddEventHandler('playerDropped', function()
    local src = source
    for _, entry in pairs(Robbery.active) do
        if entry.robber == src then finish(entry, false) end
    end
end)

CreateThread(function()
    GlobalState.sunnyTrainRobbable = {}
end)
