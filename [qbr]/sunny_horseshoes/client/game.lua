local function Contains(list, id)
    for _, v in ipairs(list or {}) do
        if v.id == id then return true end
    end
    return false
end

local function ReconcileShoes(pitId, st)
    if not HS.Near[pitId] then return HS.ClearPitShoes(pitId) end
    local list = (st and st.shoes) or {}
    for id, sh in pairs(HS.Shoes) do
        if sh.pit == pitId and not Contains(list, id) then HS.RemoveShoe(id) end
    end
    for _, sh in ipairs(list) do
        if not HS.Shoes[sh.id] and not HS.Animating[sh.id] then
            HS.PlaceShoe(sh.id, pitId, sh.x, sh.y, sh.z, sh.psi)
        end
    end
end

local function ReconcileHands(pitId, st)
    if not HS.Near[pitId] or not st or st.status ~= 'playing' or not st.turn then
        return HS.ClearPitHands(pitId)
    end
    HS.ClearPitHands(pitId, st.turn)
    if not st.busy then HS.AttachHandShoe(st.turn, pitId) end
end

local function NameOf(st, src)
    for _, p in ipairs((st and st.players) or {}) do
        if p.src == src then return p.name end
    end
    return '?'
end

local function Hud(pitId, st)
    if not Config.UI.enabled then return end
    if HS.MyPit ~= pitId or not st or st.status == 'free' or st.status == 'finished' then
        return HS.SendUI({ action = 'hud', show = false })
    end
    local me = HS.MyId()
    local players = {}
    for _, p in ipairs(st.players or {}) do
        players[#players + 1] = { name = p.name, score = p.score, ringers = p.ringers, me = p.src == me, turn = p.src == st.turn }
    end
    HS.SendUI({
        action = 'hud',
        show = true,
        status = st.status,
        solo = st.solo,
        round = st.round,
        rounds = st.rounds,
        throwsLeft = st.throwsLeft,
        throwsPerRound = st.throwsPerRound,
        maxPlayers = st.maxPlayers,
        host = st.host == me,
        myTurn = st.turn == me and not st.busy,
        turnName = st.turn and NameOf(st, st.turn) or nil,
        turnLeft = st.turnLeft,
        bet = st.bet,
        pot = st.pot,
        players = players,
    })
end

local function CheckMyTurn(pitId, st, force)
    local me = HS.MyId()
    local mine = st and st.status == 'playing' and st.turn == me and not st.busy
    if mine then
        if force or HS.AimTurn ~= st.turnId then
            if not HS.Aiming and not HS.Pending then
                HS.AimTurn = st.turnId
                if HS.CloseBoard then HS.CloseBoard() end
                HS.StartAim(pitId, st.turnId)
            end
        end
    elseif HS.Aiming and HS.Aiming.pit == pitId then
        HS.StopAim()
    end
end

function HS.Recheck(pitId, force)
    CheckMyTurn(pitId, HS.States[pitId], force)
end

RegisterNetEvent('sunny_horseshoes:client:PitState', function(pitId, st)
    if not HS.Pits[pitId] then return end
    local prev = HS.States[pitId]
    HS.States[pitId] = st

    local participant = (st.status == 'lobby' or st.status == 'playing') and HS.IsParticipant(st)
    if participant then
        if HS.MyPit ~= pitId then HS.AimTurn = nil end
        HS.MyPit = pitId
    elseif HS.MyPit == pitId then
        HS.MyPit = nil
        if st.status ~= 'finished' then HS.SendUI({ action = 'hud', show = false }) end
        if HS.Aiming then HS.StopAim() end
    end

    ReconcileShoes(pitId, st)
    ReconcileHands(pitId, st)
    Hud(pitId, st)
    CheckMyTurn(pitId, st)

    local me = HS.MyId()
    if participant and st.status == 'playing' and prev and prev.turn == me and st.turn and st.turn ~= me then
        local pit = HS.Pits[pitId]
        local spot = Sim.Spot(pit, prev.round)
        local ped = PlayerPedId()
        local c = GetEntityCoords(ped)
        if #(vector2(c.x, c.y) - vector2(spot.T.x, spot.T.y)) < 1.5 then
            local h = math.rad(spot.heading)
            local rx, ry = math.cos(h), math.sin(h)
            TaskGoStraightToCoord(ped, spot.T.x + rx * 1.8, spot.T.y + ry * 1.8, spot.T.z, 1.0, 3000, spot.heading, 0.3, 0)
        end
    end

    if participant and st.status == 'playing' and prev and prev.round and st.round ~= prev.round and prev.status == 'playing' then
        HS.SendUI({ action = 'banner', text = ('ROUND %d / %d'):format(st.round, st.rounds) })
    end
    if participant and st.status == 'playing' and (not prev or prev.status ~= 'playing' or prev.gameId ~= st.gameId) then
        HS.SendUI({ action = 'banner', text = 'LANCER DE FER' })
    end
end)

RegisterNetEvent('sunny_horseshoes:client:Throw', function(pitId, d)
    if not HS.Pits[pitId] or type(d) ~= 'table' then return end
    local st = HS.States[pitId]
    if not HS.Near[pitId] and not HS.IsParticipant(st) then return end
    if st then st.busy = true end
    CreateThread(function() HS.PlayFlight(pitId, d) end)
end)

function HS.OnLanded(pitId, d)
    local st = HS.States[pitId]
    if not HS.IsParticipant(st) then return end
    local mine = d.src == HS.MyId()
    local res = d.result
    if Config.UI.enabled then
        HS.SendUI({
            action = 'popup',
            points = res.points,
            label = res.label,
            kind = res.kind,
            mine = mine,
            name = NameOf(st, d.src),
        })
    else
        local who = mine and 'Toi' or NameOf(st, d.src)
        HS.Notify(('%s : +%d point%s - %s'):format(who, res.points, res.points > 1 and 's' or '', res.label), res.points > 0)
    end
end

RegisterNetEvent('sunny_horseshoes:client:GameOver', function(pitId, result)
    if HS.Aiming then HS.StopAim() end
    HS.MyPit = nil
    local me = HS.MyId()
    local rows = {}
    for i, r in ipairs(result.rows or {}) do
        rows[i] = { name = r.name, score = r.score, ringers = r.ringers, gain = r.gain, me = r.src == me }
    end
    if Config.UI.enabled then
        HS.SendUI({ action = 'hud', show = false })
        HS.SendUI({ action = 'final', rows = rows, winner = result.winner, tie = result.tie, solo = result.solo, reason = result.reason, pot = result.pot, ms = Config.Turn.endScreenMs })
    else
        for _, r in ipairs(rows) do
            HS.Notify(('%s : %d POINTS'):format(r.name:upper(), r.score), r.me)
        end
        if result.solo then
            HS.Notify(('Partie terminée : %d points.'):format(rows[1] and rows[1].score or 0), true)
        elseif result.tie then
            HS.Notify('ÉGALITÉ !', true)
        elseif result.winner then
            HS.Notify(('VICTOIRE : %s'):format(result.winner:upper()), true)
        end
    end
end)

RegisterNetEvent('sunny_horseshoes:client:Left', function(pitId)
    if HS.MyPit == pitId then HS.MyPit = nil end
    if HS.Aiming then HS.StopAim() end
    HS.SendUI({ action = 'hud', show = false })
end)

function HS.OnPitNear(pitId)
    TriggerServerEvent('sunny_horseshoes:server:RequestStates', pitId)
    local st = HS.States[pitId]
    ReconcileShoes(pitId, st)
    ReconcileHands(pitId, st)
end

function HS.OnPitFar(pitId)
    HS.ClearPitShoes(pitId)
    HS.ClearPitHands(pitId)
end

local QBCore = exports['qbr-core']
local BoardOpen, BoardBusy = false, false

local function CloseBoard()
    if not BoardOpen then return end
    BoardOpen = false
    SetNuiFocus(false, false)
    SendNUIMessage({ action = 'board', show = false })
end
HS.CloseBoard = CloseBoard

function HS.OpenBoard()
    if not Config.Leaderboard.enabled or BoardOpen or BoardBusy then return end
    if HS.Aiming or HS.Pending then return HS.Notify('Pas pendant un lancer.', false) end
    BoardBusy = true
    QBCore:TriggerCallback('sunny_horseshoes:server:Board', function(res)
        BoardBusy = false
        if not res or not res.ok then
            return HS.Notify(res and res.error or 'Pas de réponse du serveur.', false)
        end
        if HS.Aiming or HS.Pending then return end
        if not Config.UI.enabled then
            HS.Notify('Classement lancer de fer (meilleur score) :', true)
            for i = 1, math.min(5, #res.rows) do
                local r = res.rows[i]
                HS.Notify(('%d. %s : %d pts'):format(r.rank, r.name, r.score), r.me)
            end
            return
        end
        BoardOpen = true
        SetNuiFocus(true, true)
        SendNUIMessage({ action = 'board', show = true, data = res })
    end, { sort = 'score' })
end

RegisterNUICallback('close', function(_, cb)
    cb('ok')
    CloseBoard()
end)

RegisterNUICallback('boardData', function(data, cb)
    if not BoardOpen then return cb({ ok = false }) end
    QBCore:TriggerCallback('sunny_horseshoes:server:Board', function(res)
        cb(res or { ok = false, error = 'Pas de réponse du serveur.' })
    end, type(data) == 'table' and { sort = data.sort } or {})
end)

RegisterCommand(Config.Leaderboard.command or 'fertop', function() HS.OpenBoard() end, false)
