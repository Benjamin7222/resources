local function Lerp(a, b, t) return a + (b - a) * t end

local function LerpAngle(a, b, t)
    local d = (b - a + math.pi) % (math.pi * 2) - math.pi
    return a + d * t
end

function HS.PlaceShoe(id, pitId, x, y, z, psi)
    if HS.Shoes[id] or HS.Animating[id] then return end
    local P = Config.Physics
    local gz = HS.Ground(x, y, z - P.restHeight) + P.restHeight + Config.Shoe.zOffset
    local obj = HS.CreateProp(Config.HorseshoeModel, x, y, gz)
    if obj then
        FreezeEntityPosition(obj, true)
        SetEntityCollision(obj, false, false)
        SetEntityCoordsNoOffset(obj, x, y, gz, false, false, false)
        local rx, ry, rz = HS.ShoeRotation(psi)
        SetEntityRotation(obj, rx, ry, rz, 2, true)
    end
    HS.Shoes[id] = { obj = obj, pit = pitId, x = x, y = y, z = gz, psi = psi }
end

function HS.RemoveShoe(id)
    local sh = HS.Shoes[id]
    if not sh then return end
    HS.DeleteProp(sh.obj)
    HS.Shoes[id] = nil
end

function HS.ClearPitShoes(pitId)
    for id, sh in pairs(HS.Shoes) do
        if sh.pit == pitId then HS.RemoveShoe(id) end
    end
end

function HS.AttachHandShoe(sid, pitId)
    local cur = HS.HandProps[sid]
    if cur and cur.obj and DoesEntityExist(cur.obj) then return end
    local player = GetPlayerFromServerId(sid)
    if not player or player == -1 then return end
    local ped = GetPlayerPed(player)
    if not ped or ped == 0 or not DoesEntityExist(ped) then return end
    local c = GetEntityCoords(ped)
    local obj = HS.CreateProp(Config.HorseshoeModel, c.x, c.y, c.z + 1.0)
    if not obj then return end
    SetEntityCollision(obj, false, false)
    local s = Config.Shoe
    AttachEntityToEntity(obj, ped, GetEntityBoneIndexByName(ped, s.handBone),
        s.handPos.x, s.handPos.y, s.handPos.z, s.handRot.x, s.handRot.y, s.handRot.z,
        false, false, false, false, 2, true, false, false)
    HS.HandProps[sid] = { obj = obj, pit = pitId }
end

function HS.TakeHandShoe(sid)
    local cur = HS.HandProps[sid]
    HS.HandProps[sid] = nil
    if not cur or not cur.obj or not DoesEntityExist(cur.obj) then return nil end
    DetachEntity(cur.obj, true, false)
    FreezeEntityPosition(cur.obj, true)
    SetEntityCollision(cur.obj, false, false)
    return cur.obj
end

function HS.RemoveHandShoe(sid)
    local cur = HS.HandProps[sid]
    HS.HandProps[sid] = nil
    if cur then HS.DeleteProp(cur.obj) end
end

function HS.ClearPitHands(pitId, except)
    for sid, cur in pairs(HS.HandProps) do
        if cur.pit == pitId and sid ~= except then HS.RemoveHandShoe(sid) end
    end
end

local ChosenAnim = nil

local function LoadAnim(a)
    if not a or not DoesAnimDictExist(a.dict) then return nil end
    RequestAnimDict(a.dict)
    local deadline = GetGameTimer() + 1500
    while not HasAnimDictLoaded(a.dict) and GetGameTimer() < deadline do Wait(10) end
    if not HasAnimDictLoaded(a.dict) then return nil end
    local dur = GetAnimDuration(a.dict, a.name) or 0.0
    if dur <= 0.05 then return nil end
    local rel = math.floor(dur * 1000 * (a.releaseAt or 0.45))
    return {
        dict = a.dict,
        name = a.name,
        durationMs = math.floor(dur * 1000),
        releaseMs = math.floor(Sim.Clamp(rel, Config.AnimReleaseMin, Config.AnimReleaseMax)),
    }
end

function HS.PickAnim()
    if ChosenAnim then return ChosenAnim end
    for _, a in ipairs(Config.Animations) do
        local anim = LoadAnim(a)
        if anim then
            ChosenAnim = anim
            return anim
        end
    end
    ChosenAnim = { releaseMs = 400, durationMs = 800 }
    return ChosenAnim
end

local DisabledKeys = {
    Config.Controls.throw, Config.Controls.left, Config.Controls.right,
    Config.Controls.left2, Config.Controls.right2, Config.Controls.quit,
    0x07CE1E61, 0xF84FA74F, 0x8FFC75D6,
}

local function Unfreeze()
    if HS.Frozen then
        FreezeEntityPosition(PlayerPedId(), false)
        HS.Frozen = false
    end
end

function HS.StopAim(token)
    if token and HS.Aiming ~= token then return end
    HS.Aiming = nil
    if not HS.Pending then Unfreeze() end
    HS.SendUI({ action = 'aim', show = false })
end

local function Fire(pitId, turnId, power, aim)
    local ped = PlayerPedId()
    local anim = HS.PickAnim()
    TriggerServerEvent('sunny_horseshoes:server:Throw', pitId, turnId, power, aim, anim.releaseMs)
    local pending = { pit = pitId, turnId = turnId, start = GetGameTimer(), releaseMs = anim.releaseMs }
    HS.Pending = pending
    if anim.dict then
        TaskPlayAnim(ped, anim.dict, anim.name, 4.0, -4.0, -1, 0, 0.0, false, 0, false, '', false)
    end
    CreateThread(function()
        local animWait = math.max(anim.durationMs or 0, anim.releaseMs + 600)
        Wait(animWait)
        if not HS.Aiming then Unfreeze() end
        Wait(math.max(0, 3500 - animWait))
        if HS.Pending == pending and not pending.echo then
            HS.Pending = nil
            if anim.dict then StopAnimTask(ped, anim.dict, anim.name, 1.0) end
            if HS.Recheck then HS.Recheck(pitId, true) end
        end
    end)
end

function HS.StartAim(pitId, turnId)
    if HS.Aiming then return end
    local pit = HS.Pits[pitId]
    if not pit then return end
    local token = { pit = pitId, turnId = turnId }
    HS.Aiming = token

    CreateThread(function()
        local ped = PlayerPedId()
        local me = HS.MyId()
        local function Valid()
            local st = HS.States[pitId]
            return HS.Aiming == token and st and st.status == 'playing' and st.turn == me
                and st.turnId == turnId and not st.busy
        end

        local st0 = HS.States[pitId]
        local spot = Sim.Spot(pit, st0 and st0.round)
        local T = spot.T
        local target = vector2(T.x, T.y)
        local function Gap()
            local c = GetEntityCoords(ped)
            return #(vector2(c.x, c.y) - target)
        end
        if Gap() > 0.5 then
            TaskGoStraightToCoord(ped, T.x, T.y, T.z, 1.0, 6000, spot.heading, 0.3, 0)
            local deadline = GetGameTimer() + 6500
            while Valid() and GetGameTimer() < deadline and Gap() > 0.45 do Wait(100) end
        end
        if not Valid() then return HS.StopAim(token) end
        ClearPedTasks(ped)
        pcall(SetCurrentPedWeapon, ped, GetHashKey('WEAPON_UNARMED'), true)
        if Gap() > 1.2 then SetEntityCoords(ped, T.x, T.y, T.z, false, false, false, false) end
        SetEntityHeading(ped, spot.heading)
        FreezeEntityPosition(ped, true)
        HS.Frozen = true
        HS.AttachHandShoe(me, pitId)
        HS.PickAnim()

        local C = Config.Controls
        local maxA = Config.Aim.maxAngle
        local cycle = math.max(200, Config.Power.cycleMs)
        local aimDeg, power, charging, chargeStart = 0.0, 0.0, false, 0
        local last, lastUi = GetGameTimer(), 0
        HS.SendUI({ action = 'aim', show = true })

        while Valid() do
            local now = GetGameTimer()
            local dt = (now - last) / 1000.0
            last = now
            for i = 1, #DisabledKeys do DisableControlAction(0, DisabledKeys[i], true) end

            if IsDisabledControlJustPressed(0, C.quit) then
                HS.LeaveGame()
                break
            end

            local l = IsDisabledControlPressed(0, C.left) or IsDisabledControlPressed(0, C.left2)
            local r = IsDisabledControlPressed(0, C.right) or IsDisabledControlPressed(0, C.right2)
            if l ~= r then
                aimDeg = Sim.Clamp(aimDeg + (r and 1 or -1) * Config.Aim.speed * dt, -maxA, maxA)
            end
            SetEntityHeading(ped, spot.heading - aimDeg)

            local pressed = IsDisabledControlPressed(0, C.throw)
            if pressed and not charging then
                charging = true
                chargeStart = now
            end
            if charging then
                local phase = ((now - chargeStart) % (2 * cycle)) / cycle
                power = phase <= 1.0 and phase or (2.0 - phase)
                if not pressed then
                    token.fired = true
                    HS.Aiming = nil
                    HS.SendUI({ action = 'power', power = power, aim = aimDeg / maxA, charging = false })
                    Fire(pitId, turnId, power, aimDeg / maxA)
                    break
                end
            end

            if now - lastUi > 40 then
                lastUi = now
                HS.SendUI({ action = 'power', power = power, aim = aimDeg / maxA, charging = charging })
            end
            Wait(0)
        end

        HS.SendUI({ action = 'aim', show = false })
        if not token.fired then HS.StopAim(token) end
    end)
end

local function Sound(kind, pit)
    local c = GetEntityCoords(PlayerPedId())
    if #(c - vector3(pit.S.x, pit.S.y, pit.S.z)) < 40.0 then
        HS.SendUI({ action = 'sound', kind = kind })
    end
end

function HS.PlayFlight(pitId, d)
    local pit = HS.Pits[pitId]
    if not pit then return end
    local mine = d.src == HS.MyId()
    local start
    local pending = HS.Pending
    if mine and pending and pending.pit == pitId and pending.turnId == d.turnId then
        pending.echo = true
        start = pending.start + d.releaseMs
    else
        start = GetGameTimer() + math.floor(d.releaseMs * 0.85)
    end
    HS.Animating[d.shoeId] = true

    local delay = start - GetGameTimer()
    if delay > 0 then Wait(delay) end

    local o, fin, a = d.o, d.final, d.after
    local P = Config.Physics
    local obj = HS.TakeHandShoe(d.src)
    local off = { x = 0.0, y = 0.0, z = 0.0 }
    if obj then
        local c = GetEntityCoords(obj)
        off = { x = c.x - o.x, y = c.y - o.y, z = c.z - o.z }
    else
        obj = HS.CreateProp(Config.HorseshoeModel, o.x, o.y, o.z)
        if obj then
            FreezeEntityPosition(obj, true)
            SetEntityCollision(obj, false, false)
        end
    end

    local gz = HS.Ground(fin.x, fin.y, fin.z - P.restHeight) + P.restHeight + Config.Shoe.zOffset
    local shift = gz - fin.z
    local blendT = math.max(0.05, d.tEnd * 0.35)
    local t0 = GetGameTimer()
    local touched = false

    while obj and DoesEntityExist(obj) do
        local t = (GetGameTimer() - t0) / 1000.0
        local x, y, z, psi, pitch, roll
        if t < d.tEnd then
            x, y, z = Sim.FlightPos(d, t)
            local k = math.max(0.0, 1.0 - t / blendT)
            x, y, z = x + off.x * k, y + off.y * k, z + off.z * k + shift * (t / d.tEnd)
            psi = Sim.FlightPsi(d, t)
            pitch, roll = math.sin(t * 7.0) * 20.0, math.cos(t * 5.0) * 10.0
        else
            if not touched then
                touched = true
                Sound(a.kind == 'slide' and 'thud' or 'clang', pit)
            end
            local u = ((t - d.tEnd) * 1000.0) / math.max(a.ms, 1)
            if u >= 1.0 then break end
            if a.kind == 'slide' then
                local e = 1.0 - (1.0 - u) * (1.0 - u)
                x, y, z = Lerp(a.from.x, fin.x, e), Lerp(a.from.y, fin.y, e), gz
                psi = LerpAngle(a.psiFrom, fin.psi, e)
            elseif a.kind == 'drop' then
                local e = u * u
                x, y, z = Lerp(a.from.x, fin.x, e), Lerp(a.from.y, fin.y, e), Lerp(a.from.z + shift, gz, e)
                psi = LerpAngle(a.psiFrom, fin.psi, u)
            else
                x, y = Lerp(a.from.x, fin.x, u), Lerp(a.from.y, fin.y, u)
                z = Lerp(a.from.z + shift, gz, u) + math.sin(u * math.pi) * 0.10
                psi = LerpAngle(a.psiFrom, fin.psi, u)
            end
            pitch, roll = 0.0, 0.0
        end
        SetEntityCoordsNoOffset(obj, x, y, z, false, false, false)
        local rx, ry, rz = HS.ShoeRotation(psi, pitch, roll)
        SetEntityRotation(obj, rx, ry, rz, 2, true)
        Wait(0)
    end

    if obj and DoesEntityExist(obj) then
        SetEntityCoordsNoOffset(obj, fin.x, fin.y, gz, false, false, false)
        local rx, ry, rz = HS.ShoeRotation(fin.psi)
        SetEntityRotation(obj, rx, ry, rz, 2, true)
    end
    if d.result.kind == 'ringer' then Sound('ring', pit) end

    HS.Animating[d.shoeId] = nil
    HS.Shoes[d.shoeId] = { obj = obj, pit = pitId, x = fin.x, y = fin.y, z = gz, psi = fin.psi }

    local st = HS.States[pitId]
    if not HS.Near[pitId] or not st or st.status == 'free' or st.gameId ~= d.gameId then
        HS.RemoveShoe(d.shoeId)
    end

    if mine and HS.Pending == pending then HS.Pending = nil end
    if HS.OnLanded then HS.OnLanded(pitId, d) end
end
