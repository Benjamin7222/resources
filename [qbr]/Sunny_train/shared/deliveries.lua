-- Conversion des contrats en missions utilisant le réseau ferroviaire existant.
local cfg, Utils = Config.Deliveries, Sunny.Utils
if not cfg or not cfg.enabled then return end
assert(Config.Stations[cfg.startStation] and Config.Stations[cfg.startStation].depot, 'Livraisons : gare de départ sans dépôt')
assert(cfg.cooldownScope == 'player' or cfg.cooldownScope == 'company', 'Livraisons : cooldownScope invalide')
Utils.Network() -- figer le réseau avant de lui ajouter les itinéraires des contrats
Config.Missions = {}
for companyKey, company in pairs(cfg.companies) do
    for key, contract in pairs(company.runs) do
        local id = 'delivery_' .. companyKey .. '_' .. key
        local trip = Utils.Trip(cfg.startStation, contract.destination)
        assert(trip and trip.connected, 'Livraison sans trajet ferroviaire : ' .. id)
        assert(type(contract.reward) == 'number' and contract.reward >= 0, 'Prix invalide : ' .. id)
        local cooldown = contract.cooldown or cfg.cooldown
        assert(type(cooldown) == 'number' and cooldown >= 0, 'Cooldown invalide : ' .. id)
        assert(type(contract.items) == 'table' and #contract.items > 0, 'Cargaison vide : ' .. id)
        for _, item in ipairs(contract.items) do
            assert(type(item.item) == 'string' and type(item.amount) == 'number' and item.amount > 0 and item.amount % 1 == 0, 'Item invalide : ' .. id)
            local found = false
            for _, kit in ipairs(Config.RailTestKit) do
                if kit.item == item.item then kit.amount = math.max(kit.amount, item.amount); found = true; break end
            end
            if not found then Config.RailTestKit[#Config.RailTestKit + 1] = { item = item.item, amount = item.amount } end
        end
        local stops = {}
        for i, station in ipairs(trip.path) do
            stops[i] = { id = station, stop = i > 1 and i < #trip.path and 15 or 0, eta = 0 }
        end
        Config.Routes[id] = { label = Utils.TripLabel(trip), delivery = true, stations = stops, junctions = contract.junctions or {} }
        Config.Missions[id] = {
            label = contract.label, company = company.label, companyKey = companyKey,
            delivery = true, category = contract.category or key,
            allowedJobs = contract.allowedJobs or company.allowedJobs,
            cooldown = cooldown, type = 'freight', route = id,
            description = contract.description or 'Charger la marchandise dans le wagon à Saint Denis et livrer au terminus.',
            cargo = contract.items, reward = contract.reward, rewardPerStop = 0,
            onTimeBonus = 0, timeLimit = 0, hardTimeout = contract.hardTimeout or 120,
            canBeRobbed = contract.canBeRobbed == true,
        }
        for trainKey, train in pairs(Config.Trains) do
            if train.allowMissions ~= false and Utils.TrainAcceptsType(train, 'freight')
                and (not contract.trains or contract.trains[trainKey]) then
                train.routes[#train.routes + 1] = id
            end
        end
    end
end
