HS = {
    Pits = {},
    PitList = {},
    States = {},
    Near = {},
    MyPit = nil,
    Stakes = {},
    Npcs = {},
    Shoes = {},
    Animating = {},
    HandProps = {},
    Objects = {},
}

for i, def in ipairs(Config.HorseshoePits) do
    if def.enabled ~= false then
        local pit = Sim.Pit(def, i)
        if not HS.Pits[pit.id] then
            HS.Pits[pit.id] = pit
            HS.PitList[#HS.PitList + 1] = pit
        end
    end
end

function HS.Notify(text, success)
    if success then
        TriggerEvent('QBCore:Notify', 9, text, 5000, 0, 'hud_textures', 'check', 'COLOR_WHITE')
    else
        TriggerEvent('QBCore:Notify', 9, text, 5000, 0, 'mp_lobby_textures', 'cross', 'COLOR_WHITE')
    end
end

function HS.MyId()
    return GetPlayerServerId(PlayerId())
end

function HS.SendUI(msg)
    if Config.UI.enabled then SendNUIMessage(msg) end
end

function HS.LoadModel(name)
    local hash = type(name) == 'number' and name or GetHashKey(name)
    if not IsModelValid(hash) then
        print(('^1[sunny_horseshoes] modèle introuvable : %s^7'):format(tostring(name)))
        return nil
    end
    RequestModel(hash)
    local deadline = GetGameTimer() + 5000
    while not HasModelLoaded(hash) do
        if GetGameTimer() > deadline then return nil end
        Wait(10)
    end
    return hash
end

function HS.CreateProp(name, x, y, z)
    local hash = HS.LoadModel(name)
    if not hash then return nil end
    local obj = CreateObject(hash, x, y, z, false, false, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not obj or obj == 0 then return nil end
    HS.Objects[obj] = true
    return obj
end

function HS.DeleteProp(obj)
    if not obj then return end
    HS.Objects[obj] = nil
    if DoesEntityExist(obj) then
        SetEntityAsMissionEntity(obj, true, true)
        DeleteEntity(obj)
    end
end

function HS.Ground(x, y, z)
    local found, gz = GetGroundZFor_3dCoord(x + 0.0, y + 0.0, z + 1.5, false)
    if found and gz and math.abs(gz - z) < 2.0 then return gz end
    return z
end

function HS.ShoeRotation(psi, pitch, roll)
    local s = Config.Shoe
    return (pitch or 0.0) + s.pitch, (roll or 0.0) + s.roll, math.deg(psi) - 90.0 + s.yaw
end

function HS.NearestPit(maxDist)
    local c = GetEntityCoords(PlayerPedId())
    local best, bestD
    for _, pit in ipairs(HS.PitList) do
        local d = #(c - vector3(pit.coords.x, pit.coords.y, pit.coords.z))
        if d <= maxDist and (not bestD or d < bestD) then best, bestD = pit, d end
    end
    return best
end

function HS.IsParticipant(state)
    if not state or not state.players then return false end
    local me = HS.MyId()
    for _, p in ipairs(state.players) do
        if p.src == me then return true end
    end
    return false
end

local function SpawnStake(pit)
    if HS.Stakes[pit.id] or not Config.Stake.spawn then return end
    local S = pit.S
    local z = S.z + Config.Stake.zOffset
    local obj = HS.CreateProp(Config.StakeModel, S.x, S.y, z)
    if not obj then return end
    SetEntityCoordsNoOffset(obj, S.x, S.y, z, false, false, false)
    SetEntityHeading(obj, pit.stakeHeading)
    FreezeEntityPosition(obj, true)
    HS.Stakes[pit.id] = obj
end

local function DespawnStake(pit)
    HS.DeleteProp(HS.Stakes[pit.id])
    HS.Stakes[pit.id] = nil
end

local function SpawnNpc(pit)
    local n = pit.npc
    if not n or (HS.Npcs[pit.id] and DoesEntityExist(HS.Npcs[pit.id])) then return end
    local hash = HS.LoadModel(n.model or 'u_m_m_wtccowboy_04')
    if not hash then return end
    local c = n.coords
    local ped = CreatePed(hash, c.x, c.y, c.z - 1.0, c.w or 0.0, false, false, false, false)
    SetModelAsNoLongerNeeded(hash)
    if not ped or ped == 0 then return end
    Citizen.InvokeNative(0x283978A15512B2FE, ped, true)
    SetEntityAsMissionEntity(ped, true, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    HS.Npcs[pit.id] = ped
    HS.Objects[ped] = true
    SetTimeout(300, function()
        if DoesEntityExist(ped) then FreezeEntityPosition(ped, true) end
    end)
end

local function DespawnNpc(pit)
    local ped = HS.Npcs[pit.id]
    HS.Npcs[pit.id] = nil
    if ped then
        HS.Objects[ped] = nil
        if DoesEntityExist(ped) then DeleteEntity(ped) end
    end
end

CreateThread(function()
    local farDist = Config.SyncDistance + 10.0
    while true do
        local c = GetEntityCoords(PlayerPedId())
        for _, pit in ipairs(HS.PitList) do
            local d = #(c - vector3(pit.S.x, pit.S.y, pit.S.z))
            if d < Config.SyncDistance and not HS.Near[pit.id] then
                HS.Near[pit.id] = true
                SpawnStake(pit)
                SpawnNpc(pit)
                if HS.OnPitNear then HS.OnPitNear(pit.id) end
            elseif d > farDist and HS.Near[pit.id] then
                HS.Near[pit.id] = nil
                DespawnStake(pit)
                DespawnNpc(pit)
                if HS.OnPitFar then HS.OnPitFar(pit.id) end
            end
        end
        Wait(1000)
    end
end)

local Blips = {}
CreateThread(function()
    local b = Config.Blip
    if not b or not b.enabled then return end
    local sprite = type(b.sprite) == 'string' and GetHashKey(b.sprite) or b.sprite
    for _, pit in ipairs(HS.PitList) do
        local blip = N_0x554d9d53f696d002(1664425300, pit.coords.x, pit.coords.y, pit.coords.z)
        SetBlipSprite(blip, sprite, 1)
        SetBlipScale(blip, b.scale or 0.2)
        Citizen.InvokeNative(0x9CB1A1623062F402, blip, CreateVarString(10, 'LITERAL_STRING', b.label or 'Lancer de fer'))
        Blips[#Blips + 1] = blip
    end
end)

local function Busy()
    return HS.Aiming or HS.Pending ~= nil
end

function HS.LeaveGame()
    if not HS.MyPit then return end
    TriggerServerEvent('sunny_horseshoes:server:Leave')
    local ped = PlayerPedId()
    HS.Pending = nil
    if HS.StopAim then HS.StopAim() end
    HS.Frozen = false
    FreezeEntityPosition(ped, false)
    ClearPedTasks(ped)
    if HS.RemoveHandShoe then HS.RemoveHandShoe(HS.MyId()) end
    HS.SendUI({ action = 'aim', show = false })
    HS.SendUI({ action = 'hud', show = false })
end

CreateThread(function()
    local quit = Config.Controls.quit
    while true do
        if HS.MyPit and not HS.Aiming then
            if IsControlJustPressed(0, quit) or IsDisabledControlJustPressed(0, quit) then
                HS.LeaveGame()
            end
            Wait(0)
        else
            Wait(250)
        end
    end
end)

local BetPanel = nil

local function CloseBetPanel()
    if not BetPanel then return end
    BetPanel = nil
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'bet', show = false })
end

local function OpenBetPanel(pit, mode)
    if BetPanel or not Config.UI.enabled then return false end
    local st = HS.States[pit.id]
    BetPanel = { pit = pit.id, mode = mode }
    SetNuiFocus(true, true)
    SendNUIMessage({
        action = 'bet', show = true, mode = mode,
        min = Config.Bet.min, max = Config.Bet.max,
        bet = mode == 'join' and st and st.bet or 0,
        host = mode == 'join' and st and st.players and st.players[1] and st.players[1].name or nil,
        houseCut = Config.Bet.houseCut or 0,
    })
    return true
end

RegisterNUICallback('betConfirm', function(data, cb)
    cb('ok')
    local panel = BetPanel
    CloseBetPanel()
    if not panel then return end
    if panel.mode == 'create' then
        TriggerServerEvent('sunny_horseshoes:server:Create', panel.pit, 'multi', math.floor(tonumber(type(data) == 'table' and data.bet) or 0))
    else
        TriggerServerEvent('sunny_horseshoes:server:Join', panel.pit)
    end
end)

RegisterNUICallback('betCancel', function(_, cb)
    cb('ok')
    CloseBetPanel()
end)

function HS.Action(pit, action, arg)
    local st = HS.States[pit.id]
    if action == 'solo' then
        TriggerServerEvent('sunny_horseshoes:server:Create', pit.id, 'solo')
    elseif action == 'creer' then
        if arg ~= nil or not Config.Bet.enabled or not OpenBetPanel(pit, 'create') then
            TriggerServerEvent('sunny_horseshoes:server:Create', pit.id, 'multi', arg or 0)
        end
    elseif action == 'rejoindre' then
        if not (st and (st.bet or 0) > 0 and OpenBetPanel(pit, 'join')) then
            TriggerServerEvent('sunny_horseshoes:server:Join', pit.id)
        end
    elseif action == 'lancer' then
        TriggerServerEvent('sunny_horseshoes:server:Start', pit.id)
    elseif action == 'quitter' then
        HS.LeaveGame()
    end
end

local function Free(pit)
    local st = HS.States[pit.id]
    return not HS.MyPit and (not st or st.status == 'free')
end

local Zones = {}

local function AddZones()
    for _, pit in ipairs(HS.PitList) do
        Zones[#Zones + 1] = exports.ox_target:addSphereZone({
            name = 'sunny_horseshoes_' .. pit.id,
            coords = pit.npc and vector3(pit.npc.coords.x, pit.npc.coords.y, pit.npc.coords.z + 0.3)
                or vector3(pit.coords.x, pit.coords.y, pit.coords.z + 0.8),
            radius = Config.Interaction.radius,
            options = {
                {
                    name = 'sunny_horseshoes_solo', icon = 'fa-solid fa-horse', distance = Config.Interaction.distance,
                    label = 'Lancer de fer : jouer seul',
                    canInteract = function() return Free(pit) end,
                    onSelect = function() HS.Action(pit, 'solo') end,
                },
                {
                    name = 'sunny_horseshoes_multi', icon = 'fa-solid fa-users', distance = Config.Interaction.distance,
                    label = Config.Bet.enabled and 'Créer une partie à plusieurs'
                        or 'Lancer de fer : créer une partie à plusieurs',
                    canInteract = function() return Free(pit) and pit.maxPlayers > 1 end,
                    onSelect = function() HS.Action(pit, 'creer') end,
                },
                {
                    name = 'sunny_horseshoes_join', icon = 'fa-solid fa-right-to-bracket', distance = Config.Interaction.distance,
                    label = Config.Bet.enabled and 'Rejoindre la partie'
                        or 'Rejoindre la partie de fer à cheval',
                    canInteract = function()
                        local st = HS.States[pit.id]
                        return not HS.MyPit and st and st.status == 'lobby' and #(st.players or {}) < pit.maxPlayers
                    end,
                    onSelect = function() HS.Action(pit, 'rejoindre') end,
                },
                {
                    name = 'sunny_horseshoes_start', icon = 'fa-solid fa-flag', distance = Config.Interaction.distance,
                    label = 'Lancer la partie',
                    canInteract = function()
                        local st = HS.States[pit.id]
                        return HS.MyPit == pit.id and st and st.status == 'lobby' and st.host == HS.MyId()
                            and #(st.players or {}) >= 2
                    end,
                    onSelect = function() HS.Action(pit, 'lancer') end,
                },
                {
                    name = 'sunny_horseshoes_board', icon = 'fa-solid fa-trophy', distance = Config.Interaction.distance,
                    label = 'Voir le classement du lancer de fer',
                    canInteract = function() return Config.Leaderboard.enabled and not Busy() end,
                    onSelect = function() HS.OpenBoard() end,
                },
                {
                    name = 'sunny_horseshoes_leave', icon = 'fa-solid fa-door-open', distance = Config.Interaction.distance,
                    label = 'Quitter la partie',
                    canInteract = function() return HS.MyPit == pit.id end,
                    onSelect = function() HS.Action(pit, 'quitter') end,
                },
            },
        })
    end
end

local function RemoveZones()
    if GetResourceState('ox_target') ~= 'started' then Zones = {} return end
    for _, z in ipairs(Zones) do pcall(function() exports.ox_target:removeZone(z) end) end
    Zones = {}
end

local TargetGen = 0
local function SetupTarget()
    if not Config.Interaction.target then return end
    TargetGen = TargetGen + 1
    local gen = TargetGen
    CreateThread(function()
        local waited = 0
        while GetResourceState('ox_target') ~= 'started' and waited < 15000 do
            Wait(500)
            waited = waited + 500
        end
        if gen ~= TargetGen or GetResourceState('ox_target') ~= 'started' then return end
        Wait(500)
        if gen ~= TargetGen then return end
        RemoveZones()
        local ok, err = pcall(AddZones)
        if not ok then print('^1[sunny_horseshoes] ox_target : ' .. tostring(err) .. '^7') end
    end)
end

AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'ox_target' then
        Zones = {}
        SetupTarget()
    end
end)
SetupTarget()

local ALIASES = { creer = 'creer', ['créer'] = 'creer', multi = 'creer', solo = 'solo', rejoindre = 'rejoindre',
    join = 'rejoindre', lancer = 'lancer', start = 'lancer', quitter = 'quitter', quit = 'quitter' }

RegisterCommand(Config.Interaction.command, function(_, args)
    local action = ALIASES[(args[1] or ''):lower()]
    if not action then
        return HS.Notify(('/%s solo | creer [mise] | rejoindre | lancer | quitter'):format(Config.Interaction.command), false)
    end
    if action == 'quitter' then
        HS.LeaveGame()
        return
    end
    local pit = HS.NearestPit(Config.Interaction.distance + 4.0)
    if not pit then return HS.Notify('Aucun terrain de lancer de fer à proximité.', false) end
    HS.Action(pit, action, action == 'creer' and tonumber(args[2]) or nil)
end, false)

CreateThread(function()
    Wait(1500)
    SendNUIMessage({ action = 'config', enabled = Config.UI.enabled, sound = Config.UI.sound, volume = Config.UI.volume, popupMs = Config.UI.popupMs })
    TriggerServerEvent('sunny_horseshoes:server:RequestStates')
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if HS.StopAim then HS.StopAim() end
    if HS.CloseBoard then HS.CloseBoard() end
    CloseBetPanel()
    FreezeEntityPosition(PlayerPedId(), false)
    for obj in pairs(HS.Objects) do
        if DoesEntityExist(obj) then
            SetEntityAsMissionEntity(obj, true, true)
            DeleteEntity(obj)
        end
    end
    for _, blip in ipairs(Blips) do pcall(RemoveBlip, blip) end
    RemoveZones()
end)
