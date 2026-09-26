-- ============================================================================
--  Sunny_train - Client : registre de la compagnie & runs
--
--  Le client ne fait qu'exprimer des intentions (« à quai », « départ »,
--  « terminer ») : chaque étape est validée par le serveur (missions.lua).
-- ============================================================================

local Company = {}
Sunny.Company = Company

local Missions = {
    run = nil,     -- copie locale : { id, stations, nextIndex, state, labels... }
    busy = false,
}
Sunny.Missions = Missions

local L = Sunny.L
local Train = Sunny.Train

local MPH = 2.23694

-- ----------------------------------------------------------------------------
--  Registre (menu employé)
-- ----------------------------------------------------------------------------

function Company.Open()
    CreateThread(function()
        local res = Sunny.Request('company:context')
        if not res.ok then return Sunny.HandleResult(res) end
        Sunny.UI.Open('company', res.data)
    end)
end

-- ----------------------------------------------------------------------------
--  HUD
-- ----------------------------------------------------------------------------

local function platformVec(station)
    return vector3(station.platform.x, station.platform.y, station.platform.z)
end

function Missions.UpdateHud()
    local run = Missions.run
    if not run or run.state == 'assigned' then return Sunny.UI.Hud(nil) end
    local next = not run.free and run.stations[run.nextIndex] or nil
    local distance = next and math.floor(#(GetEntityCoords(PlayerPedId()) - platformVec(next))) or 0
    local countdown = nil
    if run.state == 'at_station' and run.dwellEnds then
        countdown = math.max(0, math.ceil((run.dwellEnds - GetGameTimer()) / 1000))
    end
    Sunny.UI.Hud({
        train = run.trainLabel,
        free = run.free == true,
        mission = run.missionLabel,
        route = not run.free and run.routeLabel or nil,
        next = next and next.label or '',
        distance = distance,
        speed = math.floor(Train.GetSpeed() * MPH + 0.5),
        notch = Train.StateLabel(),
        state = run.state,
        stateLabel = Sunny.RunStates[run.state] or run.state,
        countdown = countdown,
        index = not run.free and run.nextIndex or nil,
        total = not run.free and #run.stations or nil,
        driving = Train.IsDriver(),
        junction = Sunny.Junctions.HudInfo(),
        coal = run.needsCoal and run.coal or nil,
        noFuel = Train.noFuel,
    })
end

-- ----------------------------------------------------------------------------
--  Cycle de vie
-- ----------------------------------------------------------------------------

function Missions.Clear()
    Missions.run = nil
    Missions.busy = false
    Sunny.UI.Hud(nil)
end

--- Démarre le run validé par le serveur : mise en voie puis enregistrement.
function Missions.Begin(data)
    Missions.run = {
        id = data.runId,
        free = data.free == true,
        stations = data.stations,
        -- Voyage libre : aucun arrêt imposé, seule la destination compte.
        nextIndex = data.free and #data.stations or 2,
        state = 'assigned',
        trainLabel = data.trainLabel,
        missionLabel = data.missionLabel,
        routeLabel = data.routeLabel,
    }

    local entity, netId = Train.Spawn(data)
    if not entity then
        Sunny.Notify(L('run_spawn_failed'), 'error')
        Sunny.Request('run:cancel')
        return Missions.Clear()
    end

    -- Laisse le temps à l'entité d'être répliquée avant la vérification serveur.
    local deadline = GetGameTimer() + 3000
    while not NetworkDoesNetworkIdExist(netId) and GetGameTimer() < deadline do Wait(100) end
    Wait(500)

    local res = Sunny.Request('run:spawned', { runId = data.runId, netId = netId })
    if not res.ok then
        Sunny.HandleResult(res)
        Train.Release(0)
        return Missions.Clear()
    end
    Missions.run.state = 'ready'
    Missions.run.needsCoal = res.data and res.data.needsCoal
    Missions.run.coal = res.data and res.data.coal
    Train.noFuel = res.data and res.data.noFuel == true
    Sunny.Notify(L('run_next_station', Missions.run.stations[Missions.run.nextIndex].label), 'info')
    Missions.UpdateHud()
end

local function arrive(run)
    Missions.busy = true
    CreateThread(function()
        local res = Sunny.Request('run:arrive', { runId = run.id, index = run.nextIndex })
        if Missions.run ~= run then return end
        if res.ok then
            Sunny.Notify(res.message, 'info')
            Train.Lock(true)
            if res.data.terminus then
                run.state = 'arrived'
                Missions.StartFinishPrompt()
            else
                run.state = 'at_station'
                run.dwellEnds = GetGameTimer() + (res.data.dwell or 0) * 1000 + 600
            end
        else
            run.retryAt = GetGameTimer() + 5000
            if res.error ~= run.lastError then Sunny.HandleResult(res) end
            run.lastError = res.error
        end
        Missions.busy = false
        Missions.UpdateHud()
    end)
end

local function depart(run)
    Missions.busy = true
    CreateThread(function()
        local res = Sunny.Request('run:depart', { runId = run.id })
        if Missions.run ~= run then return end
        if res.ok then
            run.nextIndex = run.nextIndex + 1
            run.state = 'enroute'
            run.dwellEnds = nil
            run.lastError = nil
            Train.Lock(false)
            Train.Whistle(Config.Driving.whistle and Config.Driving.whistle.onDepart)
            Sunny.Notify(res.message, 'success')
        else
            run.dwellEnds = GetGameTimer() + 2000
        end
        Missions.busy = false
        Missions.UpdateHud()
    end)
end

--- Appelé par la boucle du train toutes les `stationCheckInterval` ms.
function Missions.Tick()
    local run = Missions.run
    if not run then return end
    if not Missions.busy then
        local now = GetGameTimer()
        if (run.state == 'ready' or run.state == 'enroute') and now >= (run.retryAt or 0) then
            local target = run.stations[run.nextIndex]
            if target then
                local dist = #(GetEntityCoords(PlayerPedId()) - platformVec(target))
                if run.state == 'ready' and Train.GetSpeed() > 2.0 then
                    run.state = 'enroute'
                    -- Départ effectif : les tableaux des départs passent à « Parti ».
                    CreateThread(function() Sunny.Request('run:departed', { runId = run.id }) end)
                end
                -- Sifflet d'annonce à l'approche de l'arrêt (une fois par gare).
                if run.state == 'enroute' and dist <= target.radius * 2.5 and run.whistledFor ~= run.nextIndex then
                    run.whistledFor = run.nextIndex
                    Train.Whistle(Config.Driving.whistle and Config.Driving.whistle.onApproach)
                end
                if dist <= target.radius and Train.GetSpeed() < Config.Driving.stopSpeed and run.state == 'enroute' then
                    if run.free then
                        -- La destination annoncée ne bloque pas une circulation libre.
                        -- Le conducteur peut continuer et remiser depuis le registre.
                        if not run.destinationReached then
                            run.destinationReached = true
                            Sunny.Notify(L('free_arrived', target.label), 'success')
                        end
                    else
                        arrive(run)
                    end
                end
            end
        elseif run.state == 'at_station' and run.dwellEnds and now >= run.dwellEnds then
            depart(run)
        end
    end
    Missions.UpdateHud()
end

--- Prompt « Terminer le trajet » affiché au terminus (par frame, état court).
function Missions.StartFinishPrompt()
    local run = Missions.run
    CreateThread(function()
        while run and Missions.run == run and run.state == 'arrived' do
            if not Sunny.UI.open and not Missions.busy and not IsPauseMenuActive() then
                if Sunny.Prompts.Show('finish', Missions.run.missionLabel) then
                    Missions.Finish()
                end
            end
            Wait(0)
        end
    end)
end

--- Le conducteur peut-il remiser son train ici (voyage libre, à l'arrêt,
--- au dépôt ou au quai d'une gare) ?
function Missions.CanPark()
    local run = Missions.run
    if not run or not run.free or run.state == 'assigned' or Missions.busy then return false end
    if Train.GetSpeed() > (Config.Driving.stopSpeed or 0.9) then return false end
    return Sunny.Utils.ParkingStation(GetEntityCoords(PlayerPedId())) ~= nil
end

--- Clôture le run au terminus. Renvoie le résultat serveur.
function Missions.Finish()
    local run = Missions.run
    -- Voyage libre : remisage possible à tout moment après la mise en voie.
    local allowed = run and (run.state == 'arrived' or (run.free and run.state ~= 'assigned'))
    if not allowed or Missions.busy then
        return { ok = false, error = L('run_no_active') }
    end
    Missions.busy = true
    local res = Sunny.Request('run:finish', { runId = run.id })
    Missions.busy = false
    if res.ok then
        Missions.Clear()
        Sunny.Notify(res.message, 'success')
        Sunny.UI.Open('report', res.data)
    else
        Sunny.HandleResult(res)
    end
    return res
end

function Missions.OnTrainLost()
    if not Missions.run then return end
    Sunny.Notify(L('run_train_lost'), 'error')
    CreateThread(function() Sunny.Request('run:cancel') end)
    Train.Release(0)
    Missions.Clear()
end

-- ----------------------------------------------------------------------------
--  Actions NUI
-- ----------------------------------------------------------------------------

Sunny.Actions['run:start'] = function(payload)
    if Missions.run then return { ok = false, error = L('run_already_active') } end
    local res = Sunny.Request('run:start', payload)
    if not res.ok then return res end
    -- La NUI joue le tampon « Approuvé » puis se ferme ; filet de sécurité
    -- côté Lua si elle ne l'a pas fait.
    Sunny.UI.CloseSoon(2500)
    CreateThread(function() Missions.Begin(res.data) end)
    return { ok = true, close = true, message = res.message }
end

Sunny.Actions['run:startFree'] = function(payload)
    if Missions.run then return { ok = false, error = L('run_already_active') } end
    local res = Sunny.Request('run:startFree', payload)
    if not res.ok then return res end
    Sunny.UI.CloseSoon(2500)
    CreateThread(function() Missions.Begin(res.data) end)
    return { ok = true, close = true, message = res.message }
end

Sunny.Actions['run:cancel'] = function()
    local res = Sunny.Request('run:cancel')
    if res.ok then
        Train.Release(1)
        Missions.Clear()
    end
    return res
end

Sunny.Actions['run:finish'] = function()
    local res = Missions.Finish()
    if res.ok then return { ok = true, replaced = true } end
    return res
end

-- ----------------------------------------------------------------------------
--  Événements serveur
-- ----------------------------------------------------------------------------

-- Charbon : relevé serveur (consommation au kilomètre, rechargement du wagon).
RegisterNetEvent('sunny_train:client:fuel', function(info)
    local run = Missions.run
    if not run or type(info) ~= 'table' then return end
    local wasEmpty = Train.noFuel
    run.coal = info.coal
    Train.noFuel = info.empty == true
    if Train.noFuel and not wasEmpty then
        Sunny.Notify(L('fuel_empty'), 'warning')
    elseif wasEmpty and not Train.noFuel then
        Sunny.Notify(L('fuel_ok', info.coal or 0), 'success')
    end
    Missions.UpdateHud()
end)

RegisterNetEvent('sunny_train:client:runClosed', function(info)
    if not Missions.run then return end
    if info and info.message then Sunny.Notify(info.message, info.reason == 'failed' and 'error' or 'info') end
    Missions.Clear()
end)

RegisterNetEvent('sunny_train:client:robberyStarted', function(info)
    local run = Missions.run
    if not run then return end
    run.prevState = run.state
    run.state = 'robbery'
    Train.Lock(true)
    Sunny.Notify(info.message, 'warning')
    Missions.UpdateHud()
end)

RegisterNetEvent('sunny_train:client:robberyEnded', function(info)
    local run = Missions.run
    if not run then return end
    run.state = run.prevState or 'enroute'
    run.prevState = nil
    if run.state ~= 'at_station' and run.state ~= 'arrived' then Train.Lock(false) end
    Sunny.Notify(info.message, info.success and 'warning' or 'success')
    Missions.UpdateHud()
end)

CreateThread(function()
    Sunny.Prompts.Create('finish', Config.Driving.cabHoldKey, L('prompt_finish'), true)
end)
