-- ============================================================================
--  Sunny_train - Utilitaires partagés (client + serveur)
--  Fonctions pures : aucune ne fait confiance au client, le serveur les
--  réutilise pour recalculer lui-même prix, états et droits.
-- ============================================================================

Sunny = Sunny or {}
Sunny.Utils = {}

local Utils = Sunny.Utils

Sunny.TrainStates = {
    operational      = 'Opérationnel',
    needs_maintenance = 'Maintenance nécessaire',
    damaged          = 'Endommagé',
    out_of_service   = 'Hors service',
}

Sunny.RunStates = {
    assigned   = 'Mise en voie',
    ready      = 'À quai — prêt au départ',
    enroute    = 'En circulation',
    at_station = 'Arrêt en gare',
    robbery    = 'Convoi attaqué',
    arrived    = 'Arrivé au terminus',
}

function Utils.Debug(...)
    if Config.Debug then
        print('^3[Sunny_train]^7', ...)
    end
end

function Utils.Round(value, decimals)
    local mult = 10 ^ (decimals or 0)
    return math.floor(value * mult + 0.5) / mult
end

function Utils.Money(value)
    return string.format('%.2f', value or 0)
end

--- Normalise un hash en entier signé 32 bits (les natives renvoient des
--- valeurs signées, GetHashKey peut renvoyer du non signé selon le côté).
function Utils.Signed32(value)
    -- Arithmétique pure (pas d'opérateur binaire) : sûr quelle que soit la
    -- taille des entiers de la VM.
    value = math.floor(tonumber(value) or 0) % 4294967296
    if value >= 2147483648 then value = value - 4294967296 end
    return math.tointeger(value) or value
end

--- Résout un hash : nombre, chaîne hexadécimale ('0x10461E19') ou nom.
function Utils.ResolveHash(value)
    if type(value) == 'number' then return Utils.Signed32(value) end
    if type(value) == 'string' then
        if value:match('^0[xX]%x+$') then return Utils.Signed32(tonumber(value)) end
        return Utils.Signed32(GetHashKey(value))
    end
    return 0
end

--- Réseaux de voies autorisés pour les aiguillages : [hash signé] = nom.
function Utils.JunctionTracks()
    if not Utils._tracks then
        Utils._tracks = {}
        for _, name in ipairs(Config.Junctions.tracks or {}) do
            Utils._tracks[Utils.ResolveHash(name)] = name
        end
    end
    return Utils._tracks
end

function Utils.Count(tbl)
    local n = 0
    for _ in pairs(tbl or {}) do n = n + 1 end
    return n
end

function Utils.VecToTable(v)
    if not v then return nil end
    return { x = v.x + 0.0, y = v.y + 0.0, z = v.z + 0.0 }
end

function Utils.Dist(a, b)
    local dx, dy, dz = a.x - b.x, a.y - b.y, (a.z or 0) - (b.z or 0)
    return math.sqrt(dx * dx + dy * dy + dz * dz)
end

--- Droit d'accès à partir d'une table { job = gradeMin }.
function Utils.HasJobAccess(permTable, jobName, gradeLevel)
    if type(permTable) ~= 'table' or type(jobName) ~= 'string' then return false end
    -- Comparaison insensible à la casse (Job Creator peut enregistrer « Railroad »).
    local wanted = jobName:lower()
    for name, minGrade in pairs(permTable) do
        if tostring(name):lower() == wanted then
            return (tonumber(gradeLevel) or 0) >= (tonumber(minGrade) or 0)
        end
    end
    return false
end

--- Points où le personnel accède au registre d'une gare : le bureau s'il
--- existe, et TOUJOURS le guichet (accès garanti même sans bureau configuré).
function Utils.StaffPoints(station)
    local points = {}
    if station.office then points[#points + 1] = station.office end
    if station.ticketDesk then points[#points + 1] = station.ticketDesk end
    return points
end

--- Gare où un train peut être remisé depuis `pos` (dépôt ou quai à portée),
--- ou nil. Avec parkRadius = 0, le remisage est permis partout.
function Utils.ParkingStation(pos)
    local radius = Config.FreeTravel.parkRadius or 0
    if radius <= 0 then return true end
    for key, station in pairs(Config.Stations) do
        for _, point in ipairs({ station.depot, station.platform }) do
            if point and point.coords and #(pos - point.coords) <= radius then return key end
        end
    end
    return nil
end

--- État affiché d'un train à partir de son état général et de son statut.
function Utils.TrainState(condition, status)
    condition = tonumber(condition) or 100
    if status == 'out_of_service' or condition <= 0 then return 'out_of_service' end
    local t = Config.Maintenance.thresholds
    if condition < t.damaged then return 'damaged' end
    if condition < t.needsMaintenance then return 'needs_maintenance' end
    return 'operational'
end

--- Index d'une gare dans une ligne (nil si absente).
function Utils.StationIndex(routeKey, stationKey)
    local route = Config.Routes[routeKey]
    if not route then return nil end
    for i, stop in ipairs(route.stations) do
        if stop.id == stationKey then return i end
    end
    return nil
end

function Utils.RouteOrigin(routeKey)
    local route = Config.Routes[routeKey]
    return route and route.stations[1] and route.stations[1].id or nil
end

function Utils.RouteTerminus(routeKey)
    local route = Config.Routes[routeKey]
    return route and route.stations[#route.stations] and route.stations[#route.stations].id or nil
end

function Utils.TrainServesRoute(train, routeKey)
    for _, r in ipairs(train.routes or {}) do
        if r == routeKey then return true end
    end
    return false
end

function Utils.TrainAcceptsType(train, missionType)
    for _, t in ipairs(train.serviceTypes or {}) do
        if t == missionType then return true end
    end
    return false
end

function Utils.GetClass(classId)
    for _, class in ipairs(Config.Tickets.classes) do
        if class.id == classId then return class end
    end
    return nil
end

-- ----------------------------------------------------------------------------
--  Réseau & tarification des billets
--  Graphe : chaque tronçon entre deux gares consécutives d'une ligne est une
--  arête dans les deux sens (longueur = distance entre les gares). Le prix
--  suit le plus court chemin : Saint Denis → Annesburg coûte moins cher que
--  Saint Denis → Valentine.
-- ----------------------------------------------------------------------------

local network = nil

local function stationPos(key)
    local s = Config.Stations[key]
    return s and ((s.platform and s.platform.coords) or s.coords)
end

--- Graphe du réseau (construit une fois, la config est statique).
function Utils.Network()
    if network then return network end
    network = {}
    for routeKey, route in pairs(Config.Routes) do
        for i = 1, #route.stations - 1 do
            local a, b = route.stations[i].id, route.stations[i + 1].id
            local pa, pb = stationPos(a), stationPos(b)
            if pa and pb then
                local d = Utils.Dist(pa, pb)
                network[a] = network[a] or {}
                network[b] = network[b] or {}
                network[a][#network[a] + 1] = { to = b, meters = d, line = routeKey }
                network[b][#network[b] + 1] = { to = a, meters = d, line = routeKey }
            end
        end
    end
    return network
end

--- Plus court chemin (Dijkstra) : mètres + lignes empruntées, ou nil.
local function shortestPath(fromKey, toKey)
    local graph = Utils.Network()
    local dist, prev, done = { [fromKey] = 0 }, {}, {}
    while true do
        local node, best = nil, math.huge
        for key, d in pairs(dist) do
            if not done[key] and d < best then node, best = key, d end
        end
        if not node then return nil end
        if node == toKey then break end
        done[node] = true
        for _, edge in ipairs(graph[node] or {}) do
            local nd = best + edge.meters
            local known = dist[edge.to]
            -- À distance égale, on préfère rester sur la même ligne (moins de changements).
            local sameLine = prev[node] and prev[node].line == edge.line
            if not known or nd < known - 0.5 or (math.abs(nd - known) <= 0.5 and sameLine) then
                dist[edge.to] = nd
                prev[edge.to] = { from = node, line = edge.line }
            end
        end
    end
    -- Lignes empruntées, dans l'ordre, sans doublon consécutif.
    local lines, path, node = {}, { toKey }, toKey
    while prev[node] do
        local line = prev[node].line
        if lines[1] ~= line then table.insert(lines, 1, line) end
        node = prev[node].from
        table.insert(path, 1, node)
    end
    return dist[toKey], lines, path
end

local tripCache = {}

--- Informations de trajet entre deux gares.
---@return table|nil { meters, km, lines = { routeKey... }, connected }
function Utils.Trip(fromKey, toKey)
    if fromKey == toKey or not Config.Stations[fromKey] or not Config.Stations[toKey] then return nil end
    local cacheKey = fromKey .. '>' .. toKey
    if tripCache[cacheKey] ~= nil then return tripCache[cacheKey] or nil end

    local meters, lines, path = shortestPath(fromKey, toKey)
    local trip
    if meters then
        trip = { meters = meters, lines = lines, path = path, connected = true }
    else
        local factor = Config.Tickets.pricing.unconnectedFactor
        if factor then
            trip = { meters = Utils.Dist(stationPos(fromKey), stationPos(toKey)) * factor, lines = {}, path = { fromKey, toKey }, connected = false }
        end
    end
    if trip then trip.km = Utils.Round(trip.meters / 1000, 1) end
    tripCache[cacheKey] = trip or false
    return trip
end

--- Prix d'un billet (serveur autoritaire ; la NUI ne fait qu'afficher).
function Utils.TicketPrice(fromKey, toKey, classId)
    local class = Utils.GetClass(classId)
    local trip = Utils.Trip(fromKey, toKey)
    if not class or not trip then return nil end
    local p = Config.Tickets.pricing
    local raw = math.max(p.base + p.perKm * (trip.meters / 1000), p.minimum) * class.multiplier
    local step = p.roundTo or 0.05
    return Utils.Round(math.floor(raw / step + 0.5) * step, 2)
end

--- Une ligne dessert-elle au moins un tronçon du trajet (dans un sens ou l'autre) ?
function Utils.LineCoversTrip(routeKey, trip)
    if not trip or not trip.connected then return true end
    for i = 1, #trip.path - 1 do
        local a, b = Utils.StationIndex(routeKey, trip.path[i]), Utils.StationIndex(routeKey, trip.path[i + 1])
        if a and b and math.abs(a - b) == 1 then return true end
    end
    return false
end

--- Libellé des lignes d'un trajet.
function Utils.TripLabel(trip)
    if not trip then return '' end
    if not trip.connected then return 'Avec correspondance' end
    local labels = {}
    for i, station in ipairs(trip.path) do labels[i] = Config.Stations[station] and Config.Stations[station].label or station end
    return table.concat(labels, ' › ')
end

--- Toutes les gares accessibles depuis une gare, de la plus proche à la plus lointaine.
---@return table list { to, trip }
function Utils.Destinations(fromKey)
    local list = {}
    for key in pairs(Config.Stations) do
        local trip = Utils.Trip(fromKey, key)
        if trip then list[#list + 1] = { to = key, trip = trip } end
    end
    table.sort(list, function(a, b) return a.trip.meters < b.trip.meters end)
    return list
end

--- Somme des temps minimaux de parcours (anti-téléportation) entre 2 gares.
function Utils.MinSegmentSeconds(fromKey, toKey, maxSpeed)
    local a, b = Config.Stations[fromKey], Config.Stations[toKey]
    if not a or not b then return 0 end
    local pa = (a.platform and a.platform.coords) or a.coords
    local pb = (b.platform and b.platform.coords) or b.coords
    local distance = Utils.Dist(pa, pb) - ((a.platform and a.platform.radius or 0) + (b.platform and b.platform.radius or 0))
    if distance <= 0 then return 0 end
    local speed = (maxSpeed or 20.0) * (Config.MissionSettings.speedTolerance or 1.35)
    return math.floor(distance / speed)
end

--- Données statiques envoyées à la NUI (aucune fonction, aucun vector).
function Utils.PublicData()
    local stations, routes, missionTypes, classes = {}, {}, {}, {}
    for key, s in pairs(Config.Stations) do
        local destinations = {}
        for _, d in ipairs(Utils.Destinations(key)) do
            if d.trip.connected then
                destinations[#destinations + 1] = {
                    to = d.to, label = Config.Stations[d.to].label, region = Config.Stations[d.to].region or '',
                    km = d.trip.km, via = Utils.TripLabel(d.trip),
                }
            end
        end
        stations[key] = {
            key = key, label = s.label, region = s.region or '',
            services = s.services or {},
            hasDepot = s.depot ~= nil, destinations = destinations,
        }
    end
    for key, r in pairs(Config.Routes) do
        local list = {}
        for i, stop in ipairs(r.stations) do
            list[i] = { id = stop.id, label = Config.Stations[stop.id] and Config.Stations[stop.id].label or stop.id, stop = stop.stop or 0, eta = stop.eta or 0 }
        end
        routes[key] = {
            key = key, label = r.label, color = r.color or '#6b2a1a', stations = list,
            duration = r.duration or 0,
            delivery = r.delivery == true,
        }
    end
    for key, t in pairs(Config.MissionTypes) do missionTypes[key] = t.label end
    for i, c in ipairs(Config.Tickets.classes) do classes[i] = { id = c.id, label = c.label, multiplier = c.multiplier, description = c.description or '' } end
    return {
        company = Config.Company,
        stations = stations,
        routes = routes,
        missionTypes = missionTypes,
        classes = classes,
        trainStates = Sunny.TrainStates,
        runStates = Sunny.RunStates,
        use24h = Config.UI.use24h,
        browserGamepad = Config.UI.browserGamepad,
        boardingWindow = Config.Departures.boardingWindow,
    }
end

--- Vérifie la cohérence de la configuration et renvoie la liste des erreurs.
function Utils.ValidateConfig()
    local errors = {}
    local function err(msg, ...) errors[#errors + 1] = string.format(msg, ...) end

    for routeKey, route in pairs(Config.Routes) do
        if type(route.stations) ~= 'table' or #route.stations < 2 then
            err('Ligne "%s" : au moins 2 gares requises.', routeKey)
        else
            for _, stop in ipairs(route.stations) do
                if not Config.Stations[stop.id] then err('Ligne "%s" : gare inconnue "%s".', routeKey, tostring(stop.id)) end
            end
            local origin = Config.Stations[route.stations[1].id]
            if origin and not origin.depot then
                err('Ligne "%s" : la gare de départ "%s" n\'a pas de depot.', routeKey, route.stations[1].id)
            end
        end
    end
    for trainKey, train in pairs(Config.Trains) do
        if not train.model then err('Train "%s" : modèle manquant.', trainKey) end
        for _, r in ipairs(train.routes or {}) do
            if not Config.Routes[r] then err('Train "%s" : ligne inconnue "%s".', trainKey, r) end
        end
        for _, t in ipairs(train.serviceTypes or {}) do
            if not Config.MissionTypes[t] then err('Train "%s" : type de service inconnu "%s".', trainKey, t) end
        end
    end
    for missionKey, mission in pairs(Config.Missions) do
        if not Config.Routes[mission.route] then err('Mission "%s" : ligne inconnue "%s".', missionKey, tostring(mission.route)) end
        if not Config.MissionTypes[mission.type] then err('Mission "%s" : type inconnu "%s".', missionKey, tostring(mission.type)) end
        if type(mission.reward) ~= 'number' or mission.reward < 0 then err('Mission "%s" : récompense invalide.', missionKey) end
    end
    if #Config.Tickets.classes == 0 then err('Config.Tickets.classes est vide.') end
    return errors
end
