-- Environnement serveur CFX/qbr-core simulé pour tester Sunny_train.
BASE_SEC = 1700000000
NOW_MS = 0
LOG = { flags = {}, client = {}, responses = {} }

local realTime = os.time
os.time = function(t) return t and realTime(t) or BASE_SEC + NOW_MS // 1000 end
function GetGameTimer() return NOW_MS end

-- vector3 ---------------------------------------------------------------
local vmeta = {}
vmeta.__index = vmeta
vmeta.__sub = function(a, b) return vector3(a.x - b.x, a.y - b.y, a.z - b.z) end
vmeta.__add = function(a, b) return vector3(a.x + b.x, a.y + b.y, a.z + b.z) end
vmeta.__len = function(a) return math.sqrt(a.x * a.x + a.y * a.y + a.z * a.z) end
function vector3(x, y, z) return setmetatable({ x = x, y = y, z = z }, vmeta) end

-- threads ---------------------------------------------------------------
THREADS = {}
function CreateThread(fn) THREADS[#THREADS + 1] = { co = coroutine.create(fn), wake = NOW_MS } end
function SetTimeout(ms, fn) THREADS[#THREADS + 1] = { co = coroutine.create(fn), wake = NOW_MS + ms } end
function Wait(ms) coroutine.yield(ms or 0) end

function RunThreads(untilMs)
    while true do
        local ran = false
        for i = #THREADS, 1, -1 do
            local t = THREADS[i]
            if t and t.wake <= NOW_MS then
                local ok, ms = coroutine.resume(t.co)
                if not ok then error('thread: ' .. tostring(ms)) end
                if coroutine.status(t.co) == 'dead' then table.remove(THREADS, i) else t.wake = NOW_MS + math.max(1, ms or 0) end
                ran = true
            end
        end
        if not ran then
            local nextWake = nil
            for _, t in ipairs(THREADS) do if not nextWake or t.wake < nextWake then nextWake = t.wake end end
            if not nextWake or nextWake > untilMs then NOW_MS = math.max(NOW_MS, untilMs) return end
            NOW_MS = nextWake
        end
    end
end
function Advance(sec) RunThreads(NOW_MS + math.floor(sec * 1000)) end

-- events ----------------------------------------------------------------
NET, HANDLERS = {}, {}
function RegisterNetEvent(name, fn) if fn then NET[name] = fn end end
function AddEventHandler(name, fn) HANDLERS[name] = HANDLERS[name] or {}; table.insert(HANDLERS[name], fn) end
function TriggerEvent(name, ...) for _, fn in ipairs(HANDLERS[name] or {}) do fn(...) end end
function TriggerClientEvent(name, target, ...)
    if name == 'sunny_train:client:response' then
        local _, result = ...
        LOG.responses[target] = result
    else
        LOG.client[#LOG.client + 1] = { name = name, target = target, args = { ... } }
    end
end
function FireServer(name, src, ...) source = src; NET[name](...) end
function Emit(name, src, ...) source = src; TriggerEvent(name, ...) end

-- natives serveur ---------------------------------------------------------
PEDS = {}          -- [src] = { pos = vector3, dead = false, weapon = hash, vehicle = 0 }
ENTITIES = {}      -- [entity] = { pos, vel }
NETIDS = {}        -- [netId] = entity
function GetPlayerPed(src) return PEDS[src] and ('ped' .. src) or 0 end
local function pedOf(ped) return PEDS[tonumber(tostring(ped):match('ped(%d+)'))] end
function GetEntityCoords(e)
    if type(e) == 'string' then return pedOf(e).pos end
    return ENTITIES[e] and ENTITIES[e].pos or vector3(0, 0, 0)
end
function GetEntityHealth(e) local p = pedOf(e) return (p and p.dead) and 0 or 200 end
function GetEntityVelocity(e) return ENTITIES[e] and ENTITIES[e].vel or vector3(0, 0, 0) end
function GetSelectedPedWeapon(e) local p = pedOf(e) return p and p.weapon or 0 end
function GetVehiclePedIsIn(e) local p = pedOf(e) return p and p.vehicle or 0 end
function NetworkGetEntityFromNetworkId(id) return NETIDS[id] or 0 end
function DoesEntityExist(e) return ENTITIES[e] ~= nil end
function DeleteEntity(e) ENTITIES[e] = nil end
function GetPlayerName(src) return PEDS[src] and ('Joueur' .. src) or nil end
function DropPlayer(src, reason) LOG.dropped = src end
function IsPlayerAceAllowed() return true end
function GetCurrentResourceName() return 'Sunny_train' end
function GetHashKey(s) local h = 0 for i = 1, #s do h = (h * 31 + s:byte(i)) % 4294967296 end return h end
GlobalState = {}

-- qbr-core ---------------------------------------------------------------
ITEMS = {
    animal_meat = { name = 'animal_meat', label = 'Viande' },
    coal = { name = 'coal', label = 'Charbon' }, metalscrap = { name = 'metalscrap', label = 'Ferraille' },
    iron = { name = 'iron', label = 'Fer' }, copper = { name = 'copper', label = 'Cuivre' },
}
PLAYERS = {}
USABLE = {}

function MakePlayer(src, citizenid, job, grade, cash, pos)
    PEDS[src] = { pos = pos, dead = false, weapon = 0, vehicle = 0 }
    local p = { PlayerData = {
        source = src, citizenid = citizenid, charinfo = { firstname = 'Prenom' .. src, lastname = 'Nom' },
        job = { name = job, label = job, onduty = false, grade = { level = grade, name = 'G' .. grade } },
        money = { cash = cash, bank = 0 }, items = {},
    }, Functions = {} }
    local pd = p.PlayerData
    p.Functions.GetMoney = function(t) return pd.money[t] end
    p.Functions.AddMoney = function(t, a) pd.money[t] = pd.money[t] + a return true end
    p.Functions.RemoveMoney = function(t, a) if pd.money[t] < a then return false end pd.money[t] = pd.money[t] - a return true end
    p.Functions.SetJobDuty = function(v) pd.job.onduty = v end
    p.Functions.AddItem = function(name, amount, slot, info)
        if not ITEMS[name] then return false end
        local s = #pd.items + 1
        pd.items[s] = { name = name, amount = amount, info = info or '', slot = s }
        return true
    end
    p.Functions.RemoveItem = function(name, amount, slot)
        for s, it in pairs(pd.items) do
            if (not slot or s == slot) and it.name == name and it.amount >= amount then
                it.amount = it.amount - amount
                if it.amount == 0 then pd.items[s] = nil end
                return true
            end
        end
        return false
    end
    PLAYERS[src] = p
    return p
end

local core = {}
function core:GetPlayer(src) return PLAYERS[src] end
function core:GetItems() return ITEMS end
function core:AddItem(name, def) ITEMS[name] = def return true, 'success' end
function core:CreateUseableItem(name, cb) USABLE[name] = cb end
function core:GetQBPlayers() return PLAYERS end
function core:AddCommand(name, help, arguments, required, callback, permission)
    COMMANDS[name] = callback
    COMMAND_PERMISSIONS = COMMAND_PERMISSIONS or {}
    COMMAND_PERMISSIONS[name] = permission
end

exports = setmetatable({ ['qbr-core'] = core }, { __call = function(_, name, fn) EXPORTED = EXPORTED or {}; EXPORTED[name] = fn end })

-- oxmysql (mémoire) --------------------------------------------------------
DB = { fleet = {}, tickets = {}, departures = {}, nextDeparture = 0 }
local function q(sql) return sql:gsub('%s+', ' ') end
MySQL = { query = {}, insert = {}, update = {}, scalar = {}, single = {} }
setmetatable(MySQL.query, { __call = function(_, sql, p) return MySQL.query.await(sql, p) end })
setmetatable(MySQL.insert, { __call = function(_, sql, p) return MySQL.insert.await(sql, p) end })
setmetatable(MySQL.update, { __call = function(_, sql, p) return MySQL.update.await(sql, p) end })
function MySQL.query.await(sql, p)
    sql = q(sql)
    if sql:find('SELECT category, expires_at FROM sunny_train_delivery_cooldowns') then
        local rows, prefix = {}, p[1] .. '/'
        for key, value in pairs(DB.deliveryCooldowns or {}) do
            if key:sub(1, #prefix) == prefix then rows[#rows + 1] = { category = key:sub(#prefix + 1), expires_at = value } end
        end
        return rows
    end
    if sql:find('SELECT %* FROM `sunny_train_departures`') then
        local rows = {}
        for _, d in pairs(DB.departures) do
            if d.status == p[1] and d.depart_at > p[2] then rows[#rows + 1] = d end
        end
        return rows
    end
    if sql:find('INSERT INTO stashitems') then DB.stash[p[1]] = p[2] return {} end
    if sql:find('^CREATE') or sql:find('^ALTER') then return {} end
    if sql:find('SELECT %* FROM `sunny_train_fleet`') then
        local rows = {}
        for k, v in pairs(DB.fleet) do rows[#rows + 1] = { train_key = k, condition = v.condition, status = v.status } end
        return rows
    end
    if sql:find('DELETE FROM `sunny_train_tickets` WHERE `serial`') then DB.tickets[p[1]] = nil return {} end
    if sql:find('DELETE FROM `sunny_train_tickets`') then return {} end
    error('query non gérée : ' .. sql)
end
function MySQL.insert.await(sql, p)
    sql = q(sql)
    if sql:find('sunny_train_delivery_cooldowns') then
        DB.deliveryCooldowns = DB.deliveryCooldowns or {}
        local key = p[1] .. '/' .. p[2]
        DB.deliveryCooldowns[key] = DB.deliveryCooldowns[key] or 0
        return 1
    end
    if sql:find('INSERT INTO `sunny_train_departures`') then
        DB.nextDeparture = DB.nextDeparture + 1
        DB.departures[DB.nextDeparture] = { id = DB.nextDeparture, station = p[1], destination = p[2],
            train_key = p[3], depart_at = p[4], created_by = p[5], created_name = p[6], status = p[7], auto = p[8] }
        return DB.nextDeparture
    end
    if sql:find('sunny_train_fleet') then DB.fleet[p[1]] = DB.fleet[p[1]] or { condition = 100, status = p[2] } return 1 end
    if sql:find('INSERT INTO `sunny_train_tickets`') then
        DB.tickets[p[1]] = { serial = p[1], citizenid = p[2], holder_name = p[3], from_station = p[4], to_station = p[5],
            route = p[6], class = p[7], price = p[8], issued_at = p[9], expires_at = p[10], departure_id = p[11], depart_at = p[12] }
        return 1
    end
    error('insert non géré : ' .. sql)
end
function MySQL.update.await(sql, p)
    sql = q(sql)
    if sql:find('sunny_train_delivery_cooldowns') then
        local key = p[2] .. '/' .. p[3]
        if DB.deliveryCooldowns[key] <= p[4] then DB.deliveryCooldowns[key] = p[1]; return 1 end
        return 0
    end
    if sql:find('UPDATE `sunny_train_tickets` SET `used_at` = NULL') then
        local row = DB.tickets[p[1]]
        if row and row.used_at == p[2] and row.used_by == p[3] then row.used_at = nil; row.used_by = nil; return 1 end
        return 0
    end
    if sql:find('UPDATE `sunny_train_departures`') then
        local d = assert(DB.departures[p[4]])
        d.status, d.departed_at, d.train_key = p[1], p[2], p[3]
        return 1
    end
    if sql:find('UPDATE `sunny_train_fleet`') then
        DB.fleet[p[7]] = { condition = p[1], status = p[2], owned = p[6] }
        return 1
    end
    if sql:find('UPDATE `sunny_train_tickets` SET `used_at`') then
        local row = DB.tickets[p[3]]
        if row and not row.used_at then row.used_at = p[1]; row.used_by = p[2]; return 1 end
        return 0
    end
    error('update non géré : ' .. sql)
end
function MySQL.scalar.await(sql, p)
    sql = q(sql)
    if sql:find('sunny_train_delivery_cooldowns') then
        return (DB.deliveryCooldowns or {})[p[1] .. '/' .. p[2]]
    end
    if sql:find('SELECT items FROM stashitems') then return DB.stash[p[1]] end
    if sql:find('FROM management_menu') then return DB.society[p[1]] end
    if sql:find('information_schema') then return 0 end
    if sql:find('SELECT 1 FROM') then return DB.tickets[p[1]] and 1 or nil end
    if sql:find('SELECT COUNT') then
        local n = 0
        for _, r in pairs(DB.tickets) do if r.citizenid == p[1] and not r.used_at and r.expires_at > p[2] then n = n + 1 end end
        return n
    end
    error('scalar non géré : ' .. sql)
end
function MySQL.single.await(sql, p)
    local r = DB.tickets[p[1]]
    if not r then return nil end
    local copy = {}
    for k, v in pairs(r) do copy[k] = v end
    return copy
end

-- journal des drapeaux de sécurité
local realPrint = print
function print(...)
    local s = table.concat({ ... }, ' ')
    if s:find('Suspect') then LOG.flags[#LOG.flags + 1] = s end
    if os.getenv and false then realPrint(...) end
    realPrint(...)
end
function GetPlayers() local t = {} for src in pairs(PLAYERS) do t[#t + 1] = tostring(src) end return t end

-- Sunny v2 mocks ------------------------------------------------------------
DB.stash, DB.society = {}, {}
local JSONSTORE = {}
local function deepcopy(t) if type(t) ~= 'table' then return t end local c = {} for k, v in pairs(t) do c[k] = deepcopy(v) end return c end
json = {
    encode = function(t) JSONSTORE[#JSONSTORE + 1] = deepcopy(t) return 'JSON#' .. #JSONSTORE end,
    decode = function(str) return deepcopy(JSONSTORE[tonumber(tostring(str):match('#(%d+)'))]) end,
}
COMMANDS = {}
function RegisterCommand(name, fn) COMMANDS[name] = fn end
-- qbr-management (boss menu) : événements serveur
AddEventHandler('qbr-bossmenu:server:removeAccountMoney', function(job, amount)
    if (DB.society[job] or 0) >= amount then DB.society[job] = DB.society[job] - amount end
end)
AddEventHandler('qbr-bossmenu:server:addAccountMoney', function(job, amount)
    DB.society[job] = (DB.society[job] or 0) + amount
end)
