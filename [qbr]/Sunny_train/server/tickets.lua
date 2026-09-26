-- ============================================================================
--  Sunny_train - Billets & contrôle (serveur)
--
--  Chaque billet vendu est enregistré en BDD (sunny_train_tickets) ET remis
--  comme item de l'inventaire existant. Au contrôle, l'item est confronté à
--  la BDD : un item sans enregistrement ou aux données divergentes est un faux.
-- ============================================================================

local Tickets = {}
Sunny.Tickets = Tickets

local L = Sunny.L
local Srv, Security, Bridge, Utils = Sunny.Srv, Sunny.Security, Sunny.Bridge, Sunny.Utils
local cfg = Config.Tickets

local STATUS = {
    valid    = { label = 'Valable',            ok = true  },
    used     = { label = 'Déjà poinçonné',     ok = false },
    expired  = { label = 'Périmé',             ok = false },
    forged   = { label = 'Faux billet',        ok = false },
    foreign  = { label = 'Billet nominatif — porteur différent', ok = false },
}

function Tickets.Init()
    if not cfg.enabled then return end
    if cfg.registerItem then Bridge.EnsureItem(cfg.item, cfg.itemDefinition) end
    Bridge.RegisterUsableItem(cfg.item, function(src, item)
        Tickets.ShowToHolder(src, item)
    end)
    if (cfg.purgeAfterDays or 0) > 0 then
        MySQL.query('DELETE FROM `sunny_train_tickets` WHERE `expires_at` < ?', { os.time() - cfg.purgeAfterDays * 86400 })
    end
end

local function stationLabel(key)
    return Config.Stations[key] and Config.Stations[key].label or key
end

local function displayDate(timestamp)
    return os.date('%d/%m/', timestamp) .. tostring(Config.Company.year) .. os.date(' — %H:%M', timestamp)
end

--- Vue NUI d'un billet à partir de la ligne BDD.
-- Champ « route » d'un billet : lignes empruntées séparées par des virgules,
-- ou « correspondance » pour une gare non reliée par le réseau.
local CONNECTION = 'correspondance'

local function routeField(trip)
    if not trip.connected or #trip.lines == 0 then return CONNECTION end
    return table.concat(trip.lines, ',')
end

local function routeLines(field)
    local lines = {}
    for key in tostring(field or ''):gmatch('[^,]+') do lines[#lines + 1] = key end
    return lines
end

local function routeLabel(field)
    if field == CONNECTION then return 'Avec correspondance' end
    local labels = {}
    for i, key in ipairs(routeLines(field)) do labels[i] = Config.Routes[key] and Config.Routes[key].label or key end
    return table.concat(labels, ' › ')
end

local function ticketView(row, status)
    local class = Utils.GetClass(row.class)
    return {
        serial = row.serial,
        holder = row.holder_name,
        from = row.from_station, fromLabel = stationLabel(row.from_station),
        to = row.to_station, toLabel = stationLabel(row.to_station),
        route = row.route, routeLabel = routeLabel(row.route),
        class = row.class, classLabel = class and class.label or row.class,
        price = Utils.Money(tonumber(row.price)),
        issued = displayDate(row.issued_at),
        expires = displayDate(row.expires_at),
        departure = row.depart_at and os.date('%H:%M', row.depart_at) or nil,
        departureId = row.departure_id,
        punched = row.used_at ~= nil,
        status = status,
        statusLabel = STATUS[status] and STATUS[status].label or status,
        valid = STATUS[status] and STATUS[status].ok or false,
    }
end

local function fetch(serial)
    if type(serial) ~= 'string' or #serial > 20 then return nil end
    return MySQL.single.await('SELECT * FROM `sunny_train_tickets` WHERE `serial` = ?', { serial })
end

--- Statut d'un billet (item + BDD).
function Tickets.Evaluate(row, itemInfo, holderCitizenId)
    if not row then return 'forged' end
    if type(itemInfo) == 'table' and (itemInfo.from ~= row.from_station or itemInfo.to ~= row.to_station) then
        return 'forged'
    end
    if cfg.nominative and holderCitizenId and row.citizenid ~= holderCitizenId then return 'foreign' end
    if cfg.singleUse and row.used_at then return 'used' end
    if os.time() > row.expires_at then return 'expired' end
    return 'valid'
end

local function generateSerial()
    for _ = 1, 10 do
        local serial = ('%s-%s%04d'):format(cfg.serialPrefix, string.char(math.random(65, 90), math.random(65, 90)), math.random(0, 9999))
        if not MySQL.scalar.await('SELECT 1 FROM `sunny_train_tickets` WHERE `serial` = ?', { serial }) then
            return serial
        end
    end
    return nil
end

--- Le joueur est-il au guichet de la gare ?
local function atDesk(src, stationKey)
    local station = Config.Stations[stationKey]
    return station and station.ticketDesk and station.services and station.services.tickets
        and Security.IsNear(src, station.ticketDesk.coords, station.ticketDesk.radius)
end

-- ----------------------------------------------------------------------------
--  Guichet
-- ----------------------------------------------------------------------------
--- Départ en vente à ce guichet (programmé, pas encore parti).
local function sellable(d, stationKey)
    return d ~= nil and d.status == 'scheduled' and d.station == stationKey
end

local function classPrices(from, to)
    local prices = {}
    for i, class in ipairs(cfg.classes) do
        prices[i] = { id = class.id, label = class.label, price = Utils.Money(Utils.TicketPrice(from, to, class.id)) }
    end
    return prices
end

--- Gares où descendre pour un départ (celles du trajet, après la gare de départ).
local function departureStops(d)
    local trip = Utils.Trip(d.station, d.destination)
    if not trip or not trip.connected then return {} end
    local stops = {}
    for i = 2, #trip.path do
        local to = trip.path[i]
        local leg = Utils.Trip(d.station, to)
        stops[#stops + 1] = {
            to = to, label = stationLabel(to), region = Config.Stations[to].region or '',
            km = leg and leg.km or 0, prices = classPrices(d.station, to),
        }
    end
    return stops
end

Srv.Register('tickets:office', function(src, payload)
    if not Srv.ready then return Srv.Fail('error_busy') end
    if not cfg.enabled then return Srv.Fail('error_invalid') end
    local stationKey = payload.station
    if not Security.ValidKey(Config.Stations, stationKey) or not atDesk(src, stationKey) then
        return Srv.Fail('error_too_far')
    end
    local departures = {}
    for _, d in pairs(Sunny.Departures.list) do
        if sellable(d, stationKey) then
            departures[#departures + 1] = {
                id = d.id, departAt = d.departAt, timeLabel = Sunny.Departures.TimeLabel(d.departAt),
                destination = d.destination, destinationLabel = stationLabel(d.destination),
                train = d.trainLabel, via = d.via, stops = departureStops(d),
            }
        end
    end
    table.sort(departures, function(x, y) return x.departAt < y.departAt end)
    return {
        ok = true,
        data = {
            station = stationKey,
              departures = departures,
              live = Sunny.Departures.Snapshot(),
            money = Utils.Money(Bridge.GetMoney(src, Config.Framework.ticketAccount)),
            validity = cfg.validityMinutes,
        },
    }
end, { rate = 600 })

Srv.Register('tickets:buy', function(src, payload)
    if not cfg.enabled then return Srv.Fail('error_invalid') end
    local stationKey, toKey, classId = payload.station, payload.to, payload.class
    if not Security.ValidKey(Config.Stations, stationKey) or not Security.ValidKey(Config.Stations, toKey) then
        return Srv.Fail('error_invalid')
    end
    if not atDesk(src, stationKey) then return Srv.Fail('error_too_far') end
    if not Utils.GetClass(classId) then return Srv.Fail('ticket_invalid_class') end

    -- Le billet est vendu pour un départ programmé, vers une gare de son trajet.
    local departure = Sunny.Departures.Get(payload.departure)
    if not sellable(departure, stationKey) then return Srv.Fail('ticket_no_departure') end
    local served = false
    for _, stop in ipairs(departureStops(departure)) do
        if stop.to == toKey then served = true break end
    end
    if not served then return Srv.Fail('ticket_invalid_dest') end
    local trip = Utils.Trip(stationKey, toKey)

    local citizen = Bridge.GetCitizenId(src)
    local active = MySQL.scalar.await(
        'SELECT COUNT(*) FROM `sunny_train_tickets` WHERE `citizenid` = ? AND `used_at` IS NULL AND `expires_at` > ?',
        { citizen, os.time() }) or 0
    if active >= cfg.maxActive then return Srv.Fail('ticket_limit') end

    local price = Utils.TicketPrice(stationKey, toKey, classId)
    local account = Config.Framework.ticketAccount
    if Bridge.GetMoney(src, account) < price then return Srv.Fail('ticket_no_money') end

    local serial = generateSerial()
    if not serial then return Srv.Fail('error_generic') end

    -- Les lectures BDD ci-dessus peuvent laisser passer un départ ou une annulation.
    if not sellable(departure, stationKey) then return Srv.Fail('ticket_no_departure') end
    if not Bridge.RemoveMoney(src, account, price, 'sunny_train_ticket') then
        return Srv.Fail('ticket_no_money')
    end

    local now = os.time()
    local row = {
        serial = serial, citizenid = citizen, holder_name = Bridge.GetName(src),
        from_station = stationKey, to_station = toKey, route = routeField(trip), class = classId,
        price = price, issued_at = now, expires_at = departure.departAt + cfg.validityMinutes * 60,
        departure_id = departure.id, depart_at = departure.departAt,
    }
    local inserted, insertError = pcall(MySQL.insert.await,
        'INSERT INTO `sunny_train_tickets` (`serial`, `citizenid`, `holder_name`, `from_station`, `to_station`, `route`, `class`, `price`, `issued_at`, `expires_at`, `departure_id`, `depart_at`) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)',
        { row.serial, row.citizenid, row.holder_name, row.from_station, row.to_station, row.route, row.class, row.price, row.issued_at, row.expires_at, row.departure_id, row.depart_at })
    if not inserted then
        Bridge.AddMoney(src, account, price, 'sunny_train_ticket_refund')
        error(insertError)
    end

    local class = Utils.GetClass(classId)
    local info = {
        serial = serial,
        from = stationKey, fromLabel = stationLabel(stationKey),
        to = toKey, toLabel = stationLabel(toKey),
        route = row.route, class = classId, classLabel = class.label,
        price = Utils.Money(price), issued = displayDate(now),
        departure = Sunny.Departures.TimeLabel(departure.departAt),
    }
    if not Bridge.AddItem(src, cfg.item, 1, info) then
        -- Remboursement intégral si l'inventaire refuse l'item.
        Bridge.AddMoney(src, account, price, 'sunny_train_ticket_refund')
        MySQL.query('DELETE FROM `sunny_train_tickets` WHERE `serial` = ?', { serial })
        return Srv.Fail('ticket_inventory_full')
    end

    local view = ticketView(row, 'valid')
    if type(Config.Hooks.onTicketSold) == 'function' then pcall(Config.Hooks.onTicketSold, src, view) end
    return { ok = true, message = L('ticket_bought', serial, view.toLabel), data = { ticket = view } }
end, { rate = 1500, lock = function(src) return 'tickets:buy:' .. src end })

--- Utilisation de l'item : le voyageur consulte son billet.
function Tickets.ShowToHolder(src, item)
    local info = item and item.info
    if type(info) ~= 'table' then return end
    local row = fetch(info.serial)
    local status = Tickets.Evaluate(row, info, Bridge.GetCitizenId(src))
    local view = row and ticketView(row, status) or {
        serial = tostring(info.serial or '?'), fromLabel = info.fromLabel or '?', toLabel = info.toLabel or '?',
        classLabel = info.classLabel or '?', price = info.price or '?', issued = info.issued or '?',
        status = 'forged', statusLabel = STATUS.forged.label, valid = false,
    }
    TriggerClientEvent('sunny_train:client:showTicket', src, view)
end

-- ----------------------------------------------------------------------------
--  Contrôle
-- ----------------------------------------------------------------------------

--- Ligne du train sur lequel se trouve le contrôleur (run actif le plus proche).
local function controllerRun(src)
    local pos = Security.PedCoords(src)
    if not pos then return nil end
    local best, bestDist = nil, 120.0
    for _, run in pairs(Sunny.Runs.byId) do
        local entity = Security.EntityFromNet(run.netId)
        local where = entity ~= 0 and GetEntityCoords(entity) or Security.PedCoords(run.src)
        if where then
            local d = #(pos - where)
            if d < bestDist then best, bestDist = run, d end
        end
    end
    return best
end

local function coversJourney(routeKey, fromKey, toKey)
    return Utils.LineCoversTrip(routeKey, Utils.Trip(fromKey, toKey))
end

local function controlGuard(src, target)
    if not Srv.Can(src, 'control') then return Srv.Fail('error_no_permission') end
    target = tonumber(target)
    if not target or target == src or not Bridge.GetPlayer(target) then return Srv.Fail('control_no_target') end
    if Security.DistanceBetween(src, target) > 4.5 then return Srv.Fail('control_target_far') end
    return nil, target
end

Srv.Register('control:check', function(src, payload)
    local fail, target = controlGuard(src, payload.target)
    if fail then return fail end

    local holderCitizen = Bridge.GetCitizenId(target)
    local run = controllerRun(src)
    local line = run and run.route or nil
    local departureId = run and run.departureId or nil
    local list = {}
    for _, item in ipairs(Bridge.GetItemsByName(target, cfg.item)) do
        local info = type(item.info) == 'table' and item.info or {}
        local row = fetch(info.serial)
        local status = Tickets.Evaluate(row, info, holderCitizen)
        local view = row and ticketView(row, status) or {
            serial = tostring(info.serial or '—'), fromLabel = info.fromLabel or '?', toLabel = info.toLabel or '?',
            classLabel = info.classLabel or '?', price = info.price or '?', issued = info.issued or '?',
            status = 'forged', statusLabel = STATUS.forged.label, valid = false,
        }
        if row and line and view.valid and not coversJourney(line, row.from_station, row.to_station) then
            view.warning = 'Non valable sur la ' .. Config.Routes[line].label
        elseif row and view.valid and departureId and row.departure_id and row.departure_id ~= departureId then
            view.warning = 'Billet pour le départ de ' .. (view.departure or '?')
        end
        list[#list + 1] = view
    end
    table.sort(list, function(a, b) return (a.valid and 1 or 0) > (b.valid and 1 or 0) end)

    TriggerClientEvent('sunny_train:client:notify', target, L('control_notify_target'), 'info')
    return {
        ok = true,
        data = {
            target = target,
            passenger = Bridge.GetName(target),
            line = line and Config.Routes[line].label or nil,
            tickets = list,
        },
    }
end, { rate = 1500 })

Srv.Register('control:punch', function(src, payload)
    local fail, target = controlGuard(src, payload.target)
    if fail then return fail end
    if type(payload.serial) ~= 'string' then return Srv.Fail('error_invalid') end

    local held
    for _, item in ipairs(Bridge.GetItemsByName(target, cfg.item)) do
        if type(item.info) == 'table' and item.info.serial == payload.serial then held = item break end
    end
    if not held then return Srv.Fail('control_cannot_punch') end

    local row = fetch(payload.serial)
    if Tickets.Evaluate(row, held.info, Bridge.GetCitizenId(target)) ~= 'valid' then
        return Srv.Fail('control_cannot_punch')
    end
    local now = os.time()
    local affected = MySQL.update.await('UPDATE `sunny_train_tickets` SET `used_at` = ?, `used_by` = ? WHERE `serial` = ? AND `used_at` IS NULL',
        { now, Bridge.GetCitizenId(src), payload.serial })
    if not affected or affected < 1 then return Srv.Fail('control_cannot_punch') end

    -- Relire l'inventaire après l'attente SQL : le billet a pu être déplacé.
    if not Bridge.RemoveTicket(target, cfg.item, payload.serial) then
        MySQL.update.await('UPDATE `sunny_train_tickets` SET `used_at` = NULL, `used_by` = NULL WHERE `serial` = ? AND `used_at` = ? AND `used_by` = ?',
            { payload.serial, now, Bridge.GetCitizenId(src) })
        return Srv.Fail('control_cannot_punch')
    end
    row.used_at = now
    TriggerClientEvent('sunny_train:client:notify', target, L('ticket_punched_notify', payload.serial), 'info')
    local view = ticketView(row, 'used')
    view.justPunched = true
    return { ok = true, message = L('control_punched'), data = { ticket = view } }
end, { rate = 1000 })
