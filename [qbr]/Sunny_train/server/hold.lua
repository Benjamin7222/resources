-- ============================================================================
--  Sunny_train - Wagons de chargement (serveur)
--
--  Chaque train possède un coffre de l'inventaire EXISTANT (qbr-inventory,
--  table `stashitems`) : cargaison des missions + charbon du tender.
--  Aucun inventaire n'est créé : Sunny_train ouvre ce coffre via
--  qbr-inventory et, côté serveur, lit / prélève dans la même table.
--
--  qbr-inventory recharge le coffre depuis la base à chaque ouverture et le
--  réécrit à la fermeture : Sunny_train ne modifie donc JAMAIS un coffre
--  ouvert (sinon la fermeture écraserait la modification → duplication).
--  Les ouvertures / fermetures sont suivies via les événements de
--  qbr-inventory.
-- ============================================================================

local Hold = {
    open = {},   -- [stashId] = { src, at }
}
Sunny.Hold = Hold

local L = Sunny.L
local Srv, Security, Bridge = Sunny.Srv, Sunny.Security, Sunny.Bridge
local cfg = Config.Hold
local mutations = {}

function Hold.Id(trainKey)
    return cfg.prefix .. trainKey
end

function Hold.TrainOf(stashId)
    if type(stashId) ~= 'string' or stashId:sub(1, #cfg.prefix) ~= cfg.prefix then return nil end
    local key = stashId:sub(#cfg.prefix + 1)
    return Config.Trains[key] and key or nil
end

-- ----------------------------------------------------------------------------
--  Lecture / écriture (format de qbr-inventory)
-- ----------------------------------------------------------------------------

--- Contenu du coffre : liste d'items { name, amount, info, slot, ... }.
function Hold.Read(stashId)
    local raw = MySQL.scalar.await('SELECT items FROM stashitems WHERE stash = ?', { stashId })
    if not raw then return {} end
    local ok, data = pcall(json.decode, raw)
    if not ok or type(data) ~= 'table' then return {} end
    local list = {}
    for key, item in pairs(data) do
        if type(item) == 'table' and item.name and (tonumber(item.amount) or 0) > 0 then
            item.amount = tonumber(item.amount)
            item.slot = tonumber(item.slot) or tonumber(key)
            if item.slot and item.slot > 0 and item.slot % 1 == 0 then list[#list + 1] = item end
        end
    end
    table.sort(list, function(a, b) return (a.slot or 0) < (b.slot or 0) end)
    return list
end

function Hold.Write(stashId, list)
    MySQL.query.await('INSERT INTO stashitems (stash, items) VALUES (?, ?) ON DUPLICATE KEY UPDATE items = VALUES(items)',
        { stashId, json.encode(list) })
end

function Hold.Count(list, name)
    local total = 0
    for _, item in ipairs(list) do
        if item.name == name then total = total + item.amount end
    end
    return total
end

--- Résumé { [item] = quantité } pour l'affichage.
function Hold.Summary(stashId)
    local summary = {}
    for _, item in ipairs(Hold.Read(stashId)) do
        summary[item.name] = (summary[item.name] or 0) + item.amount
    end
    return summary
end

function Hold.IsOpen(stashId)
    local o = Hold.open[stashId]
    if not o then return false end
    -- Ouverture périmée (déconnexion sans fermeture, crash client).
    if not GetPlayerName(o.src) or os.time() - o.at > 1800 then
        Hold.open[stashId] = nil
        return false
    end
    return true
end

--- Items manquants pour une liste { { item, amount } }.
function Hold.Missing(list, requirements)
    local missing = {}
    for _, req in ipairs(requirements or {}) do
        local have = Hold.Count(list, req.item)
        if have < req.amount then
            missing[#missing + 1] = { item = req.item, label = Bridge.ItemLabel(req.item), need = req.amount, have = have }
        end
    end
    return missing
end

--- Prélève des items du coffre (tout ou rien).
---@return boolean ok, string|nil errorKey, table|nil missing
local function take(stashId, requirements)
    if Hold.IsOpen(stashId) then return false, 'hold_busy' end
    local list = Hold.Read(stashId)
    if Hold.IsOpen(stashId) then return false, 'hold_busy' end
    -- Fusionner les doublons : deux lignes de 10 doivent exiger 20 items.
    local totals, merged = {}, {}
    for _, req in ipairs(requirements or {}) do totals[req.item] = (totals[req.item] or 0) + req.amount end
    for item, amount in pairs(totals) do merged[#merged + 1] = { item = item, amount = amount } end
    requirements = merged
    local missing = Hold.Missing(list, requirements)
    if #missing > 0 then return false, 'hold_missing', missing end
    for _, req in ipairs(requirements) do
        local left = req.amount
        for _, item in ipairs(list) do
            if left <= 0 then break end
            if item.name == req.item and item.amount > 0 then
                local take = math.min(item.amount, left)
                item.amount = item.amount - take
                left = left - take
            end
        end
    end
    local kept = {}
    for _, item in ipairs(list) do
        if item.amount > 0 then kept[#kept + 1] = item end
    end
    Hold.Write(stashId, kept)
    return true
end

--- Dépose des items dans le coffre (remboursement d'une cargaison).
local function put(stashId, items, maxSlots)
    if not items or #items == 0 or Hold.IsOpen(stashId) then return false end
    local list = Hold.Read(stashId)
    if Hold.IsOpen(stashId) then return false, 'hold_busy' end
    local used = {}
    for _, item in ipairs(list) do used[item.slot] = true end
    for _, it in ipairs(items) do
        local stacked = false
        for _, item in ipairs(list) do
            if item.name == it.item and (item.info == nil or item.info == '') then
                item.amount = item.amount + it.amount
                stacked = true
                break
            end
        end
        if not stacked then
            for slot = 1, maxSlots or 50 do
                if not used[slot] then
                    used[slot] = true
                    list[#list + 1] = { name = it.item, amount = it.amount, info = '', slot = slot, label = Bridge.ItemLabel(it.item) }
                    stacked = true
                    break
                end
            end
            if not stacked then return false, 'hold_full' end
        end
    end
    Hold.Write(stashId, list)
    return true
end

local function mutate(stashId, fn, ...)
    if mutations[stashId] or Hold.IsOpen(stashId) then return false, 'hold_busy' end
    mutations[stashId] = true
    local result = table.pack(pcall(fn, stashId, ...))
    mutations[stashId] = nil
    if not result[1] then error(result[2]) end
    return table.unpack(result, 2, result.n)
end

function Hold.Take(stashId, requirements) return mutate(stashId, take, requirements) end
function Hold.Put(stashId, items, maxSlots) return mutate(stashId, put, items, maxSlots) end

-- ----------------------------------------------------------------------------
--  Ouverture par un employé
-- ----------------------------------------------------------------------------

--- Le joueur est-il au dépôt d'une gare, ou à côté de ce train en circulation ?
local function canReach(src, trainKey)
    local station = Srv.NearestOffice(src)
    if station and Config.Stations[station].depot then return true end
    for _, run in pairs(Sunny.Runs.byId) do
        if run.train == trainKey then
            local entity = Security.EntityFromNet(run.netId)
            local where = entity ~= 0 and GetEntityCoords(entity) or Security.PedCoords(run.src)
            local pos = Security.PedCoords(src)
            if where and pos and #(pos - where) <= cfg.openDistance + 20.0 then return true end
        end
    end
    return false
end

Srv.Register('hold:open', function(src, payload)
    if not cfg.enabled then return Srv.Fail('error_invalid') end
    if not Srv.Can(src, 'employee') then return Srv.Fail('error_no_permission') end
    if not Srv.IsOnService(src) then return Srv.Fail('error_not_on_service') end
    local trainKey = payload.train
    if not Security.ValidKey(Config.Trains, trainKey) or not Sunny.Fleet.IsOwned(trainKey) then
        return Srv.Fail('fleet_not_owned')
    end
    if not canReach(src, trainKey) then return Srv.Fail('hold_too_far') end
    local id = Hold.Id(trainKey)
    if mutations[id] then return Srv.Fail('hold_busy') end
    if Hold.IsOpen(id) and Hold.open[id].src ~= src then return Srv.Fail('hold_busy') end
    Hold.open[id] = { src = src, at = os.time() }
    local train = Config.Trains[trainKey]
    return { ok = true, data = { stash = id, slots = train.hold.slots, weight = train.hold.weight, label = train.label } }
end, { rate = 1500 })

-- Suivi des ouvertures directes (autre script, commande) : le coffre est
-- considéré ouvert, donc jamais modifié par Sunny_train pendant ce temps.
RegisterNetEvent('inventory:server:OpenInventory', function(name, id)
    local src = source
    if name == 'stash' and Hold.TrainOf(id) and not Hold.IsOpen(id) then
        Hold.open[id] = { src = src, at = os.time() }
    end
end)

-- Fermeture : qbr-inventory réécrit le coffre ; on relit après son écriture.
RegisterNetEvent('inventory:server:SaveInventory', function(kind, id)
    local src = source
    if kind ~= 'stash' or not Hold.TrainOf(id) then return end
    local o = Hold.open[id]
    if o and o.src == src then
        SetTimeout(1500, function()
            if Hold.open[id] == o then
                Hold.open[id] = nil
                Sunny.Runs.OnHoldChanged(Hold.TrainOf(id))
            end
        end)
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    SetTimeout(3000, function()
        for id, o in pairs(Hold.open) do
            if o.src == src then Hold.open[id] = nil end
        end
    end)
end)
