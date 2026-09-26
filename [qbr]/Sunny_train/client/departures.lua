-- ============================================================================
--  Sunny_train - Client : départs programmés
--  Reçoit la liste en direct (tableaux des départs, guichets) et les avis aux
--  voyageurs, et les transmet à la NUI. Les heures sont celles du serveur
--  (heure réelle) : la NUI reçoit l'heure du serveur et son fuseau.
-- ============================================================================

local Departures = { snapshot = { list = {}, now = 0, tz = 0 } }
Sunny.Departures = Departures

local cfg = Config.Departures
local receivedAt = GetGameTimer()

function Departures.CurrentSnapshot()
    local snapshot = Departures.snapshot
    return {
        list = snapshot.list, tz = snapshot.tz,
        now = snapshot.now > 0 and snapshot.now + (GetGameTimer() - receivedAt) / 1000 or 0,
    }
end

local function pushLive()
    SendNUIMessage({ action = 'live', live = Departures.snapshot })
end

function Departures.ApplySnapshot(snapshot)
    if type(snapshot) ~= 'table' or type(snapshot.list) ~= 'table' or type(snapshot.now) ~= 'number' then return false end
    Departures.snapshot = snapshot
    receivedAt = GetGameTimer()
    pushLive()
    return true
end

RegisterNetEvent('sunny_train:client:departures', Departures.ApplySnapshot)

--- Avis aux voyageurs (départ programmé, train à quai, parti, annulé).
RegisterNetEvent('sunny_train:client:departureNotice', function(notice)
    if type(notice) ~= 'table' then return end
    SendNUIMessage({ action = 'notice', notice = notice, duration = cfg.duration })
    if cfg.sound and cfg.sound.name then
        PlaySoundFrontend(cfg.sound.name, cfg.sound.set, true, 0)
    end
end)

-- Liste initiale (départs programmés avant la connexion du joueur).
local syncing = false
local function syncWhenLoaded()
    if not cfg.enabled or syncing then return end
    syncing = true
    CreateThread(function()
        Wait(3000)
        while true do
            local res = Sunny.Request('departure:list')
            if res and res.ok and Departures.ApplySnapshot(res.data) then break end
            Wait(5000) -- sélection du personnage, serveur en démarrage ou timeout
        end
        syncing = false
    end)
end
RegisterNetEvent('QBCore:Client:OnPlayerLoaded', syncWhenLoaded)
syncWhenLoaded()
