-- ============================================================================
--  Sunny_train - Runs & missions (serveur, autoritaire)
--
--  Machine à états d'un run (un seul par conducteur) :
--    assigned  -> le serveur a validé train + mission, le client met en voie
--    ready     -> train à quai à la gare d'origine (netId enregistré)
--    enroute   -> en circulation vers nextIndex
--    at_station-> arrêt validé, temps d'arrêt en cours
--    robbery   -> convoi attaqué (voir robbery.lua)
--    arrived   -> terminus atteint, prêt à être clôturé
--
--  Le client ne transmet JAMAIS de montant, de prime ni d'état : seulement des
--  intentions (« je suis à quai à l'arrêt n »), que le serveur vérifie
--  (position du conducteur, entité, temps minimal de parcours, ordre).
-- ============================================================================

local Runs = {
    bySource = {},     -- [src] = run
    byId = {},         -- [runId] = run
    trainInUse = {},   -- [trainKey] = runId
    cooldowns = {},    -- [citizenid] = os.time() de fin de cooldown
    nextId = 0,
}
Sunny.Runs = Runs

local L = Sunny.L
local Srv, Security, Bridge, Utils = Sunny.Srv, Sunny.Security, Sunny.Bridge, Sunny.Utils
local settings = Config.MissionSettings

-- Une réservation couvre les attentes SQL, y compris entre voyage et livraison.
local pendingSources, pendingTrains = {}, {}
local function registerStart(name, fn, opts)
    Srv.Register(name, function(src, payload)
        local train = payload.train
        if type(train) ~= 'string' then return Srv.Fail('error_invalid') end
        if pendingSources[src] or pendingTrains[train] then return Srv.Fail('error_busy') end
        pendingSources[src], pendingTrains[train] = true, true
        local ok, result = pcall(fn, src, payload)
        pendingSources[src], pendingTrains[train] = nil, nil
        if not ok then error(result) end
        return result
    end, opts)
end

-- ----------------------------------------------------------------------------
--  Accès
-- ----------------------------------------------------------------------------

function Runs.Get(src) return Runs.bySource[src] end
function Runs.GetById(id) return Runs.byId[id] end
function Runs.IsTrainInUse(trainKey) return Runs.trainInUse[trainKey] ~= nil end

--- Arrêts d'un run : ligne de la mission, ou chemin sur le réseau (voyage libre).
local function runStops(run)
    if run.free then return run.stops end
    return Config.Routes[run.route].stations
end

local function stationOf(run, index)
    local stop = runStops(run)[index]
    return stop, stop and Config.Stations[stop.id]
end

local function platformOf(station)
    if station.platform then return station.platform.coords, station.platform.radius or 50.0 end
    return station.coords, 50.0
end

--- Résumé d'un run pour la NUI / le client.
function Runs.Summary(src)
    local run = Runs.bySource[src]
    if not run then return nil end
    local route = run.route and Config.Routes[run.route]
    local train = Config.Trains[run.train]
    local mission = run.mission and Config.Missions[run.mission]
    local stations = {}
    for i, stop in ipairs(runStops(run)) do
        stations[i] = {
            id = stop.id,
            label = Config.Stations[stop.id].label,
            stop = stop.stop or 0,
            served = i < run.nextIndex or (i == run.nextIndex and (run.state == 'at_station' or run.state == 'arrived')),
            current = i == run.nextIndex,
        }
    end
    local _, nextStation = stationOf(run, run.nextIndex)
    return {
        id = run.id,
        state = run.state,
        stateLabel = Sunny.RunStates[run.state] or run.state,
        train = run.train,
        trainLabel = train.label,
        mission = run.mission,
        missionLabel = run.free and L('free_label') or (mission and mission.label or '—'),
        missionType = run.free and 'Voyage' or (mission and Config.MissionTypes[mission.type].label or '—'),
        free = run.free == true,
        origin = run.origin,
        destination = run.destination,
        destinationLabel = run.destination and Config.Stations[run.destination].label or nil,
        route = run.route,
        routeLabel = run.free and run.tripLabel or route.label,
        nextIndex = run.nextIndex,
        nextStation = nextStation and nextStation.label or '',
        stations = stations,
        elapsed = run.startedAt and (os.time() - run.startedAt) or 0,
        timeLimit = mission and mission.timeLimit or 0,
        robbed = run.robbed,
        canBeRobbed = Runs.IsRobbable(run),
        condition = Sunny.Fleet.Get(run.train).condition,
        trainState = Sunny.Fleet.State(run.train),
        coal = run.coal,
        noFuel = run.noFuel == true,
        needsCoal = run.needsCoal == true,
        company = mission and mission.company or nil,
        cargo = run.cargoView,
    }
end

-- ----------------------------------------------------------------------------
--  Charbon & wagon
-- ----------------------------------------------------------------------------

local function needsCoal(trainKey)
    return Config.Fuel.enabled and Config.Trains[trainKey].fuel ~= false
end

local function cargoView(list)
    local view = {}
    for i, c in ipairs(list or {}) do view[i] = { item = c.item, label = Bridge.ItemLabel(c.item), amount = c.amount } end
    return view
end

--- Liste publique des trains en circulation (ox_target : ouvrir le wagon).
function Runs.PublishActive()
    local list = {}
    for id, run in pairs(Runs.byId) do
        if run.netId then list[#list + 1] = { runId = id, netId = run.netId, train = run.train, driver = run.src } end
    end
    GlobalState.sunnyTrains = list
end

--- Consommation de charbon : distance réellement parcourue par le conducteur
--- dans son train (relevée côté serveur), convertie en charbon prélevé du wagon.
local function burnCoal(run, now)
    if not run.needsCoal or run.state == 'assigned' then return end
    if now - (run.fuelSampleAt or 0) < Config.Fuel.checkInterval then return end
    local ped = GetPlayerPed(run.src)
    local pos = Security.PedCoords(run.src)
    if not pos or ped == 0 then return end
    local inVehicle = GetVehiclePedIsIn(ped, false) ~= 0
    if run.fuelPos and inVehicle then
        local elapsed = now - (run.fuelSampleAt or now)
        local cap = (Config.Trains[run.train].maxSpeed or 20) * 1.5 * math.max(elapsed, 1)
        run.fuelMeters = (run.fuelMeters or 0) + math.min(#(pos - run.fuelPos), cap)
    end
    run.fuelPos, run.fuelSampleAt = pos, now

    local perCoal = 1000 / math.max(Config.Trains[run.train].coalPerKm or 2, 0.01)
    local burn = math.floor((run.fuelMeters or 0) / perCoal)
    if burn <= 0 or run.noFuel then return end
    local id = Sunny.Hold.Id(run.train)
    if Sunny.Hold.IsOpen(id) then return end -- prélevé à la fermeture du wagon
    local have = Sunny.Hold.Count(Sunny.Hold.Read(id), Config.Fuel.item)
    local take = math.min(burn, have)
    if take > 0 and not Sunny.Hold.Take(id, { { item = Config.Fuel.item, amount = take } }) then return end
    run.fuelMeters = run.fuelMeters - burn * perCoal
    run.coal = have - take
    if run.coal <= 0 then
        run.noFuel = true
        run.fuelMeters = 0
    end
    TriggerClientEvent('sunny_train:client:fuel', run.src, { coal = run.coal, empty = run.noFuel })
end

--- Le wagon d'un train vient d'être refermé : recompte du charbon.
function Runs.OnHoldChanged(trainKey)
    if not trainKey then return end
    for _, run in pairs(Runs.byId) do
        if run.train == trainKey and run.needsCoal then
            run.coal = Sunny.Hold.Count(Sunny.Hold.Read(Sunny.Hold.Id(trainKey)), Config.Fuel.item)
            if run.coal > 0 then run.noFuel = false end
            TriggerClientEvent('sunny_train:client:fuel', run.src, { coal = run.coal, empty = run.noFuel == true })
        end
    end
end

function Runs.IsRobbable(run)
    if not Config.Robbery.enabled or not run.mission or run.robbed then return false end
    local mission = Config.Missions[run.mission]
    local train = Config.Trains[run.train]
    return mission.canBeRobbed == true and train.allowRobbery == true
end

-- ----------------------------------------------------------------------------
--  Nettoyage
-- ----------------------------------------------------------------------------

local function deleteTrainEntity(run, delay)
    local netId = run.netId
    local owner = run.src
    if not netId then return end
    TriggerClientEvent('sunny_train:client:deleteTrain', owner, netId, delay)
    -- Filet de sécurité : suppression serveur si le client ne l'a pas fait.
    SetTimeout((delay + 4) * 1000, function()
        local entity = Security.EntityFromNet(netId)
        if entity ~= 0 then DeleteEntity(entity) end
    end)
end

--- Termine un run (succès, échec ou annulation) et libère le train.
---@param reason 'finished'|'cancelled'|'failed'|'dropped'
function Runs.Close(run, reason, message, deleteDelay)
    if not run or not Runs.byId[run.id] then return end
    Runs.byId[run.id] = nil
    if Runs.bySource[run.src] == run then Runs.bySource[run.src] = nil end
    if Runs.trainInUse[run.train] == run.id then Runs.trainInUse[run.train] = nil end
    Sunny.Robbery.OnRunClosed(run)
    Sunny.Departures.OnRunClosed(run)
    -- Cargaison restituée au wagon si le train n'est jamais parti
    -- (annulation, échec de mise en voie, déconnexion avant le départ).
    if run.cargo and #run.cargo > 0 and not run.departed and not run.robbed and reason ~= 'finished' then
        local id = Sunny.Hold.Id(run.train)
        if not Sunny.Hold.Put(id, run.cargo, Config.Trains[run.train].hold.slots) then
            SetTimeout(5000, function() Sunny.Hold.Put(id, run.cargo, Config.Trains[run.train].hold.slots) end)
        end
    end
    deleteTrainEntity(run, deleteDelay or 0)
    Runs.PublishActive()
    if reason ~= 'dropped' then
        TriggerClientEvent('sunny_train:client:runClosed', run.src, { reason = reason, message = message })
    end
    Utils.Debug(('Run %d fermé (%s)'):format(run.id, reason))
end

function Runs.Fail(run, reasonText)
    Runs.Close(run, 'failed', L('run_failed', reasonText), 2)
    if run.citizenid and not (run.mission and Config.Missions[run.mission].delivery) then Runs.cooldowns[run.citizenid] = os.time() + settings.cancelCooldown end
end

-- ----------------------------------------------------------------------------
--  Surveillance (uniquement tant qu'au moins un run existe)
-- ----------------------------------------------------------------------------
local watchdogRunning = false

local function watchRun(run, now)
    if run.state == 'assigned' then
        if now - run.createdAt > settings.spawnTimeout then
            Runs.Close(run, 'failed', L('run_spawn_failed'), 0)
        end
        return
    end

    local mission = run.mission and Config.Missions[run.mission]
    if mission and (mission.hardTimeout or 0) > 0 and run.startedAt
        and now - run.startedAt > mission.hardTimeout * 60 and run.state ~= 'arrived' then
        return Runs.Fail(run, L('run_timeout'))
    end

    local entity = Security.EntityFromNet(run.netId)
    if entity ~= 0 then
        run.entitySeen = true
        run.missingSince = nil
        local grace = (run.free and Config.FreeTravel.exitCabGrace or Config.Driving.exitCabGrace) or 0
        if grace > 0 and (run.state == 'enroute' or run.free) then
            local ped = GetPlayerPed(run.src)
            if ped ~= 0 and GetVehiclePedIsIn(ped, false) ~= entity then
                run.outOfCabSince = run.outOfCabSince or now
                if now - run.outOfCabSince > grace then
                    if run.free then return Runs.Close(run, 'finished', L('free_parked_auto'), 0) end
                    return Runs.Fail(run, 'le conducteur a abandonné la cabine')
                end
            else
                run.outOfCabSince = nil
            end
        end
    elseif run.entitySeen then
        -- Train déjà vu côté serveur puis disparu (détruit / supprimé).
        run.missingSince = run.missingSince or now
        if now - run.missingSince > 20 then
            if run.free then return Runs.Close(run, 'finished', L('run_train_lost'), 0) end
            return Runs.Fail(run, L('run_train_lost'))
        end
    end
end

local function ensureWatchdog()
    if watchdogRunning then return end
    watchdogRunning = true
    CreateThread(function()
        while next(Runs.byId) do
            local now = os.time()
            for _, run in pairs(Runs.byId) do
                watchRun(run, now)
                if Runs.byId[run.id] then burnCoal(run, now) end
            end
            Wait(5000)
        end
        watchdogRunning = false
    end)
end

-- ----------------------------------------------------------------------------
--  Tableau des missions (registre)
-- ----------------------------------------------------------------------------

---@param forFree boolean disponibilité pour un voyage libre (sinon : mission)
local function trainAvailability(trainKey, forFree)
    local train = Config.Trains[trainKey]
    if Runs.IsTrainInUse(trainKey) then return false, 'En circulation' end
    if Sunny.Fleet.IsBlocked(trainKey) then return false, Sunny.TrainStates[Sunny.Fleet.State(trainKey)] end
    if forFree and train.allowFreeRun == false then return false, 'Réservé aux missions' end
    if not forFree and train.allowMissions == false then return false, 'Réservé aux voyages' end
    return true, nil
end

Srv.Register('missions:board', function(src, payload)
    if not Srv.Can(src, 'drive') then return Srv.Fail('error_no_permission') end
    if not Srv.IsOnService(src) then return Srv.Fail('error_not_on_service') end
    local stationKey = payload.station
    if not Security.ValidKey(Config.Stations, stationKey) or not Srv.AtOffice(src, stationKey) then
        return Srv.Fail('error_too_far')
    end

    local trains = {}
    for key, train in pairs(Config.Trains) do
      if Sunny.Fleet.IsOwned(key) then
        local view = Sunny.Fleet.ViewWithHold(key)
        local available, reason = trainAvailability(key)
        local servesHere = false
        for _, r in ipairs(train.routes or {}) do
            if Utils.RouteOrigin(r) == stationKey then servesHere = true break end
        end
        if available and not servesHere then available, reason = false, 'Aucun départ ici' end
        view.available, view.reason = available, reason
        trains[#trains + 1] = view
      end
    end
    table.sort(trains, function(a, b)
        if a.available ~= b.available then return a.available end
        return a.label < b.label
    end)

    local missions = {}
    local deliveryCooldowns = Sunny.Deliveries and Sunny.Deliveries.RemainingAll(src)
    for key, m in pairs(Config.Missions) do
        local compatible = {}
        for trainKey, train in pairs(Config.Trains) do
            if train.allowMissions ~= false and Utils.TrainServesRoute(train, m.route) and Utils.TrainAcceptsType(train, m.type) then
                compatible[#compatible + 1] = trainKey
            end
        end
        local origin = Utils.RouteOrigin(m.route)
        local route = Config.Routes[m.route]
        missions[#missions + 1] = {
            key = key,
            label = m.label,
            description = m.description or '',
            type = m.type,
            typeLabel = Config.MissionTypes[m.type].label,
            route = m.route,
            routeLabel = route.label,
            origin = origin,
            originLabel = Config.Stations[origin].label,
            terminusLabel = Config.Stations[Utils.RouteTerminus(m.route)].label,
            stops = #route.stations,
            reward = m.reward,
            rewardPerStop = m.rewardPerStop or 0,
            onTimeBonus = m.onTimeBonus or 0,
            timeLimit = m.timeLimit or 0,
            canBeRobbed = m.canBeRobbed == true and Config.Robbery.enabled,
            fromHere = origin == stationKey,
            trains = compatible,
            company = m.company or '',
            cargo = cargoView(m.cargo),
            rewardItems = cargoView(m.rewardItems),
            delivery = m.delivery == true,
            cooldown = Sunny.Deliveries and Sunny.Deliveries.Remaining(src, m, deliveryCooldowns) or 0,
            allowed = not Sunny.Deliveries or Sunny.Deliveries.Allowed(src, m),
        }
    end
    table.sort(missions, function(a, b)
        if a.fromHere ~= b.fromHere then return a.fromHere end
        return a.label < b.label
    end)

    local citizen = Bridge.GetCitizenId(src)
    local cooldown = math.max(0, (Runs.cooldowns[citizen] or 0) - os.time())
    local deliveries = Config.Deliveries and Config.Deliveries.enabled
    if deliveries then cooldown = 0 end
    return { ok = true, data = { station = stationKey, trains = trains, missions = missions, cooldown = cooldown,
        deliveries = deliveries, startStation = deliveries and Config.Deliveries.startStation or nil,
        fuelItem = Config.Fuel.item, fuelLabel = Bridge.ItemLabel(Config.Fuel.item), fuelMin = Config.Fuel.minToStart } }
end, { rate = 600 })

-- ----------------------------------------------------------------------------
--  Signature de l'ordre de mission
-- ----------------------------------------------------------------------------
registerStart('run:start', function(src, payload)
    if not Srv.Can(src, 'drive') then return Srv.Fail('error_no_permission') end
    if not Srv.IsOnService(src) then return Srv.Fail('error_not_on_service') end
    if Runs.bySource[src] then return Srv.Fail('run_already_active') end

    local stationKey, trainKey = payload.station, payload.train
    if not Security.ValidKey(Config.Stations, stationKey) or not Security.ValidKey(Config.Trains, trainKey) then
        return Srv.Fail('error_invalid')
    end
    if not Srv.AtOffice(src, stationKey) then return Srv.Fail('error_too_far') end

    local citizen = Bridge.GetCitizenId(src)
    local remaining = (Runs.cooldowns[citizen] or 0) - os.time()

    local train = Config.Trains[trainKey]
    if not Security.ValidKey(Config.Missions, payload.mission) then return Srv.Fail('run_mission_invalid') end
    local missionKey = payload.mission
    local mission = Config.Missions[missionKey]
    if not mission.delivery and remaining > 0 then return Srv.Fail('run_cooldown', remaining) end
    if mission.delivery then
        if stationKey ~= Config.Deliveries.startStation then
            return Srv.Fail('run_wrong_station', Config.Stations[Config.Deliveries.startStation].label)
        end
        if not Sunny.Deliveries.Allowed(src, mission) then return Srv.Fail('error_no_permission') end
        remaining = Sunny.Deliveries.Remaining(src, mission)
        if remaining > 0 then return Srv.Fail('run_cooldown', remaining) end
    end
    local routeKey = mission.route
    if train.allowMissions == false or not Utils.TrainAcceptsType(train, mission.type) then
        return Srv.Fail('run_mission_invalid')
    end

    if not Utils.TrainServesRoute(train, routeKey) then return Srv.Fail('run_mission_invalid') end
    local origin = Utils.RouteOrigin(routeKey)
    if origin ~= stationKey then return Srv.Fail('run_wrong_station', Config.Stations[origin].label) end
    if not Sunny.Fleet.IsOwned(trainKey) then return Srv.Fail('fleet_not_owned') end
    if Runs.IsTrainInUse(trainKey) then return Srv.Fail('run_train_in_use') end
    if Sunny.Fleet.IsBlocked(trainKey) then
        return Srv.Fail('run_train_state', Sunny.TrainStates[Sunny.Fleet.State(trainKey)])
    end

    local originStation = Config.Stations[origin]
    if not originStation.depot then return Srv.Fail('run_spawn_failed') end

    -- Wagon : charbon suffisant, puis prélèvement de la cargaison (livraison).
    local holdId = Sunny.Hold.Id(trainKey)
    if Sunny.Hold.IsOpen(holdId) then return Srv.Fail('hold_busy') end
    local coal = Sunny.Hold.Count(Sunny.Hold.Read(holdId), Config.Fuel.item)
    if needsCoal(trainKey) and coal < Config.Fuel.minToStart then
        return Srv.Fail('fuel_min', Config.Fuel.minToStart, Bridge.ItemLabel(Config.Fuel.item))
    end
    local cargo = mission.cargo or {}
    if #cargo > 0 then
        local taken, errKey, missing = Sunny.Hold.Take(holdId, cargo)
        if not taken then
            if errKey == 'hold_missing' then
                local parts = {}
                for _, m in ipairs(missing) do parts[#parts + 1] = ('%s %d/%d'):format(m.label, m.have, m.need) end
                return Srv.Fail('hold_missing_cargo', table.concat(parts, ', '))
            end
            return Srv.Fail(errKey)
        end
    end

    if mission.delivery then
        local valid = Bridge.GetCitizenId(src) == citizen and Srv.Can(src, 'drive') and Srv.AtOffice(src, stationKey)
            and Sunny.Deliveries.Allowed(src, mission)
        local ok, claimed = true, false
        if valid then ok, claimed = pcall(Sunny.Deliveries.Claim, src, mission) end
        if not valid or not ok or not claimed then
            if #cargo > 0 then Sunny.Hold.Put(holdId, cargo, train.hold.slots) end
            if not ok then error(claimed) end
            return valid and Srv.Fail('run_cooldown', Sunny.Deliveries.Remaining(src, mission)) or Srv.Fail('error_invalid')
        end
    end

    Runs.nextId = Runs.nextId + 1
    local run = {
        id = Runs.nextId,
        src = src,
        citizenid = citizen,
        train = trainKey,
        mission = missionKey,
        route = routeKey,
        origin = origin,
        cargo = cargo,
        cargoView = cargoView(cargo),
        needsCoal = needsCoal(trainKey),
        coal = coal,
        state = 'assigned',
        nextIndex = 2,
        served = 0,
        createdAt = os.time(),
        robbed = false,
    }
    Runs.bySource[src] = run
    Runs.byId[run.id] = run
    Runs.trainInUse[trainKey] = run.id
    ensureWatchdog()

    local route = Config.Routes[routeKey]
    local stations = {}
    for i, stop in ipairs(route.stations) do
        local st = Config.Stations[stop.id]
        local coords, radius = platformOf(st)
        stations[i] = { id = stop.id, label = st.label, platform = Utils.VecToTable(coords), radius = radius, stop = stop.stop or 0 }
    end

    local missionLabel = mission.label
    return {
        ok = true,
        message = L('run_started', missionLabel),
        data = {
            runId = run.id,
            model = train.model,
            trainLabel = train.label,
            missionLabel = missionLabel,
            route = routeKey,
            routeLabel = route.label,
            maxSpeed = train.maxSpeed,
            passengers = train.passengers == true,
            depot = Utils.VecToTable(originStation.depot.coords),
            direction = originStation.depot.direction ~= false,
            junctions = route.junctions or {},
            stations = stations,
        },
    }
end, { rate = 2000 })

-- ----------------------------------------------------------------------------
--  Progression
-- ----------------------------------------------------------------------------

local function ownRun(src, payload, ...)
    local run = Runs.bySource[src]
    if not run or run.id ~= payload.runId then return nil end
    local allowed = { ... }
    for _, state in ipairs(allowed) do
        if run.state == state then return run end
    end
    return nil
end

Srv.Register('run:spawned', function(src, payload)
    local run = ownRun(src, payload, 'assigned')
    if not run then return Srv.Fail('error_invalid') end
    if type(payload.netId) ~= 'number' then return Srv.Fail('error_invalid') end

    local depot = Config.Stations[run.origin].depot.coords
    local entity = Security.EntityFromNet(payload.netId)
    if entity ~= 0 then
        if #(GetEntityCoords(entity) - depot) > 300.0 then
            Security.Flag(src, 'spawn_far', 'train loin du dépôt')
            Runs.Close(run, 'failed', L('run_spawn_failed'), 0)
            return Srv.Fail('run_spawn_failed')
        end
        run.entitySeen = true
    end
    if not Security.IsNear(src, depot, 300.0) then
        Runs.Close(run, 'failed', L('run_spawn_failed'), 0)
        return Srv.Fail('error_too_far')
    end

    run.netId = payload.netId
    run.state = 'ready'
    run.startedAt = os.time()
    run.lastStationAt = os.time()
    Sunny.Robbery.Refresh()
    -- Relevé de distance (charbon) dès la mise en voie.
    run.fuelPos, run.fuelSampleAt = Security.PedCoords(src), os.time()
    -- Un contrat de fret ne crée pas un second départ voyageurs au guichet.
    if not (run.mission and Config.Missions[run.mission].delivery) then
        Sunny.Departures.ForRun(run, run.free and run.announceDelay or Config.Departures.missionLead)
    end
    Runs.PublishActive()
    return { ok = true, data = Runs.Summary(src) }
end, { rate = 1000 })

Srv.Register('run:arrive', function(src, payload)
    local run = ownRun(src, payload, 'ready', 'enroute')
    if not run then return Srv.Fail('error_invalid') end
    if payload.index ~= run.nextIndex then return Srv.Fail('error_invalid') end

    local stop, station = stationOf(run, run.nextIndex)
    local coords, radius = platformOf(station)
    if not Security.IsNear(src, coords, radius) then return Srv.Fail('run_not_at_station') end

    local entity = Security.EntityFromNet(run.netId)
    if entity ~= 0 and #(GetEntityCoords(entity) - coords) > radius + 80.0 then
        return Srv.Fail('run_not_at_station')
    end

    local prev = Config.Routes[run.route].stations[run.nextIndex - 1]
    local minSeconds = Utils.MinSegmentSeconds(prev.id, stop.id, Config.Trains[run.train].maxSpeed)
    if os.time() - run.lastStationAt < minSeconds then
        Security.Flag(src, 'too_fast', ('%s -> %s en %ds (min %ds)'):format(prev.id, stop.id, os.time() - run.lastStationAt, minSeconds))
        return Srv.Fail('run_too_fast')
    end

    run.arrivedAt = os.time()
    run.dwell = stop.stop or 0
    if run.nextIndex >= #Config.Routes[run.route].stations then
        run.state = 'arrived'
        return { ok = true, message = L('run_terminus', station.label), data = { terminus = true, summary = Runs.Summary(src) } }
    end
    run.state = 'at_station'
    return { ok = true, message = L('run_arrived_station', station.label, run.dwell), data = { dwell = run.dwell, summary = Runs.Summary(src) } }
end, { rate = 800 })

Srv.Register('run:depart', function(src, payload)
    local run = ownRun(src, payload, 'at_station')
    if not run then return Srv.Fail('error_invalid') end
    if os.time() - run.arrivedAt < run.dwell - 1 then return Srv.Fail('error_invalid') end

    local _, station = stationOf(run, run.nextIndex)
    local coords, radius = platformOf(station)
    if not Security.IsNear(src, coords, radius + 40.0) then return Srv.Fail('run_not_at_station') end

    run.served = run.served + 1
    run.nextIndex = run.nextIndex + 1
    run.lastStationAt = os.time()
    run.state = 'enroute'
    local _, nextStation = stationOf(run, run.nextIndex)
    return { ok = true, message = L('run_depart_allowed', nextStation.label), data = { summary = Runs.Summary(src) } }
end, { rate = 800 })

--- Calcul de la prime — exclusivement serveur, à partir de la config.
local function computeReward(run)
    if not run.mission then return 0, {} end
    local mission = Config.Missions[run.mission]
    local lines = {}
    local total = mission.reward
    lines[#lines + 1] = { label = 'Prime de mission', amount = mission.reward }

    local perStop = (mission.rewardPerStop or 0) * run.served
    if perStop > 0 then
        total = total + perStop
        lines[#lines + 1] = { label = ('Gares desservies (%d)'):format(run.served), amount = perStop }
    end

    local elapsed = os.time() - (run.startedAt or os.time())
    if (mission.timeLimit or 0) > 0 and elapsed <= mission.timeLimit * 60 and (mission.onTimeBonus or 0) > 0 then
        total = total + mission.onTimeBonus
        lines[#lines + 1] = { label = 'Ponctualité', amount = mission.onTimeBonus }
    end

    if run.robbed then
        local reduced = math.floor(total * Config.Robbery.rewardMultiplier)
        lines[#lines + 1] = { label = 'Retenue — convoi dévalisé', amount = reduced - total }
        total = reduced
    end
    return math.max(0, math.floor(total)), lines
end

Srv.Register('run:finish', function(src, payload)
    -- Voyage libre : remisage à tout moment, sans prime ni pénalité.
    local free = Runs.bySource[src]
    if free and free.free and free.id == payload.runId and free.state ~= 'assigned' then
        local pos = Security.PedCoords(src)
        if not pos or not Utils.ParkingStation(pos) then return Srv.Fail('park_too_far') end
        local summary = Runs.Summary(src)
        Sunny.Fleet.Wear(free.train, math.floor((Config.Trains[free.train].wearPerRun or 0) * (Config.FreeTravel.wearFactor or 1)))
        Runs.Close(free, 'finished', nil, settings.finishDeleteDelay)
        return { ok = true, message = L('free_parked'), data = { reward = 0, lines = {}, summary = summary } }
    end

    local run = ownRun(src, payload, 'arrived')
    if not run or run.delivered then return Srv.Fail('error_invalid') end

    local _, station = stationOf(run, #Config.Routes[run.route].stations)
    local coords, radius = platformOf(station)
    if not Security.IsNear(src, coords, radius + 20.0) then return Srv.Fail('run_not_at_station') end

    local reward, lines = computeReward(run)
    local summary = Runs.Summary(src)
    run.delivered = true -- réserver le paiement avant toute attente du bridge/SQL
    if reward > 0 then
        Bridge.AddMoney(src, Config.Framework.rewardAccount, reward, 'sunny_train_mission')
    end
    for _, it in ipairs(Config.Missions[run.mission].rewardItems or {}) do
        Bridge.AddItem(src, it.item, it.amount)
    end
    Sunny.Fleet.Wear(run.train, Config.Trains[run.train].wearPerRun or 0)
    if not Config.Missions[run.mission].delivery then Runs.cooldowns[run.citizenid] = os.time() + settings.cooldown end

    if type(Config.Hooks.onMissionCompleted) == 'function' then
        pcall(Config.Hooks.onMissionCompleted, src, summary, reward)
    end

    local message = run.mission and L('run_finished', Utils.Money(reward)) or L('run_finished_free')
    Runs.Close(run, 'finished', nil, settings.finishDeleteDelay)
    return { ok = true, message = message, data = { reward = reward, lines = lines, summary = summary } }
end, { rate = 2000 })

Srv.Register('run:cancel', function(src)
    local run = Runs.bySource[src]
    if not run then return Srv.Fail('run_no_active') end
    if run.state == 'robbery' then return Srv.Fail('error_invalid') end
    Runs.Close(run, 'cancelled', nil, 1)
    if run.free then return { ok = true, message = L('free_parked') } end
    if not Config.Missions[run.mission].delivery then Runs.cooldowns[run.citizenid] = os.time() + settings.cancelCooldown end
    return { ok = true, message = L('run_cancelled') }
end, { rate = 1500 })

--- Le train a quitté sa gare d'origine (mise à jour des tableaux).
Srv.Register('run:departed', function(src, payload)
    local run = ownRun(src, payload, 'ready', 'enroute', 'at_station', 'arrived')
    if not run then return Srv.Fail('error_invalid') end
    if not run.departed then
        run.departed = true
        Sunny.Departures.Departed(run)
    end
    return { ok = true }
end, { rate = 1000 })

-- ----------------------------------------------------------------------------
--  Voyage libre
-- ----------------------------------------------------------------------------

local function validAnnounceDelay(delay)
    for _, d in ipairs(Config.FreeTravel.announceDelays) do if d == delay then return true end end
    return false
end

Srv.Register('free:board', function(src, payload)
    if not Config.FreeTravel.enabled then return Srv.Fail('free_disabled') end
    if not Srv.Can(src, 'drive') then return Srv.Fail('error_no_permission') end
    if not Srv.IsOnService(src) then return Srv.Fail('error_not_on_service') end
    local stationKey = payload.station
    if not Security.ValidKey(Config.Stations, stationKey) or not Srv.AtOffice(src, stationKey) then
        return Srv.Fail('error_too_far')
    end

    local trains = {}
    for key in pairs(Config.Trains) do
        if Sunny.Fleet.IsOwned(key) then
            local view = Sunny.Fleet.ViewWithHold(key)
            view.available, view.reason = trainAvailability(key, true)
            if view.available and view.needsCoal and view.coal < Config.Fuel.minToStart then
                view.available, view.reason = false, L('fuel_min', Config.Fuel.minToStart, Bridge.ItemLabel(Config.Fuel.item))
            end
            trains[#trains + 1] = view
        end
    end
    table.sort(trains, function(a, b)
        if a.available ~= b.available then return a.available end
        return a.label < b.label
    end)

    local destinations = {}
    for _, d in ipairs(Utils.Destinations(stationKey)) do
        if d.trip.connected then
            destinations[#destinations + 1] = {
                to = d.to, label = Config.Stations[d.to].label, region = Config.Stations[d.to].region or '',
                km = d.trip.km, routeLabel = Utils.TripLabel(d.trip), stops = #d.trip.path - 1,
            }
        end
    end

    local scheduled = {}
    for _, d in pairs(Sunny.Departures.list) do
        if d.station == stationKey and Sunny.Departures.IsAvailable(d) then
            scheduled[#scheduled + 1] = {
                id = d.id, departAt = d.departAt, timeLabel = Sunny.Departures.TimeLabel(d.departAt),
                destination = d.destination, destinationLabel = Config.Stations[d.destination].label,
                trainKey = d.trainKey, train = d.trainLabel, via = d.via, by = d.byName,
            }
        end
    end
    table.sort(scheduled, function(a, b) return a.departAt < b.departAt end)

    return { ok = true, data = {
        station = stationKey,
        scheduled = scheduled,
        hasDepot = Config.Stations[stationKey].depot ~= nil,
        trains = trains,
        destinations = destinations,
        delays = Config.FreeTravel.announceDelays,
    } }
end, { rate = 600 })

registerStart('run:startFree', function(src, payload)
    if not Config.FreeTravel.enabled then return Srv.Fail('free_disabled') end
    if not Srv.Can(src, 'drive') then return Srv.Fail('error_no_permission') end
    if not Srv.IsOnService(src) then return Srv.Fail('error_not_on_service') end
    if Runs.bySource[src] then return Srv.Fail('run_already_active') end

    local stationKey, trainKey, destination = payload.station, payload.train, payload.destination
    -- Départ programmé : destination et train imposés par la programmation.
    local departure = nil
    if payload.departure ~= nil then
        departure = Sunny.Departures.Get(payload.departure)
        if not Sunny.Departures.IsAvailable(departure) or departure.station ~= stationKey then return Srv.Fail('dep_invalid') end
        if departure.trainKey and departure.trainKey ~= trainKey then
            return Srv.Fail('dep_wrong_train', Config.Trains[departure.trainKey].label)
        end
        destination = departure.destination
        payload.delay = 0
    end
    if not Security.ValidKey(Config.Stations, stationKey) or not Security.ValidKey(Config.Trains, trainKey)
        or not Security.ValidKey(Config.Stations, destination) then
        return Srv.Fail('error_invalid')
    end
    if not Srv.AtOffice(src, stationKey) then return Srv.Fail('error_too_far') end
    local origin = Config.Stations[stationKey]
    if not origin.depot then return Srv.Fail('free_no_depot') end
    local trip = Utils.Trip(stationKey, destination)
    if not trip or not trip.connected then return Srv.Fail('free_invalid_dest') end
    local delay = tonumber(payload.delay)
    if not validAnnounceDelay(delay) then return Srv.Fail('error_invalid') end

    if not Sunny.Fleet.IsOwned(trainKey) then return Srv.Fail('fleet_not_owned') end
    local available, reason = trainAvailability(trainKey, true)
    if not available then return { ok = false, error = reason } end
    local coal = Sunny.Hold.Count(Sunny.Hold.Read(Sunny.Hold.Id(trainKey)), Config.Fuel.item)
    if needsCoal(trainKey) and coal < Config.Fuel.minToStart then
        return Srv.Fail('fuel_min', Config.Fuel.minToStart, Bridge.ItemLabel(Config.Fuel.item))
    end

    local train = Config.Trains[trainKey]
    local stops, stations = {}, {}
    for i, id in ipairs(trip.path) do
        stops[i] = { id = id, stop = 0 }
        local coords, radius = platformOf(Config.Stations[id])
        stations[i] = { id = id, label = Config.Stations[id].label, platform = Utils.VecToTable(coords), radius = radius, stop = 0 }
    end

    -- La lecture du wagon attend la BDD : le départ peut avoir été pris entre-temps.
    if departure and not Sunny.Departures.IsAvailable(departure) then return Srv.Fail('dep_invalid') end
    Runs.nextId = Runs.nextId + 1
    local run = {
        id = Runs.nextId,
        src = src,
        citizenid = Bridge.GetCitizenId(src),
        train = trainKey,
        free = true,
        origin = stationKey,
        destination = destination,
        stops = stops,
        tripLabel = Utils.TripLabel(trip),
        announceDelay = delay,
        departureId = departure and departure.id or nil,
        needsCoal = needsCoal(trainKey),
        coal = coal,
        state = 'assigned',
        nextIndex = #stops,
        served = 0,
        createdAt = os.time(),
        robbed = false,
    }
    Runs.bySource[src] = run
    Runs.byId[run.id] = run
    Runs.trainInUse[trainKey] = run.id
    if departure then Sunny.Departures.Claim(departure, run) end
    ensureWatchdog()

    local destLabel = Config.Stations[destination].label
    return {
        ok = true,
        message = L('free_started', destLabel),
        data = {
            runId = run.id,
            free = true,
            model = train.model,
            trainLabel = train.label,
            missionLabel = L('free_label'),
            routeLabel = run.tripLabel,
            destinationLabel = destLabel,
            maxSpeed = train.maxSpeed,
            passengers = train.passengers == true,
            depot = Utils.VecToTable(origin.depot.coords),
            direction = origin.depot.direction ~= false,
            junctions = {},
            stations = stations,
        },
    }
end, { rate = 2000 })

Srv.Register('run:summary', function(src)
    return { ok = true, data = Runs.Summary(src) }
end, { rate = 500 })

AddEventHandler('playerDropped', function()
    local run = Runs.bySource[source]
    if run then Runs.Close(run, 'dropped', nil, 0) end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    for _, run in pairs(Runs.byId) do
        local entity = Security.EntityFromNet(run.netId)
        if entity ~= 0 then DeleteEntity(entity) end
    end
end)

-- ----------------------------------------------------------------------------
--  Admin : /sunnytrain_despawn [all | n° de run]
--  Sans argument : le train Sunny_train le plus proche de l'admin, sinon le
--  train (quel qu'il soit) le plus proche côté client.
-- ----------------------------------------------------------------------------
RegisterCommand(Config.Commands.despawn, function(src, args)
    if src > 0 and not IsPlayerAceAllowed(src, Config.Commands.positionAce) then
        return Srv.Notify(src, L('error_no_permission'), 'error')
    end
    local closed = 0
    local function close(run)
        Runs.Close(run, 'cancelled', L('admin_despawned'), 0)
        closed = closed + 1
    end

    if args[1] == 'all' then
        for _, run in pairs(Runs.byId) do close(run) end
    elseif args[1] and tonumber(args[1]) then
        local run = Runs.byId[tonumber(args[1])]
        if run then close(run) end
    elseif src > 0 then
        local pos = Security.PedCoords(src)
        local best, bestDist = nil, 150.0
        for _, run in pairs(Runs.byId) do
            local entity = Security.EntityFromNet(run.netId)
            local where = entity ~= 0 and GetEntityCoords(entity) or Security.PedCoords(run.src)
            if pos and where and #(pos - where) < bestDist then best, bestDist = run, #(pos - where) end
        end
        if best then close(best) else TriggerClientEvent('sunny_train:client:adminDespawnNearest', src) end
    end

    local msg = L('admin_despawn_done', closed)
    if src > 0 then Srv.Notify(src, msg, 'info') else print('[Sunny_train] ' .. msg) end
end, false)

-- Exports serveur (intégrations tierces, lecture seule)
exports('IsOnService', function(src) return Srv.IsOnService(src) end)
exports('GetActiveRun', function(src) return Runs.Summary(src) end)
