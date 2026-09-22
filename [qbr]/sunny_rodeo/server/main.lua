local QBCore = exports['qbr-core']

local databaseReady = false
local Sessions = {}
local Cooldowns = {}

local ActiveSrc = nil

local function Now() return GetGameTimer() end

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

CreateThread(function()
    local ok = pcall(function()
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
    end)
    if ok then
        databaseReady = true
    end
end)

local function RegisterCallback(name, handler)
    QBCore:CreateCallback(name, function(source, cb, data)
        if not databaseReady then
            return cb({ ok = false, error = 'Le rodéo n\'est pas encore prêt, réessaie dans un instant.' })
        end
        local ok, result = pcall(handler, source, data)
        if not ok then
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

RegisterCallback('sunny_rodeo:server:Start', function(src)
    local Player = QBCore:GetPlayer(src)
    if not Player then return { ok = false, error = 'Joueur introuvable.' } end
    if not NearDesk(src) then return { ok = false, error = 'Tu es trop loin du maître du rodéo.' } end

    local cid = Player.PlayerData.citizenid
    local session = Sessions[src]
    if session and session.expires > Now() then
        return { ok = false, error = 'Un tour est déjà en cours.' }
    end

    if ActiveSrc and ActiveSrc ~= src and Sessions[ActiveSrc] and Sessions[ActiveSrc].expires > Now() then
        return { ok = false, error = ('%s est déjà sur le buffle, attends que le rodéo se termine.'):format(Sessions[ActiveSrc].name or 'Quelqu\'un') }
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
    ActiveSrc = src
    return { ok = true, token = token, price = price, level = LevelOf(0).title }
end)

local function ReleaseActive(src)
    if ActiveSrc == src then ActiveSrc = nil end
end

RegisterNetEvent('sunny_rodeo:server:Cancel', function(token)
    local src = source
    local session = Sessions[src]
    if not session or session.token ~= token then return end
    Sessions[src] = nil
    ReleaseActive(src)
    if session.paid > 0 then
        local Player = QBCore:GetPlayer(src)
        if Player and Player.PlayerData.citizenid == session.citizenid then
            Player.Functions.AddMoney('cash', session.paid, 'rodeo-remboursement')
            Notify(src, 'Le tour n\'a pas pu démarrer, tu es remboursé.', true)
        end
    end
end)

local REASONS = { fall = true, quit = true, max = true, dead = true, error = true }

RegisterCallback('sunny_rodeo:server:Finish', function(src, data)
    data = type(data) == 'table' and data or {}
    local session = Sessions[src]
    if not session or session.token ~= data.token then
        return { ok = false, error = 'Aucun tour en cours.' }
    end
    Sessions[src] = nil
    ReleaseActive(src)

    local Player = QBCore:GetPlayer(src)
    if not Player or Player.PlayerData.citizenid ~= session.citizenid then
        return { ok = false, error = 'Joueur introuvable.' }
    end
    local cid = session.citizenid
    Cooldowns[cid] = Now() + math.max(0, tonumber(Config.Cooldown) or 0) * 1000

    local elapsed = Now() - session.startedAt
    local ms = math.floor(Clamp(tonumber(data.ms) or 0, 0, math.min(elapsed + 1500, Config.Ride.MaxSeconds * 1000)))
    local reason = REASONS[data.reason] and data.reason or 'fall'

    local maxCombos = math.floor(ms / math.max(1, Config.Ride.GapMin)) + 1
    local combos = math.floor(Clamp(tonumber(data.combos) or 0, 0, maxCombos))

    local counted = ms >= Config.MinRideMs
    local seconds = ms / 1000
    local xp, record, rank = 0, false, nil
    local prev = MySQL.single.await('SELECT best_ms, best_combo, xp FROM rodeo_players WHERE citizenid = ?', { cid })

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

        rank = tonumber(MySQL.scalar.await('SELECT COUNT(*) + 1 FROM rodeo_players WHERE best_combo > ?', { bestScore })) or 1

        if record and rank == 1 and Config.AnnounceRecord then
            Notify(-1, ('Nouveau record du rodéo : %s a enchaîné %d épreuves en %d secondes !'):format(session.name, combos, Config.Ride.MaxSeconds), true)
        end
    end

    local newXp = prevXp + xp
    local before, after = LevelOf(prevXp), LevelOf(newXp)
    return {
        ok = true, ms = ms, combos = combos, reason = reason, counted = counted,
        xp = xp, record = record and prevBest > 0, first = record and prevBest == 0,
        bestScore = bestScore, rank = rank, level = after, levelUp = after.level > before.level,
    }
end)

local SORTS = {
    time  = { col = 'best_ms' },
    combo = { col = 'best_combo' },
    level = { col = 'xp' },
}

RegisterCallback('sunny_rodeo:server:Board', function(src, data)
    data = type(data) == 'table' and data or {}
    local sort = SORTS[data.sort] and data.sort or 'combo'
    local spec = SORTS[sort]

    local rows = MySQL.query.await(([[SELECT citizenid, name, xp, %s AS value FROM rodeo_players
        WHERE %s > 0 ORDER BY value DESC, xp DESC LIMIT 500]]):format(spec.col, spec.col))

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
        ok = true, sort = sort, rows = top, me = me, profile = profile,
        arena = Config.Arena.name, price = Config.Price, size = Config.TopSize,
    }
end)

RegisterCommand('rodeoreset', function(src, args)
    if not HasAdminGroup(src) then return end
    if args[1] ~= 'oui' then
        if src ~= 0 then Notify(src, 'Cette commande efface TOUT le classement du rodéo. Tape /rodeoreset oui pour confirmer.', false) end
        return
    end
    MySQL.query.await('TRUNCATE TABLE `rodeo_players`')
    Cooldowns = {}
    if src ~= 0 then Notify(src, 'Classement du rodéo remis à zéro.', true) end
end, false)

AddEventHandler('playerDropped', function()
    Sessions[source] = nil
    ReleaseActive(source)
end)
