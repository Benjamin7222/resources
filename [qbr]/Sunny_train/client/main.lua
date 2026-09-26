-- ============================================================================
--  Sunny_train - Client : cœur
--  Requêtes serveur (promesses), notifications, lecture du job (UX uniquement
--  — le serveur revérifie tout), helpers natifs, commandes.
-- ============================================================================

local Client = {
    requests = {},
    requestId = 0,
}
Sunny.Client = Client

local L = Sunny.L

-- ----------------------------------------------------------------------------
--  Requêtes serveur
-- ----------------------------------------------------------------------------

--- Envoie une requête au serveur et attend la réponse (à appeler dans un thread).
---@return table result { ok, error?, message?, data? }
function Sunny.Request(name, payload, timeoutMs)
    Client.requestId = Client.requestId + 1
    local id = Client.requestId
    local p = promise.new()
    Client.requests[id] = p
    TriggerServerEvent('sunny_train:server:request', id, name, payload or {})
    SetTimeout(timeoutMs or 10000, function()
        if Client.requests[id] then
            Client.requests[id] = nil
            p:resolve({ ok = false, error = L('error_generic') })
        end
    end)
    return Citizen.Await(p)
end

RegisterNetEvent('sunny_train:client:response', function(id, result)
    local p = Client.requests[id]
    if not p then return end
    Client.requests[id] = nil
    p:resolve(type(result) == 'table' and result or { ok = false, error = L('error_generic') })
end)

-- ----------------------------------------------------------------------------
--  Notifications
-- ----------------------------------------------------------------------------

---@param kind 'info'|'success'|'error'|'warning'
function Sunny.Notify(text, kind)
    if not text or text == '' then return end
    if Config.Notify.mode == 'nui' then
        SendNUIMessage({ action = 'toast', text = text, kind = kind or 'info', duration = Config.Notify.duration })
    else
        local icon = kind == 'error' and 'cross' or 'tick'
        exports[Config.Framework.core]:Notify(9, text, Config.Notify.duration, 0, 'mp_lobby_textures', icon, 'COLOR_WHITE')
    end
end

--- Affiche le message / l'erreur d'un résultat serveur.
function Sunny.HandleResult(result)
    if not result then return end
    if result.ok and result.message then
        Sunny.Notify(result.message, 'success')
    elseif not result.ok and result.error then
        Sunny.Notify(result.error, 'error')
    end
end

RegisterNetEvent('sunny_train:client:notify', function(text, kind)
    Sunny.Notify(text, kind)
end)

-- ----------------------------------------------------------------------------
--  Job (lecture seule, pour l'affichage des prompts uniquement)
-- ----------------------------------------------------------------------------

function Sunny.GetJob()
    local ok, data = pcall(function() return exports[Config.Framework.core]:GetPlayerData() end)
    if not ok or type(data) ~= 'table' or not data.job then return nil, 0 end
    return data.job.name, (data.job.grade and tonumber(data.job.grade.level)) or 0
end

function Sunny.IsEmployee()
    local job, grade = Sunny.GetJob()
    return Sunny.Utils.HasJobAccess(Config.Permissions.employees, job, grade)
end

-- ----------------------------------------------------------------------------
--  Helpers natifs
-- ----------------------------------------------------------------------------

function Sunny.VarString(text)
    return CreateVarString(10, 'LITERAL_STRING', text)
end

--- Charge un modèle avec délai max.
function Sunny.LoadModel(model, timeoutMs)
    if not IsModelValid(model) then return false end
    RequestModel(model, false)
    local deadline = GetGameTimer() + (timeoutMs or 8000)
    while not HasModelLoaded(model) do
        if GetGameTimer() > deadline then return false end
        Wait(25)
    end
    return true
end

function Sunny.LoadAnimDict(dict, timeoutMs)
    if not DoesAnimDictExist(dict) then return false end
    RequestAnimDict(dict)
    local deadline = GetGameTimer() + (timeoutMs or 5000)
    while not HasAnimDictLoaded(dict) do
        if GetGameTimer() > deadline then return false end
        Wait(25)
    end
    return true
end

function Sunny.PlaySound(name)
    local s = Config.UI.sounds
    if not s.enabled or not name then return end
    PlaySoundFrontend(name, s.soundset, true, 0)
end

--- Crée un blip de coordonnées.
function Sunny.CreateBlip(coords, sprite, label, scale)
    local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, coords.x, coords.y, coords.z) -- BLIP_ADD_FOR_COORDS
    local spriteHash = type(sprite) == 'string' and GetHashKey(sprite) or sprite
    Citizen.InvokeNative(0x74F74D3207ED525C, blip, spriteHash, true)                             -- SET_BLIP_SPRITE
    Citizen.InvokeNative(0xD38744167B2FA257, blip, scale or 0.2)                                   -- SET_BLIP_SCALE
    Citizen.InvokeNative(0x9CB1A1623062F402, blip, Sunny.VarString(label))                          -- SET_BLIP_NAME
    return blip
end

--- Joueur le plus proche (serverId, distance).
function Sunny.ClosestPlayer(maxDistance)
    local ped = PlayerPedId()
    local pos = GetEntityCoords(ped)
    local best, bestDist = nil, maxDistance or 3.0
    for _, player in ipairs(GetActivePlayers()) do
        local other = GetPlayerPed(player)
        if other ~= ped then
            local d = #(GetEntityCoords(other) - pos)
            if d < bestDist then best, bestDist = GetPlayerServerId(player), d end
        end
    end
    return best, bestDist
end

-- ----------------------------------------------------------------------------
--  Commandes
-- ----------------------------------------------------------------------------

RegisterCommand(Config.Commands.menu, function()
    if Sunny.UI.open then return end
    Sunny.Company.Open()
end, false)

-- Sécurité joueur : force la libération du focus NUI.
RegisterCommand(Config.Commands.unlock, function()
    Sunny.UI.Close(true)
end, false)

RegisterCommand(Config.Commands.position, function()
    CreateThread(function()
        if not Sunny.Request('admin:allowed').ok then return end
        local ped = PlayerPedId()
        local c = GetEntityCoords(ped)
        local line = ('vector3(%.2f, %.2f, %.2f) -- heading %.1f'):format(c.x, c.y, c.z, GetEntityHeading(ped))
        print('[Sunny_train] ' .. line)
        Sunny.Notify(line, 'info')
    end)
end, false)

RegisterCommand(Config.Commands.debug, function()
    CreateThread(function()
        if not Sunny.Request('admin:allowed').ok then return end
        Sunny.Stations.ToggleDebug()
    end)
end, false)

-- ----------------------------------------------------------------------------
--  Nettoyage
-- ----------------------------------------------------------------------------

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    SetNuiFocus(false, false)
end)
