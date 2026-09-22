local QBCore = exports['qbr-core']

math.randomseed(os.time() + GetGameTimer())

CreateThread(function()
    MySQL.query.await([[
        CREATE TABLE IF NOT EXISTS `newspapers` (
          `journal_id` varchar(16) NOT NULL,
          `title` varchar(100) NOT NULL,
          `paper` varchar(50) NOT NULL DEFAULT '',
          `edition` int(11) NOT NULL DEFAULT 1,
          `author_name` varchar(100) NOT NULL,
          `author_citizenid` varchar(50) NOT NULL,
          `pages` longtext NOT NULL,
          `status` enum('draft','published') NOT NULL DEFAULT 'draft',
          `printed` int(11) NOT NULL DEFAULT 0,
          `created_at` timestamp NOT NULL DEFAULT current_timestamp(),
          `published_at` timestamp NULL DEFAULT NULL,
          PRIMARY KEY (`journal_id`),
          KEY `edition` (`edition`),
          KEY `status` (`status`),
          KEY `paper` (`paper`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_general_ci
    ]])
    MySQL.query.await("ALTER TABLE `newspapers` ADD COLUMN IF NOT EXISTS `paper` varchar(50) NOT NULL DEFAULT '' AFTER `title`")
    MySQL.query.await('ALTER TABLE `newspapers` ADD INDEX IF NOT EXISTS `paper` (`paper`)')
end)

local function Notify(src, text, success)
    if success then
        TriggerClientEvent('QBCore:Notify', src, 9, text, 5000, 0, 'hud_textures', 'check', 'COLOR_WHITE')
    else
        TriggerClientEvent('QBCore:Notify', src, 9, text, 5000, 0, 'mp_lobby_textures', 'cross', 'COLOR_WHITE')
    end
end

local function Fail(text)
    return { ok = false, error = text }
end

local DENIED = 'Il faut être journaliste pour faire ça.'

local PaperByJob, PaperByItem = {}, {}
for _, paper in ipairs(Config.Papers) do
    PaperByJob[paper.job] = paper
    PaperByItem[paper.item] = paper
end

local function GetEditor(src)
    local Player = QBCore:GetPlayer(src)
    if not Player then return nil end
    local job = Player.PlayerData.job
    local paper = job and PaperByJob[job.name]
    if not paper then return nil end
    return Player, paper
end

local ALL_PERMS = { create = true, publish = true, print = true, delete = true }

local NOT_FOUND = 'Édition introuvable.'

local function CleanText(value, maxLength)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('[%c<>]', '')
    value = value:gsub('^%s+', ''):gsub('%s+$', '')
    local length = utf8.len(value)
    if not length or length < 1 or length > maxLength then return nil end
    return value
end

-- Liens Discord interdits : cdn.discordapp.com / media.discordapp.net expirent au bout de quelques heures (URLs signées).
local DISCORD_HOSTS = { 'discordapp.com', 'discordapp.net', 'discord.com', 'discord.gg' }
local function IsDiscordHost(host)
    for _, domain in ipairs(DISCORD_HOSTS) do
        if host == domain or host:sub(-(#domain + 1)) == '.' .. domain then return true end
    end
    return false
end

local function CleanUrl(value)
    if type(value) ~= 'string' then return nil end
    value = value:gsub('^%s+', ''):gsub('%s+$', '')
    if #value == 0 or #value > Config.MaxUrlLength then return nil end
    if not value:find('^https?://') then return nil end
    if value:find('[%s%c"\'<>`\\]') then return nil end
    local host = (value:match('^https?://([^/:?#]+)') or ''):lower()
    if IsDiscordHost(host) then return nil, 'discord' end
    if #Config.AllowedHosts > 0 then
        local allowed = false
        for _, allowedHost in ipairs(Config.AllowedHosts) do
            if host == allowedHost:lower() then
                allowed = true
                break
            end
        end
        if not allowed then return nil end
    end
    return value
end

local function GenerateJournalId()
    while true do
        local id = string.format('%08x', math.random(0, 0xFFFFFFFF))
        if not MySQL.scalar.await('SELECT 1 FROM newspapers WHERE journal_id = ?', { id }) then
            return id
        end
    end
end

local function DecodePages(raw)
    local pages = json.decode(raw or '[]') or {}
    local urls = {}
    for _, page in ipairs(pages) do
        urls[#urls + 1] = page.url
    end
    return urls
end

local function CleanPaper(value)
    if type(value) == 'string' and PaperByItem[value] then return value end
    return Config.Papers[1].item
end

local function CharName(Player)
    return Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname
end

local function ValidateEdition(data, Player)
    if type(data) ~= 'table' then return nil, 'Données invalides.' end

    local title = CleanText(data.title, Config.MaxTitleLength)
    if not title then return nil, 'Le titre est obligatoire (' .. Config.MaxTitleLength .. ' caractères max).' end

    local edition = tonumber(data.edition)
    if not edition or edition ~= math.floor(edition) or edition < 1 or edition > 99999 then
        return nil, 'Le numéro d\'édition doit être un nombre entier positif.'
    end

    local author = CleanText(data.author, Config.MaxAuthorLength) or CharName(Player)

    if type(data.pages) ~= 'table' then return nil, 'Données invalides.' end
    if #data.pages > Config.MaxPages then
        return nil, 'Une édition ne peut pas dépasser ' .. Config.MaxPages .. ' pages.'
    end
    local pages = {}
    for i, url in ipairs(data.pages) do
        local clean, cleanErr = CleanUrl(url)
        if not clean then
            if cleanErr == 'discord' then return nil, 'Page ' .. i .. ' : les liens Discord sont interdits (ils expirent au bout de quelques heures). Utilise un autre hébergeur d\'images (imgur, imgbb, etc.).' end
            return nil, 'Page ' .. i .. ' : le lien de l\'image est invalide.'
        end
        pages[#pages + 1] = { url = clean }
    end

    return { title = title, edition = math.floor(edition), author = author, pages = pages }
end

local function GetPublished(journalId, paperItem)
    if type(journalId) ~= 'string' then return nil end
    if paperItem then
        return MySQL.single.await("SELECT journal_id, title, edition, author_name, pages FROM newspapers WHERE journal_id = ? AND status = 'published' AND paper = ?", { journalId, paperItem })
    end
    return MySQL.single.await("SELECT journal_id, title, edition, author_name, pages FROM newspapers WHERE journal_id = ? AND status = 'published'", { journalId })
end

QBCore:CreateCallback('sunny_journal:server:List', function(source, cb)
    local Player, paper = GetEditor(source)
    if not Player then return cb(Fail(DENIED)) end

    local editions = MySQL.query.await([[
        SELECT journal_id, title, edition, author_name, status, printed,
               JSON_LENGTH(pages) AS page_count,
               UNIX_TIMESTAMP(created_at) AS created_at
        FROM newspapers WHERE paper = ? ORDER BY edition DESC, created_at DESC LIMIT 200
    ]], { paper.item }) or {}
    local lastEdition = MySQL.scalar.await('SELECT COALESCE(MAX(edition), 0) FROM newspapers WHERE paper = ?', { paper.item }) or 0

    cb({
        ok = true,
        perms = ALL_PERMS,
        editions = editions,
        defaults = { title = paper.title, author = CharName(Player), nextEdition = tonumber(lastEdition) + 1 },
        limits = { maxPages = Config.MaxPages, maxCopies = Config.MaxCopies },
        paper = { item = paper.item, label = paper.label },
    })
end)

QBCore:CreateCallback('sunny_journal:server:Get', function(source, cb, data)
    local Player, paper = GetEditor(source)
    if not Player then return cb(Fail(DENIED)) end
    local journalId = type(data) == 'table' and data.journal_id
    if type(journalId) ~= 'string' then return cb(Fail(NOT_FOUND)) end

    local row = MySQL.single.await('SELECT journal_id, title, edition, author_name, status, printed, pages FROM newspapers WHERE journal_id = ? AND paper = ?', { journalId, paper.item })
    if not row then return cb(Fail(NOT_FOUND)) end

    cb({
        ok = true,
        edition = {
            journal_id = row.journal_id,
            title = row.title,
            edition = row.edition,
            author = row.author_name,
            status = row.status,
            printed = row.printed,
            pages = DecodePages(row.pages),
        },
    })
end)

QBCore:CreateCallback('sunny_journal:server:Save', function(source, cb, data)
    local Player, paper = GetEditor(source)
    if not Player then return cb(Fail(DENIED)) end

    local clean, err = ValidateEdition(data, Player)
    if not clean then return cb(Fail(err)) end
    local pages = json.encode(clean.pages)

    local journalId = data.journal_id
    if journalId ~= nil then
        if type(journalId) ~= 'string' then return cb(Fail(NOT_FOUND)) end
        local row = MySQL.single.await('SELECT status FROM newspapers WHERE journal_id = ? AND paper = ?', { journalId, paper.item })
        if not row then return cb(Fail(NOT_FOUND)) end
        if row.status ~= 'draft' then
            return cb(Fail('Cette édition est publiée : elle ne peut plus être modifiée.'))
        end
        MySQL.update.await("UPDATE newspapers SET title = ?, edition = ?, author_name = ?, pages = ? WHERE journal_id = ? AND paper = ? AND status = 'draft'",
            { clean.title, clean.edition, clean.author, pages, journalId, paper.item })
    else
        journalId = GenerateJournalId()
        MySQL.insert.await('INSERT INTO newspapers (journal_id, title, paper, edition, author_name, author_citizenid, pages) VALUES (?, ?, ?, ?, ?, ?, ?)',
            { journalId, clean.title, paper.item, clean.edition, clean.author, Player.PlayerData.citizenid, pages })
    end

    cb({ ok = true, journal_id = journalId })
end)

QBCore:CreateCallback('sunny_journal:server:Publish', function(source, cb, data)
    local Player, paper = GetEditor(source)
    if not Player then return cb(Fail(DENIED)) end
    local journalId = type(data) == 'table' and data.journal_id
    if type(journalId) ~= 'string' then return cb(Fail(NOT_FOUND)) end

    local row = MySQL.single.await('SELECT status, pages FROM newspapers WHERE journal_id = ? AND paper = ?', { journalId, paper.item })
    if not row then return cb(Fail(NOT_FOUND)) end
    if row.status ~= 'draft' then return cb(Fail('Cette édition est déjà publiée.')) end
    if #DecodePages(row.pages) < 1 then return cb(Fail('Ajoute au moins une page avant de publier.')) end

    MySQL.update.await("UPDATE newspapers SET status = 'published', published_at = NOW() WHERE journal_id = ? AND paper = ? AND status = 'draft'", { journalId, paper.item })
    cb({ ok = true })
end)

QBCore:CreateCallback('sunny_journal:server:Delete', function(source, cb, data)
    local Player, paper = GetEditor(source)
    if not Player then return cb(Fail(DENIED)) end
    local journalId = type(data) == 'table' and data.journal_id
    if type(journalId) ~= 'string' then return cb(Fail(NOT_FOUND)) end

    local row = MySQL.single.await('SELECT status FROM newspapers WHERE journal_id = ? AND paper = ?', { journalId, paper.item })
    if not row then return cb(Fail(NOT_FOUND)) end

    MySQL.update.await('DELETE FROM newspapers WHERE journal_id = ? AND paper = ?', { journalId, paper.item })
    cb({ ok = true })
end)

QBCore:CreateCallback('sunny_journal:server:Print', function(source, cb, data)
    local Player, paper = GetEditor(source)
    if not Player then return cb(Fail(DENIED)) end
    if type(data) ~= 'table' then return cb(Fail('Données invalides.')) end

    local copies = tonumber(data.copies)
    if not copies or copies ~= math.floor(copies) or copies < 1 or copies > Config.MaxCopies then
        return cb(Fail('Le nombre d\'exemplaires doit être entre 1 et ' .. Config.MaxCopies .. '.'))
    end
    copies = math.floor(copies)

    local row = GetPublished(data.journal_id, paper.item)
    if not row then return cb(Fail('Seule une édition publiée de ton journal peut être imprimée.')) end

    local paperItem = paper.item
    local given = 0
    if copies <= Config.MaxLooseCopies then
        local info = { journal_id = row.journal_id, edition = row.edition, title = row.title, author = row.author_name }
        for _ = 1, copies do
            if not Player.Functions.AddItem(paperItem, 1, nil, info) then break end
            given = given + 1
        end
    else
        local info = { journal_id = row.journal_id, edition = row.edition, title = row.title, author = row.author_name, count = copies, paper = paperItem }
        if Player.Functions.AddItem('newspaper_bundle', 1, nil, info) then
            given = copies
        end
    end

    if given == 0 then return cb(Fail('Ton inventaire est plein.')) end
    MySQL.update.await('UPDATE newspapers SET printed = printed + ? WHERE journal_id = ?', { given, row.journal_id })
    cb({ ok = true, given = given, requested = copies })
end)

QBCore:AddCommand(Config.Command, 'Ouvrir l\'éditeur de journaux', {}, false, function(source)
    if source <= 0 then return end
    if not GetEditor(source) then return Notify(source, DENIED) end
    TriggerClientEvent('sunny_journal:client:OpenEditor', source)
end, 'user')

QBCore:AddCommand(Config.ReadCommand, 'Lire le dernier journal publié', {}, false, function(source)
    if source <= 0 then return end
    local row = MySQL.single.await("SELECT pages FROM newspapers WHERE status = 'published' ORDER BY published_at DESC, edition DESC LIMIT 1")
    if not row then return Notify(source, 'Aucun journal n\'a encore été publié.') end
    TriggerClientEvent('sunny_journal:client:OpenReader', source, { pages = DecodePages(row.pages) })
end, 'user')

local function GetOwnedItem(Player, item, name)
    local slot = type(item) == 'table' and tonumber(item.slot)
    if not slot then return nil end
    local owned = Player.Functions.GetItemBySlot(slot)
    if not owned or owned.name ~= name then return nil end
    return owned, slot
end
for _, paper in ipairs(Config.Papers) do
    QBCore:CreateUseableItem(paper.item, function(source, item)
        local Player = QBCore:GetPlayer(source)
        if not Player then return end
        local owned = GetOwnedItem(Player, item, paper.item)
        if not owned or type(owned.info) ~= 'table' then return end

        local row = GetPublished(owned.info.journal_id)
        if not row then return Notify(source, 'Ce journal est trop froissé pour être lu.') end

        TriggerClientEvent('sunny_journal:client:OpenReader', source, { pages = DecodePages(row.pages) })
    end)
end

QBCore:CreateUseableItem('newspaper_bundle', function(source, item)
    local Player = QBCore:GetPlayer(source)
    if not Player then return end
    local owned, slot = GetOwnedItem(Player, item, 'newspaper_bundle')
    if not owned or type(owned.info) ~= 'table' then return end

    local row = GetPublished(owned.info.journal_id)
    local count = math.min(tonumber(owned.info.count) or 0, Config.MaxCopies)
    if not row or count < 1 then return Notify(source, 'Ces journaux sont trop froissés pour être lus.') end

    local info = { journal_id = row.journal_id, edition = row.edition, title = row.title, author = row.author_name }
    local paper = CleanPaper(owned.info.paper)
    local given = 0
    for _ = 1, math.min(count, Config.UnpackAmount) do
        if not Player.Functions.AddItem(paper, 1, nil, info) then break end
        given = given + 1
    end
    if given == 0 then return Notify(source, 'Ton inventaire est plein.') end

    local remaining = count - given
    if remaining <= 0 then
        Player.Functions.RemoveItem('newspaper_bundle', 1, slot)
    else
        owned.info.count = remaining
        Player.Functions.UpdatePlayerItems(slot)
    end
    Notify(source, given .. ' exemplaire(s) sorti(s) du lot' .. (remaining > 0 and (', ' .. remaining .. ' restant(s).') or '.'), true)
end)
