-- ============================================================================
--  Sunny_train - Client : aiguillages
--
--  À l'approche d'une intersection, le conducteur peut basculer
--  l'aiguillage situé devant son train.
--
--  Natives RDR3 utilisées (vérifiées dans alloc8or/rdr3-nativedb-data) :
--    _RETURN_TRAIN_INFO_FROM_HANDLE        0x09034479E6E3E269 (train, Hash* track, int* junction) -> BOOL
--    _GET_TRAIN_TRACK_JUNCTION_AT_COORDS   0x86AFC343CF7F0B34 (Hash track, x, y, z, int* junction) -> BOOL
--    _GET_JUNCTION_COORDS_FOR_TRAIN_TRACK  0x785639D89F8451AB (Hash track, int junction) -> Vector3
--    _SET_TRAIN_TRACK_JUNCTION_SWITCH      0xE6C5E2125EB210C1 (Hash track, int junction, BOOL enabled)
--    _0x3ABFA128F5BF5A70                   (Hash track, int junction, BOOL enabled)
--        appelée avec la précédente dans les scripts Rockstar (medium_update)
--    _SET_ALL_JUNCTIONS_CLEARED            0x138398153824E332 ()
--
--  Détection : 1) voie/aiguillage renvoyés par le train lui-même,
--              2) sondage de points devant le train sur chaque réseau connu.
--  Seuls les aiguillages DEVANT le train et à portée sont proposés.
-- ============================================================================

local Junctions = {
    states = {},     -- ["track:index"] = enabled
    current = nil,   -- aiguillage proposé { track, index, name, coords, distance, enabled, locked }
    pending = false,
    changed = false,
}
Sunny.Junctions = Junctions

local L = Sunny.L
local Utils = Sunny.Utils
local cfg = Config.Junctions

local N = {
    RETURN_TRAIN_INFO   = 0x09034479E6E3E269,
    JUNCTION_AT_COORDS  = 0x86AFC343CF7F0B34,
    JUNCTION_COORDS     = 0x785639D89F8451AB,
    SET_SWITCH          = 0xE6C5E2125EB210C1,
    SET_SWITCH_COMPANION = 0x3ABFA128F5BF5A70,
    CLEAR_ALL           = 0x138398153824E332,
}

local function key(track, index)
    return ('%d:%d'):format(track, index)
end

function Junctions.Get(track, index)
    return Junctions.states[key(track, index)] == true
end

function Junctions.Label(enabled)
    return cfg.labels[enabled == true] or tostring(enabled)
end

--- Applique une position d'aiguillage sur ce client.
function Junctions.Apply(track, index, enabled)
    track, index = Utils.Signed32(track), math.floor(tonumber(index) or -1)
    if index < 0 then return end
    Citizen.InvokeNative(N.SET_SWITCH, track, index, enabled == true)
    Citizen.InvokeNative(N.SET_SWITCH_COMPANION, track, index, enabled == true)
    Junctions.states[key(track, index)] = enabled == true
    Junctions.changed = true
    local cur = Junctions.current
    if cur and cur.track == track and cur.index == index then
        cur.enabled = enabled == true
        Junctions.RefreshPrompt()
    end
end

local function junctionCoords(track, index)
    local c = Citizen.InvokeNative(N.JUNCTION_COORDS, track, index, Citizen.ResultAsVector())
    if not c or (c.x == 0.0 and c.y == 0.0 and c.z == 0.0) then return nil end
    return c
end

--- Aiguillages candidats autour du train.
---@param includeUnknown boolean inclure les voies absentes de Config.Junctions.tracks (debug)
local function candidates(train, pos, fwd, dir, includeUnknown)
    local tracks = Utils.JunctionTracks()
    local list, seen = {}, {}
    local function add(track, index, source)
        track, index = Utils.Signed32(track), tonumber(index)
        if not index or index < 0 or track == 0 then return end
        if not includeUnknown and not tracks[track] then return end
        local k = key(track, index)
        if seen[k] then return end
        seen[k] = true
        list[#list + 1] = { track = track, index = index, source = source }
    end

    -- 1) Voie et aiguillage renvoyés par le train.
    local ok, track, index = Citizen.InvokeNative(N.RETURN_TRAIN_INFO, train,
        Citizen.PointerValueInt(), Citizen.PointerValueInt(), Citizen.ResultAsInteger())
    if ok == 1 then add(track, index, 'train') end

    -- 2) Aiguillage déjà suivi : reste évalué jusqu'à ce qu'il soit franchi,
    --    même quand les points sondés l'ont dépassé.
    local cur = Junctions.current
    if cur then add(cur.track, cur.index, 'suivi') end

    -- 3) Points sondés devant le train, sur chaque réseau connu.
    for _, distance in ipairs(cfg.lookAhead) do
        local p = pos + fwd * (distance * dir)
        for hash in pairs(tracks) do
            local found, idx = Citizen.InvokeNative(N.JUNCTION_AT_COORDS, hash, p.x, p.y, p.z,
                Citizen.PointerValueInt(), Citizen.ResultAsInteger())
            if found == 1 then add(hash, idx, ('sonde %d m'):format(distance)) end
        end
    end
    return list
end

--- Évalue les candidats : coordonnées, distance, devant/derrière.
local function evaluate(list, pos, fwd, dir)
    local tracks = Utils.JunctionTracks()
    for _, c in ipairs(list) do
        c.name = tracks[c.track] or ('0x%08X'):format(math.floor(c.track % 4294967296))
        c.coords = junctionCoords(c.track, c.index)
        if c.coords then
            local to = c.coords - pos
            c.distance = #to
            c.ahead = (to.x * fwd.x + to.y * fwd.y) * dir > 0
        end
        c.enabled = Junctions.Get(c.track, c.index)
    end
    return list
end

--- Recherche l'aiguillage le plus proche devant le train (appel périodique).
function Junctions.Scan(train, dir)
    if not cfg.enabled or not train or not DoesEntityExist(train) then
        Junctions.current = nil
        return
    end
    local pos = GetEntityCoords(train)
    local fwd = GetEntityForwardVector(train)
    local best = nil
    for _, c in ipairs(evaluate(candidates(train, pos, fwd, dir, false), pos, fwd, dir)) do
        if c.coords and c.ahead and c.distance <= cfg.detectDistance and (not best or c.distance < best.distance) then
            best = c
        end
    end
    if best then best.locked = best.distance < cfg.lockDistance end

    local previous = Junctions.current
    Junctions.current = best
    if best and (not previous or previous.track ~= best.track or previous.index ~= best.index or previous.enabled ~= best.enabled) then
        Junctions.RefreshPrompt()
    end
end

function Junctions.RefreshPrompt()
    local cur = Junctions.current
    if not cur then return end
    Sunny.Prompts.SetText('junction', L('junction_prompt', Junctions.Label(not cur.enabled)))
end

--- Affichage du prompt (appelé chaque frame quand le joueur conduit).
function Junctions.Frame(sharedDrivingGroup)
    local cur = Junctions.current
    if not cur or cur.locked or Junctions.pending or Sunny.UI.open or IsPauseMenuActive() or Sunny.Train.locked then return end
    if sharedDrivingGroup then
        for _, key in ipairs(cfg.keys) do
            if IsControlJustPressed(0, key) then Junctions.Toggle() break end
        end
        return
    end
    local title = L('junction_title', math.floor(cur.distance), Junctions.Label(cur.enabled))
    if Sunny.Prompts.Show('junction', title) then
        Junctions.Toggle()
    end
end

--- Bascule l'aiguillage proposé (synchronisé par le serveur si activé).
function Junctions.Toggle()
    local cur = Junctions.current
    if not cur or Junctions.pending then return end
    local target = not Junctions.Get(cur.track, cur.index)
    if not cfg.sync then
        Junctions.Apply(cur.track, cur.index, target)
        Sunny.Notify(L('junction_switched', Junctions.Label(target)), 'info')
        return
    end
    Junctions.pending = true
    CreateThread(function()
        local res = Sunny.Request('junction:set', { track = cur.track, index = cur.index, enabled = target })
        Junctions.pending = false
        if not res.ok then return Sunny.HandleResult(res) end
        Junctions.Apply(cur.track, cur.index, target)
        Sunny.Notify(res.message, 'info')
    end)
end

function Junctions.Reset()
    Junctions.current = nil
end

--- Données pour la plaque de conduite.
function Junctions.HudInfo()
    local cur = Junctions.current
    if not cur then return nil end
    return { distance = math.floor(cur.distance), label = Junctions.Label(cur.enabled), locked = cur.locked }
end

-- ----------------------------------------------------------------------------
--  Synchronisation
-- ----------------------------------------------------------------------------

RegisterNetEvent('sunny_train:client:junction', function(track, index, enabled)
    Junctions.Apply(track, index, enabled)
end)

CreateThread(function()
    Sunny.Prompts.Create('junction', cfg.keys, L('junction_prompt', Junctions.Label(true)), false)
    if not cfg.enabled or not cfg.sync then return end
    Wait(2000)
    while true do
        local res = Sunny.Request('junction:state')
        if res and res.ok and type(res.data) == 'table' then
            for _, j in ipairs(res.data) do Junctions.Apply(j.track, j.index, j.enabled) end
            break
        end
        Wait(5000)
    end
end)

-- ----------------------------------------------------------------------------
--  Commande de test : /sunnytrain_junction [track index 0|1]
--  Sans argument : liste les aiguillages détectés autour du train occupé.
--  Avec arguments : force une position localement (ex. TRAINS_OLD_WEST01 2 1).
-- ----------------------------------------------------------------------------
RegisterCommand(cfg.debugCommand, function(_, args)
    CreateThread(function()
        if not Sunny.Request('admin:allowed').ok then return end

        if args[1] and args[2] then
            local track = Utils.ResolveHash(args[1])
            Junctions.Apply(track, tonumber(args[2]), args[3] == '1' or args[3] == 'true')
            Sunny.Notify(('Aiguillage %s #%s -> %s'):format(args[1], args[2], Junctions.Label(args[3] == '1' or args[3] == 'true')), 'info')
            return
        end

        local ped = PlayerPedId()
        local train = Sunny.Train.entity or GetVehiclePedIsIn(ped, false)
        if not train or train == 0 then
            Sunny.Notify('Montez dans un train pour sonder les aiguillages.', 'error')
            return
        end
        local pos, fwd = GetEntityCoords(train), GetEntityForwardVector(train)
        local dir = Sunny.Train.entity == train and Sunny.Train.MovingDirection() or 1
        local list = evaluate(candidates(train, pos, fwd, dir, true), pos, fwd, dir)
        print(('[Sunny_train] %d aiguillage(s) détecté(s) :'):format(#list))
        for _, c in ipairs(list) do
            print(('  %-32s index %-3d %-12s %s  dist %s  %s  position %s'):format(
                c.name, c.index, c.source,
                c.coords and ('(%.1f, %.1f, %.1f)'):format(c.coords.x, c.coords.y, c.coords.z) or '(?)',
                c.distance and ('%.0f m'):format(c.distance) or '?',
                c.ahead and 'devant' or 'derrière',
                Junctions.Label(c.enabled)))
        end
        Sunny.Notify(('%d aiguillage(s) — détails dans la console F8'):format(#list), 'info')
    end)
end, false)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if Junctions.changed then Citizen.InvokeNative(N.CLEAR_ALL) end
end)
