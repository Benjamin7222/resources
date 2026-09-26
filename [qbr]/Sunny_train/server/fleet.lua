-- ============================================================================
--  Sunny_train - Flotte & maintenance (serveur)
--  État général persistant de chaque train (sunny_train_fleet).
--  Les items de réparation viennent de l'inventaire existant (Bridge).
-- ============================================================================

local Fleet = {
    data = {},         -- [trainKey] = { condition, status, lastInspection, lastRepair, owned }
    inspections = {},  -- [trainKey] = os.time() de la dernière inspection
    work = {},         -- [src] = { kind, train, repair, startedAt, duration }
}
Sunny.Fleet = Fleet

local L = Sunny.L
local Srv, Security, Bridge, Utils = Sunny.Srv, Sunny.Security, Sunny.Bridge, Sunny.Utils
local cfg = Config.Maintenance

function Fleet.Load()
    local rows = MySQL.query.await('SELECT * FROM `sunny_train_fleet`') or {}
    for _, row in ipairs(rows) do
        if Config.Trains[row.train_key] then
            Fleet.data[row.train_key] = {
                condition = tonumber(row.condition) or 100,
                status = row.status or 'auto',
                lastInspection = row.last_inspection,
                lastRepair = row.last_repair,
                owned = tonumber(row.owned) == 1,
            }
        end
    end
    for key in pairs(Config.Trains) do
        if not Fleet.data[key] then
            Fleet.data[key] = { condition = 100, status = 'auto' }
            MySQL.insert('INSERT IGNORE INTO `sunny_train_fleet` (`train_key`, `condition`, `status`) VALUES (?, 100, ?)', { key, 'auto' })
        end
    end
end

local starter = {}
for _, key in ipairs(Config.Fleet.starter or {}) do starter[key] = true end

--- La compagnie possède-t-elle ce train (fourni au départ ou acheté) ?
function Fleet.IsOwned(trainKey)
    if starter[trainKey] then return true end
    local e = Fleet.data[trainKey]
    return e ~= nil and e.owned == true
end

function Fleet.IsStarter(trainKey)
    return starter[trainKey] == true
end

function Fleet.Get(trainKey)
    return Fleet.data[trainKey] or { condition = 100, status = 'auto' }
end

function Fleet.State(trainKey)
    local entry = Fleet.Get(trainKey)
    return Utils.TrainState(entry.condition, entry.status)
end

function Fleet.IsBlocked(trainKey)
    if not cfg.enabled then return false end
    return cfg.blockedStates[Fleet.State(trainKey)] == true
end

local function save(trainKey, by)
    local e = Fleet.data[trainKey]
    if not e then return end
    MySQL.update('UPDATE `sunny_train_fleet` SET `condition` = ?, `status` = ?, `last_inspection` = ?, `last_repair` = ?, `updated_by` = ?, `owned` = ? WHERE `train_key` = ?',
        { e.condition, e.status, e.lastInspection, e.lastRepair, by, e.owned and 1 or 0, trainKey })
end

--- Usure du matériel (fin de trajet, braquage...).
function Fleet.Wear(trainKey, amount)
    if not cfg.enabled or not Fleet.data[trainKey] or (amount or 0) <= 0 then return end
    local e = Fleet.data[trainKey]
    e.condition = math.max(0, e.condition - math.floor(amount))
    if e.condition <= 0 then e.status = 'out_of_service' end
    save(trainKey, 'usure')
end

--- Rapport d'inspection détaillé (déterministe selon l'état).
local COMPONENTS = {
    { key = 'boiler',   label = 'Chaudière & foyer',     weight = 1.00 },
    { key = 'running',  label = 'Bielles & essieux',     weight = 0.85 },
    { key = 'brakes',   label = 'Freins à air',          weight = 1.15 },
    { key = 'coupling', label = 'Attelages & tampons',   weight = 0.70 },
    { key = 'cars',     label = 'Voitures & wagons',     weight = 0.60 },
}

local function componentReport(condition)
    local list = {}
    for i, c in ipairs(COMPONENTS) do
        local wear = (100 - condition) * c.weight + ((i * 7) % 5)
        local value = math.max(0, math.min(100, math.floor(100 - wear)))
        list[#list + 1] = {
            label = c.label,
            value = value,
            state = Utils.TrainState(value, 'auto'),
        }
    end
    return list
end

--- Vue publique d'un train pour la NUI.
function Fleet.View(trainKey)
    local train = Config.Trains[trainKey]
    local entry = Fleet.Get(trainKey)
    local routes = {}
    for i, r in ipairs(train.routes or {}) do routes[i] = Config.Routes[r] and Config.Routes[r].label or r end
    local types = {}
    for i, t in ipairs(train.serviceTypes or {}) do types[i] = Config.MissionTypes[t] and Config.MissionTypes[t].label or t end
    local inspectedAt = Fleet.inspections[trainKey]
    return {
        key = trainKey,
        label = train.label,
        description = train.description or '',
        condition = entry.condition,
        state = Fleet.State(trainKey),
        manualOut = entry.status == 'out_of_service',
        inUse = Sunny.Runs.IsTrainInUse(trainKey),
        routes = routes,
        routeKeys = train.routes or {},
        serviceTypes = types,
        allowMissions = train.allowMissions ~= false,
        allowFreeRun = train.allowFreeRun == true,
        allowRobbery = train.allowRobbery == true,
        maxSpeed = train.maxSpeed,
        inspectionValid = inspectedAt ~= nil and (os.time() - inspectedAt) <= cfg.inspectionValidity,
        tier = train.tier or 0,
        category = train.category or '',
        price = train.price or 0,
        owned = Fleet.IsOwned(trainKey),
        starter = Fleet.IsStarter(trainKey),
        holdSlots = train.hold and train.hold.slots or 0,
        holdWeight = train.hold and train.hold.weight or 0,
        needsCoal = Config.Fuel.enabled and train.fuel ~= false,
        coalPerKm = train.coalPerKm or 0,
    }
end

--- Vue d'un train avec le contenu de son wagon (charbon + marchandises).
function Fleet.ViewWithHold(trainKey)
    local view = Fleet.View(trainKey)
    local summary = Sunny.Hold.Summary(Sunny.Hold.Id(trainKey))
    local items, used = {}, 0
    for name, amount in pairs(summary) do
        used = used + 1
        items[#items + 1] = { item = name, label = Bridge.ItemLabel(name), amount = amount }
    end
    table.sort(items, function(a, b) return a.label < b.label end)
    view.coal = summary[Config.Fuel.item] or 0
    view.hold = items
    view.holdSummary = summary
    view.holdOpen = Sunny.Hold.IsOpen(Sunny.Hold.Id(trainKey))
    return view
end

--- Gare équipée d'un dépôt dont le bureau est à portée.
local function atDepot(src)
    for key, station in pairs(Config.Stations) do
        if station.services and station.services.maintenance then
            for _, point in ipairs(Utils.StaffPoints(station)) do
                if Security.IsNear(src, point.coords, (point.radius or 2.0) + 25.0) then return key end
            end
        end
    end
    return nil
end

local function repairById(id)
    for _, repair in ipairs(cfg.repairs) do
        if repair.id == id then return repair end
    end
    return nil
end

local function missingItems(src, items)
    local missing = {}
    for _, it in ipairs(items or {}) do
        local have = Bridge.CountItem(src, it.name)
        if have < it.amount then
            missing[#missing + 1] = ('%s x%d'):format(Bridge.ItemLabel(it.name), it.amount - have)
        end
    end
    return missing
end

local function guard(src, payload, action)
    if not cfg.enabled then return nil, Srv.Fail('error_invalid') end
    if not Srv.Can(src, action) then return nil, Srv.Fail('error_no_permission') end
    if not Srv.IsOnService(src) then return nil, Srv.Fail('error_not_on_service') end
    if not Security.ValidKey(Config.Trains, payload.train) then return nil, Srv.Fail('error_invalid') end
    if not atDepot(src) then return nil, Srv.Fail('maint_not_depot') end
    return payload.train
end

-- ----------------------------------------------------------------------------
--  Requêtes
-- ----------------------------------------------------------------------------

Srv.Register('fleet:list', function(src)
    if not Srv.Can(src, 'employee') then return Srv.Fail('error_no_permission') end
    local list = {}
    for key in pairs(Config.Trains) do
        if Fleet.IsOwned(key) then list[#list + 1] = Fleet.ViewWithHold(key) end
    end
    table.sort(list, function(a, b) return (a.tier or 0) < (b.tier or 0) end)
    local repairs = {}
    for i, r in ipairs(cfg.repairs) do
        local items = {}
        for j, it in ipairs(r.items or {}) do
            items[j] = { label = Bridge.ItemLabel(it.name), amount = it.amount, have = Bridge.CountItem(src, it.name) }
        end
        repairs[i] = { id = r.id, label = r.label, description = r.description, restore = r.restore, duration = r.duration, items = items }
    end
    return { ok = true, data = {
        trains = list, repairs = repairs, atDepot = atDepot(src) ~= nil, onService = Srv.IsOnService(src),
        requireInspection = cfg.requireInspection, inspectDuration = cfg.inspectDuration,
        canMaintain = Srv.Can(src, 'maintenance'), canRestore = Srv.Can(src, 'restore'),
        restoreMin = cfg.restoreMinCondition,
        fuelItem = Bridge.ItemLabel(Config.Fuel.item), fuelMin = Config.Fuel.minToStart,
    } }
end, { rate = 600 })

-- ----------------------------------------------------------------------------
--  Catalogue & acquisitions (patron)
-- ----------------------------------------------------------------------------

Srv.Register('fleet:catalogue', function(src)
    if not Srv.Can(src, 'employee') then return Srv.Fail('error_no_permission') end
    local list = {}
    for key in pairs(Config.Trains) do list[#list + 1] = Fleet.View(key) end
    table.sort(list, function(a, b) return (a.tier or 0) < (b.tier or 0) end)
    return { ok = true, data = {
        trains = list,
        canBuy = Srv.Can(src, 'purchase'),
        balance = Utils.Money(Bridge.PurchaseBalance(src)),
        account = Config.Purchase.account,
        sellRatio = Config.Purchase.sellRatio,
    } }
end, { rate = 800 })

Srv.Register('fleet:buy', function(src, payload)
    if not Srv.Can(src, 'purchase') then return Srv.Fail('error_no_permission') end
    local trainKey = payload.train
    if not Security.ValidKey(Config.Trains, trainKey) then return Srv.Fail('error_invalid') end
    if Fleet.IsOwned(trainKey) then return Srv.Fail('fleet_already_owned') end
    if not Srv.NearestOffice(src) then return Srv.Fail('error_too_far') end
    local price = Config.Trains[trainKey].price or 0
    if not Bridge.PayPurchase(src, price, 'sunny_train_purchase') then
        return Srv.Fail('fleet_no_funds', Utils.Money(price))
    end
    Fleet.data[trainKey] = Fleet.data[trainKey] or { condition = 100, status = 'auto' }
    Fleet.data[trainKey].owned = true
    Fleet.data[trainKey].condition = 100
    Fleet.data[trainKey].status = 'auto'
    save(trainKey, Bridge.GetCitizenId(src))
    return { ok = true, message = L('fleet_bought', Config.Trains[trainKey].label, Utils.Money(price)), data = { train = Fleet.View(trainKey) } }
end, { rate = 2000, lock = 'fleet:purchase' })

Srv.Register('fleet:sell', function(src, payload)
    if not Srv.Can(src, 'purchase') then return Srv.Fail('error_no_permission') end
    local ratio = Config.Purchase.sellRatio or 0
    local trainKey = payload.train
    if ratio <= 0 or not Security.ValidKey(Config.Trains, trainKey) then return Srv.Fail('error_invalid') end
    if not Fleet.IsOwned(trainKey) or Fleet.IsStarter(trainKey) then return Srv.Fail('fleet_cannot_sell') end
    if Sunny.Runs.IsTrainInUse(trainKey) then return Srv.Fail('maint_in_use') end
    if not Srv.NearestOffice(src) then return Srv.Fail('error_too_far') end
    local amount = math.floor((Config.Trains[trainKey].price or 0) * ratio)
    Fleet.data[trainKey].owned = false
    save(trainKey, Bridge.GetCitizenId(src))
    Bridge.RefundPurchase(src, amount, 'sunny_train_sale')
    return { ok = true, message = L('fleet_sold', Config.Trains[trainKey].label, Utils.Money(amount)), data = { train = Fleet.View(trainKey) } }
end, { rate = 2000, lock = 'fleet:purchase' })

-- Inspection / réparation en 2 temps : « begin » ouvre un chantier horodaté
-- côté serveur, « finish » n'est accepté qu'une fois la durée écoulée.
Srv.Register('fleet:begin', function(src, payload)
    local trainKey, fail = guard(src, payload, 'maintenance')
    if not trainKey then return fail end
    if Sunny.Runs.IsTrainInUse(trainKey) then return Srv.Fail('maint_in_use') end

    local kind, duration, repairId = payload.kind, nil, nil
    if kind == 'inspect' then
        duration = cfg.inspectDuration
    elseif kind == 'repair' then
        local repair = repairById(payload.repair)
        if not repair then return Srv.Fail('error_invalid') end
        if Fleet.Get(trainKey).condition >= 100 then return Srv.Fail('maint_full') end
        local inspectedAt = Fleet.inspections[trainKey]
        if cfg.requireInspection and (not inspectedAt or os.time() - inspectedAt > cfg.inspectionValidity) then
            return Srv.Fail('maint_need_inspection')
        end
        local missing = missingItems(src, repair.items)
        if #missing > 0 then return Srv.Fail('maint_missing_items', table.concat(missing, ', ')) end
        duration, repairId = repair.duration, repair.id
    else
        return Srv.Fail('error_invalid')
    end

    Fleet.work[src] = { kind = kind, train = trainKey, repair = repairId, startedAt = GetGameTimer(), duration = duration }
    return { ok = true, data = { duration = duration, scenario = cfg.scenario } }
end, { rate = 1000 })

Srv.Register('fleet:finish', function(src)
    local work = Fleet.work[src]
    Fleet.work[src] = nil
    if not work then return Srv.Fail('error_invalid') end
    if GetGameTimer() - work.startedAt < work.duration * 0.9 then
        Security.Flag(src, 'maintenance_too_fast', work.kind)
        return Srv.Fail('error_invalid')
    end
    local trainKey = work.train
    if not cfg.enabled or not Srv.Can(src, 'maintenance') or not Fleet.IsOwned(trainKey) then
        return Srv.Fail('error_no_permission')
    end
    if not atDepot(src) then return Srv.Fail('maint_not_depot') end
    if Sunny.Runs.IsTrainInUse(trainKey) then return Srv.Fail('maint_in_use') end
    local entry = Fleet.data[trainKey]
    local citizen = Bridge.GetCitizenId(src)

    if work.kind == 'inspect' then
        Fleet.inspections[trainKey] = os.time()
        entry.lastInspection = os.time()
        save(trainKey, citizen)
        return {
            ok = true, message = L('maint_inspected'),
            data = { train = Fleet.View(trainKey), report = componentReport(entry.condition), inspector = Bridge.GetName(src) },
        }
    end

    local repair = repairById(work.repair)
    if not repair then return Srv.Fail('error_invalid') end
    local missing = missingItems(src, repair.items)
    if #missing > 0 then return Srv.Fail('maint_missing_items', table.concat(missing, ', ')) end
    local removed = {}
    for _, it in ipairs(repair.items or {}) do
        if not Bridge.RemoveItem(src, it.name, it.amount) then
            for _, refund in ipairs(removed) do Bridge.AddItem(src, refund.name, refund.amount) end
            return Srv.Fail('maint_missing_items', Bridge.ItemLabel(it.name))
        end
        removed[#removed + 1] = it
    end
    local before = entry.condition
    entry.condition = math.min(100, entry.condition + repair.restore)
    entry.lastRepair = os.time()
    save(trainKey, citizen)
    return { ok = true, message = L('maint_repaired', entry.condition - before), data = { train = Fleet.View(trainKey) } }
end, { rate = 1000 })

Srv.Register('fleet:cancelWork', function(src)
    Fleet.work[src] = nil
    return { ok = true }
end)

Srv.Register('fleet:restore', function(src, payload)
    local trainKey, fail = guard(src, payload, 'restore')
    if not trainKey then return fail end
    local entry = Fleet.data[trainKey]
    if entry.condition < cfg.restoreMinCondition then
        return Srv.Fail('maint_restore_refused', cfg.restoreMinCondition)
    end
    entry.status = 'auto'
    save(trainKey, Bridge.GetCitizenId(src))
    return { ok = true, message = L('maint_restored'), data = { train = Fleet.View(trainKey) } }
end, { rate = 1000 })

Srv.Register('fleet:retire', function(src, payload)
    local trainKey, fail = guard(src, payload, 'restore')
    if not trainKey then return fail end
    if Sunny.Runs.IsTrainInUse(trainKey) then return Srv.Fail('maint_in_use') end
    Fleet.data[trainKey].status = 'out_of_service'
    save(trainKey, Bridge.GetCitizenId(src))
    return { ok = true, message = L('maint_retired'), data = { train = Fleet.View(trainKey) } }
end, { rate = 1000 })

AddEventHandler('playerDropped', function()
    Fleet.work[source] = nil
end)
