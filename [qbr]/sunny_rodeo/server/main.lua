local QBCore = exports['qbr-core']

local databaseReady = false
local Sessions = {}   -- [source] = { token, citizenid, name, paid, startedAt, expires }
local Cooldowns = {}  -- [citizenid] = timestamp (GetGameTimer) de fin d'attente

local function Now() return GetGameTimer() end

local function Log(text) print(('[sunny_rodeo] %s'):format(text)) end

local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function Round2(v) return math.floor((tonumber(v) or 0) * 100 + 0.5) / 100 end

local function Money(v)
    local s = ('%.2f'):format(v)
    return (s:gsub('%.?0+$', ''))
end

local function CharName(Player)
    local info = Player.PlayerData.charinfo
    return ('%s %s'):format(info.firstname or '?', info.lastname or '')
end

local function Notify(target, text, success)
    if success then
        TriggerClientEvent('QBCore:Notify', target, 9, text, 6000, 0, 'hud_textures', 'check', 'COLOR_WHITE')
    else
        TriggerClientEvent('QBCore:Notify', target, 9, text, 5000, 0, 'mp_lobby_textures', 'cross', 'COLOR_WHITE')
    end
end

-- NIVEAUX --------------------------------------------------------------------
local Levels = {}
for i, l in ipairs(Config.Levels) do
    Levels[i] = { xp = tonumber(l.xp) or 0, title = tostring(l.title or ('Niveau ' .. i)) }
end
table.sort(Levels, function(a, b) return a.xp < b.xp end)
if #Levels == 0 or Levels[1].xp > 0 then
    table.insert(Levels, 1, { xp = 0, title = 'Débutant' })
end

local function LevelOf(xp)
    xp = tonumber(xp) or 0
    local idx = 1
    for i, l in ipairs(Levels) do
        if xp >= l.xp then idx = i end
    end
    local cur, nxt = Levels[idx], Levels[idx + 1]
    return { level = idx, title = cur.title, xp = xp, from = cur.xp, to = nxt and nxt.xp or nil }
end

-- BASE DE DONNEES -----------------------------------------------------------------
CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS `rodeo_players` (
            `citizenid` varchar(50) NOT NULL,
            `name` varchar(100) NOT NULL,
            `best_ms` int unsigned NOT NULL DEFAULT 0,
            `best_combo` int unsigned NOT NULL DEFAULT 0,
            `rides` int unsigned NOT NULL DEFAULT 0,
            `total_ms` bigint unsigned NOT NULL DEFAULT 0,
            `xp` int unsigned NOT NULL DEFAULT 0,
            PRIMARY KEY (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS `rodeo_rides` (
            `id` int unsigned NOT NULL AUTO_INCREMENT,
            `citizenid` varchar(50) NOT NULL,
            `duration_ms` int unsigned NOT NULL,
            `combos` int unsigned NOT NULL DEFAULT 0,
            `xp` int unsigned NOT NULL DEFAULT 0,
            `reason` varchar(16) NOT NULL DEFAULT 'fall',
            `created_at` timestamp NOT NULL DEFAULT CURRENT_TIMESTAMP,
            PRIMARY KEY (`id`),
            KEY `created` (`created_at`),
            KEY `citizen` (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
        MySQL.query.await('DELETE FROM `rodeo_rides` WHERE `created_at` < (NOW() - INTERVAL ? DAY)',
            { math.max(8, math.floor(tonumber(Config.KeepRideDays) or 60)) })
    end)
    if ok then
        databaseReady = true
    else
        Log('base de données indisponible : ' .. tostring(err))
    end
end)

local function RegisterCallback(name, handler)
    QBCore:CreateCallback(name, function(source, cb, data)
        if not databaseReady then
            return cb({ ok = false, error = 'Le rodéo n\'est pas encore prêt, réessaie dans un instant.' })
        end
        local ok, result = pcall(handler, source, data)
        if not ok then
            Log(tostring(result))
            result = { ok = false, error = 'Une erreur serveur est survenue. Réessaie dans un instant.' }
        end
        cb(result or { ok = false, error = 'Opération incomplète.' })
    end)
end

local function NearDesk(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return true end
    local c = GetEntityCoords(ped)
    if c.x == 0.0 and c.y == 0.0 and c.z == 0.0 then return true end
    local d = Config.Desk.coords
    return #(c - vector3(d.x, d.y, d.z)) <= (Config.Desk.distance or 2.5) + 8.0
end

local function HasAdminGroup(src)
    if src == 0 then return true end
    for _, group in ipairs(Config.AdminGroups) do
        if QBCore:HasPermission(src, group) then return true end
    end
    return false
end

-- TOUR ---------------------------------------------------------------------------
RegisterCallback('sunny_rodeo:server:Start', function(src)
    local Player = QBCore:GetPlayer(src)
    if not Player then return { ok = false, error = 'Joueur introuvable.' } end
    if not NearDesk(src) then return { ok = false, error = 'Tu es trop loin du maître du rodéo.' } end

    local cid = Player.PlayerData.citizenid
    local session = Sessions[src]
    if session and session.expires > Now() then
        return { ok = false, error = 'Un tour est déjà en cours.' }
    end

    local wait = (Cooldowns[cid] or 0) - Now()
    if wait > 0 then
        return { ok = false, error = ('Le buffle reprend son souffle, reviens dans %d secondes.'):format(math.ceil(wait / 1000)) }
    end

    local price = tonumber(Config.Price) or 0
    if price > 0 and not Player.Functions.RemoveMoney('cash', price, 'rodeo-entree') then
        return { ok = false, error = ('Il te faut %s $ pour monter sur le buffle.'):format(Money(price)) }
    end

    local token = ('%08x%08x%08x'):format(math.random(0, 0x7fffffff), math.random(0, 0x7fffffff), Now() % 0x7fffffff)
    Sessions[src] = {
        token = token,
        citizenid = cid,
        name = CharName(Player),
        paid = price,
        startedAt = Now(),
        expires = Now() + (Config.Ride.MaxSeconds + 90) * 1000,
    }
    return { ok = true, token = token, price = price, level = LevelOf(0).title }
end)

-- Le tour n'a pas pu démarrer côté client (ex. modèle de buffle introuvable) : remboursement.
RegisterNetEvent('sunny_rodeo:server:Cancel', function(token)
    local src = source
    local session = Sessions[src]
    if not session or session.token ~= token then return end
    Sessions[src] = nil
    if session.paid > 0 then
        local Player = QBCore:GetPlayer(src)
        if Player and Player.PlayerData.citizenid == session.citizenid then
            Player.Functions.AddMoney('cash', session.paid, 'rodeo-remboursement')
            Notify(src, 'Le tour n\'a pas pu démarrer, tu es remboursé.', true)
        end
    end
end)

local REASONS = { fall = true, quit = true, max = true, dead = true, error = true }

local function SendWebhook(title, description)
    local url = Config.Webhook
    if type(url) ~= 'string' or url == '' then return end
    PerformHttpRequest(url, function() end, 'POST', json.encode({
        username = Config.WebhookName,
        allowed_mentions = { parse = {} },
        embeds = { { title = title, description = description, color = 0xA3321F } },
    }), { ['Content-Type'] = 'application/json' })
end

RegisterCallback('sunny_rodeo:server:Finish', function(src, data)
    data = type(data) == 'table' and data or {}
    local session = Sessions[src]
    if not session or session.token ~= data.token then
        return { ok = false, error = 'Aucun tour en cours.' }
    end
    Sessions[src] = nil

    local Player = QBCore:GetPlayer(src)
    if not Player or Player.PlayerData.citizenid ~= session.citizenid then
        return { ok = false, error = 'Joueur introuvable.' }
    end
    local cid = session.citizenid
    Cooldowns[cid] = Now() + math.max(0, tonumber(Config.Cooldown) or 0) * 1000

    -- la durée annoncée ne peut pas dépasser le temps réellement écoulé depuis le départ
    local elapsed = Now() - session.startedAt
    local ms = math.floor(Clamp(tonumber(data.ms) or 0, 0, math.min(elapsed + 1500, Config.Ride.MaxSeconds * 1000)))
    local reason = REASONS[data.reason] and data.reason or 'fall'
    -- le score (épreuves réussies) ne peut pas dépasser le nombre d'épreuves possibles dans ce temps (pause minimale entre deux épreuves)
    local maxCombos = math.floor(ms / math.max(1, Config.Ride.GapMin)) + 1
    local combos = math.floor(Clamp(tonumber(data.combos) or 0, 0, maxCombos))

    local counted = ms >= Config.MinRideMs
    local seconds = ms / 1000
    local xp, cash, record, rank = 0, 0, false, nil
    local prev = MySQL.single.await('SELECT best_ms, best_combo, xp FROM rodeo_players WHERE citizenid = ?', { cid })
    -- le classement se fait sur le SCORE d'une manche = nombre d'épreuves réussies (colonne best_combo)
    local prevBest, prevXp = prev and prev.best_combo or 0, prev and prev.xp or 0
    local bestScore = prevBest

    if counted then
        xp = math.floor(seconds * Config.XP.perSecond + combos * Config.XP.perCombo + (reason == 'max' and Config.XP.maxBonus or 0))
        record = combos > prevBest
        bestScore = math.max(prevBest, combos)

        MySQL.query.await([[INSERT INTO rodeo_players (citizenid, name, best_ms, best_combo, rides, total_ms, xp)
            VALUES (?, ?, ?, ?, 1, ?, ?)
            ON DUPLICATE KEY UPDATE name = VALUES(name),
                best_ms = GREATEST(best_ms, VALUES(best_ms)),
                best_combo = GREATEST(best_combo, VALUES(best_combo)),
                rides = rides + 1, total_ms = total_ms + VALUES(total_ms), xp = xp + VALUES(xp)]],
            { cid, session.name, ms, combos, ms, xp })
        MySQL.insert.await('INSERT INTO rodeo_rides (citizenid, duration_ms, combos, xp, reason) VALUES (?, ?, ?, ?, ?)',
            { cid, ms, combos, xp, reason })

        cash = Round2(math.min(Config.Reward.max, combos * Config.Reward.perCombo) + (record and prevBest > 0 and Config.Reward.recordBonus or 0))
        if cash > 0 then Player.Functions.AddMoney('cash', cash, 'rodeo-gain') end

        rank = tonumber(MySQL.scalar.await('SELECT COUNT(*) + 1 FROM rodeo_players WHERE best_combo > ?', { bestScore })) or 1

        if record and rank == 1 then
            if Config.AnnounceRecord then
                Notify(-1, ('Nouveau record du rodéo : %s a enchaîné %d épreuves en %d secondes !'):format(session.name, combos, Config.Ride.MaxSeconds), true)
            end
            SendWebhook('[RODEO] Nouveau record', ('%s a enchaîné %d épreuves (manche de %d secondes).'):format(session.name, combos, Config.Ride.MaxSeconds))
        end
    end

    local newXp = prevXp + xp
    local before, after = LevelOf(prevXp), LevelOf(newXp)
    return {
        ok = true, ms = ms, combos = combos, reason = reason, counted = counted,
        xp = xp, cash = cash, record = record and prevBest > 0, first = record and prevBest == 0,
        bestScore = bestScore, rank = rank, level = after, levelUp = after.level > before.level,
    }
end)

-- CLASSEMENT -------------------------------------------------------------------------
-- Colonne (classement général) et agrégat (7 derniers jours) de chaque tri : liste fixe, jamais issue du client.
local SORTS = {
    time  = { col = 'best_ms',    week = 'MAX(r.duration_ms)' },
    combo = { col = 'best_combo', week = 'MAX(r.combos)' },
    level = { col = 'xp',         week = 'SUM(r.xp)' },
}

RegisterCallback('sunny_rodeo:server:Board', function(src, data)
    data = type(data) == 'table' and data or {}
    local sort = SORTS[data.sort] and data.sort or 'combo'
    local week = data.period == 'week'
    local spec = SORTS[sort]

    local rows
    if week then
        rows = MySQL.query.await(([[SELECT p.citizenid, p.name, p.xp, %s AS value
            FROM rodeo_rides r JOIN rodeo_players p ON p.citizenid = r.citizenid
            WHERE r.created_at >= (NOW() - INTERVAL 7 DAY)
            GROUP BY p.citizenid, p.name, p.xp HAVING value > 0
            ORDER BY value DESC, p.xp DESC LIMIT 500]]):format(spec.week))
    else
        rows = MySQL.query.await(([[SELECT citizenid, name, xp, %s AS value FROM rodeo_players
            WHERE %s > 0 ORDER BY value DESC, xp DESC LIMIT 500]]):format(spec.col, spec.col))
    end

    local Player = QBCore:GetPlayer(src)
    local cid = Player and Player.PlayerData.citizenid
    local top, me = {}, nil
    for i, row in ipairs(rows or {}) do
        local isMe = cid ~= nil and row.citizenid == cid
        if isMe then me = { rank = i, value = tonumber(row.value) or 0 } end
        if i <= Config.TopSize then
            local lv = LevelOf(row.xp)
            top[#top + 1] = { rank = i, name = row.name, value = tonumber(row.value) or 0, level = lv.level, title = lv.title, me = isMe }
        end
    end

    local profile
    if cid then
        local p = MySQL.single.await('SELECT best_ms, best_combo, rides, total_ms, xp FROM rodeo_players WHERE citizenid = ?', { cid })
        if p then
            profile = {
                bestMs = p.best_ms, bestCombo = p.best_combo, rides = p.rides, totalMs = tonumber(p.total_ms) or 0,
                level = LevelOf(p.xp),
            }
        end
    end

    return {
        ok = true, sort = sort, period = week and 'week' or 'all', rows = top, me = me, profile = profile,
        arena = Config.Arena.name, price = Config.Price, size = Config.TopSize,
    }
end)

-- ADMIN --------------------------------------------------------------------------------
RegisterCommand('rodeoreset', function(src, args)
    if not HasAdminGroup(src) then return end
    if args[1] ~= 'oui' then
        local msg = 'Cette commande efface TOUT le classement du rodéo. Tape /rodeoreset oui pour confirmer.'
        if src == 0 then print(msg) else Notify(src, msg, false) end
        return
    end
    MySQL.query.await('TRUNCATE TABLE `rodeo_rides`')
    MySQL.query.await('TRUNCATE TABLE `rodeo_players`')
    Cooldowns = {}
    if src == 0 then Log('classement remis à zéro') else Notify(src, 'Classement du rodéo remis à zéro.', true) end
end, false)

AddEventHandler('playerDropped', function()
    Sessions[source] = nil
end)
