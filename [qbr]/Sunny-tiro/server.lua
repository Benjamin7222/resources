local activeGames, cooldowns, boardRequests = {}, {}, {}
local databaseReady = false
local nextSession = 0

local function TargetOrder()
    local count = #Config.Bottles
    local order = {}
    for i = 1, count do order[i] = i end
    for attempt = 1, 64 do

        for i = count - 1, 2, -1 do
            local j = math.random(i)
            order[i], order[j] = order[j], order[i]
        end
        local valid = true
        for i = 1, count - 2, 2 do
            local a, b = Config.Bottles[order[i]].Coords, Config.Bottles[order[i + 1]].Coords

            if math.abs(a.x-b.x) < 0.1 and math.abs(a.y-b.y) < 0.1 then valid = false break end
        end
        if valid then return order end
    end
    for i = 1, count do order[i] = i end
    return order
end

local function GetPlayer(src)
    return exports['qbr-core']:GetPlayer(src)
end

local function Character(player, src)
    if not player or not player.PlayerData then return end
    local info = player.PlayerData.charinfo or {}
    local name = ((info.firstname or '') .. ' ' .. (info.lastname or '')):match('^%s*(.-)%s*$')
    return player.PlayerData.citizenid, name ~= '' and name or GetPlayerName(src)
end

local function NearStand(src, radius)
    local ped = GetPlayerPed(src)
    return ped ~= 0 and #(GetEntityCoords(ped) - Config.Start) <= radius
end

local function Deny(src, message, request)
    TriggerClientEvent('Sunny-tiro:client:Denied', src, message, request)
end

CreateThread(function()
    local ok, err = pcall(function()
        MySQL.query.await([[
            CREATE TABLE IF NOT EXISTS sunny_tiro_scores (
                citizenid VARCHAR(80) NOT NULL,
                player_name VARCHAR(120) NOT NULL,
                best_score TINYINT UNSIGNED NOT NULL DEFAULT 0,
                best_time_ms INT UNSIGNED NULL,
                best_shots SMALLINT UNSIGNED NULL,
                updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
                PRIMARY KEY (citizenid), INDEX idx_best_score (best_score DESC)
            ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4 COLLATE=utf8mb4_unicode_ci
        ]])
        local columns = MySQL.query.await("SHOW COLUMNS FROM sunny_tiro_scores LIKE 'best_time_ms'")
        if not columns or #columns == 0 then
            MySQL.query.await('ALTER TABLE sunny_tiro_scores ADD COLUMN best_time_ms INT UNSIGNED NULL')
        end
        local shotColumns = MySQL.query.await("SHOW COLUMNS FROM sunny_tiro_scores LIKE 'best_shots'")
        if not shotColumns or #shotColumns == 0 then
            MySQL.query.await('ALTER TABLE sunny_tiro_scores ADD COLUMN best_shots SMALLINT UNSIGNED NULL')
        end
    end)
    databaseReady = ok
    if not ok then print('[Sunny-tiro] SQL indisponible: ' .. tostring(err)) end
end)

RegisterNetEvent('Sunny-tiro:server:StartGame', function(request)
    local src = source
    local function Reject(message) Deny(src, message, request) end
    if not databaseReady then return Reject('Le classement est indisponible. Reessayez plus tard.') end
    if not NearStand(src, Config.StartRadius) then return Reject('Approchez-vous du stand.') end
    local player = GetPlayer(src)
    local citizenid = Character(player, src)
    if not citizenid then return Reject('Personnage indisponible.') end
    local now = os.time()

    for owner, game in pairs(activeGames) do
        if now > game.expires then
            if game.started then cooldowns[game.citizenid] = now + Config.Cooldown end
            activeGames[owner] = nil
        elseif owner ~= src then
            return Reject('Le stand est occupe par un autre joueur. Attendez la fin de sa partie.')
        end
    end
    if activeGames[src] then
        return Reject('Une partie est deja en cours.')
    end
    if (cooldowns[citizenid] or 0) > now then
        return Reject(('Attendez encore %d seconde(s).'):format(cooldowns[citizenid] - now))
    end
    if (player.PlayerData.money.cash or 0) < Config.EntryFee then
        return Reject(('Il vous faut %d dollars en especes pour participer.'):format(Config.EntryFee))
    end
    nextSession = nextSession + 1
    activeGames[src] = {
        id = nextSession, request = request, citizenid = citizenid, hits = {}, score = 0, order = TargetOrder(),
        expires = now + Config.SetupTimeout
    }
    TriggerClientEvent('Sunny-tiro:client:Approved', src, nextSession, request, activeGames[src].order)
end)

RegisterNetEvent('Sunny-tiro:server:Ready', function(id)
    local src = source
    local game = activeGames[src]
    local function Reject(message) Deny(src, message, game.request) end
    if not game or game.id ~= id or game.started then return end
    if game.expires < os.time() or not NearStand(src, Config.PlayRadius) then
        activeGames[src] = nil
        return Reject('Preparation expiree ou stand trop eloigne.')
    end
    local start = Config.PlayerStart
    if #(GetEntityCoords(GetPlayerPed(src)) - vector3(start.x, start.y, start.z)) > 2.0 then
        activeGames[src] = nil
        return Reject('Placez-vous au pas de tir pour commencer.')
    end
    local player = GetPlayer(src)
    if Character(player, src) ~= game.citizenid then
        activeGames[src] = nil
        return Reject('Personnage indisponible.')
    end
    if (player.PlayerData.money.cash or 0) < Config.EntryFee then
        activeGames[src] = nil
        return Reject(('Il vous faut %d dollars en especes pour participer.'):format(Config.EntryFee))
    end

    game.started = os.time()
    local ok, paid = pcall(player.Functions.RemoveMoney, 'cash', Config.EntryFee, 'Sunny-tiro-entry')
    if not ok or paid ~= true then
        activeGames[src] = nil
        return Reject('Paiement impossible. La partie n a pas commence.')
    end
    game.expires = game.started + Config.GameDuration + 5
    game.startedMs = GetGameTimer()
    TriggerClientEvent('Sunny-tiro:client:Begin', src, id)
end)

RegisterNetEvent('Sunny-tiro:server:Hit', function(id, index)
    local src = source
    local game = activeGames[src]
    if not game or game.id ~= id or not game.started or os.time() > game.expires then return end
    if type(index) ~= 'number' or index % 1 ~= 0 or not Config.Bottles[index] or game.hits[index] then return end

    local first = math.floor(game.score / 2) * 2 + 1
    if game.score == #game.order - 1 then first = #game.order end
    local last = first == #game.order and first or math.min(first + 1, #game.order - 1)
    if index ~= game.order[first] and index ~= game.order[last] then return end
    if not NearStand(src, Config.PlayRadius) then return end
    game.hits[index] = true
    game.score = game.score + 1
end)

RegisterNetEvent('Sunny-tiro:server:CancelPending', function(request)
    local src = source
    local game = activeGames[src]
    if game and not game.started and request ~= nil and game.request == request then
        activeGames[src] = nil
    end
end)

RegisterNetEvent('Sunny-tiro:server:Cancel', function(id)
    local src = source
    local game = activeGames[src]
    if not game or game.id ~= id then return end
    if game.started then cooldowns[game.citizenid] = os.time() + Config.Cooldown end
    activeGames[src] = nil
end)

RegisterNetEvent('Sunny-tiro:server:FinishGame', function(id, shots)
    local src = source
    local game = activeGames[src]
    if not game or game.id ~= id or not game.started then return end

    activeGames[src] = nil
    cooldowns[game.citizenid] = os.time() + Config.Cooldown
    local player = GetPlayer(src)
    local citizenid, name = Character(player, src)
    if citizenid ~= game.citizenid then return end
    local score = game.score
    if os.time() > game.expires or not NearStand(src, Config.PlayRadius) then score = 0 end
    if type(shots) ~= 'number' or shots ~= shots or shots % 1 ~= 0 or shots < 0 or shots > Config.MaxShots then shots = nil end
    local elapsedMs = math.max(0, math.min(Config.GameDuration * 1000, GetGameTimer() - game.startedMs))
    local newRecord = false
    local ok, err = pcall(function()
        local old = MySQL.single.await('SELECT best_score, best_time_ms, best_shots FROM sunny_tiro_scores WHERE citizenid = ?', { citizenid })
        local oldScore = old and tonumber(old.best_score) or -1
        local oldTime = old and tonumber(old.best_time_ms)
        newRecord = score > oldScore or (score == oldScore and (not oldTime or elapsedMs < oldTime))
        MySQL.insert.await([[
            INSERT INTO sunny_tiro_scores (citizenid, player_name, best_score, best_time_ms, best_shots)
            VALUES (?, ?, ?, ?, NULLIF(?, -1))
            ON DUPLICATE KEY UPDATE player_name = VALUES(player_name),
                updated_at = IF(VALUES(best_score) > best_score OR
                    (VALUES(best_score) = best_score AND (best_time_ms IS NULL OR VALUES(best_time_ms) < best_time_ms)), CURRENT_TIMESTAMP, updated_at),
                best_shots = IF(VALUES(best_score) > best_score OR
                    (VALUES(best_score) = best_score AND (best_time_ms IS NULL OR VALUES(best_time_ms) < best_time_ms)) OR
                    (VALUES(best_score) = best_score AND VALUES(best_time_ms) = best_time_ms AND best_shots IS NULL), VALUES(best_shots), best_shots),
                best_time_ms = IF(VALUES(best_score) > best_score OR
                    (VALUES(best_score) = best_score AND (best_time_ms IS NULL OR VALUES(best_time_ms) < best_time_ms)), VALUES(best_time_ms), best_time_ms),
                best_score = GREATEST(best_score, VALUES(best_score))
        ]], { citizenid, name, score, elapsedMs, shots or -1 })
    end)
    if not ok then
        print('[Sunny-tiro] Sauvegarde impossible: ' .. tostring(err))
        newRecord = false
    end

    player = GetPlayer(src)
    if Character(player, src) ~= citizenid then return end
    TriggerClientEvent('Sunny-tiro:client:Result', src, {
        session = id, score = score, elapsedMs = elapsedMs, shots = shots, newRecord = newRecord
    })
    if not ok then TriggerClientEvent('Sunny-tiro:client:Notice', src, 'Le score n a pas pu etre sauvegarde.') end
end)

RegisterNetEvent('Sunny-tiro:server:Leaderboard', function()
    local src = source
    if (boardRequests[src] or 0) > os.time() then
        return TriggerClientEvent('Sunny-tiro:client:Notice', src, 'Patientez un instant avant de rouvrir le classement.')
    end
    boardRequests[src] = os.time() + 3
    local player = GetPlayer(src)
    local citizenid = Character(player, src)
    if not citizenid then return end
    if not databaseReady then
        return TriggerClientEvent('Sunny-tiro:client:Notice', src, 'Classement indisponible.')
    end
    local limit = math.max(1, math.min(50, math.floor(Config.LeaderboardLimit)))
    local ok, rows, personal, personalTime, personalShots = pcall(function()
        local top = MySQL.query.await('SELECT player_name, best_score, best_time_ms, best_shots FROM sunny_tiro_scores ORDER BY best_score DESC, best_time_ms IS NULL ASC, best_time_ms ASC, updated_at ASC LIMIT ' .. limit)
        local own = MySQL.single.await('SELECT best_score, best_time_ms, best_shots FROM sunny_tiro_scores WHERE citizenid = ?', { citizenid })
        return top or {}, own and tonumber(own.best_score) or 0, own and tonumber(own.best_time_ms), own and tonumber(own.best_shots)
    end)
    if Character(GetPlayer(src), src) ~= citizenid then return end
    if not ok then
        print('[Sunny-tiro] Classement: ' .. tostring(rows))
        return TriggerClientEvent('Sunny-tiro:client:Notice', src, 'Classement indisponible.')
    end
    TriggerClientEvent('Sunny-tiro:client:Leaderboard', src, { rows = rows, personalBest = personal, personalTime = personalTime, personalShots = personalShots })
end)

CreateThread(function()
    while true do
        Wait(10000)
        local now = os.time()
        for src, game in pairs(activeGames) do
            if now > game.expires then
                if game.started then cooldowns[game.citizenid] = now + Config.Cooldown end
                activeGames[src] = nil
            end
        end
        for citizenid, expiry in pairs(cooldowns) do
            if expiry <= now then cooldowns[citizenid] = nil end
        end
    end
end)

AddEventHandler('playerDropped', function()
    local src = source
    local game = activeGames[src]
    if game and game.started then cooldowns[game.citizenid] = os.time() + Config.Cooldown end
    activeGames[src] = nil
    boardRequests[src] = nil
end)
