-- ============================================================================
--  Sunny_train - Serveur : cœur
--  - Routeur unique de requêtes client -> serveur (réponse par identifiant)
--  - Permissions (lecture du job existant)
--  - Service ferroviaire (état de travail Sunny_train, synchronisable avec le
--    duty du système de job)
--  - Initialisation BDD, validation de la configuration, commandes
-- ============================================================================

local Srv = {
    handlers = {},
}
Sunny.Srv = Srv

local L = Sunny.L
local Bridge, Security, Utils = Sunny.Bridge, Sunny.Security, Sunny.Utils

-- ----------------------------------------------------------------------------
--  Routeur de requêtes
-- ----------------------------------------------------------------------------

--- Enregistre un gestionnaire de requête.
---@param name string
---@param fn fun(src:number, payload:table):table
---@param opts? { rate?: number }
local actionLocks = {}
function Srv.Register(name, fn, opts)
    if opts and opts.lock then
        local handler = fn
        fn = function(src, payload)
            local key = type(opts.lock) == 'function' and opts.lock(src, payload) or opts.lock
            if actionLocks[key] then return Srv.Fail('error_busy') end
            actionLocks[key] = true
            local ok, result = pcall(handler, src, payload)
            actionLocks[key] = nil
            if not ok then error(result) end
            return result
        end
    end
    Srv.handlers[name] = { fn = fn, rate = opts and opts.rate or nil }
end

function Srv.Fail(key, ...)
    return { ok = false, error = L(key, ...) }
end

function Srv.Notify(src, text, kind)
    TriggerClientEvent('sunny_train:client:notify', src, text, kind or 'info')
end

RegisterNetEvent('sunny_train:server:request', function(requestId, name, payload)
    local src = source
    if type(requestId) ~= 'number' or type(name) ~= 'string' then return end

    local handler = Srv.handlers[name]
    if not handler then
        Security.Flag(src, 'unknown_request', name)
        return
    end

    local function reply(result)
        TriggerClientEvent('sunny_train:client:response', src, requestId, result)
    end

    if not Security.RateLimit(src, name, handler.rate) then
        return reply(Srv.Fail('error_busy'))
    end
    if not Bridge.GetPlayer(src) then
        return reply(Srv.Fail('error_not_loaded'))
    end
    if not Srv.ready then return reply(Srv.Fail('error_busy')) end

    local ok, result = pcall(handler.fn, src, type(payload) == 'table' and payload or {})
    if not ok then
        print(('^1[Sunny_train] Erreur "%s" : %s^7'):format(name, tostring(result)))
        result = Srv.Fail('error_generic')
    end
    reply(result or { ok = true })
end)

-- ----------------------------------------------------------------------------
--  Permissions
-- ----------------------------------------------------------------------------

--- Le joueur a-t-il le droit d'effectuer `action` ?
---@param action 'employee'|'service'|'drive'|'control'|'maintenance'|'restore'
function Srv.Can(src, action)
    local job, grade = Bridge.GetJob(src)
    if not job then return false end
    local perms = Config.Permissions
    local table_ = action == 'employee' and perms.employees or perms.actions[action]
    if not Utils.HasJobAccess(table_, job, grade) then return false end
    return true
end

function Srv.IsOnService(src)
    return Srv.Can(src, 'employee')
end

--- Gare dont le bureau de la compagnie est à portée du joueur.
function Srv.NearestOffice(src)
    for key, station in pairs(Config.Stations) do
        for _, point in ipairs(Utils.StaffPoints(station)) do
            if Security.IsNear(src, point.coords, point.radius) then return key end
        end
    end
    return nil
end

--- Le joueur est-il au bureau de la gare `stationKey` ?
function Srv.AtOffice(src, stationKey)
    local station = Config.Stations[stationKey]
    if not station then return false end
    for _, point in ipairs(Utils.StaffPoints(station)) do
        if Security.IsNear(src, point.coords, point.radius) then return true end
    end
    return false
end

-- ----------------------------------------------------------------------------
--  Contexte du registre (menu employé)
-- ----------------------------------------------------------------------------
Srv.Register('company:context', function(src)
    if not Srv.Can(src, 'employee') then
        -- Diagnostic : job réellement lu par le serveur.
        local job, grade = Bridge.GetJob(src)
        local allowed = {}
        for name, min in pairs(Config.Permissions.employees) do allowed[#allowed + 1] = ('%s (grade %d+)'):format(name, min) end
        return Srv.Fail('error_not_employee', tostring(job), tonumber(grade) or 0, table.concat(allowed, ', '))
    end
    local _, _, onDuty, jobLabel, gradeName = Bridge.GetJob(src)
    return {
        ok = true,
        data = {
            name = Bridge.GetName(src),
            job = jobLabel,
            grade = gradeName,
            frameworkDuty = onDuty,
            onService = Srv.IsOnService(src),
            station = Srv.NearestOffice(src),
            perms = {
                drive = Srv.Can(src, 'drive'),
                control = Srv.Can(src, 'control'),
                maintenance = Srv.Can(src, 'maintenance') and Config.Maintenance.enabled,
                restore = Srv.Can(src, 'restore') and Config.Maintenance.enabled,
                freeTravel = Srv.Can(src, 'drive') and Config.FreeTravel.enabled,
                schedule = Srv.Can(src, 'schedule') and Config.Departures.enabled,
                purchase = Srv.Can(src, 'purchase'),
            },
            run = Sunny.Runs.Summary(src),
        },
    }
end)

-- ----------------------------------------------------------------------------
--  Service
-- ----------------------------------------------------------------------------
-- Les cheminots sont toujours actifs ; les droits suivent leur job actuel.

-- Le job peut changer à tout moment (Job Creator) : chaque action revérifie
-- les droits via Srv.Can, aucune donnée de job n'est mise en cache ici.

-- ----------------------------------------------------------------------------
--  Outils d'administration
-- ----------------------------------------------------------------------------
Srv.Register('admin:allowed', function(src)
    return { ok = IsPlayerAceAllowed(src, Config.Commands.positionAce) }
end, { rate = 1000 })

-- ----------------------------------------------------------------------------
--  Démarrage : BDD + validation
-- ----------------------------------------------------------------------------
local SCHEMA = {
    [[CREATE TABLE IF NOT EXISTS `sunny_train_delivery_cooldowns` (
        `owner` VARCHAR(64) NOT NULL,
        `category` VARCHAR(128) NOT NULL,
        `expires_at` BIGINT NOT NULL DEFAULT 0,
        PRIMARY KEY (`owner`, `category`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]],
    [[CREATE TABLE IF NOT EXISTS `sunny_train_fleet` (
        `train_key` VARCHAR(64) NOT NULL,
        `condition` TINYINT UNSIGNED NOT NULL DEFAULT 100,
        `status` VARCHAR(24) NOT NULL DEFAULT 'auto',
        `last_inspection` INT UNSIGNED NULL DEFAULT NULL,
        `last_repair` INT UNSIGNED NULL DEFAULT NULL,
        `updated_by` VARCHAR(64) NULL DEFAULT NULL,
        `owned` TINYINT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (`train_key`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci]],
    [[CREATE TABLE IF NOT EXISTS `sunny_train_tickets` (
        `serial` VARCHAR(20) NOT NULL,
        `citizenid` VARCHAR(64) NOT NULL,
        `holder_name` VARCHAR(128) NOT NULL DEFAULT '',
        `from_station` VARCHAR(64) NOT NULL,
        `to_station` VARCHAR(64) NOT NULL,
        `route` VARCHAR(255) NOT NULL,
        `class` VARCHAR(32) NOT NULL,
        `price` DECIMAL(10,2) NOT NULL DEFAULT 0,
        `issued_at` INT UNSIGNED NOT NULL,
        `expires_at` INT UNSIGNED NOT NULL,
        `used_at` INT UNSIGNED NULL DEFAULT NULL,
        `used_by` VARCHAR(64) NULL DEFAULT NULL,
        PRIMARY KEY (`serial`),
        KEY `idx_citizen` (`citizenid`),
        KEY `idx_expires` (`expires_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci]],
    [[CREATE TABLE IF NOT EXISTS `sunny_train_departures` (
        `id` INT UNSIGNED NOT NULL AUTO_INCREMENT,
        `station` VARCHAR(64) NOT NULL,
        `destination` VARCHAR(64) NOT NULL,
        `train_key` VARCHAR(64) NULL DEFAULT NULL,
        `depart_at` INT UNSIGNED NOT NULL,
        `created_by` VARCHAR(64) NULL DEFAULT NULL,
        `created_name` VARCHAR(128) NOT NULL DEFAULT '',
        `status` VARCHAR(16) NOT NULL DEFAULT 'scheduled',
        `departed_at` INT UNSIGNED NULL DEFAULT NULL,
        `auto` TINYINT UNSIGNED NOT NULL DEFAULT 0,
        PRIMARY KEY (`id`),
        KEY `idx_status` (`status`, `depart_at`)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci]],
    -- Mise à niveau : billets rattachés à un départ programmé.
    [[ALTER TABLE `sunny_train_tickets` ADD COLUMN IF NOT EXISTS `departure_id` INT UNSIGNED NULL DEFAULT NULL]],
    [[ALTER TABLE `sunny_train_tickets` ADD COLUMN IF NOT EXISTS `depart_at` INT UNSIGNED NULL DEFAULT NULL]],
    -- Mise à niveau : propriété du matériel (achats du patron).
    [[ALTER TABLE `sunny_train_fleet` ADD COLUMN IF NOT EXISTS `owned` TINYINT UNSIGNED NOT NULL DEFAULT 0]],
    -- Mise à niveau : un billet peut désormais couvrir plusieurs lignes.
    [[ALTER TABLE `sunny_train_tickets` MODIFY `route` VARCHAR(255) NOT NULL]],
}

Srv.ready = false

-- Étape de démarrage en cours : affichée si le démarrage reste bloqué
-- (base de données qui ne répond pas, requête verrouillée...).
local startupStep = 'validation de la configuration'
CreateThread(function()
    Wait(15000)
    if not Srv.ready then
        print(('^1[Sunny_train] Démarrage bloqué depuis 15 s à l\'étape : %s. Tant que ce n\'est pas terminé, toutes les actions répondent « Patientez un instant... ».^7'):format(startupStep))
    end
end)

CreateThread(function()
    local errors = Utils.ValidateConfig()
    for _, e in ipairs(errors) do
        print('^1[Sunny_train] Config : ' .. e .. '^7')
    end

    -- Migration : l'ancienne version s'appelait « Sunn_train » (tables sunn_train_*).
    for _, name in ipairs({ 'fleet', 'tickets' }) do
        local old, new = 'sunn_train_' .. name, 'sunny_train_' .. name
        startupStep = 'BDD : migration ' .. old
        local ok, e = pcall(function()
            local exists = function(t)
                return (MySQL.scalar.await('SELECT COUNT(*) FROM information_schema.tables WHERE table_schema = DATABASE() AND table_name = ?', { t }) or 0) > 0
            end
            if exists(old) and not exists(new) then
                MySQL.query.await(('RENAME TABLE `%s` TO `%s`'):format(old, new))
                print(('^2[Sunny_train]^7 Table %s renommée en %s.'):format(old, new))
            end
        end)
        if not ok then print('^1[Sunny_train] Migration : ' .. tostring(e) .. '^7') end
    end

    local schemaReady = true
    for _, query in ipairs(SCHEMA) do
        startupStep = 'BDD : ' .. query:gsub('%s+', ' '):sub(1, 90)
        local ok, e = pcall(MySQL.query.await, query)
        if not ok then
            schemaReady = false
            print('^1[Sunny_train] BDD : ' .. tostring(e) .. '^7')
        end
    end
    if not schemaReady then
        print('^1[Sunny_train] Démarrage interrompu : base de données incomplète (voir les erreurs BDD ci-dessus).^7')
        return -- ne pas accepter de paiements avec une BDD incomplète
    end

    startupStep = 'chargement de la flotte'
    Sunny.Fleet.Load()
    startupStep = 'initialisation des items'
    Sunny.Items.Init()
    startupStep = 'chargement des billets'
    Sunny.Tickets.Init()
    -- Départs programmés : chargés à part pour qu'une table verrouillée en BDD
    -- ne bloque pas toute la compagnie (registre, missions, billets).
    CreateThread(function()
        local done = false
        SetTimeout(10000, function()
            if not done then
                print('^1[Sunny_train] La lecture de la table sunny_train_departures ne répond pas : table verrouillée en BDD ? (SHOW FULL PROCESSLIST)^7')
            end
        end)
        Sunny.Departures.Load()
        done = true
    end)

    Srv.ready = true
    print(('^2[Sunny_train]^7 Prêt : %d gares, %d lignes, %d trains, %d missions.'):format(
        Utils.Count(Config.Stations), Utils.Count(Config.Routes), Utils.Count(Config.Trains), Utils.Count(Config.Missions)))
end)
