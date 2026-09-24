Sim = {}

local sin, cos, sqrt, rad, deg = math.sin, math.cos, math.sqrt, math.rad, math.deg
local TAU = math.pi * 2

function Sim.Clamp(v, lo, hi)
    if v < lo then return lo end
    if v > hi then return hi end
    return v
end

local function Gravity()
    local g = Config.ThrowGravity
    if type(g) == 'number' and g > 0 then return g end
    return 9.81
end

function Sim.HeadingFromVec(dx, dy)
    return deg(math.atan(-dx, dy)) % 360.0
end

function Sim.DirFromHeading(h)
    local r = rad(h)
    return -sin(r), cos(r)
end

local function V(x, y, z)
    return { x = x + 0.0, y = y + 0.0, z = (z or 0.0) + 0.0 }
end

function Sim.Pit(def, index)
    local list = def.throwPoints or { def.throwPoint }
    local T = V(list[1].x, list[1].y, list[1].z)
    local S
    if def.stakePoint then
        S = V(def.stakePoint.x, def.stakePoint.y, def.stakePoint.z)
    else
        local dx, dy = Sim.DirFromHeading(def.heading or 0.0)
        local d = def.distance or 8.0
        S = V(T.x + dx * d, T.y + dy * d, T.z)
    end
    local heading = Sim.HeadingFromVec(S.x - T.x, S.y - T.y)

    local zones = {}
    for i, z in ipairs(Config.Score.zones or {}) do
        zones[i] = { distance = tonumber(z.distance) or 0.0, points = tonumber(z.points) or 0, label = z.label or 'PROCHE' }
    end
    table.sort(zones, function(a, b) return a.distance < b.distance end)
    if def.nearRadius and #zones > 0 then zones[#zones].distance = def.nearRadius + 0.0 end

    local spots = {}
    for i, p in ipairs(list) do
        spots[i] = { T = V(p.x, p.y, p.z), heading = Sim.HeadingFromVec(S.x - p.x, S.y - p.y) }
    end

    local c = def.coords or (def.npc and def.npc.coords) or list[1]
    return {
        spots = spots,
        index = index,
        id = tostring(def.id or ('pit' .. index)),
        label = def.label or ('Terrain ' .. index),
        T = T,
        S = S,
        heading = heading,
        stakeHeading = def.heading or heading,
        coords = V(c.x, c.y, c.z),
        npc = def.npc,
        stakeHeight = def.stakeHeight or Config.Stake.height,
        stakeRadius = Config.Stake.radius,
        maxPlayers = math.max(1, math.floor(def.maxPlayers or Config.MaxPlayers)),
        rounds = math.max(1, math.floor(def.rounds or Config.Rounds)),
        throwsPerRound = math.max(1, math.floor(def.throwsPerRound or Config.ThrowsPerRound)),
        zones = zones,
    }
end

function Sim.Spot(pit, round)
    local n = #pit.spots
    local i = ((math.max(1, math.floor(tonumber(round) or 1)) - 1) % n) + 1
    return pit.spots[i]
end

local Outline = nil

local function GetOutline()
    if Outline then return Outline end
    local s = Config.Shoe
    local R, leg, inset = s.radius, s.leg, s.inset
    local pts = { { R - inset, -leg } }
    local n = 14
    for i = 0, n do
        local a = math.pi * i / n
        pts[#pts + 1] = { R * cos(a), R * sin(a) }
    end
    pts[#pts + 1] = { -R + inset, -leg }
    Outline = pts
    return pts
end

local function DistSeg(px, py, ax, ay, bx, by)
    local vx, vy = bx - ax, by - ay
    local len2 = vx * vx + vy * vy
    local t = 0.0
    if len2 > 0 then t = Sim.Clamp(((px - ax) * vx + (py - ay) * vy) / len2, 0.0, 1.0) end
    local cx, cy = ax + vx * t - px, ay + vy * t - py
    return sqrt(cx * cx + cy * cy)
end

local function DistToSteel(lx, ly)
    local pts = GetOutline()
    local best = math.huge
    for i = 1, #pts - 1 do
        local d = DistSeg(lx, ly, pts[i][1], pts[i][2], pts[i + 1][1], pts[i + 1][2])
        if d < best then best = d end
    end
    return best
end

local function DistToHeelLine(lx, ly)
    local pts = GetOutline()
    local a, b = pts[1], pts[#pts]
    return DistSeg(lx, ly, a[1], a[2], b[1], b[2])
end

local function InsideShoe(lx, ly)
    local pts = GetOutline()
    local inside = false
    local j = #pts
    for i = 1, #pts do
        local xi, yi, xj, yj = pts[i][1], pts[i][2], pts[j][1], pts[j][2]
        if ((yi > ly) ~= (yj > ly)) and (lx < (xj - xi) * (ly - yi) / (yj - yi) + xi) then
            inside = not inside
        end
        j = i
    end
    return inside
end

local function ToLocal(px, py, cx, cy, psi)
    local dx, dy = px - cx, py - cy
    local fx, fy = cos(psi), sin(psi)
    local rx, ry = sin(psi), -cos(psi)
    return dx * rx + dy * ry, dx * fx + dy * fy
end

local function StakeTouch(pit)
    return Config.Shoe.steel + pit.stakeRadius
end

local function Ringer(pit, lx, ly)
    return InsideShoe(lx, ly)
        and DistToSteel(lx, ly) >= StakeTouch(pit) - 0.001
        and DistToHeelLine(lx, ly) > pit.stakeRadius
end

function Sim.FlightPos(th, t)
    return th.o.x + th.v.x * t,
        th.o.y + th.v.y * t,
        th.o.z + th.v.z * t - 0.5 * th.g * t * t
end

function Sim.FlightPsi(th, t)
    return th.psi0 + th.spin * t
end

local function Gauss(rnd)
    local u1 = math.max(rnd(), 1e-9)
    local u2 = rnd()
    return sqrt(-2.0 * math.log(u1)) * cos(TAU * u2)
end

local function PushOut(pit, cx, cy, psi, nx, ny)
    local touch = StakeTouch(pit)
    for _ = 1, 200 do
        local lx, ly = ToLocal(pit.S.x, pit.S.y, cx, cy, psi)
        if DistToSteel(lx, ly) >= touch then break end
        cx, cy = cx + nx * 0.002, cy + ny * 0.002
    end
    return cx, cy
end

function Sim.Simulate(pit, power, aim, round)
    local rnd = math.random
    local P = Config.Physics
    local g = Gravity()

    local spot = Sim.Spot(pit, round)
    local heading = spot.heading - Sim.Clamp(aim, -1.0, 1.0) * Config.Aim.maxAngle
    heading = heading + Gauss(rnd) * Config.Accuracy.aimNoiseDeg
    local p = Sim.Clamp(Sim.Clamp(power, 0.0, 1.0) + Gauss(rnd) * Config.Accuracy.powerNoise, 0.0, 1.0)

    local dx, dy = Sim.DirFromHeading(heading)
    local vh = Config.ThrowForceMin + p * (Config.ThrowForce - Config.ThrowForceMin)
    local apex = Config.ThrowHeight * (0.85 + 0.3 * p)
    local vz = sqrt(2.0 * g * apex)

    local o = V(spot.T.x + dx * P.releaseForward, spot.T.y + dy * P.releaseForward, spot.T.z + P.releaseHeight)
    local zRest = pit.S.z + P.restHeight
    local tLand = (vz + sqrt(vz * vz + 2.0 * g * math.max(0.0, o.z - zRest))) / g

    local spin = rad(P.spinMin + rnd() * (P.spinMax - P.spinMin))
    if rnd() < 0.5 then spin = -spin end
    local th = {
        o = o,
        v = V(dx * vh, dy * vh, vz),
        g = g,
        psi0 = rnd() * TAU,
        spin = spin,
    }

    local touch = StakeTouch(pit)
    local stakeTop = pit.S.z + pit.stakeHeight
    local S = pit.S

    local event
    local dt = 1.0 / 240.0
    local below = false
    local prev = nil
    local t = dt
    while t < tLand do
        local x, y, z = Sim.FlightPos(th, t)
        if z <= stakeTop then
            local psi = Sim.FlightPsi(th, t)
            local lx, ly = ToLocal(S.x, S.y, x, y, psi)
            if not below and Ringer(pit, lx, ly) then
                event = { kind = 'ringer', t = t, x = x, y = y, psi = psi }
                break
            end
            if DistToSteel(lx, ly) < touch then
                if prev and InsideShoe(lx, ly) then
                    event = { kind = 'ringer', t = prev.t, x = prev.x, y = prev.y, psi = prev.psi }
                else
                    event = { kind = 'hit', t = t, x = x, y = y, z = z, psi = psi }
                end
                break
            end
            below = true
            prev = { t = t, x = x, y = y, psi = psi }
        end
        t = t + dt
    end

    local after, final, kind
    if event and event.kind == 'ringer' then
        th.tEnd = event.t
        local fx, fy, fz = Sim.FlightPos(th, event.t)
        final = V(event.x, event.y, zRest)
        final.psi = event.psi
        after = { kind = 'drop', from = V(fx, fy, fz), psiFrom = event.psi, ms = 220 }
        kind = 'ringer'
    elseif event and event.kind == 'hit' then
        th.tEnd = event.t
        local nx, ny = event.x - S.x, event.y - S.y
        local len = sqrt(nx * nx + ny * ny)
        if len < 0.001 then nx, ny, len = -dx, -dy, 1.0 end
        nx, ny = nx / len, ny / len
        local cx, cy = PushOut(pit, event.x, event.y, event.psi, nx, ny)
        local psi = event.psi
        if rnd() < P.leanerChance then
            kind = 'leaner'
        else
            local a = (rnd() - 0.5) * rad(80.0)
            local bx, by = nx * cos(a) - ny * sin(a), nx * sin(a) + ny * cos(a)
            local extra = vh * P.bounce * (0.3 + rnd() * 0.9)
            psi = psi + (rnd() - 0.5) * 1.5
            cx, cy = cx + bx * extra, cy + by * extra
            cx, cy = PushOut(pit, cx, cy, psi, bx, by)
            kind = 'rest'
        end
        final = V(cx, cy, zRest)
        final.psi = psi
        after = { kind = 'bounce', from = V(event.x, event.y, event.z), psiFrom = event.psi, ms = 450 }
    else
        th.tEnd = tLand
        local lx0, ly0 = Sim.FlightPos(th, tLand)
        local psiL = Sim.FlightPsi(th, tLand)
        local D = math.max(0.0, vh * P.slide * (1.0 + (rnd() * 2.0 - 1.0) * P.slideRandom))
        local turn = th.spin * 0.12
        local n = math.max(1, math.ceil(D / 0.004))
        local cx, cy, psi = lx0, ly0, psiL
        kind = 'rest'
        local sx0, sy0 = ToLocal(S.x, S.y, lx0, ly0, psiL)
        if DistToSteel(sx0, sy0) < touch then
            local nx, ny = lx0 - S.x, ly0 - S.y
            local len = sqrt(nx * nx + ny * ny)
            if len < 0.001 then nx, ny, len = -dx, -dy, 1.0 end
            cx, cy = PushOut(pit, lx0, ly0, psiL, nx / len, ny / len)
            kind = 'leaner'
            n = 0
        end
        for i = 1, n do
            local f = i / n
            local nx, ny = lx0 + dx * D * f, ly0 + dy * D * f
            local npsi = psiL + turn * f
            local sx, sy = ToLocal(S.x, S.y, nx, ny, npsi)
            if DistToSteel(sx, sy) < touch then
                kind = InsideShoe(sx, sy) and 'ringer' or 'leaner'
                break
            end
            cx, cy, psi = nx, ny, npsi
        end
        final = V(cx, cy, zRest)
        final.psi = psi
        local slideMs = math.floor(Sim.Clamp(D / math.max(vh * 0.5, 0.1), 0.15, 0.9) * 1000)
        after = { kind = 'slide', from = V(lx0, ly0, zRest), psiFrom = psiL, ms = slideMs }
    end

    local sx, sy = ToLocal(S.x, S.y, final.x, final.y, final.psi)
    local gap = math.max(0.0, DistToSteel(sx, sy) - touch)
    if kind == 'ringer' and not (InsideShoe(sx, sy) and DistToHeelLine(sx, sy) > pit.stakeRadius) then
        kind = 'leaner'
    end
    if kind == 'rest' and gap < 0.004 then kind = 'leaner' end

    local result
    if kind == 'ringer' then
        result = { kind = 'ringer', points = Config.Score.ringer, label = 'FER ACCROCHÉ !' }
    elseif kind == 'leaner' then
        result = { kind = 'leaner', points = Config.Score.leaner, label = 'CONTRE LE PIQUET !' }
    else
        result = { kind = 'miss', points = 0, label = 'TROP LOIN' }
        for _, z in ipairs(pit.zones) do
            if gap <= z.distance then
                result = { kind = 'zone', points = z.points, label = z.label }
                break
            end
        end
    end
    result.gap = math.floor(gap * 100 + 0.5) / 100

    th.after = after
    th.final = final
    th.result = result
    th.totalMs = math.floor((th.tEnd * 1000) + after.ms)
    return th
end
