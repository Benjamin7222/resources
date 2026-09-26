-- ============================================================================
--  Sunny_train - Aiguillages (serveur)
--  Valide les demandes du conducteur et diffuse la position à tous les
--  joueurs : la voie empruntée reste la même quel que soit le client qui
--  simule le train (changement de propriétaire réseau).
-- ============================================================================

local Junctions = { states = {} } -- ["track:index"] = { track, index, enabled }
Sunny.JunctionsServer = Junctions

local L = Sunny.L
local Srv, Security, Utils = Sunny.Srv, Sunny.Security, Sunny.Utils
local cfg = Config.Junctions

local DRIVING_STATES = { ready = true, enroute = true, at_station = true }

Srv.Register('junction:set', function(src, payload)
    if not cfg.enabled or not cfg.sync then return Srv.Fail('error_invalid') end

    local run = Sunny.Runs.Get(src)
    if not run or not DRIVING_STATES[run.state] then return Srv.Fail('junction_no_run') end

    local track, index = tonumber(payload.track), tonumber(payload.index)
    if not track or not index or index < 0 or index > 1024 or index % 1 ~= 0 then
        Security.Flag(src, 'junction_invalid', tostring(payload.track) .. ':' .. tostring(payload.index))
        return Srv.Fail('junction_invalid')
    end
    track = Utils.Signed32(track)
    if not Utils.JunctionTracks()[track] then return Srv.Fail('junction_invalid') end

    -- Le demandeur doit être dans la cabine de son train (si l'entité est connue du serveur).
    local entity = Security.EntityFromNet(run.netId)
    if entity ~= 0 and GetVehiclePedIsIn(GetPlayerPed(src), false) ~= entity then
        return Srv.Fail('junction_no_run')
    end

    local enabled = payload.enabled == true
    Junctions.states[('%d:%d'):format(track, index)] = { track = track, index = index, enabled = enabled }
    TriggerClientEvent('sunny_train:client:junction', -1, track, index, enabled)
    return { ok = true, message = L('junction_switched', cfg.labels[enabled] or tostring(enabled)) }
end, { rate = 800 })

--- État complet (joueurs qui se connectent après des changements).
Srv.Register('junction:state', function()
    local list = {}
    for _, j in pairs(Junctions.states) do list[#list + 1] = j end
    return { ok = true, data = list }
end, { rate = 2000 })
