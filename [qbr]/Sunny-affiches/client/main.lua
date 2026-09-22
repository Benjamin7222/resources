local QBCore = exports['qbr-core']

local isOpen, opening = false, false
local currentBoard = nil
local cam = nil

local Boards = {}       
local BoardList = {}
local Props = {}       
local BadModels = {}
local TargetState = {}  
local TargetZones = {}


local function Notify(text, success)
    if success then
        TriggerEvent('QBCore:Notify', 9, text, 5000, 0, 'hud_textures', 'check', 'COLOR_WHITE')
    else
        TriggerEvent('QBCore:Notify', 9, text, 5000, 0, 'mp_lobby_textures', 'cross', 'COLOR_WHITE')
    end
end

local function Forward(heading)
    local h = math.rad(heading)
    return -math.sin(h), math.cos(h)
end

for _, board in ipairs(Config.Boards) do
    if type(board.id) == 'string' and not Boards[board.id] and board.enabled ~= false then
        local c = board.coords
        board.pos = vector3(c.x, c.y, c.z)
        local fx, fy = Forward(c.w)
        local offset = board.boardOffset or 1.2
        board.boardPos = vector3(c.x + fx * offset, c.y + fy * offset, c.z)
        board.distance = board.distance or 2.0
        board.open = board.open or Config.DefaultOpen or 'target'

        -- model : nil = modèles par défaut, false = aucun prop, 'nom' ou { 'nom1', 'nom2' } = candidats
        local models = board.model
        if models == nil then models = Config.DefaultModel end
        if type(models) == 'string' then models = { models } end
        board.models = type(models) == 'table' and #models > 0 and models or false

        Boards[board.id] = board
        BoardList[#BoardList + 1] = board
    end
end



local function StartCamera(board)
    if not Config.CameraTarget or board.camera == false then return end
    local c = Config.Camera
    local fx, fy = Forward(board.coords.w)
    local p, bp = board.pos, board.boardPos

    cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(cam, p.x + fx * c.forward, p.y + fy * c.forward, p.z + c.height)
    PointCamAtCoord(cam, bp.x, bp.y, p.z + c.targetHeight)
    SetCamFov(cam, c.fov)
    SetCamActive(cam, true)
    RenderScriptCams(true, true, 900, true, true)
end

local function StopCamera()
    if not cam then return end
    RenderScriptCams(false, true, 700, true, true)
    DestroyCam(cam, false)
    cam = nil
end


local function CloseBoard()
    if not isOpen then return end
    isOpen = false
    currentBoard = nil
    SetNuiFocus(false, false)
    StopCamera()
end

local function OpenBoard(boardId)
    local board = Boards[boardId]
    if not board or isOpen or opening then return end
    opening = true

    QBCore:TriggerCallback('Sunny-affiches:server:Open', function(res)
        opening = false
        if not res or not res.ok then
            return Notify(res and res.error or 'Pas de réponse du serveur.', false)
        end
        if isOpen then return end
        isOpen = true
        currentBoard = boardId
        StartCamera(board)
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'open', data = res })
    end, boardId)
end

RegisterNUICallback('close', function(_, cb)
    CloseBoard()
    cb('ok')
end)

local function BridgeServerCallback(nuiName, serverName)
    RegisterNUICallback(nuiName, function(data, cb)
        if not isOpen then return cb({ ok = false, error = 'Le panneau est fermé.' }) end
        data = type(data) == 'table' and data or {}
        data.board_id = currentBoard
        QBCore:TriggerCallback(serverName, function(result)
            cb(result or { ok = false, error = 'Pas de réponse du serveur.' })
        end, data)
    end)
end

BridgeServerCallback('list', 'Sunny-affiches:server:List')
BridgeServerCallback('save', 'Sunny-affiches:server:Save')
BridgeServerCallback('delete', 'Sunny-affiches:server:Delete')
BridgeServerCallback('pin', 'Sunny-affiches:server:Pin')
BridgeServerCallback('editions', 'Sunny-affiches:server:Editions')
BridgeServerCallback('buy', 'Sunny-affiches:server:Buy')
BridgeServerCallback('stock', 'Sunny-affiches:server:AddStock')
BridgeServerCallback('take', 'Sunny-affiches:server:Take')
BridgeServerCallback('claim', 'Sunny-affiches:server:Claim')
BridgeServerCallback('collect', 'Sunny-affiches:server:Collect')


local PromptGroup = GetRandomIntInRange(0, 0xffffff)
local OpenPrompt = nil

local function CreateOpenPrompt()
    OpenPrompt = PromptRegisterBegin()
    PromptSetControlAction(OpenPrompt, Config.OpenKey)
    PromptSetText(OpenPrompt, CreateVarString(10, 'LITERAL_STRING', 'Consulter'))
    PromptSetEnabled(OpenPrompt, true)
    PromptSetVisible(OpenPrompt, true)
    PromptSetHoldMode(OpenPrompt, true)
    PromptSetGroup(OpenPrompt, PromptGroup, 0)
    PromptRegisterEnd(OpenPrompt)
end

local function UsesPrompt(board)
    return board.open ~= 'target' or (Config.PromptFallback and TargetState[board.id] == 'fallback')
end

local function DrawBoardMarker(board)
    local m = board.marker
    local p = board.pos
    Citizen.InvokeNative(0x2A32FAA57B937173, 0x94FDAE17, p.x, p.y, p.z - 0.98, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0,
        board.distance, board.distance, 0.4, m.r or 255, m.g or 255, m.b or 255, m.a or 90,
        false, false, 2, false, nil, nil, false)
end

CreateThread(function()
    CreateOpenPrompt()
    while true do
        local sleep = 1000
        if not isOpen and not opening then
            local ped = PlayerPedId()
            local coords = GetEntityCoords(ped)
            local nearest, nearestDist

            for _, board in ipairs(BoardList) do
                local dist = #(coords - board.pos)
                if board.marker and dist < Config.MarkerDistance then
                    sleep = 0
                    DrawBoardMarker(board)
                end
                if dist <= board.distance and UsesPrompt(board) and (not nearestDist or dist < nearestDist) then
                    nearest, nearestDist = board, dist
                end
            end

            if nearest and not IsEntityDead(ped) then
                sleep = 0
                Citizen.InvokeNative(0xC65A45D4453C2627, PromptGroup, CreateVarString(10, 'LITERAL_STRING', 'Panneau d\'affichage — ' .. nearest.name), 1)
                if PromptHasHoldModeCompleted(OpenPrompt) then
                    PromptDelete(OpenPrompt)
                    CreateOpenPrompt()
                    OpenBoard(nearest.id)
                end
            end
        end
        Wait(sleep)
    end
end)


local function AddTargetZone(board)
    local bp = board.boardPos
    local id = exports.ox_target:addSphereZone({
        name = 'qbr_affiches_' .. board.id,
        coords = vector3(bp.x, bp.y, bp.z + 0.4),
        radius = board.targetRadius or 1.2,
        debug = Config.Debug,
        options = {
            {
                name = 'qbr_affiches_open_' .. board.id,
                icon = 'fa-solid fa-thumbtack',
                label = 'Consulter le panneau d\'affichage — ' .. board.name,
                distance = board.distance + 1.0,
                onSelect = function() OpenBoard(board.id) end,
            },
        },
    })
    TargetZones[board.id] = id
    TargetState[board.id] = 'ok'
end

local function SetupTargets()
    for _, board in ipairs(BoardList) do
        if board.open == 'target' and TargetState[board.id] ~= 'ok' then
            TargetState[board.id] = 'pending'
        end
    end

    CreateThread(function()
        local waited = 0
        while GetResourceState('ox_target') ~= 'started' and waited < 15000 do
            Wait(500)
            waited = waited + 500
        end
        local ready = GetResourceState('ox_target') == 'started'
        if ready then Wait(500) end

        for _, board in ipairs(BoardList) do
            if board.open == 'target' and TargetState[board.id] == 'pending' then
                if ready then
                    local ok, err = pcall(AddTargetZone, board)
                    if not ok then
                        print(('[Sunny-affiches] ox_target : zone %s impossible (%s)%s'):format(board.id, err,
                            Config.PromptFallback and ', repli sur le prompt.' or '.'))
                        TargetState[board.id] = 'fallback'
                    end
                else
                    TargetState[board.id] = 'fallback'
                end
            end
        end
        if not ready then
            print('[Sunny-affiches] ox_target n\'est pas démarré : les panneaux en mode \'target\' sont inutilisables'
                .. (Config.PromptFallback and ' (repli sur le prompt).' or ' (Config.PromptFallback = true pour un repli sur le prompt).'))
        end
    end)
end

AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'ox_target' then
        TargetZones = {}
        for _, board in ipairs(BoardList) do TargetState[board.id] = nil end
        SetupTargets()
    end
end)

SetupTargets()



-- Premier modèle de la liste qui existe dans le jeu (nil si aucun).
local function ResolveModel(board)
    if board._modelHash then return board._modelHash end
    for _, name in ipairs(board.models) do
        local hash = joaat(name)
        if IsModelInCdimage(hash) then
            board._modelHash = hash
            print(('[Sunny-affiches] panneau %s : modèle %s'):format(board.id, name))
            return hash
        end
    end
    BadModels[board.id] = true
    print(('[Sunny-affiches] panneau %s : aucun modèle valide parmi %s. Vérifie Config.DefaultModel.')
        :format(board.id, table.concat(board.models, ', ')))
end

local function SpawnProp(board)
    local hash = ResolveModel(board)
    if not hash then return end
    RequestModel(hash)
    local timeout = GetGameTimer() + 5000
    while not HasModelLoaded(hash) and GetGameTimer() < timeout do Wait(50) end
    if not HasModelLoaded(hash) then return end

    local bp = board.boardPos
    local obj = CreateObject(hash, bp.x, bp.y, bp.z, false, false, false)
    SetEntityHeading(obj, (board.coords.w + 180.0 + (board.modelRotation or 0.0)) % 360.0)
    PlaceObjectOnGroundProperly(obj)
    FreezeEntityPosition(obj, true)
    SetModelAsNoLongerNeeded(hash)
    Props[board.id] = obj
end

local function DeleteProp(id)
    local obj = Props[id]
    if obj and DoesEntityExist(obj) then DeleteEntity(obj) end
    Props[id] = nil
end

CreateThread(function()
    while true do
        local coords = GetEntityCoords(PlayerPedId())
        for _, board in ipairs(BoardList) do
            if board.models and not BadModels[board.id] then
                local dist = #(coords - board.boardPos)
                if dist < 60.0 and not (Props[board.id] and DoesEntityExist(Props[board.id])) then
                    Props[board.id] = nil
                    SpawnProp(board)
                elseif dist > 90.0 and Props[board.id] then
                    DeleteProp(board.id)
                end
            end
        end
        Wait(2000)
    end
end)


local Blips = {}

CreateThread(function()
    local settings = type(Config.Blip) == 'table' and Config.Blip or {}
    for _, board in ipairs(BoardList) do
        if board.blip then
            -- board.blip : nom de sprite (ex 'blip_proc_bank') converti en hash, ou hash déjà calculé
            local sprite = type(board.blip) == 'string' and joaat(board.blip) or board.blip
            local blip = N_0x554d9d53f696d002(1664425300, board.pos)
            SetBlipSprite(blip, sprite, 1)
            SetBlipScale(blip, settings.scale or 0.2)
            Citizen.InvokeNative(0x9CB1A1623062F402, blip,
                CreateVarString(10, 'LITERAL_STRING', (settings.label or 'Panneau d\'affichage') .. ' — ' .. board.name))
            Blips[#Blips + 1] = blip
        end
    end
end)



AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if isOpen then SetNuiFocus(false, false) end
    StopCamera()
    for id in pairs(Props) do DeleteProp(id) end
    for _, blip in ipairs(Blips) do pcall(RemoveBlip, blip) end
    if OpenPrompt then PromptDelete(OpenPrompt) end
    if GetResourceState('ox_target') == 'started' then
        for _, zoneId in pairs(TargetZones) do
            pcall(function() exports.ox_target:removeZone(zoneId) end)
        end
    end
end)
