-- ============================================================================
--  Sunny_train - Sécurité serveur
--  Anti-spam, vérifications de distance, journalisation des tentatives.
-- ============================================================================

local Security = {}
Sunny.Security = Security

local lastCall = {}   -- [src][key] = GetGameTimer()
local bursts = {}     -- [src] = { windowStart, count }

--- Limite la fréquence d'une requête par joueur.
---@return boolean allowed
function Security.RateLimit(src, key, minInterval)
    local now = GetGameTimer()
    local calls = lastCall[src]
    if not calls then calls = {}; lastCall[src] = calls end
    local last = calls[key]
    if last and now - last < (minInterval or Config.Security.rateLimit) then
        return false
    end
    calls[key] = now

    local burst = bursts[src]
    if not burst or now - burst.windowStart > 5000 then
        bursts[src] = { windowStart = now, count = 1 }
    else
        burst.count = burst.count + 1
        if burst.count > Config.Security.burstLimit then
            Security.Flag(src, 'burst', ('%d requêtes en 5 s'):format(burst.count))
            return false
        end
    end
    return true
end

--- Journalise une tentative suspecte (et expulse si configuré).
function Security.Flag(src, reason, details)
    if Config.Security.logExploits then
        local msg = ('[Sunny_train] Suspect %s (%s) : %s %s'):format(
            GetPlayerName(src) or '?', tostring(src), reason, details and ('- ' .. tostring(details)) or '')
        print('^1' .. msg .. '^7')
        TriggerEvent('qbr-log:server:CreateLog', 'anticheat', 'Sunny_train', 'red', msg)
    end
    if Config.Security.dropOnExploit and reason ~= 'burst' and reason ~= 'too_far' then
        DropPlayer(src, 'Sunny_train : requête invalide.')
    end
end

function Security.PedCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    return GetEntityCoords(ped)
end

--- Le joueur est-il à moins de `radius` (+ marge) de `coords` ?
function Security.IsNear(src, coords, radius)
    if not coords then return false end
    local pos = Security.PedCoords(src)
    if not pos then return false end
    return #(pos - coords) <= (radius or 2.0) + Config.Security.interactionMargin
end

--- Distance entre deux joueurs.
function Security.DistanceBetween(a, b)
    local pa, pb = Security.PedCoords(a), Security.PedCoords(b)
    if not pa or not pb then return math.huge end
    return #(pa - pb)
end

--- Clé de table de config valide (chaîne existante).
function Security.ValidKey(tbl, key)
    return type(key) == 'string' and #key < 64 and tbl[key] ~= nil
end

--- Entité réseau résolue côté serveur (0 si inconnue).
function Security.EntityFromNet(netId)
    if type(netId) ~= 'number' or netId <= 0 then return 0 end
    local entity = NetworkGetEntityFromNetworkId(netId)
    if entity and entity ~= 0 and DoesEntityExist(entity) then return entity end
    return 0
end

AddEventHandler('playerDropped', function()
    local src = source
    lastCall[src] = nil
    bursts[src] = nil
end)
