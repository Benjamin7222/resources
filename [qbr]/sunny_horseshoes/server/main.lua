local QBCore = exports['qbr-core']

local Bridge = {}

function Bridge.GetPlayer(src)
    local ok, Player = pcall(function() return QBCore:GetPlayer(src) end)
    if ok then return Player end
    return nil
end

function Bridge.Name(src)
    local Player = Bridge.GetPlayer(src)
    if Player and Player.PlayerData and Player.PlayerData.charinfo then
        local info = Player.PlayerData.charinfo
        return ('%s %s'):format(info.firstname or '?', info.lastname or '')
    end
    return GetPlayerName(src) or ('Joueur ' .. src)
end

function Bridge.RemoveMoney(src, amount, reason)
    if amount <= 0 then return true end
    local Player = Bridge.GetPlayer(src)
    if not Player then return false end
    return Player.Functions.RemoveMoney(Config.Money.account, amount, reason) and true or false
end

function Bridge.HasMoney(src, amount)
    if amount <= 0 then return true end
    local Player = Bridge.GetPlayer(src)
    local money = Player and Player.PlayerData and Player.PlayerData.money
    if not money then return true end
    return (tonumber(money[Config.Money.account]) or 0) >= amount
end

function Bridge.AddMoney(src, amount, reason)
    if amount <= 0 then return end
    local Player = Bridge.GetPlayer(src)
    if Player then Player.Functions.AddMoney(Config.Money.account, amount, reason) end
end

function Bridge.CitizenId(src)
    local Player = Bridge.GetPlayer(src)
    return Player and Player.PlayerData and Player.PlayerData.citizenid or nil
end

function Bridge.Notify(src, text, success)
    if success then
        TriggerClientEvent('QBCore:Notify', src, 9, text, 5000, 0, 'hud_textures', 'check', 'COLOR_WHITE')
    else
        TriggerClientEvent('QBCore:Notify', src, 9, text, 5000, 0, 'mp_lobby_textures', 'cross', 'COLOR_WHITE')
    end
end

local Now = GetGameTimer

local function Money(v)
    local s = ('%.2f'):format(v)
    return (s:gsub('%.?0+$', ''))
end

local function Round2(v) return math.floor(v * 100 + 0.5) / 100 end

local function Finite(v)
    return type(v) == 'number' and v == v and v ~= math.huge and v ~= -math.huge
end

local function BetAmount(v)
    if not Config.Bet.enabled then return 0 end
    v = tonumber(v)
    if not Finite(v) or v <= 0 then return 0 end
    v = math.floor(v)
    if v < Config.Bet.min or v > Config.Bet.max then return nil end
    return v
end

math.randomseed(os.time())

local Pits = {}
local PitOrder = {}
local PlayerPit = {}
local GameSeq = 0

for i, def in ipairs(Config.HorseshoePits) do
    if def.enabled ~= false then
        local pit = Sim.Pit(def, i)
        if Pits[pit.id] then
            print(('^1[sunny_horseshoes] id de terrain en double : %s (ignoré)^7'):format(pit.id))
        else
            Pits[pit.id] = { pit = pit, game = nil }
            PitOrder[#PitOrder + 1] = pit.id
        end
    end
end

local function PedCoords(src)
    local ped = GetPlayerPed(src)
    if not ped or ped == 0 then return nil end
    local c = GetEntityCoords(ped)
    if c.x == 0.0 and c.y == 0.0 and c.z == 0.0 then return nil end
    return c
end

local function Dist2D(c, v)
    return math.sqrt((c.x - v.x) ^ 2 + (c.y - v.y) ^ 2)
end

local function Near(src, v, maxDist)
    local c = PedCoords(src)
    if not c then return true end
    return Dist2D(c, v) <= maxDist
end

local function FindPlayer(game, src)
    for i, p in ipairs(game.players) do
        if p.src == src then return i, p end
    end
    return nil
end

local function Current(game)
    return game.players[game.turnIndex]
end

local function Public(entry)
    local pit, game = entry.pit, entry.game
    local s = { id = pit.id, status = 'free', maxPlayers = pit.maxPlayers, rounds = pit.rounds, throwsPerRound = pit.throwsPerRound, bet = 0, pot = 0 }
    if not game then return s end
    s.status = game.status
    s.bet = game.bet
    s.pot = game.pot
    s.gameId = game.id
    s.host = game.host
    s.solo = game.solo
    s.round = game.round
    s.turnId = game.turnId
    s.throwsLeft = game.throwsLeft
    s.busy = game.advanceAt ~= nil
    local cur = game.status == 'playing' and Current(game) or nil
    s.turn = cur and cur.src or nil
    s.turnLeft = (cur and not game.advanceAt) and math.max(0, math.ceil((game.turnStart + Config.Turn.timeout * 1000 - Now()) / 1000)) or nil
    s.players = {}
    for i, p in ipairs(game.players) do
        s.players[i] = { src = p.src, name = p.name, score = p.score, ringers = p.ringers }
    end
    s.shoes = {}
    for i, sh in ipairs(game.shoes) do
        s.shoes[i] = { id = sh.id, x = sh.x, y = sh.y, z = sh.z, psi = sh.psi }
    end
    return s
end

local function CanReceiveState(src, entry)
    if PlayerPit[src] == entry.pit.id then return true end
    local c = PedCoords(src)
    return c and (Dist2D(c, entry.pit.S) <= Config.SyncDistance + 20.0
        or Dist2D(c, entry.pit.coords) <= Config.SyncDistance + 20.0)
end

local function Broadcast(id, target)
    local entry = Pits[id]
    if not entry then return end
    if target then
        if CanReceiveState(target, entry) then
            TriggerClientEvent('sunny_horseshoes:client:PitState', target, id, Public(entry))
        end
        return
    end
    local state
    for _, pid in ipairs(GetPlayers()) do
        local src = tonumber(pid)
        if src and CanReceiveState(src, entry) then
            state = state or Public(entry)
            TriggerClientEvent('sunny_horseshoes:client:PitState', src, id, state)
        end
    end
end

local function NotifyGame(game, text, success)
    for _, p in ipairs(game.players) do Bridge.Notify(p.src, text, success) end
end

local function ResetPit(id)
    local entry = Pits[id]
    if not entry then return end
    if entry.game then
        for _, p in ipairs(entry.game.players) do
            if PlayerPit[p.src] == id then PlayerPit[p.src] = nil end
        end
    end
    entry.game = nil
    Broadcast(id)
end

local function BeginTurn(game)
    game.turnId = game.turnId + 1
    game.turnStart = Now()
    game.advanceAt = nil
end

local DbReady = false
local BOARD_SORTS = { score = 'best_score', ringers = 'ringers', wins = 'wins' }

CreateThread(function()
    if not Config.Leaderboard.enabled then return end
    local ok, err = pcall(function()
        MySQL.query.await([[CREATE TABLE IF NOT EXISTS `horseshoes_players` (
            `citizenid` varchar(50) NOT NULL,
            `name` varchar(100) NOT NULL,
            `best_score` int unsigned NOT NULL DEFAULT 0,
            `games` int unsigned NOT NULL DEFAULT 0,
            `wins` int unsigned NOT NULL DEFAULT 0,
            `ringers` int unsigned NOT NULL DEFAULT 0,
            `throws` int unsigned NOT NULL DEFAULT 0,
            `points` int unsigned NOT NULL DEFAULT 0,
            PRIMARY KEY (`citizenid`)
        ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    end)
    DbReady = ok
    if not ok then print('^1[sunny_horseshoes] classement désactivé (MySQL) : ' .. tostring(err) .. '^7') end
end)

local function SaveStats(game, rows, winners, reason)
    if not (Config.Leaderboard.enabled and DbReady) then return end
    local byId = {}
    for _, p in ipairs(game.players) do byId[p.src] = p end
    local soleWinner = (not game.solo and #winners == 1) and winners[1].src or nil
    local entries = {}
    for _, r in ipairs(rows) do
        local p = byId[r.src]
        if p and p.cid then
            entries[#entries + 1] = { src = p.src, cid = p.cid, name = p.name, score = p.score, ringers = p.ringers,
                throws = p.throws, win = (p.src == soleWinner) and 1 or 0, best = (reason == 'complete') and p.score or 0 }
        end
    end
    if #entries == 0 then return end
    CreateThread(function()
        for _, e in ipairs(entries) do
            local ok, err = pcall(function()
                local prev = MySQL.scalar.await('SELECT best_score FROM horseshoes_players WHERE citizenid = ?', { e.cid })
                MySQL.query.await([[INSERT INTO horseshoes_players (citizenid, name, best_score, games, wins, ringers, throws, points)
                    VALUES (?, ?, ?, 1, ?, ?, ?, ?)
                    ON DUPLICATE KEY UPDATE name = VALUES(name), best_score = GREATEST(best_score, VALUES(best_score)),
                    games = games + 1, wins = wins + VALUES(wins), ringers = ringers + VALUES(ringers),
                    throws = throws + VALUES(throws), points = points + VALUES(points)]],
                    { e.cid, e.name, e.best, e.win, e.ringers, e.throws, e.score })
                if e.best > 0 and e.best > (tonumber(prev) or 0) then
                    Bridge.Notify(e.src, ('Nouveau record personnel : %d points !'):format(e.best), true)
                end
            end)
            if not ok then print('^1[sunny_horseshoes] sauvegarde du classement : ' .. tostring(err) .. '^7') end
        end
    end)
end

local BoardCache, BoardRequests, BoardLists = {}, {}, {}
local StateRequests = {}

QBCore:CreateCallback('sunny_horseshoes:server:Board', function(source, cb, data)
    if not (Config.Leaderboard.enabled and DbReady) then
        return cb({ ok = false, error = "Le classement n'est pas disponible." })
    end
    local sort = type(data) == 'table' and BOARD_SORTS[data.sort] and data.sort or 'score'
    local col = BOARD_SORTS[sort]
    local now = Now()
    local request = BoardRequests[source]
    if request and (request.busy or now - request.at < 500) then
        return cb({ ok = false, error = 'Patiente un instant avant de recharger le classement.' })
    end
    local cached = BoardCache[source] and BoardCache[source][sort]
    if cached and now - cached.at < 20000 then
        BoardRequests[source] = { at = now, busy = false }
        return cb(cached.value)
    end
    request = { at = now, busy = true }
    BoardRequests[source] = request
    local ok, res = pcall(function()
        local size = math.max(1, math.min(50, math.floor(Config.Leaderboard.size or 10)))
        local shared = BoardLists[sort]
        local list
        if shared and now - shared.at < 20000 then
            list = shared.value
        else
            list = MySQL.query.await(('SELECT citizenid, name, best_score, games, wins, ringers, throws FROM horseshoes_players WHERE games > 0 ORDER BY %s DESC, games ASC, name ASC LIMIT %d'):format(col, size)) or {}
            BoardLists[sort] = { at = now, value = list }
        end
        local cid = Bridge.CitizenId(source)
        local rows, meRow = {}, nil
        for i, r in ipairs(list) do
            rows[i] = { rank = i, name = r.name, score = r.best_score, games = r.games, wins = r.wins, ringers = r.ringers, throws = r.throws, me = r.citizenid == cid }
        end
        if cid then
            local m = MySQL.single.await('SELECT name, best_score, games, wins, ringers, throws FROM horseshoes_players WHERE citizenid = ?', { cid })
            if m then
                local mine = ({ score = m.best_score, ringers = m.ringers, wins = m.wins })[sort]
                local rank = MySQL.scalar.await(('SELECT COUNT(*) + 1 FROM horseshoes_players WHERE games > 0 AND %s > ?'):format(col), { mine })
                meRow = { rank = tonumber(rank) or 0, name = m.name, score = m.best_score, games = m.games, wins = m.wins, ringers = m.ringers, throws = m.throws, me = true }
            end
        end
        return { ok = true, sort = sort, rows = rows, me = meRow }
    end)
    request.busy = false
    if BoardRequests[source] ~= request then return end
    if not ok then
        print('^1[sunny_horseshoes] classement : ' .. tostring(res) .. '^7')
        return cb({ ok = false, error = 'Erreur du classement, réessaie.' })
    end
    BoardCache[source] = BoardCache[source] or {}
    BoardCache[source][sort] = { at = BoardLists[sort] and BoardLists[sort].at or now, value = res }
    cb(res)
end)

local function Finish(entry, reason)
    local game = entry.game
    if not game or game.status == 'finished' then return end
    game.status = 'finished'
    game.advanceAt = nil

    local rows = {}
    for _, p in ipairs(game.players) do
        rows[#rows + 1] = { src = p.src, name = p.name, score = p.score, ringers = p.ringers, gain = 0 }
    end
    table.sort(rows, function(a, b) return a.score > b.score end)

    local winners = {}
    for _, r in ipairs(rows) do
        if r.score == rows[1].score then winners[#winners + 1] = r end
    end

    if not game.solo and #winners > 0 and game.pot > 0 then
        local share = Round2(game.pot * (1.0 - (Config.Bet.houseCut or 0)) / #winners)
        if share > 0 then
            for _, w in ipairs(winners) do
                Bridge.AddMoney(w.src, share, 'horseshoes-pari-gagne')
                w.gain = share
            end
        end
    end

    SaveStats(game, rows, winners, reason)

    local result = {
        solo = game.solo,
        reason = reason,
        rows = rows,
        tie = #winners > 1,
        winner = (#winners == 1) and winners[1].name or nil,
        rounds = entry.pit.rounds,
        pot = game.pot,
    }
    for _, p in ipairs(game.players) do
        TriggerClientEvent('sunny_horseshoes:client:GameOver', p.src, entry.pit.id, result)
        PlayerPit[p.src] = nil
    end
    game.finishedAt = Now()
    Broadcast(entry.pit.id)
end

local function Advance(entry)
    local game = entry.game
    if not game or game.status ~= 'playing' then return end
    if #game.players == 0 then return ResetPit(entry.pit.id) end

    if game.throwsLeft <= 0 then
        game.turnIndex = game.turnIndex + 1
        if game.turnIndex > #game.players then
            game.turnIndex = 1
            if game.round >= entry.pit.rounds then
                return Finish(entry, 'complete')
            end
            game.round = game.round + 1
            game.shoes = {}
        end
        game.throwsLeft = entry.pit.throwsPerRound
    end
    BeginTurn(game)
    Broadcast(entry.pit.id)
end

local function RemovePlayer(src, reason)
    local id = PlayerPit[src]
    if not id then return end
    PlayerPit[src] = nil
    local entry = Pits[id]
    local game = entry and entry.game
    if not game or game.status == 'finished' then return end
    local idx, p = FindPlayer(game, src)
    if not idx then return end

    local wasCurrent = game.status == 'playing' and idx == game.turnIndex
    table.remove(game.players, idx)
    if reason ~= 'drop' then
        Bridge.Notify(src, reason == 'far' and 'Tu t\'es éloigné du terrain : partie quittée.' or 'Tu as quitté la partie de fer à cheval.', false)
        TriggerClientEvent('sunny_horseshoes:client:Left', src, id)
    end

    if #game.players == 0 then return ResetPit(id) end
    if game.host == src then game.host = game.players[1].src end

    if game.status == 'lobby' then
        return Broadcast(id)
    end

    NotifyGame(game, ('%s a quitté la partie.'):format(p.name), false)
    if not game.solo and #game.players == 1 then
        return Finish(entry, 'forfeit')
    end

    if idx < game.turnIndex then
        game.turnIndex = game.turnIndex - 1
    elseif wasCurrent then
        if game.turnIndex > #game.players then
            game.turnIndex = #game.players
            game.throwsLeft = 0
            return Advance(entry)
        end
        game.throwsLeft = entry.pit.throwsPerRound
        BeginTurn(game)
    end
    Broadcast(id)
end

local function StartGame(entry)
    local game = entry.game
    local fee = game.bet or 0
    local keep = {}
    for _, p in ipairs(game.players) do
        if Bridge.RemoveMoney(p.src, fee, 'horseshoes-pari') then
            game.paid[p.src] = fee
            game.pot = game.pot + fee
            keep[#keep + 1] = p
        else
            PlayerPit[p.src] = nil
            Bridge.Notify(p.src, ('Il te faut %s $ sur toi pour couvrir la mise.'):format(Money(fee)), false)
            TriggerClientEvent('sunny_horseshoes:client:Left', p.src, entry.pit.id)
        end
    end
    game.players = keep
    if #keep == 0 then return ResetPit(entry.pit.id) end

    if game.mode == 'multi' and #keep < 2 then
        for _, p in ipairs(keep) do
            Bridge.AddMoney(p.src, game.paid[p.src] or 0, 'horseshoes-pari-rembourse')
            Bridge.Notify(p.src, "Ton adversaire n'a pas assez d'argent : mise remboursée, en attente d'un autre joueur.", false)
        end
        game.paid, game.pot = {}, 0
        game.host = keep[1].src
        game.lobbyUntil = Now() + Config.Lobby.timeout * 1000
        return Broadcast(entry.pit.id)
    end

    game.host = keep[1].src
    game.solo = #keep == 1
    game.status = 'playing'
    game.round = 1
    game.turnIndex = 1
    game.throwsLeft = entry.pit.throwsPerRound
    game.shoes = {}
    BeginTurn(game)
    local msg = game.solo and 'Partie solo : bonne chance !'
        or (game.pot > 0 and ('La partie commence ! Pot : %s $, le gagnant rafle tout.'):format(Money(game.pot))
        or 'La partie commence ! (sans mise)')
    NotifyGame(game, msg, true)
    Broadcast(entry.pit.id)
end

local function Validate(src, id)
    local entry = type(id) == 'string' and Pits[id] or nil
    if not entry then return nil end
    if not Bridge.GetPlayer(src) then return nil end
    return entry
end

local function NearLine(src, entry)
    return Near(src, entry.pit.coords, Config.Interaction.distance + 6.0)
end

RegisterNetEvent('sunny_horseshoes:server:Create', function(id, mode, bet)
    local src = source
    local entry = Validate(src, id)
    if not entry then return end
    if PlayerPit[src] then return Bridge.Notify(src, 'Tu es déjà dans une partie.', false) end
    if entry.game then return Bridge.Notify(src, 'Ce terrain est déjà occupé.', false) end
    if not NearLine(src, entry) then return Bridge.Notify(src, 'Approche-toi de la ligne de lancer.', false) end
    local solo = mode == 'solo' or entry.pit.maxPlayers <= 1
    bet = solo and 0 or BetAmount(bet)
    if not bet then
        return Bridge.Notify(src, ('La mise doit être comprise entre %d $ et %d $.'):format(Config.Bet.min, Config.Bet.max), false)
    end
    if not Bridge.HasMoney(src, bet) then
        return Bridge.Notify(src, ("Tu n'as pas %s $ sur toi pour miser."):format(Money(bet)), false)
    end

    GameSeq = GameSeq + 1
    entry.game = {
        id = GameSeq,
        status = 'lobby',
        host = src,
        solo = true,
        players = { { src = src, name = Bridge.Name(src), score = 0, ringers = 0, throws = 0, cid = Bridge.CitizenId(src) } },
        round = 0,
        turnIndex = 1,
        throwsLeft = 0,
        turnId = 0,
        turnStart = Now(),
        shoes = {},
        shoeSeq = 0,
        paid = {},
        pot = 0,
        bet = bet,
        lobbyUntil = Now() + Config.Lobby.timeout * 1000,
    }
    PlayerPit[src] = id

    if solo then
        entry.game.mode = 'solo'
        return StartGame(entry)
    end
    entry.game.mode = 'multi'
    entry.game.solo = false
    local betText = bet > 0 and (' Mise : %s $ par joueur.'):format(Money(bet)) or ' Sans mise.'
    Bridge.Notify(src, (entry.pit.maxPlayers == 2
        and "Partie créée : elle démarre dès qu'un adversaire la rejoint via le PNJ."
        or ('Partie créée : lance-la via le PNJ quand tout le monde est là (%d max).'):format(entry.pit.maxPlayers)) .. betText, true)
    local host = entry.game.players[1].name
    for _, pid in ipairs(GetPlayers()) do
        local other = tonumber(pid)
        if other and other ~= src and PedCoords(other) and Near(other, entry.pit.coords, 40.0) then
            Bridge.Notify(other, ('%s propose une partie de lancer de fer.%s Parle au PNJ pour la rejoindre.'):format(host, betText), true)
        end
    end
    Broadcast(id)
end)

RegisterNetEvent('sunny_horseshoes:server:Join', function(id)
    local src = source
    local entry = Validate(src, id)
    if not entry then return end
    local game = entry.game
    if PlayerPit[src] then return Bridge.Notify(src, 'Tu es déjà dans une partie.', false) end
    if not game or game.status ~= 'lobby' then return Bridge.Notify(src, 'Aucune partie à rejoindre ici.', false) end
    if #game.players >= entry.pit.maxPlayers then return Bridge.Notify(src, 'La partie est complète.', false) end
    if not NearLine(src, entry) then return Bridge.Notify(src, 'Approche-toi de la ligne de lancer.', false) end
    if not Bridge.HasMoney(src, game.bet) then
        return Bridge.Notify(src, ('Il te faut %s $ sur toi pour suivre la mise.'):format(Money(game.bet)), false)
    end

    local name = Bridge.Name(src)
    game.players[#game.players + 1] = { src = src, name = name, score = 0, ringers = 0, throws = 0, cid = Bridge.CitizenId(src) }
    PlayerPit[src] = id
    NotifyGame(game, ('%s rejoint la partie (%d/%d).%s'):format(name, #game.players, entry.pit.maxPlayers,
        game.bet > 0 and (' Mise : %s $ par joueur.'):format(Money(game.bet)) or ''), true)
    if #game.players >= entry.pit.maxPlayers then
        return StartGame(entry)
    end
    Broadcast(id)
end)

RegisterNetEvent('sunny_horseshoes:server:Start', function(id)
    local src = source
    local entry = Validate(src, id)
    if not entry then return end
    local game = entry.game
    if not game or game.status ~= 'lobby' then return end
    if game.host ~= src then return Bridge.Notify(src, 'Seul le créateur de la partie peut la lancer.', false) end
    if #game.players < 2 then
        return Bridge.Notify(src, "Il faut au moins 2 joueurs : attends qu'un adversaire rejoigne via le PNJ (ou choisis « Jouer seul »).", false)
    end
    StartGame(entry)
end)

RegisterNetEvent('sunny_horseshoes:server:Leave', function()
    RemovePlayer(source, 'leave')
end)

RegisterNetEvent('sunny_horseshoes:server:Throw', function(id, turnId, power, aim, releaseMs)
    local src = source
    local entry = Validate(src, id)
    if not entry then return end
    local game = entry.game
    if not game or game.status ~= 'playing' or PlayerPit[src] ~= id then return end
    local cur = Current(game)
    if not cur or cur.src ~= src then return end
    if turnId ~= game.turnId or game.advanceAt or game.throwsLeft <= 0 then return end
    if not (Finite(power) and Finite(aim) and Finite(releaseMs)) then return end
    if not Near(src, Sim.Spot(entry.pit, game.round).T, Config.Turn.positionTolerance) then
        return Bridge.Notify(src, 'Place-toi sur la ligne de lancer.', false)
    end

    releaseMs = math.floor(Sim.Clamp(releaseMs, Config.AnimReleaseMin, Config.AnimReleaseMax))

    local th = Sim.Simulate(entry.pit, power, aim, game.round)
    local res = th.result
    cur.score = cur.score + res.points
    if res.kind == 'ringer' then cur.ringers = cur.ringers + 1 end
    cur.throws = cur.throws + 1
    game.throwsLeft = game.throwsLeft - 1
    game.shoeSeq = game.shoeSeq + 1
    local shoeId = ('%d_%d'):format(game.id, game.shoeSeq)
    game.shoes[#game.shoes + 1] = { id = shoeId, x = th.final.x, y = th.final.y, z = th.final.z, psi = th.final.psi }
    game.advanceAt = Now() + releaseMs + th.totalMs + Config.Turn.afterThrowMs

    local payload = {
        gameId = game.id,
        src = src,
        turnId = turnId,
        shoeId = shoeId,
        releaseMs = releaseMs,
        o = th.o, v = th.v, g = th.g, psi0 = th.psi0, spin = th.spin, tEnd = th.tEnd,
        after = th.after,
        final = th.final,
        result = res,
    }
    local players = {}
    for _, p in ipairs(game.players) do players[p.src] = true end
    local range = Config.SyncDistance + 20.0
    for _, pid in ipairs(GetPlayers()) do
        local target = tonumber(pid)
        if target and (players[target] or Near(target, entry.pit.S, range)) then
            TriggerClientEvent('sunny_horseshoes:client:Throw', target, id, payload)
        end
    end
end)

RegisterNetEvent('sunny_horseshoes:server:RequestStates', function(id)
    local src = source
    if id ~= nil and (type(id) ~= 'string' or not Pits[id]) then return end
    local key = id or '*'
    local now = Now()
    StateRequests[src] = StateRequests[src] or {}
    local previous = StateRequests[src][key]
    if previous and now - previous < 500 then return end
    StateRequests[src][key] = now
    if id then return Broadcast(id, src) end
    for _, pitId in ipairs(PitOrder) do Broadcast(pitId, src) end
end)

AddEventHandler('playerDropped', function()
    BoardCache[source], BoardRequests[source], StateRequests[source] = nil, nil, nil
    RemovePlayer(source, 'drop')
end)

CreateThread(function()
    while true do
        Wait(500)
        local now = Now()
        for _, id in ipairs(PitOrder) do
            local entry = Pits[id]
            local game = entry.game
            if game then
                if game.status == 'lobby' and now > game.lobbyUntil then
                    NotifyGame(game, 'Personne n\'a lancé la partie : elle est annulée.', false)
                    for _, p in ipairs(game.players) do TriggerClientEvent('sunny_horseshoes:client:Left', p.src, id) end
                    ResetPit(id)
                elseif game.status == 'finished' then
                    if now - (game.finishedAt or now) > Config.Turn.endScreenMs then ResetPit(id) end
                else
                    for i = #game.players, 1, -1 do
                        local p = game.players[i]
                        if not GetPlayerName(p.src) then
                            RemovePlayer(p.src, 'drop')
                        elseif not Near(p.src, entry.pit.coords, Config.Turn.leaveDistance) then
                            RemovePlayer(p.src, 'far')
                        end
                    end
                    game = entry.game
                    if game and game.status == 'playing' then
                        if game.advanceAt then
                            if now >= game.advanceAt then Advance(entry) end
                        elseif now - game.turnStart > Config.Turn.timeout * 1000 then
                            local cur = Current(game)
                            if cur then Bridge.Notify(cur.src, 'Temps écoulé : lancer perdu.', false) end
                            game.throwsLeft = game.throwsLeft - 1
                            game.advanceAt = now + 300
                        end
                    end
                end
            end
        end
    end
end)
