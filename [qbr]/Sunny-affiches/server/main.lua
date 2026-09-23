local QBCore = exports['qbr-core']


local databaseReady, operationBusy = false, false
local function RegisterCallback(name, handler)
    QBCore:CreateCallback(name, function(source, cb, data)
        if not databaseReady or operationBusy then
            return cb({ ok = false, error = 'Le panneau est occupé, réessaie dans un instant.' })
        end
        operationBusy = true
        local response
        local ok, err = xpcall(function()
            handler(source, function(result) response = result end, data)
        end, debug.traceback)
        operationBusy = false
        if not ok then
            print('[Sunny-affiches] ' .. tostring(err))
            response = { ok = false, error = 'Une erreur serveur est survenue. Réessaie dans un instant.' }
        end
        cb(response or { ok = false, error = 'Opération incomplète.' })
    end)
end

local function ParkStock(ids)
    if #ids == 0 then return true end
    local marks = {}
    for i = 1, #ids do marks[i] = '?' end
    local list = table.concat(marks, ',')
    return MySQL.transaction.await({
        { query = ('SELECT id FROM affiches_posters WHERE id IN (%s) FOR UPDATE'):format(list), values = ids },
        { query = ("INSERT INTO affiches_returns (citizenid, journal_id, journal_item, journal_title, journal_edition, copies) SELECT author_citizenid, journal_id, journal_item, journal_title, journal_edition, stock FROM affiches_posters WHERE id IN (%s) AND journal_id <> '' AND stock > 0"):format(list), values = ids },
        { query = ('DELETE FROM affiches_posters WHERE id IN (%s)'):format(list), values = ids },
    })
end



local Countries, CountryList, Cats, CatList, Boards = {}, {}, {}, {}, {}
local MaxDays = math.max(1, math.floor(tonumber(Config.MaxDays) or 30))


local function NormalizeJobs(spec)
    if spec == true then return true end
    local map = {}
    if type(spec) ~= 'table' then return map end
    for key, value in pairs(spec) do
        if type(key) == 'number' then
            if type(value) == 'string' then map[value] = 0 end
        elseif type(key) == 'string' and value ~= false then
            map[key] = tonumber(value) or 0
        end
    end
    return map
end

for _, country in ipairs(Config.Countries) do
    if type(country.key) ~= 'string' or not country.key:match('^[%w_]+$') or Countries[country.key] then
        print(('[Sunny-affiches] pays ignoré (clé invalide ou en double) : %s'):format(tostring(country.key)))
    else
        Countries[country.key] = country
        CountryList[#CountryList + 1] = country
    end
end
assert(#CountryList > 0, '[Sunny-affiches] Config.Countries est vide')

for _, cat in ipairs(Config.Categories) do
    if type(cat.key) ~= 'string' or Cats[cat.key] then
        print(('[Sunny-affiches] catégorie ignorée (clé manquante ou en double) : %s'):format(tostring(cat.key)))
    else
        -- durées en jours : entre 1 et Config.MaxDays (jamais plus) ; 0 = indéfiniment si Config.AllowIndefinite
        local durations = {}
        for _, d in ipairs(cat.durations or Config.Durations) do
            if type(d) == 'number' then
                if d == 0 then
                    if Config.AllowIndefinite then durations[#durations + 1] = 0 end
                elseif d >= 1 and d <= MaxDays then
                    durations[#durations + 1] = math.floor(d)
                end
            end
        end
        if #durations == 0 then durations[1] = MaxDays end
        cat.durations = durations
        if cat.defaultDays == nil then cat.defaultDays = Config.DefaultDays end
        local found = false
        for _, d in ipairs(cat.durations) do if d == cat.defaultDays then found = true end end
        if not found then cat.defaultDays = cat.durations[1] or 0 end

        -- pays où la catégorie existe (défaut : tous)
        cat.inCountry = {}
        for _, country in ipairs(CountryList) do
            local listed = cat.countries == nil
            for _, key in ipairs(cat.countries or {}) do
                if key == country.key then listed = true end
            end
            cat.inCountry[country.key] = listed
        end

        cat.viewRule = cat.view ~= nil and NormalizeJobs(cat.view) or nil
        Cats[cat.key] = cat
        CatList[#CatList + 1] = cat
    end
end

for _, board in ipairs(Config.Boards) do
    if board.enabled == false then
        -- panneau désactivé dans la config : ignoré
    elseif type(board.id) ~= 'string' or Boards[board.id] then
        print(('[Sunny-affiches] panneau ignoré (id manquant ou en double) : %s'):format(tostring(board.id)))
    elseif not Countries[board.country] then
        print(('[Sunny-affiches] panneau %s ignoré : pays inconnu (%s)'):format(board.id, tostring(board.country)))
    else
        Boards[board.id] = board
    end
end

-------------------------------------------------------------------------

local Perms = {}
for _, country in ipairs(CountryList) do
    Perms[country.key] = {}
    for _, cat in ipairs(CatList) do
        -- Propagande : tout le monde peut publier ; modifier / supprimer / épingler = admins
        -- (Config.AdminBypass) et l'auteur de l'affiche seulement (Config.AuthorCanManageOwn).
        if cat.key == 'propagande' then
            Perms[country.key][cat.key] = {
                publier = true,
                gerer = {},
                epingler = {},
            }
        else
            local spec = {}
            local ofCountry = type(Config.Jobs) == 'table' and Config.Jobs[country.key]
            if type(ofCountry) == 'table' and type(ofCountry[cat.key]) == 'table' then spec = ofCountry[cat.key] end
            local gerer = NormalizeJobs(spec.gerer)
            -- Gérer une catégorie inclut la publication, dès le grade minimum.
            -- Une autorisation explicite dans publier peut ouvrir l'accès plus tôt.
            local publier = NormalizeJobs(spec.publier)
            if gerer == true then
                publier = true
            elseif publier ~= true then
                for job, grade in pairs(gerer) do
                    publier[job] = math.min(publier[job] or grade, grade)
                end
            end
            Perms[country.key][cat.key] = {
                publier = publier,
                gerer = gerer,
                epingler = spec.epingler ~= nil and NormalizeJobs(spec.epingler) or gerer,
            }
        end
    end
end

local function CheckJobs()
    local problems = {}
    if type(Config.Jobs) ~= 'table' then return { 'Config.Jobs est absent ou invalide.' }, false end

    for countryKey, cats in pairs(Config.Jobs) do
        if not Countries[countryKey] then
            problems[#problems + 1] = ('Config.Jobs : pays inconnu « %s » (pays valides : Config.Countries)'):format(tostring(countryKey))
        elseif type(cats) == 'table' then
            for catKey, spec in pairs(cats) do
                if not Cats[catKey] then
                    problems[#problems + 1] = ('Config.Jobs.%s : catégorie inconnue « %s »'):format(countryKey, tostring(catKey))
                elseif type(spec) == 'table' then
                    for right in pairs(spec) do
                        if right ~= 'publier' and right ~= 'gerer' and right ~= 'epingler' then
                            problems[#problems + 1] = ('Config.Jobs.%s.%s : droit inconnu « %s » (attendu : publier, gerer, epingler)'):format(countryKey, catKey, tostring(right))
                        end
                    end
                end
            end
        end
    end

    local ok, jobs = pcall(function() return QBCore:GetJobs() end)
    if not ok or type(jobs) ~= 'table' then return problems, false end

    for _, country in ipairs(CountryList) do
        for _, cat in ipairs(CatList) do
            local perms = Perms[country.key][cat.key]
            local spec = type(Config.Jobs[country.key]) == 'table' and Config.Jobs[country.key][cat.key] or {}
            for _, right in ipairs({ 'publier', 'gerer', 'epingler' }) do
                local map = perms[right]
                if map ~= true and (right ~= 'epingler' or (type(spec) == 'table' and spec.epingler ~= nil)) then
                    for job, grade in pairs(map) do
                        local def = jobs[job]
                        if not def then
                            problems[#problems + 1] = ('%s / %s / %s : le métier « %s » n\'existe pas dans jobs.lua'):format(country.label, cat.label, right, job)
                        else
                            local maxGrade = 0
                            for level in pairs(def.grades or {}) do maxGrade = math.max(maxGrade, tonumber(level) or 0) end
                            if grade > maxGrade then
                                problems[#problems + 1] = ('%s / %s / %s : le métier « %s » n\'a pas de grade %d (grade max : %d)'):format(country.label, cat.label, right, job, grade, maxGrade)
                            end
                        end
                    end
                end
            end
        end
    end
    return problems, true
end

CreateThread(function()
    if not Config.Debug then return end
    Wait(6000)
    local problems, checked = CheckJobs()
    for _, problem in ipairs(problems) do print('[Sunny-affiches] ATTENTION : ' .. problem) end
    if not checked then print('[Sunny-affiches] Les noms de métiers n\'ont pas pu être vérifiés (GetJobs de qbr-core indisponible).') end
end)



CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `affiches_posters` (
          `id` int(11) NOT NULL AUTO_INCREMENT,
          `country` varchar(32) NOT NULL,
          `category` varchar(32) NOT NULL,
          `title` varchar(100) NOT NULL,
          `url` varchar(500) NOT NULL DEFAULT '',
          `org` varchar(100) NOT NULL DEFAULT '',
          `author_name` varchar(100) NOT NULL,
          `author_citizenid` varchar(50) NOT NULL,
          `author_job` varchar(50) NOT NULL DEFAULT '',
          `pinned` tinyint(1) NOT NULL DEFAULT 0,
          `anonymous` tinyint(1) NOT NULL DEFAULT 0,
          `journal_id` varchar(16) NOT NULL DEFAULT '',
          `journal_item` varchar(50) NOT NULL DEFAULT '',
          `journal_title` varchar(100) NOT NULL DEFAULT '',
          `journal_edition` int(11) NOT NULL DEFAULT 0,
          `price_cents` int(11) NOT NULL DEFAULT 0,
          `stock` int(11) NOT NULL DEFAULT 0,
          `sold` int(11) NOT NULL DEFAULT 0,
          `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
          `updated_at` timestamp NULL DEFAULT NULL,
          `expires_at` timestamp NULL DEFAULT NULL,
          PRIMARY KEY (`id`),
          KEY `country_category` (`country`, `category`),
          KEY `expires_at` (`expires_at`),
          KEY `author` (`author_citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]])

    for _, column in ipairs({
        '`anonymous` tinyint(1) NOT NULL DEFAULT 0',
        "`journal_id` varchar(16) NOT NULL DEFAULT ''",
        "`journal_item` varchar(50) NOT NULL DEFAULT ''",
        "`journal_title` varchar(100) NOT NULL DEFAULT ''",
        '`journal_edition` int(11) NOT NULL DEFAULT 0',
        '`price_cents` int(11) NOT NULL DEFAULT 0',
        '`stock` int(11) NOT NULL DEFAULT 0',
        '`sold` int(11) NOT NULL DEFAULT 0',
    }) do
        MySQL.query.await(('ALTER TABLE `affiches_posters` ADD COLUMN IF NOT EXISTS %s'):format(column))
    end
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `affiches_wallet` (
          `citizenid` varchar(50) NOT NULL,
          `cents` bigint(20) NOT NULL DEFAULT 0,
          `updated_at` timestamp NOT NULL DEFAULT current_timestamp() ON UPDATE current_timestamp(),
          PRIMARY KEY (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]])
    -- Recettes personnelles s?par?es par pays et r?daction. L'ancienne caisse reste conserv?e.
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS affiches_journal_wallet (
        citizenid varchar(50) NOT NULL,
        country varchar(32) NOT NULL,
        paper varchar(50) NOT NULL,
        cents bigint(20) NOT NULL DEFAULT 0,
        PRIMARY KEY (citizenid, country, paper)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci]])

    -- Exemplaires invendus d'une affiche supprimée ou expirée : ils attendent que le journaliste les récupère.
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `affiches_returns` (
          `id` int(11) NOT NULL AUTO_INCREMENT,
          `citizenid` varchar(50) NOT NULL,
          `journal_id` varchar(16) NOT NULL,
          `journal_item` varchar(50) NOT NULL DEFAULT '',
          `journal_title` varchar(100) NOT NULL DEFAULT '',
          `journal_edition` int(11) NOT NULL DEFAULT 0,
          `copies` int(11) NOT NULL DEFAULT 0,
          `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
          PRIMARY KEY (`id`),
          KEY `citizenid` (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]])

    MySQL.query.await(("ALTER TABLE `affiches_posters` ADD COLUMN IF NOT EXISTS `country` varchar(32) NOT NULL DEFAULT '%s' AFTER `id`"):format(CountryList[1].key))
    MySQL.query.await('ALTER TABLE `affiches_posters` ADD INDEX IF NOT EXISTS `country_category` (`country`, `category`)')
    MySQL.query.await('ALTER TABLE `affiches_posters` DROP INDEX IF EXISTS `category_city`')
    MySQL.query.await('ALTER TABLE `affiches_posters` DROP COLUMN IF EXISTS `description`')
    MySQL.query.await('ALTER TABLE `affiches_posters` DROP COLUMN IF EXISTS `city`')
    MySQL.query.await('ALTER TABLE `affiches_posters` ADD COLUMN IF NOT EXISTS `pinned` tinyint(1) NOT NULL DEFAULT 0 AFTER `author_job`')


    local capWhere = Config.AllowIndefinite and 'expires_at IS NOT NULL AND expires_at > created_at + INTERVAL %d DAY'
        or 'expires_at IS NULL OR expires_at > created_at + INTERVAL %d DAY'
    local capped = MySQL.update.await(('UPDATE affiches_posters SET expires_at = created_at + INTERVAL %d DAY WHERE ' .. capWhere):format(MaxDays, MaxDays))
    if Config.Debug and capped and capped > 0 then
        print(('[Sunny-affiches] %d affiche(s) raccourcie(s) à %d jours maximum.'):format(capped, MaxDays))
    end

    local keys = {}
    for _, cat in ipairs(CatList) do keys[#keys + 1] = cat.key end
    if #keys > 0 then
        local marks = {}
        for i = 1, #keys do marks[i] = '?' end
        local rows = MySQL.query.await(('SELECT id FROM affiches_posters WHERE category NOT IN (%s)'):format(table.concat(marks, ',')), keys)
        local ids = {}
        for _, row in ipairs(rows or {}) do ids[#ids + 1] = row.id end
        if #ids > 0 and ParkStock(ids) then
            if Config.Debug then
                print(('[Sunny-affiches] %d affiche(s) supprimée(s) : catégorie retirée de la config.'):format(#ids))
            end
        end
    end
    databaseReady = true
end)


local function Fail(text)
    return { ok = false, error = text }
end

-- Argent : les prix sont stockés en centimes (entiers), affichés et versés en dollars.
local function Cents(dollars)
    return math.floor((tonumber(dollars) or 0) * 100 + 0.5)
end

local function Dollars(cents)
    return (tonumber(cents) or 0) / 100
end

-- Colonnes tinyint(1) : oxmysql les renvoie en booléens (true/false), pas en 0/1.
local function IsFlag(value)
    return value == true or value == 1 or value == '1'
end

local function CharName(Player)
    local info = Player.PlayerData.charinfo
    return info.firstname .. ' ' .. info.lastname
end

local function Trim(value)
    return (value:gsub('^%s+', ''):gsub('%s+$', ''))
end

-- Texte d'une ligne (titre, organisation) : nil si invalide, '' si vide.
local function CleanLine(value, maxLength)
    if value == nil then return '' end
    if type(value) ~= 'string' then return nil end
    value = Trim(value:gsub('[%c<>]', ''))
    local length = utf8.len(value)
    if not length or length > maxLength then return nil end
    return value
end

local function CleanUrl(value)
    if value == nil then return '' end
    if type(value) ~= 'string' then return nil end
    value = Trim(value)
    if value == '' then return '' end
    if #value > Config.MaxUrlLength then return nil end
    if not value:find('^https?://') then return nil end
    if value:find('[%s%c"\'<>`\\]') then return nil end
    local host = (value:match('^https?://([^/:?#]+)') or ''):lower()
    if #Config.AllowedHosts > 0 then
        for _, allowed in ipairs(Config.AllowedHosts) do
            if host == allowed:lower() then return value end
        end
        return nil
    end
    return value
end




local function HasAdminGroup(src)
    for _, group in ipairs(Config.AdminGroups) do
        if QBCore:HasPermission(src, group) then return true end
    end
    return false
end

-- Config.AdminBypass controls administrator access.
local function IsAdmin(src)
    if not Config.AdminBypass then return false end
    return HasAdminGroup(src)
end

-- rule : true / false / { metier = grade_minimum } ; nil -> default
local function RuleAllows(Player, rule, default)
    if rule == nil then return default end
    if rule == true then return true end
    if type(rule) ~= 'table' then return false end
    local job = Player.PlayerData.job
    local min = job and rule[job.name]
    if min == nil then return false end
    if min == true then return true end
    local level = job.grade and tonumber(job.grade.level) or 0
    return level >= min
end

local RIGHT_OF = { create = 'publier', edit = 'gerer', delete = 'gerer', pin = 'epingler' }
local function RuleFor(cat, country, field)
    local perms = Perms[country] and Perms[country][cat.key]
    return perms and perms[RIGHT_OF[field]] or {}
end

local function CanCreate(ctx, cat, country)
    return ctx.admin or RuleAllows(ctx.Player, RuleFor(cat, country, 'create'), false)
end

local function CanPin(ctx, cat, row)
    return ctx.admin or RuleAllows(ctx.Player, RuleFor(cat, row.country, 'pin'), false)
end

local function CanView(ctx, cat)
    return ctx.admin or RuleAllows(ctx.Player, cat.viewRule, true)
end

local function IsAuthor(ctx, row)
    return row.author_citizenid == ctx.Player.PlayerData.citizenid
end

local function CanEdit(ctx, cat, row)
    if ctx.admin or RuleAllows(ctx.Player, RuleFor(cat, row.country, 'edit'), false) then return true end
    return Config.AuthorCanManageOwn and IsAuthor(ctx, row) and CanCreate(ctx, cat, row.country)
end

local function CanDelete(ctx, cat, row)
    if ctx.admin or RuleAllows(ctx.Player, RuleFor(cat, row.country, 'delete'), false) then return true end
    return Config.AuthorCanManageOwn and IsAuthor(ctx, row) and CanCreate(ctx, cat, row.country)
end

local function NearBoard(src, board)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return true end
    local c = GetEntityCoords(ped)
    if c.x == 0.0 and c.y == 0.0 and c.z == 0.0 then return true end
    local target = vector3(board.coords.x, board.coords.y, board.coords.z)
    return #(c - target) <= (board.distance or 2.0) + Config.ServerDistanceSlack + 1.5
end

local function GetContext(src, boardId)
    local Player = QBCore:GetPlayer(src)
    if not Player then return nil, 'Joueur introuvable.' end
    local board = type(boardId) == 'string' and Boards[boardId]
    if not board then return nil, 'Ce panneau n\'existe pas.' end
    if not NearBoard(src, board) then return nil, 'Tu es trop loin du panneau.' end
    return { src = src, Player = Player, admin = IsAdmin(src), board = board }
end

-- Catégorie consultable dans un pays donné.
local function CatFor(ctx, key, country)
    local cat = type(key) == 'string' and Cats[key]
    if not cat or type(country) ~= 'string' or not Countries[country] then return nil end
    if not cat.inCountry[country] or not CanView(ctx, cat) then return nil end
    return cat
end



local COLORS = { create = 0x3F6B2B, edit = 0xC77B1E, delete = 0x8F2D1F, pin = 0x2F4A6B, unpin = 0x5B4A38, expire = 0x777777 }
local TITLES = {
    create = '[AFFICHAGE] Nouvelle affiche',
    edit = '[AFFICHAGE] Affiche modifiée',
    delete = '[AFFICHAGE] Affiche supprimée',
    pin = '[AFFICHAGE] Affiche épinglée',
    unpin = '[AFFICHAGE] Affiche désépinglée',
    expire = '[AFFICHAGE] Affiches expirées',
}

local function CountryLabel(key)
    return Countries[key] and Countries[key].label or tostring(key)
end

local function ExpiryLabel(days)
    if not days or days <= 0 then return 'Jamais' end
    return days .. ' jour' .. (days > 1 and 's' or '')
end

local function Actor(Player)
    local job = Player.PlayerData.job
    local grade = job and job.grade and job.grade.name
    local name = CharName(Player)
    return (grade and grade ~= '' and (grade .. ' ') or '') .. name, job and job.label or 'Civil'
end

local function PlayerFooter(ctx)
    local parts = { ('ID %d'):format(ctx.src), 'CitizenID ' .. ctx.Player.PlayerData.citizenid, GetPlayerName(ctx.src) or '?' }
    if GetPlayerIdentifierByType then
        local discord = GetPlayerIdentifierByType(ctx.src, 'discord')
        if discord then parts[#parts + 1] = '<@' .. discord:gsub('^discord:', '') .. '>' end
    end
    return table.concat(parts, ' · ')
end

local function SendWebhook(kind, cat, payload)
    if not Config.LogEvents[kind] then return end
    local url = cat and cat.webhook
    if type(url) ~= 'string' or url == '' then url = Config.Webhook end
    if type(url) ~= 'string' or url == '' then return end

    payload.username = Config.WebhookName
    payload.allowed_mentions = { parse = {} }
    PerformHttpRequest(url, function() end, 'POST', json.encode(payload), { ['Content-Type'] = 'application/json' })
end

local function LogPoster(kind, ctx, cat, row, days)
    local who, jobLabel = Actor(ctx.Player)
    local country = CountryLabel(row.country)
    local verb = kind == 'create' and 'a publié une nouvelle affiche dans'
        or kind == 'edit' and ('a modifié l\'affiche « %s » dans'):format(row.title)
        or kind == 'pin' and ('a épinglé l\'affiche « %s » dans'):format(row.title)
        or kind == 'unpin' and ('a retiré l\'épingle de l\'affiche « %s » dans'):format(row.title)
        or ('a supprimé l\'affiche « %s » de'):format(row.title)

    local description = ('**%s** (%s) %s la catégorie **%s** (%s).'):format(who, jobLabel, verb, cat.label, country)
    if kind == 'delete' and row.author_citizenid ~= ctx.Player.PlayerData.citizenid then
        description = description .. ('\nAffiche publiée par **%s**.'):format(row.author_name)
    end

    local fields = {
        { name = 'Titre', value = row.title, inline = true },
        { name = 'Catégorie', value = cat.label, inline = true },
        { name = 'Pays', value = country, inline = true },
    }
    if row.org and row.org ~= '' then
        fields[#fields + 1] = { name = 'Organisation', value = row.org, inline = true }
    end
    -- Le staff garde toujours l'identité de l'auteur dans les logs, même si l'affiche est anonyme en jeu.
    if IsFlag(row.anonymous) then
        fields[#fields + 1] = { name = 'Anonyme', value = ('Oui, auteur : %s (CitizenID %s)'):format(row.author_name or '?', row.author_citizenid or '?'), inline = false }
    end
    if days ~= nil then
        fields[#fields + 1] = { name = 'Expiration', value = ExpiryLabel(days), inline = true }
    end
    fields[#fields + 1] = { name = 'Date', value = os.date('%d/%m/%Y %H:%M:%S'), inline = true }
    if row.journal then
        fields[#fields + 1] = {
            name = 'Journal lié',
            value = ('Édition n°%s « %s » — %.2f $ — stock : %d'):format(tostring(row.journal.edition), row.journal.title or '?', Dollars(row.journal.price_cents), tonumber(row.journal.stock) or 0),
            inline = false,
        }
    end
    if row.url and row.url ~= '' then fields[#fields + 1] = { name = 'Image', value = row.url, inline = false } end

    local embed = {
        title = TITLES[kind],
        description = description,
        color = COLORS[kind],
        fields = fields,
        footer = { text = PlayerFooter(ctx) },
        timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
    }
    if row.url and row.url ~= '' then embed.image = { url = row.url } end

    local plain = ('[AFFICHAGE] %s %s la catégorie %s (%s).'):format(who, verb, cat.label, country)
    SendWebhook(kind, cat, { content = plain, embeds = { embed } })
end


local lastPurge = 0

local function PurgeExpired(force)
    local now = os.time()
    if not force and now - lastPurge < 30 then return end
    lastPurge = now

    local rows = MySQL.query.await('SELECT id, country, category, title, journal_id, stock FROM affiches_posters WHERE expires_at IS NOT NULL AND expires_at <= NOW()')
    if not rows or #rows == 0 then return end

    local ids = {}
    for i, row in ipairs(rows) do ids[i] = row.id end
    if not ParkStock(ids) then return end
    local deleted = #ids

    if Config.LogEvents.expire and (deleted or 0) > 0 then
        local lines = {}
        for i, row in ipairs(rows) do
            if i > 10 then lines[#lines + 1] = ('… et %d autre(s)'):format(#rows - 10) break end
            local cat = Cats[row.category]
            lines[#lines + 1] = ('• %s — %s (%s)'):format(row.title, cat and cat.label or row.category, CountryLabel(row.country))
        end
        SendWebhook('expire', nil, {
            embeds = {{
                title = TITLES.expire,
                description = table.concat(lines, '\n'),
                color = COLORS.expire,
                timestamp = os.date('!%Y-%m-%dT%H:%M:%SZ'),
            }},
        })
    end
end

CreateThread(function()
    Wait(5000)
    while true do
        if databaseReady and not operationBusy then
            operationBusy = true
            local ok, err = xpcall(function() PurgeExpired(true) end, debug.traceback)
            operationBusy = false
            if not ok then print('[Sunny-affiches] ' .. tostring(err)) end
        end
        Wait(5 * 60 * 1000)
    end
end)



local function JournalOn()
    return type(Config.Journal) == 'table' and Config.Journal.Enabled == true and Cats[Config.Journal.Category] ~= nil
end

local function PaperOf(Player)
    local job = Player.PlayerData.job
    return job and type(Config.Journal.Papers) == 'table' and Config.Journal.Papers[job.name] or nil
end


local function FetchEditions(ctx)
    local where, params = 'paper = ?', { PaperOf(ctx.Player) }
    if ctx.admin then where, params = '1 = 1', {} end
    local ok, rows = pcall(function()
        return MySQL.query.await(("SELECT journal_id, title, edition, paper, JSON_UNQUOTE(JSON_EXTRACT(pages, '$[0].url')) AS cover FROM newspapers WHERE status = 'published' AND (%s) ORDER BY edition DESC, published_at DESC LIMIT 40"):format(where), params)
    end)
    if not ok then return nil end          -- sunny_journal absent ou table introuvable
    return rows or {}
end

local function GetEdition(journalId)
    local ok, row = pcall(function()
        return MySQL.single.await("SELECT journal_id, title, edition, paper, author_name, author_citizenid, JSON_UNQUOTE(JSON_EXTRACT(pages, '$[0].url')) AS cover FROM newspapers WHERE journal_id = ? AND status = 'published'", { journalId })
    end)
    return ok and row or nil
end

local function CanLinkEdition(ctx, edition)
    if ctx.admin then return true end
    local paper = PaperOf(ctx.Player)
    return paper ~= nil and edition.paper == paper
end

local BUNDLE = 'newspaper_bundle'

-- Ne recense que les exemplaires seuls : les lots (BUNDLE) ne comptent pas pour la mise en vente.
local function InventorySlots(Player, journalId)
    local found = {}
    for key, item in pairs(Player.PlayerData.items or {}) do
        local newspaper = false
        if type(item) == 'table' then
            for _, paper in pairs(Config.Journal.Papers or {}) do
                if item.name == paper then newspaper = true break end
            end
        end
        if newspaper and type(item.info) == 'table' and item.info.journal_id == journalId then
            local count = math.floor(tonumber(item.amount) or 1)
            if count > 0 then found[#found + 1] = { slot = tonumber(item.slot) or tonumber(key) or 0, item = item, count = count } end
        end
    end
    table.sort(found, function(a, b) return a.slot < b.slot end)
    return found
end

local function InventoryCopies(Player, journalId)
    local total = 0
    for _, entry in ipairs(InventorySlots(Player, journalId)) do total = total + entry.count end
    return total
end

-- Retire `amount` exemplaires seuls de l'inventaire (jamais de lot) ; renvoie le nombre réellement retiré.
local function TakeCopies(Player, journalId, amount)
    local took = 0
    for _, entry in ipairs(InventorySlots(Player, journalId)) do
        if took >= amount then break end
        local use = math.min(entry.count, amount - took)
        if not Player.Functions.RemoveItem(entry.item.name, use, entry.slot) then break end
        took = took + use
    end
    return took
end


local function GiveCopies(Player, edition, amount)
    local item = (edition.paper and edition.paper ~= '') and edition.paper or nil
    if not item or amount < 1 then return 0 end
    local info = { journal_id = edition.journal_id, edition = edition.edition, title = edition.title, author = edition.author_name or '' }
    if amount <= (tonumber(Config.Journal.MaxLooseCopies) or 3) then
        local given = 0
        for _ = 1, amount do
            if not Player.Functions.AddItem(item, 1, nil, info) then break end
            given = given + 1
        end
        return given
    end
    info.count, info.paper = amount, item
    return Player.Functions.AddItem(BUNDLE, 1, nil, info) and amount or 0
end

local function RefundCopies(Player, edition, amount)
    local remaining = amount - GiveCopies(Player, edition, amount)
    if remaining > 0 then
        MySQL.insert.await('INSERT INTO affiches_returns (citizenid, journal_id, journal_item, journal_title, journal_edition, copies) VALUES (?, ?, ?, ?, ?, ?)',
            { Player.PlayerData.citizenid, edition.journal_id, edition.paper, edition.title, edition.edition, remaining })
    end
end

local function EditionOf(row)
    return GetEdition(row.journal_id) or {
        journal_id = row.journal_id, edition = tonumber(row.journal_edition) or 0, title = row.journal_title or '',
        author_name = '', paper = row.journal_item,
    }
end

local function CanCollect(ctx, country)
    local cat = JournalOn() and Cats[Config.Journal.Category]
    if not cat or not Countries[country] or not cat.inCountry[country] then return false end
    if not PaperOf(ctx.Player) then return false end
    return RuleAllows(ctx.Player, RuleFor(cat, country, 'edit'), false)
end

local function WalletOf(ctx, country)
    if not CanCollect(ctx, country) then return 0 end
    local cents = MySQL.scalar.await('SELECT cents FROM affiches_journal_wallet WHERE citizenid = ? AND country = ? AND paper = ?',
        { ctx.Player.PlayerData.citizenid, country, PaperOf(ctx.Player) })
    return tonumber(cents) or 0
end


local function ReturnsOf(citizenid)
    local copies = MySQL.scalar.await('SELECT COALESCE(SUM(copies), 0) FROM affiches_returns WHERE citizenid = ?', { citizenid })
    return math.floor(tonumber(copies) or 0)
end

local function JournalPayload(ctx, country)
    if not JournalOn() then return { enabled = false } end
    local cfg = Config.Journal
    local citizenid = ctx.Player.PlayerData.citizenid
    return {
        enabled = true,
        category = cfg.Category,
        defaultPrice = Cents(cfg.DefaultPrice), minPrice = Cents(cfg.MinPrice), maxPrice = Cents(cfg.MaxPrice),
        maxStock = math.floor(tonumber(cfg.MaxStock) or 100),
        wallet = WalletOf(ctx, country),
        canCollect = CanCollect(ctx, country),
        returns = ReturnsOf(citizenid),
    }
end

local function ParsePrice(value)
    local cfg = Config.Journal
    local cents = Cents(value ~= nil and value or cfg.DefaultPrice)
    if cents < Cents(cfg.MinPrice) or cents > Cents(cfg.MaxPrice) then
        return nil, ('Le prix doit être compris entre %.2f et %.2f $.'):format(cfg.MinPrice, cfg.MaxPrice)
    end
    return cents
end



local SELECT_FIELDS = [[
    id, category, country, title, url, author_name, author_citizenid, pinned, anonymous,
    journal_id, journal_title, journal_edition, price_cents, stock, sold,
    DATE_FORMAT(created_at, '%d/%m/%Y %H:%i') AS published,
    DATE_FORMAT(updated_at, '%d/%m/%Y %H:%i') AS updated
]]
local ACTIVE = '(expires_at IS NULL OR expires_at > NOW())'

local function ToClient(ctx, cat, row)
    local linked = row.journal_id ~= nil and row.journal_id ~= ''
    local mine = linked and (ctx.admin or row.author_citizenid == ctx.Player.PlayerData.citizenid) and true or false
    -- Affiche anonyme : le nom de l'auteur ne quitte jamais le serveur, pour personne (admins compris).
    -- Le staff le retrouve dans les logs Discord et en base (author_name / author_citizenid).
    local anonymous = IsFlag(row.anonymous)
    return {
        journal = linked and {
            title = row.journal_title,
            edition = tonumber(row.journal_edition) or 0,
            price = tonumber(row.price_cents) or 0,
            stock = tonumber(row.stock) or 0,
            sold = tonumber(row.sold) or 0,
            mine = mine,
            owned = mine and InventoryCopies(ctx.Player, row.journal_id) or 0,      -- exemplaires que j'ai sur moi
        } or nil,
        id = row.id,
        category = row.category,
        country = row.country,
        title = row.title,
        url = row.url,
        author = not anonymous and row.author_name or nil,
        anonymous = anonymous,
        published = row.published,
        updated = row.updated,
        pinned = IsFlag(row.pinned),
        canEdit = CanEdit(ctx, cat, row) and true or false,
        canDelete = CanDelete(ctx, cat, row) and true or false,
        canPin = CanPin(ctx, cat, row) and true or false,
    }
end

local function ListPosters(ctx, cat, country)
    local limit = math.max(1, math.floor(tonumber(cat.max or Config.MaxPostersPerCategory) or 30))
    local rows

    -- PROPAGANDE : catégorie globale.
    -- Une affiche publiée dans un pays est visible dans tous les pays.
    if cat.key == 'propagande' then
        rows = MySQL.query.await(('SELECT %s FROM affiches_posters WHERE category = ? AND %s ORDER BY pinned DESC, id DESC LIMIT %d'):format(SELECT_FIELDS, ACTIVE, limit),
            { cat.key }) or {}
    else
        rows = MySQL.query.await(('SELECT %s FROM affiches_posters WHERE country = ? AND category = ? AND %s ORDER BY pinned DESC, id DESC LIMIT %d'):format(SELECT_FIELDS, ACTIVE, limit),
            { country, cat.key }) or {}
    end

    local posters = {}
    for i, row in ipairs(rows) do posters[i] = ToClient(ctx, cat, row) end
    return posters
end

local function DurationAllowed(cat, days)
    for _, d in ipairs(cat.durations) do
        if d == days then return true end
    end
    return false
end

RegisterCallback('Sunny-affiches:server:Open', function(source, cb, boardId)
    local ctx, err = GetContext(source, boardId)
    if not ctx then return cb(Fail(err)) end
    PurgeExpired()

    -- counts[pays][catégorie]
    local counts = {}
    for _, row in ipairs(MySQL.query.await(('SELECT country, category, COUNT(*) AS c FROM affiches_posters WHERE %s GROUP BY country, category'):format(ACTIVE)) or {}) do
        counts[row.country] = counts[row.country] or {}
        counts[row.country][row.category] = tonumber(row.c) or 0
    end

    local cats = {}
    for _, cat in ipairs(CatList) do
        if CanView(ctx, cat) then
            local create = {}
            for _, country in ipairs(CountryList) do
                create[country.key] = CanCreate(ctx, cat, country.key) and true or false
            end
            cats[#cats + 1] = {
                key = cat.key, label = cat.label, color = cat.color, desc = cat.desc,
                countries = cat.inCountry, create = create,
                anonymous = cat.anonymous == true,
                durations = cat.durations, defaultDays = cat.defaultDays,
                group = cat.group, groupLabel = cat.groupLabel,
            }
        end
    end

    local countries, startCountry, current = {}, nil, nil
    local order = { ctx.board.country }
    for _, country in ipairs(CountryList) do
        if country.key ~= ctx.board.country then order[#order + 1] = country.key end
    end
    for _, country in ipairs(CountryList) do
        local total = 0
        for _, cat in ipairs(cats) do
            if cat.countries[country.key] then total = total + ((counts[country.key] or {})[cat.key] or 0) end
        end
        countries[#countries + 1] = { key = country.key, label = country.label, count = total }
    end

    for _, key in ipairs(order) do
        for _, cat in ipairs(cats) do
            if cat.countries[key] then startCountry = key break end
        end
        if startCountry then break end
    end
    if not startCountry then return cb(Fail('Aucune catégorie disponible.')) end

    -- catégorie de départ : la première qui contient des affiches, sinon la première du pays
    for _, cat in ipairs(cats) do
        if cat.countries[startCountry] then
            current = current or cat.key
            if ((counts[startCountry] or {})[cat.key] or 0) > 0 then current = cat.key break end
        end
    end

    cb({
        ok = true,
        board = { id = ctx.board.id, name = ctx.board.name, country = ctx.board.country, countryLabel = CountryLabel(ctx.board.country) },
        countries = countries,
        country = startCountry,
        categories = cats,
        counts = counts,
        current = current,
        posters = ListPosters(ctx, Cats[current], startCountry),
        limits = { title = Config.MaxTitleLength },
        journal = JournalPayload(ctx, startCountry),
        me = (function()
            local job = ctx.Player.PlayerData.job or {}
            return {
                job = job.name or '', label = job.label or '',
                grade = job.grade and tonumber(job.grade.level) or 0,
                gradeName = job.grade and job.grade.name or '',
                admin = ctx.admin and true or false,
            }
        end)(),
        background = Config.BoardBackground,
    })
end)

RegisterCallback('Sunny-affiches:server:List', function(source, cb, data)
    if type(data) ~= 'table' then return cb(Fail('Données invalides.')) end
    local ctx, err = GetContext(source, data.board_id)
    if not ctx then return cb(Fail(err)) end
    PurgeExpired()

    local cat = CatFor(ctx, data.category, data.country)
    if not cat then return cb(Fail('Catégorie introuvable.')) end
    cb({ ok = true, country = data.country, category = cat.key, posters = ListPosters(ctx, cat, data.country), journal = JournalPayload(ctx, data.country) })
end)



local Cooldowns = {}
AddEventHandler('playerDropped', function()
    Cooldowns[source] = nil
end)

local function Validate(ctx, data)
    local title = CleanLine(data.title, Config.MaxTitleLength)
    if not title then return nil, 'Le titre est trop long (' .. Config.MaxTitleLength .. ' caractères max).' end
    if title == '' then return nil, 'Le titre est obligatoire.' end

    local url = CleanUrl(data.url)
    if not url then return nil, 'Le lien de l\'image est invalide.' end

    local job = ctx.Player.PlayerData.job
    return { title = title, url = url, org = job and job.label or '' }
end

RegisterCallback('Sunny-affiches:server:Save', function(source, cb, data)
    if type(data) ~= 'table' then return cb(Fail('Données invalides.')) end
    local ctx, err = GetContext(source, data.board_id)
    if not ctx then return cb(Fail(err)) end

    local now = os.time()
    if Cooldowns[source] and now - Cooldowns[source] < Config.SaveCooldown then
        return cb(Fail('Doucement, attends quelques secondes.'))
    end

    local id = data.id ~= nil and tonumber(data.id) or nil
    local row, cat, country
    if id then
        row = MySQL.single.await('SELECT * FROM affiches_posters WHERE id = ?', { id })
        cat = row and Cats[row.category]
        if not row or not cat then return cb(Fail('Cette affiche n\'existe plus.')) end
        country = row.country
        if not CanEdit(ctx, cat, row) then return cb(Fail('Tu n\'as pas le droit de modifier cette affiche.')) end
    else
        country = data.country
        cat = CatFor(ctx, data.category, country)
        if not cat then return cb(Fail('Catégorie introuvable.')) end
        if not CanCreate(ctx, cat, country) then return cb(Fail('Tu n\'as pas le droit de publier dans cette catégorie.')) end
    end

    local clean, verr = Validate(ctx, data)
    if not clean then return cb(Fail(verr)) end

    local link
    local linkedRow = row ~= nil and row.journal_id ~= nil and row.journal_id ~= ''
    if linkedRow then
        clean.url = row.url                                   -- la couverture ne change jamais
        if data.price ~= nil then
            if not (ctx.admin or IsAuthor(ctx, row)) then return cb(Fail('Seul l\'auteur peut changer le prix.')) end
            local cents, perr = ParsePrice(data.price)
            if not cents then return cb(Fail(perr)) end
            link = { price_cents = cents }
        end
    elseif data.journal_id ~= nil and data.journal_id ~= '' then
        if not JournalOn() or cat.key ~= Config.Journal.Category then return cb(Fail('Cette catégorie n\'accepte pas de journal lié.')) end
        if row then return cb(Fail('Le lien avec un journal se choisit à la création de l\'affiche.')) end
        if type(data.journal_id) ~= 'string' or #data.journal_id > 16 then return cb(Fail('Édition invalide.')) end

        local edition = GetEdition(data.journal_id)
        if not edition then return cb(Fail('Cette édition n\'existe pas ou n\'est pas publiée.')) end
        if not CanLinkEdition(ctx, edition) then return cb(Fail('Tu ne peux lier que les éditions de la rédaction liée à ton métier.')) end
        if not edition.cover or edition.cover == '' then return cb(Fail('Cette édition n\'a pas de première page.')) end

        local cents, perr = ParsePrice(data.price)
        if not cents then return cb(Fail(perr)) end
        local stock = math.floor(tonumber(data.stock) or 0)
        local maxStock = math.floor(tonumber(Config.Journal.MaxStock) or 100)
        if stock < 0 or stock > maxStock then return cb(Fail(('Le stock doit être compris entre 0 et %d exemplaires.'):format(maxStock))) end

        local have = InventoryCopies(ctx.Player, edition.journal_id)
        if stock > have then
            return cb(Fail(('Il te faut %d exemplaire(s) de cette édition dans ton inventaire pour les mettre en vente (tu en as %d).'):format(stock, have)))
        end

        link = { edition = edition, price_cents = cents, stock = stock }
        clean.url = edition.cover
    end

    local days = tonumber(data.days)
    -- Propagande : durée strictement limitée à 24 heures.
    if cat.key == 'propagande' then
        days = 1
    elseif id and days == -1 then
        days = nil                                    -- conserver l'expiration actuelle
    elseif not days or not DurationAllowed(cat, days) then
        return cb(Fail('Durée invalide pour cette catégorie.'))
    end
    -- days : 1 à MaxDays (DurationAllowed), ou 0 = indéfiniment (pas de date d'expiration)
    local expires = days == nil and 'expires_at' or (days > 0 and ('NOW() + INTERVAL %d DAY'):format(days) or 'NULL')

    local Player = ctx.Player
    if not id then
        if cat.key == 'propagande' then
            local recent = MySQL.scalar.await([[
                SELECT COUNT(*)
                FROM affiches_posters
                WHERE category = 'propagande'
                  AND author_citizenid = ?
                  AND created_at > NOW() - INTERVAL 24 HOUR
            ]], { Player.PlayerData.citizenid }) or 0

            if tonumber(recent) > 0 then
                return cb(Fail('Tu as déjà publié une affiche de propagande. Tu pourras en publier une nouvelle dans 24 heures.'))
            end
        end

        local limit = tonumber(cat.max or Config.MaxPostersPerCategory) or 30
        local count
        if cat.key == 'propagande' then
            -- La limite de propagande est globale.
            count = MySQL.scalar.await('SELECT COUNT(*) FROM affiches_posters WHERE category = ? AND (expires_at IS NULL OR expires_at > NOW())', { cat.key }) or 0
        else
            count = MySQL.scalar.await('SELECT COUNT(*) FROM affiches_posters WHERE country = ? AND category = ? AND (expires_at IS NULL OR expires_at > NOW())', { country, cat.key }) or 0
        end
        if tonumber(count) >= limit then
            return cb(Fail('Cette catégorie est pleine : attends qu\'une affiche expire ou soit retirée.'))
        end

        local job = Player.PlayerData.job
        local edition = link and link.edition

        local taken = 0
        if edition and link.stock > 0 then
            taken = TakeCopies(Player, edition.journal_id, link.stock)
            if taken < link.stock then
                if taken > 0 then RefundCopies(Player, edition, taken) end
                return cb(Fail('Impossible de retirer ces exemplaires de ton inventaire : réessaie.'))
            end
        end

        -- Publication anonyme : seulement si la catégorie le permet, choisie à la création et jamais modifiable ensuite.
        local anonymous = cat.anonymous == true and data.anonymous == true

        local inserted, result = pcall(MySQL.insert.await, ('INSERT INTO affiches_posters (country, category, title, url, org, author_name, author_citizenid, author_job, anonymous, journal_id, journal_item, journal_title, journal_edition, price_cents, stock, expires_at) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, %s)'):format(expires),
            { country, cat.key, clean.title, clean.url, clean.org, CharName(Player), Player.PlayerData.citizenid, job and job.name or '', anonymous and 1 or 0,
              edition and edition.journal_id or '', edition and edition.paper or '', edition and edition.title or '',
              edition and tonumber(edition.edition) or 0, link and link.price_cents or 0, link and link.stock or 0 })
        id = inserted and result or nil
        if not id then
            if taken > 0 then RefundCopies(Player, edition, taken) end
            return cb(Fail('L\'affiche n\'a pas pu être créée : réessaie.'))
        end
        Cooldowns[source] = now
        LogPoster('create', ctx, cat, {
            title = clean.title, url = clean.url, org = clean.org, country = country,
            author_name = CharName(Player), author_citizenid = Player.PlayerData.citizenid, anonymous = anonymous and 1 or 0,
            journal = link and { title = edition.title, edition = edition.edition, price_cents = link.price_cents, stock = link.stock } or nil,
        }, days)
    elseif linkedRow then
        MySQL.update.await(('UPDATE affiches_posters SET title = ?, price_cents = ?, updated_at = NOW(), expires_at = %s WHERE id = ?'):format(expires),
            { clean.title, link and link.price_cents or row.price_cents, id })
        Cooldowns[source] = now
        LogPoster('edit', ctx, cat, {
            title = clean.title, url = clean.url, org = row.org, country = country,
            author_name = row.author_name, author_citizenid = row.author_citizenid, anonymous = row.anonymous,
            journal = { title = row.journal_title, edition = row.journal_edition, price_cents = link and link.price_cents or row.price_cents, stock = row.stock },
        }, days)
    else
        MySQL.update.await(('UPDATE affiches_posters SET title = ?, url = ?, updated_at = NOW(), expires_at = %s WHERE id = ?'):format(expires),
            { clean.title, clean.url, id })
        Cooldowns[source] = now
        LogPoster('edit', ctx, cat, {
            title = clean.title, url = clean.url, org = row.org, country = country,
            author_name = row.author_name, author_citizenid = row.author_citizenid, anonymous = row.anonymous,
        }, days)
    end

    cb({ ok = true, id = id, country = country, category = cat.key })
end)

RegisterCallback('Sunny-affiches:server:Delete', function(source, cb, data)
    if type(data) ~= 'table' then return cb(Fail('Données invalides.')) end
    local ctx, err = GetContext(source, data.board_id)
    if not ctx then return cb(Fail(err)) end

    local row = MySQL.single.await('SELECT * FROM affiches_posters WHERE id = ?', { tonumber(data.id) or 0 })
    local cat = row and Cats[row.category]
    if not row or not cat then return cb(Fail('Cette affiche n\'existe plus.')) end
    if not CanDelete(ctx, cat, row) then return cb(Fail('Tu n\'as pas le droit de supprimer cette affiche.')) end

    local parked = row.journal_id and row.journal_id ~= '' and (tonumber(row.stock) or 0) or 0
    if not ParkStock({ row.id }) then
        return cb(Fail('Impossible de mettre les invendus de côté : l\'affiche est conservée.'))
    end
    LogPoster('delete', ctx, cat, row)
    cb({ ok = true, country = row.country, category = cat.key, parked = parked })
end)

RegisterCallback('Sunny-affiches:server:Pin', function(source, cb, data)
    if type(data) ~= 'table' or type(data.pinned) ~= 'boolean' then return cb(Fail('Données invalides.')) end
    local ctx, err = GetContext(source, data.board_id)
    if not ctx then return cb(Fail(err)) end

    local row = MySQL.single.await('SELECT * FROM affiches_posters WHERE id = ? AND (expires_at IS NULL OR expires_at > NOW())', { tonumber(data.id) or 0 })
    local cat = row and Cats[row.category]
    if not row or not cat then return cb(Fail('Cette affiche n\'existe plus.')) end
    if not CanPin(ctx, cat, row) then return cb(Fail('Tu n\'as pas le droit d\'épingler cette affiche.')) end

    local wasPinned = IsFlag(row.pinned)
    if data.pinned and not wasPinned then
        local pinned = MySQL.scalar.await('SELECT COUNT(*) FROM affiches_posters WHERE country = ? AND category = ? AND pinned = 1 AND (expires_at IS NULL OR expires_at > NOW())', { row.country, row.category }) or 0
        if tonumber(pinned) >= (tonumber(Config.MaxPinned) or 3) then
            return cb(Fail('Trop d\'affiches épinglées dans cette catégorie (' .. (tonumber(Config.MaxPinned) or 3) .. ' max).'))
        end
    end

    if data.pinned ~= wasPinned then
        MySQL.update.await('UPDATE affiches_posters SET pinned = ? WHERE id = ?', { data.pinned and 1 or 0, row.id })
        LogPoster(data.pinned and 'pin' or 'unpin', ctx, cat, row)
    end
    cb({ ok = true, country = row.country, category = cat.key, pinned = data.pinned })
end)



local function FetchPoster(ctx, id)
    local fresh = MySQL.single.await(('SELECT %s FROM affiches_posters WHERE id = ?'):format(SELECT_FIELDS), { id })
    local cat = fresh and Cats[fresh.category]
    return fresh and cat and ToClient(ctx, cat, fresh) or nil
end

-- Éditions publiées que le joueur peut lier à une nouvelle affiche de la catégorie Journal.
RegisterCallback('Sunny-affiches:server:Editions', function(source, cb, data)
    if type(data) ~= 'table' then return cb(Fail('Données invalides.')) end
    local ctx, err = GetContext(source, data.board_id)
    if not ctx then return cb(Fail(err)) end
    if not JournalOn() then return cb(Fail('La vente de journaux est désactivée.')) end
    local cat = CatFor(ctx, Config.Journal.Category, data.country)
    if not cat or not CanCreate(ctx, cat, data.country) then
        return cb(Fail('Tu ne peux pas publier de journal ici.'))
    end

    if not ctx.admin and not PaperOf(ctx.Player) then
        return cb(Fail('Ton métier n\'est lié à aucune rédaction : ajoute-le dans Config.Journal.Papers.'))
    end

    local editions = FetchEditions(ctx)
    if editions == nil then return cb(Fail('sunny_journal est introuvable : impossible de lister les éditions.')) end
    local list = {}
    for _, e in ipairs(editions) do
        if e.cover and e.cover ~= '' then
            list[#list + 1] = {
                id = e.journal_id, title = e.title, edition = tonumber(e.edition) or 0, cover = e.cover,
                owned = InventoryCopies(ctx.Player, e.journal_id),          -- exemplaires que le journaliste a sur lui
            }
        end
    end
    cb({ ok = true, editions = list })
end)

RegisterCallback('Sunny-affiches:server:Buy', function(source, cb, data)
    if type(data) ~= 'table' then return cb(Fail('Données invalides.')) end
    local ctx, err = GetContext(source, data.board_id)
    if not ctx then return cb(Fail(err)) end
    if not JournalOn() then return cb(Fail('La vente de journaux est désactivée.')) end

    local row = MySQL.single.await(('SELECT * FROM affiches_posters WHERE id = ? AND journal_id <> \'\' AND %s'):format(ACTIVE), { tonumber(data.id) or 0 })
    local cat = row and Cats[row.category]
    if not row or not cat or not CanView(ctx, cat) then return cb(Fail('Ce journal n\'est plus en vente.')) end

    local edition = GetEdition(row.journal_id)
    if not edition then return cb(Fail('Cette édition n\'est plus disponible.')) end

    local Player = ctx.Player
    local currency = Config.Journal.Currency
    local price = tonumber(row.price_cents) or 0
    local dollars = Dollars(price)

    local expected = tonumber(data.price)
    if expected and expected ~= price then
        return cb(Fail(('Le prix a changé : ce journal coûte maintenant %.2f $.'):format(dollars)))
    end
    if (Player.Functions.GetMoney(currency) or 0) < dollars then
        return cb(Fail(('Il te faut %.2f $ pour acheter ce journal.'):format(dollars)))
    end

    local reserved = MySQL.update.await(('UPDATE affiches_posters SET stock = stock - 1, sold = sold + 1 WHERE id = ? AND stock > 0 AND %s'):format(ACTIVE), { row.id })
    if not reserved or reserved < 1 then return cb(Fail('Plus aucun exemplaire disponible.')) end
    local function release()
        MySQL.update.await('UPDATE affiches_posters SET stock = stock + 1, sold = sold - 1 WHERE id = ?', { row.id })
    end

    -- 2) paiement
    if not Player.Functions.RemoveMoney(currency, dollars, 'journal-achat') then
        release()
        return cb(Fail('Paiement refusé.'))
    end

    local item = (edition.paper and edition.paper ~= '') and edition.paper or row.journal_item
    local info = { journal_id = edition.journal_id, edition = edition.edition, title = edition.title, author = edition.author_name }
    if not Player.Functions.AddItem(item, 1, nil, info) then
        Player.Functions.AddMoney(currency, dollars, 'journal-remboursement')
        release()
        return cb(Fail('Ton inventaire est plein ou trop lourd : tu n\'as pas été débité.'))
    end

    -- 4) caisse du journaliste
    MySQL.update.await('INSERT INTO affiches_journal_wallet (citizenid, country, paper, cents) VALUES (?, ?, ?, ?) ON DUPLICATE KEY UPDATE cents = cents + VALUES(cents)', { row.author_citizenid, row.country, row.journal_item, price })

    cb({ ok = true, poster = FetchPoster(ctx, row.id), wallet = WalletOf(ctx, row.country) })
end)

RegisterCallback('Sunny-affiches:server:AddStock', function(source, cb, data)
    if type(data) ~= 'table' then return cb(Fail('Données invalides.')) end
    local ctx, err = GetContext(source, data.board_id)
    if not ctx then return cb(Fail(err)) end
    if not JournalOn() then return cb(Fail('La vente de journaux est désactivée.')) end

    local amount = math.floor(tonumber(data.amount) or 0)
    if amount < 1 then return cb(Fail('Indique un nombre d\'exemplaires (1 minimum).')) end

    local row = MySQL.single.await(('SELECT * FROM affiches_posters WHERE id = ? AND journal_id <> \'\' AND %s'):format(ACTIVE), { tonumber(data.id) or 0 })
    if not row then return cb(Fail('Cette affiche n\'existe plus.')) end
    if not (ctx.admin or IsAuthor(ctx, row)) then return cb(Fail('Seul l\'auteur peut ajouter des exemplaires.')) end

    local maxStock = math.floor(tonumber(Config.Journal.MaxStock) or 100)
    local current = tonumber(row.stock) or 0
    if current + amount > maxStock then
        return cb(Fail(('Le stock est limité à %d exemplaires (il en reste %d en vente).'):format(maxStock, current)))
    end

    local Player = ctx.Player
    local have = InventoryCopies(Player, row.journal_id)
    if amount > have then
        return cb(Fail(('Tu n\'as que %d exemplaire(s) de cette édition dans ton inventaire.'):format(have)))
    end
    local edition = EditionOf(row)
    local taken = TakeCopies(Player, row.journal_id, amount)
    if taken < amount then
        if taken > 0 then RefundCopies(Player, edition, taken) end
        return cb(Fail('Impossible de retirer ces exemplaires de ton inventaire : réessaie.'))
    end

    local success, updated = pcall(MySQL.update.await, ('UPDATE affiches_posters SET stock = stock + ? WHERE id = ? AND stock + ? <= ? AND %s'):format(ACTIVE), { amount, row.id, amount, maxStock })
    if not success or not updated or updated < 1 then
        RefundCopies(Player, edition, taken)
        return cb(Fail('Le stock a changé : réessaie.'))
    end
    cb({ ok = true, poster = FetchPoster(ctx, row.id) })
end)

-- Reprendre des exemplaires en vente sur une affiche : ils retournent dans l'inventaire du journaliste.
RegisterCallback('Sunny-affiches:server:Take', function(source, cb, data)
    if type(data) ~= 'table' then return cb(Fail('Données invalides.')) end
    local ctx, err = GetContext(source, data.board_id)
    if not ctx then return cb(Fail(err)) end
    if not JournalOn() then return cb(Fail('La vente de journaux est désactivée.')) end

    local amount = math.floor(tonumber(data.amount) or 0)
    if amount < 1 then return cb(Fail('Indique un nombre d\'exemplaires (1 minimum).')) end

    local row = MySQL.single.await(('SELECT * FROM affiches_posters WHERE id = ? AND journal_id <> \'\' AND %s'):format(ACTIVE), { tonumber(data.id) or 0 })
    if not row then return cb(Fail('Cette affiche n\'existe plus.')) end
    if not (ctx.admin or IsAuthor(ctx, row)) then return cb(Fail('Seul l\'auteur peut reprendre des exemplaires.')) end
    if amount > (tonumber(row.stock) or 0) then
        return cb(Fail(('Il ne reste que %d exemplaire(s) en vente.'):format(tonumber(row.stock) or 0)))
    end

    -- 1) retire du stock (atomique : ne peut pas reprendre un exemplaire qu'un acheteur vient de prendre)
    local updated = MySQL.update.await(('UPDATE affiches_posters SET stock = stock - ? WHERE id = ? AND stock >= ? AND %s'):format(ACTIVE), { amount, row.id, amount })
    if not updated or updated < 1 then return cb(Fail('Le stock a changé : réessaie.')) end

    -- 2) les remet dans l'inventaire ; ceux qui ne rentrent pas retournent en vente
    local given = GiveCopies(ctx.Player, EditionOf(row), amount)
    if given < amount then
        MySQL.update.await('UPDATE affiches_posters SET stock = stock + ? WHERE id = ?', { amount - given, row.id })
    end
    if given == 0 then return cb(Fail('Ton inventaire est plein ou trop lourd : rien n\'a été repris.')) end
    cb({ ok = true, given = given, requested = amount, poster = FetchPoster(ctx, row.id) })
end)

-- Récupérer les exemplaires invendus d'affiches supprimées ou expirées.
RegisterCallback('Sunny-affiches:server:Claim', function(source, cb, data)
    if type(data) ~= 'table' then return cb(Fail('Données invalides.')) end
    local ctx, err = GetContext(source, data.board_id)
    if not ctx then return cb(Fail(err)) end
    if not JournalOn() then return cb(Fail('La vente de journaux est désactivée.')) end

    local citizenid = ctx.Player.PlayerData.citizenid
    local rows = MySQL.query.await('SELECT id, journal_id, journal_item, journal_title, journal_edition, copies FROM affiches_returns WHERE citizenid = ? AND copies > 0 ORDER BY id', { citizenid })
    if not rows or #rows == 0 then return cb(Fail('Tu n\'as aucun exemplaire invendu à récupérer.')) end

    -- par édition : un seul lot si plusieurs affiches ont laissé des exemplaires de la même édition
    local groups, order = {}, {}
    for _, row in ipairs(rows) do
        local g = groups[row.journal_id]
        if not g then g = { rows = {}, total = 0 }; groups[row.journal_id] = g; order[#order + 1] = row.journal_id end
        g.rows[#g.rows + 1] = row
        g.total = g.total + (tonumber(row.copies) or 0)
    end

    local given, total = 0, 0
    for _, journalId in ipairs(order) do
        local g = groups[journalId]
        total = total + g.total
        local first = g.rows[1]
        local got = GiveCopies(ctx.Player, EditionOf(first), g.total)
        given = given + got

        -- retire des exemplaires mis de côté ceux qui ont été remis (les autres restent à récupérer)
        local left = got
        for _, row in ipairs(g.rows) do
            if left <= 0 then break end
            local copies = tonumber(row.copies) or 0
            if left >= copies then
                MySQL.update.await('DELETE FROM affiches_returns WHERE id = ?', { row.id })
                left = left - copies
            else
                MySQL.update.await('UPDATE affiches_returns SET copies = copies - ? WHERE id = ?', { left, row.id })
                left = 0
            end
        end
    end

    if given == 0 then return cb(Fail('Ton inventaire est plein ou trop lourd : rien n\'a été récupéré.')) end
    cb({ ok = true, given = given, remaining = total - given, returns = ReturnsOf(citizenid) })
end)

-- Récupérer l'argent des ventes de ses journaux (caisse du journaliste).
RegisterCallback('Sunny-affiches:server:Collect', function(source, cb, data)
    if type(data) ~= 'table' then return cb(Fail('Données invalides.')) end
    local ctx, err = GetContext(source, data.board_id)
    if not ctx then return cb(Fail(err)) end
    if not JournalOn() then return cb(Fail('La vente de journaux est désactivée.')) end

    local country = type(data.country) == 'string' and data.country or ''
    if not CanCollect(ctx, country) then
        return cb(Fail('Ton metier ou ton grade ne permet pas de recuperer les recettes de cette redaction.'))
    end
    local paper = PaperOf(ctx.Player)
    local citizenid = ctx.Player.PlayerData.citizenid
    local cents = WalletOf(ctx, country)
    if cents <= 0 then return cb(Fail('Il n\'y a pas d\'argent à récupérer.')) end

    local moved = MySQL.update.await('UPDATE affiches_journal_wallet SET cents = cents - ? WHERE citizenid = ? AND country = ? AND paper = ? AND cents >= ?', { cents, citizenid, country, paper, cents })
    if not moved or moved < 1 then return cb(Fail('La caisse a changé : réessaie.')) end
    if not CanCollect(ctx, country) or PaperOf(ctx.Player) ~= paper or not ctx.Player.Functions.AddMoney(Config.Journal.Currency, Dollars(cents), 'journal-ventes') then
        MySQL.update.await('UPDATE affiches_journal_wallet SET cents = cents + ? WHERE citizenid = ? AND country = ? AND paper = ?', { cents, citizenid, country, paper })
        return cb(Fail('Impossible de te verser l\'argent : réessaie.'))
    end
    cb({ ok = true, collected = cents, wallet = WalletOf(ctx, country) })
end)
