-- ============================================================================
--  Sunny_train - Pont framework (serveur)
--
--  SEUL fichier qui parle au core (qbr-core), à l'inventaire et au système de
--  job. Pour un autre framework, il suffit d'adapter les fonctions ci-dessous.
--
--  Sunny_train ne crée aucun job, grade, salaire, société ni inventaire : il
--  LIT le job (PlayerData.job, renseigné par qbr-core / Job Creator) et
--  UTILISE l'argent / les items existants.
-- ============================================================================

local Bridge = {}
Sunny.Bridge = Bridge

local CORE = Config.Framework.core

local function core()
    return exports[CORE]
end

function Bridge.GetPlayer(src)
    local ok, player = pcall(function() return core():GetPlayer(src) end)
    if ok then return player end
    return nil
end

function Bridge.GetCitizenId(src)
    local player = Bridge.GetPlayer(src)
    return player and player.PlayerData.citizenid or nil
end

function Bridge.GetName(src)
    local player = Bridge.GetPlayer(src)
    if not player then return GetPlayerName(src) or 'Inconnu' end
    local info = player.PlayerData.charinfo or {}
    if info.firstname then
        return ('%s %s'):format(info.firstname, info.lastname or '')
    end
    return GetPlayerName(src) or 'Inconnu'
end

--- Job du joueur (lecture seule).
---@return string|nil jobName, number grade, boolean onDuty, string label, string gradeName
function Bridge.GetJob(src)
    local player = Bridge.GetPlayer(src)
    if not player then return nil, 0, false, '', '' end
    if type(Config.Permissions.getJob) == 'function' then
        local ok, name, grade, onDuty = pcall(Config.Permissions.getJob, src, player)
        if ok then return name, tonumber(grade) or 0, onDuty ~= false, name or '', '' end
    end
    local job = player.PlayerData.job or {}
    local grade = job.grade or {}
    return job.name, tonumber(grade.level) or 0, job.onduty == true, job.label or '', grade.name or ''
end

function Bridge.GetMoney(src, account)
    local player = Bridge.GetPlayer(src)
    if not player then return 0 end
    return tonumber(player.Functions.GetMoney(account)) or 0
end

function Bridge.RemoveMoney(src, account, amount, reason)
    local player = Bridge.GetPlayer(src)
    if not player or amount < 0 then return false end
    if Bridge.GetMoney(src, account) < amount then return false end
    return player.Functions.RemoveMoney(account, amount, reason) == true
end

function Bridge.AddMoney(src, account, amount, reason)
    local player = Bridge.GetPlayer(src)
    if not player or amount <= 0 then return false end
    return player.Functions.AddMoney(account, amount, reason) == true
end

local function itemDefinition(name)
    local ok, items = pcall(function() return core():GetItems() end)
    if ok and type(items) == 'table' then return items[name] end
    return nil
end

function Bridge.ItemExists(name)
    return itemDefinition(name) ~= nil
end

function Bridge.ItemLabel(name)
    local def = itemDefinition(name)
    return def and def.label or name
end

--- Quantité totale d'un item.
function Bridge.CountItem(src, name)
    local player = Bridge.GetPlayer(src)
    if not player then return 0 end
    local total = 0
    for _, item in pairs(player.PlayerData.items or {}) do
        if item and item.name == name then total = total + (tonumber(item.amount) or 0) end
    end
    return total
end

--- Liste des items d'un nom donné (avec info).
function Bridge.GetItemsByName(src, name)
    local player = Bridge.GetPlayer(src)
    if not player then return {} end
    local list = {}
    for _, item in pairs(player.PlayerData.items or {}) do
        if item and item.name == name then list[#list + 1] = item end
    end
    return list
end

local function itemBox(src, name, action)
    local def = itemDefinition(name)
    if def then TriggerClientEvent('inventory:client:ItemBox', src, def, action) end
end

function Bridge.AddItem(src, name, amount, info)
    local player = Bridge.GetPlayer(src)
    if not player then return false end
    local ok = player.Functions.AddItem(name, amount, nil, info) == true
    if ok then itemBox(src, name, 'add') end
    return ok
end

function Bridge.RemoveItem(src, name, amount)
    local player = Bridge.GetPlayer(src)
    if not player then return false end
    local ok = player.Functions.RemoveItem(name, amount) == true
    if ok then itemBox(src, name, 'remove') end
    return ok
end

-- Retire le billet sélectionné, jamais le premier billet trouvé par son nom.
function Bridge.RemoveTicket(src, name, serial)
    local player = Bridge.GetPlayer(src)
    if not player then return false end
    for slot, item in pairs(player.PlayerData.items or {}) do
        if item and item.name == name and type(item.info) == 'table' and item.info.serial == serial then
            local ok = player.Functions.RemoveItem(name, 1, tonumber(item.slot or slot)) == true
            if ok then itemBox(src, name, 'remove') end
            return ok
        end
    end
    return false
end

--- Déclare l'item du billet s'il n'existe pas encore (aucun inventaire créé).
function Bridge.EnsureItem(name, definition)
    if Bridge.ItemExists(name) then return true end
    local ok, success, reason = pcall(function() return core():AddItem(name, definition) end)
    if ok and success then
        print(('^2[Sunny_train]^7 Item "%s" déclaré dans qbr-core.'):format(name))
        return true
    end
    print(('^1[Sunny_train]^7 Impossible de déclarer l\'item "%s" (%s). Ajoutez-le à qbr-core/shared/items.lua.'):format(name, tostring(reason)))
    return false
end

function Bridge.RegisterUsableItem(name, cb)
    local ok, e = pcall(function() core():CreateUseableItem(name, cb) end)
    if not ok then print(('^1[Sunny_train]^7 CreateUseableItem(%s) : %s'):format(name, tostring(e))) end
end

--- Joueurs (sources) ayant un des jobs donnés, optionnellement en service.
function Bridge.GetPlayersWithJobs(jobs, onDutyOnly)
    local lookup = {}
    for _, job in ipairs(jobs or {}) do lookup[job] = true end
    local result = {}
    local ok, players = pcall(function() return core():GetQBPlayers() end)
    if not ok or type(players) ~= 'table' then return result end
    for src, player in pairs(players) do
        local job = player.PlayerData and player.PlayerData.job
        if job and lookup[job.name] and (not onDutyOnly or job.onduty) then
            result[#result + 1] = tonumber(src)
        end
    end
    return result
end

-- ----------------------------------------------------------------------------
--  Société (achats de matériel) — aucun système de société n'est créé ici :
--  on utilise celui du serveur (qbr-management) ou des fonctions fournies
--  dans Config.Purchase.society (ex. Job Creator sur le serveur principal).
-- ----------------------------------------------------------------------------

function Bridge.SocietyBalance(job)
    local s = Config.Purchase.society
    if s.system == 'custom' then
        local ok, value = pcall(s.getBalance, job)
        return ok and (tonumber(value) or 0) or 0
    end
    -- qbr-management : le solde en mémoire est enregistré à chaque mouvement.
    local amount = MySQL.scalar.await('SELECT amount FROM management_menu WHERE job_name = ? AND menu_type = ?', { job, 'boss' })
    return tonumber(amount) or 0
end

function Bridge.SocietyRemove(job, amount)
    local s = Config.Purchase.society
    if s.system == 'custom' then
        local ok, done = pcall(s.remove, job, amount)
        return ok and done == true
    end
    if Bridge.SocietyBalance(job) < amount then return false end
    TriggerEvent('qbr-bossmenu:server:removeAccountMoney', job, amount)
    return true
end

function Bridge.SocietyAdd(job, amount)
    local s = Config.Purchase.society
    if s.system == 'custom' then
        pcall(s.add, job, amount)
        return
    end
    TriggerEvent('qbr-bossmenu:server:addAccountMoney', job, amount)
end

--- Débite un achat de matériel selon Config.Purchase.account.
function Bridge.PayPurchase(src, amount, reason)
    local account = Config.Purchase.account
    if account == 'society' then
        local job = Bridge.GetJob(src)
        return job ~= nil and Bridge.SocietyRemove(job, amount)
    end
    return Bridge.RemoveMoney(src, account, amount, reason)
end

--- Crédite une revente de matériel selon Config.Purchase.account.
function Bridge.RefundPurchase(src, amount, reason)
    local account = Config.Purchase.account
    if account == 'society' then
        local job = Bridge.GetJob(src)
        if job then Bridge.SocietyAdd(job, amount) end
        return
    end
    Bridge.AddMoney(src, account, amount, reason)
end

--- Solde disponible pour les achats (affichage).
function Bridge.PurchaseBalance(src)
    local account = Config.Purchase.account
    if account == 'society' then
        local job = Bridge.GetJob(src)
        return job and Bridge.SocietyBalance(job) or 0
    end
    return Bridge.GetMoney(src, account)
end
