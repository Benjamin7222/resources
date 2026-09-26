-- ============================================================================
--  Sunny_train - Départs programmés (serveur)
--
--  Un départ = « tel train partira de telle gare à HH:MM (heure réelle du
--  serveur) à destination de telle gare ». Il est programmé par un cheminot,
--  ou créé automatiquement par un voyage sans horaire / une mission.
--  - Tableau des départs et guichet : n'affichent / ne vendent que ces départs
--  - Avis aux voyageurs (programmé, à quai, parti, annulé)
--  - Persistés en base (sunny_train_departures) : survivent au redémarrage
--
--  Statuts stockés : scheduled → departed | cancelled. Les statuts affichés
--  (« À l'heure », « Embarquement », « Retardé ») sont calculés à partir de
--  l'heure : la NUI les recalcule chaque seconde.
-- ============================================================================

local Departures = {
    list = {},        -- [id] = départ en attente ou parti récemment
    byRun = {},       -- [runId] = id
}
Sunny.Departures = Departures

local L = Sunny.L
local Srv, Security, Bridge, Utils = Sunny.Srv, Sunny.Security, Sunny.Bridge, Sunny.Utils
local cfg = Config.Departures

local function stationLabel(key)
    return Config.Stations[key] and Config.Stations[key].label or key
end

--- Décalage du fuseau du serveur (s) : les heures affichées sont celles du serveur.
local function tzOffset()
    local now = os.time()
    local utc = os.date('!*t', now)
    utc.isdst = os.date('*t', now).isdst
    return os.difftime(now, os.time(utc))
end

function Departures.TimeLabel(epoch)
    return os.date('%H:%M', epoch)
end

--- Gares du trajet (origine incluse) avec la distance depuis l'origine.
local function tripStops(station, destination)
    local trip = Utils.Trip(station, destination)
    if not trip or not trip.connected then return nil end
    return trip
end

local function public(d)
    local run = d.runId and Sunny.Runs.GetById(d.runId)
    return {
        id = d.id,
        station = d.station, stationLabel = stationLabel(d.station),
        destination = d.destination, destinationLabel = stationLabel(d.destination),
        via = d.via,
        train = d.trainLabel,                -- nil si non précisé
        trainKey = d.trainKey,
        by = d.byName,
        departAt = d.departAt,
        timeLabel = Departures.TimeLabel(d.departAt),
        departed = d.status == 'departed',
        departedAt = d.departedAt,
        atPlatform = run ~= nil and d.status ~= 'departed' and run.state ~= 'assigned',
        linked = d.runId ~= nil,
        auto = d.auto == true,
    }
end

function Departures.Snapshot()
    local list = {}
    for _, d in pairs(Departures.list) do list[#list + 1] = public(d) end
    table.sort(list, function(a, b) return a.departAt < b.departAt end)
    return { list = list, now = os.time(), tz = tzOffset() }
end

local function recipients(stationKey)
    if cfg.audience ~= 'nearby' then return { -1 } end
    local station = Config.Stations[stationKey]
    local targets = {}
    for _, id in ipairs(GetPlayers()) do
        local src = tonumber(id)
        local pos = Security.PedCoords(src)
        if pos and station and #(pos - station.coords) <= cfg.nearbyRadius then targets[#targets + 1] = src end
    end
    return targets
end

--- Diffuse la liste à jour et, si demandé, un avis aux voyageurs.
---@param kind? 'created'|'boarding'|'departed'|'cancelled'
function Departures.Broadcast(d, kind)
    TriggerClientEvent('sunny_train:client:departures', -1, Departures.Snapshot())
    if d and kind and cfg.notify[kind] then
        local notice = public(d)
        notice.kind = kind
        notice.now = os.time()
        for _, target in ipairs(recipients(d.station)) do
            TriggerClientEvent('sunny_train:client:departureNotice', target, notice)
        end
    end
end

local function saveStatus(d)
    MySQL.update('UPDATE `sunny_train_departures` SET `status` = ?, `departed_at` = ?, `train_key` = ? WHERE `id` = ?',
        { d.status, d.departedAt, d.trainKey, d.id })
end

-- Surveillance : départs partis puis retirés, départs jamais partis annulés.
local watching = false
local function watch()
    if watching then return end
    watching = true
    CreateThread(function()
        while next(Departures.list) do
            Wait(15000)
            local now, changed = os.time(), false
            for id, d in pairs(Departures.list) do
                if d.status == 'departed' and now - (d.departedAt or now) > cfg.keepDeparted * 60 then
                    Departures.list[id] = nil
                    changed = true
                elseif d.status == 'scheduled' and not d.runId and now - d.departAt > cfg.expireAfter * 60 then
                    d.status = 'cancelled'
                    saveStatus(d)
                    Departures.list[id] = nil
                    Departures.Broadcast(d, 'cancelled')
                end
            end
            if changed then Departures.Broadcast() end
        end
        watching = false
    end)
end

--- Crée un départ.
--- data : { station, destination, departAt, trainKey?, byCitizen?, byName?, auto?, runId? }
function Departures.Create(data)
    if not cfg.enabled then return nil end
    local trip = tripStops(data.station, data.destination)
    if not trip then return nil end
    local d = {
        station = data.station,
        destination = data.destination,
        departAt = math.floor(data.departAt),
        trainKey = data.trainKey,
        trainLabel = data.trainKey and Config.Trains[data.trainKey] and Config.Trains[data.trainKey].label or nil,
        via = Utils.TripLabel(trip),
        by = data.byCitizen,
        byName = data.byName,
        status = 'scheduled',
        auto = data.auto == true,
    }
    d.id = MySQL.insert.await('INSERT INTO `sunny_train_departures` (`station`, `destination`, `train_key`, `depart_at`, `created_by`, `created_name`, `status`, `auto`) VALUES (?, ?, ?, ?, ?, ?, ?, ?)',
        { d.station, d.destination, d.trainKey, d.departAt, d.by, d.byName or '', d.status, d.auto and 1 or 0 })
    if not d.id then return nil end
    Departures.list[d.id] = d
    if data.runId then
        d.runId = data.runId
        Departures.byRun[data.runId] = d.id
    end
    Departures.Broadcast(d, 'created')
    watch()
    return d
end

function Departures.Get(id)
    return Departures.list[tonumber(id) or -1]
end

--- Départ programmé encore prenable (non parti, non lié à un train).
function Departures.IsAvailable(d)
    return d ~= nil and d.status == 'scheduled' and not d.runId
end

-- Réserver dès l'affectation, avant que le client fasse apparaître le train.
function Departures.Claim(d, run)
    if not Departures.IsAvailable(d) then return false end
    d.runId = run.id
    Departures.byRun[run.id] = d.id
    Departures.Broadcast()
    return true
end

--- Mise en voie d'un train : on le rattache à son départ (ou on en crée un).
function Departures.ForRun(run, leadMinutes)
    if not cfg.enabled then return end
    local d = run.departureId and Departures.list[run.departureId]
    if d and d.status == 'scheduled' and (d.runId == run.id or Departures.IsAvailable(d)) then
        d.runId = run.id
        Departures.byRun[run.id] = d.id
        if not d.trainKey then
            d.trainKey = run.train
            d.trainLabel = Config.Trains[run.train].label
            saveStatus(d)
        end
        Departures.Broadcast(d, 'boarding')
        return
    end
    -- Voyage sans horaire / mission : départ créé automatiquement.
    local destination = run.free and run.destination or Utils.RouteTerminus(run.route)
    local created = Departures.Create({
        station = run.origin,
        destination = destination,
        departAt = os.time() + math.floor((leadMinutes or 0) * 60),
        trainKey = run.train,
        byCitizen = run.citizenid,
        byName = Bridge.GetName(run.src),
        auto = true,
        runId = run.id,
    })
    if created then run.departureId = created.id end
end

--- Le train a quitté sa gare d'origine.
function Departures.Departed(run)
    local id = Departures.byRun[run.id]
    local d = id and Departures.list[id]
    if not d or d.status ~= 'scheduled' then return end
    d.status = 'departed'
    d.departedAt = os.time()
    saveStatus(d)
    Departures.Broadcast(d, 'departed')
end

--- Fin d'un run avant le départ : un départ créé automatiquement est annulé,
--- un départ programmé à la main redevient disponible pour un autre train.
function Departures.OnRunClosed(run)
    local id = Departures.byRun[run.id]
    if not id then return end
    Departures.byRun[run.id] = nil
    local d = Departures.list[id]
    if not d or d.status ~= 'scheduled' then return end
    d.runId = nil
    if d.auto then
        d.status = 'cancelled'
        saveStatus(d)
        Departures.list[id] = nil
        Departures.Broadcast(d, 'cancelled')
    else
        Departures.Broadcast()
    end
end

--- Chargement au démarrage (départs encore à venir).
function Departures.Load()
    local rows = MySQL.query.await('SELECT * FROM `sunny_train_departures` WHERE `status` = ? AND `depart_at` > ?',
        { 'scheduled', os.time() - cfg.expireAfter * 60 }) or {}
    for _, row in ipairs(rows) do
        if Config.Stations[row.station] and Config.Stations[row.destination] then
            local trip = tripStops(row.station, row.destination)
            local key = row.train_key ~= '' and row.train_key or nil
            if key and not Config.Trains[key] then key = nil end
            Departures.list[row.id] = {
                id = row.id, station = row.station, destination = row.destination,
                departAt = row.depart_at, trainKey = key,
                trainLabel = key and Config.Trains[key] and Config.Trains[key].label or nil,
                via = trip and Utils.TripLabel(trip) or '', by = row.created_by, byName = row.created_name,
                status = 'scheduled', auto = tonumber(row.auto) == 1,
            }
        end
    end
    if next(Departures.list) then watch() end
end

-- ----------------------------------------------------------------------------
--  Horaires proposés (grille alignée sur Config.Departures.slotStep)
-- ----------------------------------------------------------------------------
function Departures.Slots()
    local step = cfg.slotStep * 60
    local first = math.ceil((os.time() + cfg.minLead * 60) / step) * step
    local slots = {}
    for i = 0, cfg.slotCount - 1 do
        local at = first + i * step
        slots[#slots + 1] = { at = at, label = Departures.TimeLabel(at), inMinutes = math.floor((at - os.time()) / 60) }
    end
    return slots
end

local function validSlot(at)
    at = tonumber(at)
    if not at or at % (cfg.slotStep * 60) ~= 0 then return false end
    local now = os.time()
    return at >= now + cfg.minLead * 60 - cfg.slotStep * 60 and at <= now + (cfg.minLead + cfg.slotStep * cfg.slotCount) * 60
end

-- ----------------------------------------------------------------------------
--  Requêtes
-- ----------------------------------------------------------------------------

Srv.Register('departure:options', function(src, payload)
    if not cfg.enabled then return Srv.Fail('error_invalid') end
    if not Srv.Can(src, 'schedule') then return Srv.Fail('error_no_permission') end
    local trains = {}
    for key, train in pairs(Config.Trains) do
        if Sunny.Fleet.IsOwned(key) then trains[#trains + 1] = { key = key, label = train.label, category = train.category or '', tier = train.tier or 0 } end
    end
    table.sort(trains, function(a, b) return a.tier < b.tier end)
    return { ok = true, data = { slots = Departures.Slots(), trains = trains } }
end, { rate = 800 })

Srv.Register('departure:create', function(src, payload)
    if not cfg.enabled then return Srv.Fail('error_invalid') end
    if not Srv.Can(src, 'schedule') then return Srv.Fail('error_no_permission') end
    if not Srv.IsOnService(src) then return Srv.Fail('error_not_on_service') end
    local station, destination = payload.station, payload.destination
    if not Security.ValidKey(Config.Stations, station) or not Security.ValidKey(Config.Stations, destination) or station == destination then
        return Srv.Fail('dep_invalid')
    end
    if not Srv.AtOffice(src, station) then return Srv.Fail('error_too_far') end
    if not tripStops(station, destination) then return Srv.Fail('free_invalid_dest') end
    if not validSlot(payload.departAt) then return Srv.Fail('dep_bad_time') end
    local trainKey = payload.train
    if trainKey ~= nil and (not Security.ValidKey(Config.Trains, trainKey) or not Sunny.Fleet.IsOwned(trainKey)) then
        return Srv.Fail('dep_invalid')
    end

    local citizen = Bridge.GetCitizenId(src)
    local mine = 0
    for _, d in pairs(Departures.list) do
        if d.by == citizen and d.status == 'scheduled' and not d.auto then mine = mine + 1 end
    end
    if mine >= cfg.maxPerPlayer then return Srv.Fail('dep_limit', cfg.maxPerPlayer) end
    for _, d in pairs(Departures.list) do
        if d.station == station and d.departAt == tonumber(payload.departAt) and d.status == 'scheduled' then
            return Srv.Fail('dep_slot_taken', Departures.TimeLabel(d.departAt))
        end
    end

    local d = Departures.Create({
        station = station, destination = destination, departAt = tonumber(payload.departAt),
        trainKey = trainKey, byCitizen = citizen, byName = Bridge.GetName(src),
    })
    if not d then return Srv.Fail('error_generic') end
    return { ok = true, message = L('dep_created', stationLabel(station), stationLabel(destination), Departures.TimeLabel(d.departAt)) }
end, { rate = 1500, lock = 'departure:create' })

Srv.Register('departure:cancel', function(src, payload)
    local d = Departures.Get(payload.id)
    if not d or d.status ~= 'scheduled' then return Srv.Fail('dep_invalid') end
    if not Srv.Can(src, 'schedule') then return Srv.Fail('error_no_permission') end
    if d.by ~= Bridge.GetCitizenId(src) and not Srv.Can(src, 'restore') then return Srv.Fail('error_no_permission') end
    if d.runId then return Srv.Fail('dep_in_progress') end
    d.status = 'cancelled'
    saveStatus(d)
    Departures.list[d.id] = nil
    Departures.Broadcast(d, 'cancelled')
    return { ok = true, message = L('dep_cancelled', Departures.TimeLabel(d.departAt)) }
end, { rate = 1000 })

--- Liste publique (tableaux des départs, joueurs qui se connectent).
Srv.Register('departure:list', function()
    if not Srv.ready then return Srv.Fail('error_busy') end
    return { ok = true, data = Departures.Snapshot() }
end, { rate = 1000 })
