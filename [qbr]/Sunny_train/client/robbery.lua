-- ============================================================================
--  Sunny_train - Client : braquages & alertes de secours
--
--  Convois braquables publiés par le serveur (GlobalState.sunnyTrainRobbable).
--  Avec ox_target : option « Braquer le convoi » sur n'importe quel wagon.
--  Sans ox_target : scan à basse fréquence et prompt à portée d'un convoi.
-- ============================================================================

local L = Sunny.L
local cfg = Config.Robbery

local Robbery = { robbing = nil }
Sunny.RobberyClient = Robbery

local UNARMED = GetHashKey('WEAPON_UNARMED')

local function isArmed(ped)
    local ok, weapon = GetCurrentPedWeapon(ped, true, 0, false)
    return ok and weapon ~= UNARMED
end

--- Convoi braquable auquel appartient une entité (locomotive ou wagon).
--- Utilisé par ox_target (canInteract / onSelect). Renvoie entry, locomotive.
function Robbery.EntryForEntity(entity)
    if not cfg.enabled or Robbery.robbing or not entity or entity == 0 then return nil end
    local list = GlobalState.sunnyTrainRobbable
    if type(list) ~= 'table' or #list == 0 then return nil end
    if IsEntityDead(PlayerPedId()) then return nil end
    local me = GetPlayerServerId(PlayerId())
    local N = Sunny.Train.Natives
    for _, entry in ipairs(list) do
        if entry.driver ~= me and NetworkDoesNetworkIdExist(entry.netId) then
            local engine = NetworkGetEntityFromNetworkId(entry.netId)
            if engine ~= 0 and DoesEntityExist(engine) then
                if engine == entity then return entry, engine end
                local cars = Citizen.InvokeNative(N.GET_TRAIN_CARRIAGE_TRAILER_NUM, engine, Citizen.ResultAsInteger()) or 0
                for i = 1, cars do
                    if Citizen.InvokeNative(N.GET_TRAIN_CARRIAGE, engine, i, Citizen.ResultAsInteger()) == entity then
                        return entry, engine
                    end
                end
            end
        end
    end
    return nil
end

local function tryRob(entry, entity)
    local ped = PlayerPedId()
    if cfg.requireWeapon and not isArmed(ped) then return Sunny.Notify(L('rob_need_weapon'), 'error') end
    if GetEntitySpeed(entity) > cfg.maxTrainSpeed then return Sunny.Notify(L('rob_too_fast'), 'error') end
    CreateThread(function()
        local res = Sunny.Request('robbery:start', { runId = entry.runId })
        Sunny.HandleResult(res)
        if not res.ok then return end
        -- Compte à rebours affiché au braqueur (information seulement).
        local endsAt = GetGameTimer() + res.data.duration * 1000
        Robbery.robbing = entry.runId
        while Robbery.robbing == entry.runId and GetGameTimer() < endsAt do
            SendNUIMessage({ action = 'robbery', remaining = math.ceil((endsAt - GetGameTimer()) / 1000) })
            Wait(1000)
        end
        SendNUIMessage({ action = 'robbery', remaining = nil })
        Robbery.robbing = nil
    end)
end

Robbery.Try = tryRob

RegisterNetEvent('sunny_train:client:robberyState', function(runId, state)
    if state == nil and Robbery.robbing == runId then Robbery.robbing = nil end
end)

CreateThread(function()
    if not cfg.enabled then return end
    Sunny.Prompts.Create('robbery', cfg.holdKey, L('rob_prompt'), true)
    local myServerId = GetPlayerServerId(PlayerId())

    while true do
        local sleep = 1500
        local list = GlobalState.sunnyTrainRobbable
        -- Avec ox_target actif, le braquage passe par le target des wagons.
        if type(list) == 'table' and #list > 0 and not Robbery.robbing and Sunny.Target.UsePrompts() then
            local ped = PlayerPedId()
            local pos = GetEntityCoords(ped)
            for _, entry in ipairs(list) do
                if entry.driver ~= myServerId and NetworkDoesNetworkIdExist(entry.netId) then
                    local entity = NetworkGetEntityFromNetworkId(entry.netId)
                    if entity ~= 0 and DoesEntityExist(entity) then
                        local dist = #(pos - GetEntityCoords(entity))
                        if dist < 60.0 then sleep = 400 end
                        if dist <= cfg.interactDistance + 10.0 and not IsEntityDead(ped) and not Sunny.UI.open then
                            sleep = 0
                            if Sunny.Prompts.Show('robbery', 'Convoi de la compagnie') then
                                tryRob(entry, entity)
                            end
                            break
                        end
                    end
                end
            end
        end
        Wait(sleep)
    end
end)

-- ----------------------------------------------------------------------------
--  Dispatch de secours (Config.Dispatch.system = 'fallback')
-- ----------------------------------------------------------------------------
RegisterNetEvent('sunny_train:client:dispatchFallback', function(data)
    if type(data) ~= 'table' or not data.coords then return end
    Sunny.Notify(('%s — %s'):format(data.code or '', data.message or ''), 'warning')
    local fb = Config.Dispatch.fallback
    local blip = Sunny.CreateBlip(data.coords, fb.blipSprite, data.title or 'Alerte', 0.8)
    local area = Citizen.InvokeNative(0x45F13B7E0A15C880, -1282792512, data.coords.x, data.coords.y, data.coords.z, fb.blipRadius) -- BLIP_ADD_FOR_RADIUS
    SetTimeout(fb.blipDuration * 1000, function()
        if DoesBlipExist(blip) then RemoveBlip(blip) end
        if area and DoesBlipExist(area) then RemoveBlip(area) end
    end)
end)
