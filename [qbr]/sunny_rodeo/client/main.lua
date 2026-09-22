local QBCore = exports['qbr-core']

local Ride = nil            -- état du tour en cours
local Busy = false          -- demande de départ en cours
local BoardOpen = false
local Cam, CamPos, CamEntity = nil, nil, nil
local CamHeading, CamZ = 0.0, 0.0   -- cap et hauteur lissés de la caméra
local Leftover = {}         -- buffles à supprimer
local DeskPed, DeskZone, DeskBlip = nil, nil, nil

local DIRS = { 'up', 'down', 'left', 'right' }

-- OUTILS -------------------------------------------------------------------------
local function Notify(text, success)
    if success then
        TriggerEvent('QBCore:Notify', 9, text, 5000, 0, 'hud_textures', 'check', 'COLOR_WHITE')
    else
        TriggerEvent('QBCore:Notify', 9, text, 5000, 0, 'mp_lobby_textures', 'cross', 'COLOR_WHITE')
    end
end

-- Appelle une native qui peut ne pas exister ; nil si elle échoue.
local function Try(fn, ...)
    if type(fn) ~= 'function' then return nil end
    local ok, result = pcall(fn, ...)
    if ok then return result end
    return nil
end

-- Appelle une native RedM par son NOM si elle existe, sinon par son HASH (une native absente sous son nom
-- échouerait sinon en silence). wantResult = récupère la valeur de retour quand on passe par le hash.
local function NativeCall(name, hash, wantResult, ...)
    local ok, fn = pcall(function() return _G[name] end)
    if ok and type(fn) == 'function' then
        local done, res = pcall(fn, ...)
        if done then return res end
        return nil
    end
    local args = { ... }
    if wantResult then
        args[#args + 1] = Citizen.ReturnResultAnyway()
        args[#args + 1] = Citizen.ResultAsInteger()
    end
    local done, res = pcall(Citizen.InvokeNative, hash, table.unpack(args))
    if done then return res end
    return nil
end

-- Le ped est-il en selle ? (IsPedOnMount, et GetMount comme 2e avis)
local function OnMount(ped, horse)
    local r = NativeCall('IsPedOnMount', 0x460BC76A0E10655E, true, ped)
    if r == true or r == 1 then return true end
    if horse then
        local m = NativeCall('GetMount', 0xE7E11B8DCBED1058, true, ped)
        return tonumber(m) == horse
    end
    return false
end

local function Lerp(a, b, t) return a + (b - a) * t end
local function Clamp(v, lo, hi) return math.max(lo, math.min(hi, v)) end

local function LoadModel(hash, timeoutMs)
    RequestModel(hash)
    local limit = GetGameTimer() + (timeoutMs or 5000)
    while not HasModelLoaded(hash) and GetGameTimer() < limit do Wait(50) end
    return HasModelLoaded(hash)
end

-- Premier modèle de la liste qui existe dans le jeu.
local function FirstValidModel(list)
    for _, name in ipairs(list) do
        local hash = joaat(name)
        if IsModelInCdimage(hash) then return hash, name end
    end
end

local function Send(action, data)
    SendNUIMessage({ action = action, data = data })
end

local function GroundAt(x, y, hint)
    local found, z = GetGroundZFor_3dCoord(x, y, hint + 3.0, false)
    if found then return z end
    return hint
end

-- CAMERA ---------------------------------------------------------------------------
-- Position voulue de la caméra : calculée avec le CAP et la HAUTEUR lissés (CamHeading / CamZ), pas avec
-- l'orientation instantanée de l'animal. Ainsi ni les sauts, ni les cabrages, ni les pivotements ne la secouent.
local function CamWanted(e)
    local c = Config.Camera
    local h = math.rad(CamHeading)
    return vector3(
        e.x + math.cos(h) * c.side + math.sin(h) * c.back,
        e.y + math.sin(h) * c.side - math.cos(h) * c.back,
        CamZ + c.height)
end

local function StartCamera(entity)
    if not Config.Camera.enabled then return end
    local c = Config.Camera
    CamEntity = entity
    local e = GetEntityCoords(entity)
    CamHeading, CamZ = GetEntityHeading(entity), e.z
    CamPos = CamWanted(e)
    Cam = CreateCam('DEFAULT_SCRIPTED_CAMERA', true)
    SetCamCoord(Cam, CamPos.x, CamPos.y, CamPos.z)
    SetCamFov(Cam, c.fov)
    SetCamActive(Cam, true)
    RenderScriptCams(true, true, 700, true, true)
end

local function UpdateCamera(dt)
    if not Cam or not CamEntity or not DoesEntityExist(CamEntity) then return end
    local c = Config.Camera
    local e = GetEntityCoords(CamEntity)
    -- cap et hauteur rattrapent l'animal en douceur
    local diff = ((GetEntityHeading(CamEntity) - CamHeading + 180.0) % 360.0) - 180.0
    CamHeading = CamHeading + diff * Clamp(dt * (c.turnFollow or 1.5), 0.0, 1.0)
    CamZ = CamZ + (e.z - CamZ) * Clamp(dt * (c.zFollow or 1.5), 0.0, 1.0)
    local want = CamWanted(e)
    CamPos = CamPos + (want - CamPos) * Clamp(dt * c.follow, 0.0, 1.0)
    SetCamCoord(Cam, CamPos.x, CamPos.y, CamPos.z)
    PointCamAtCoord(Cam, e.x, e.y, CamZ + c.lookHeight)
end

local function StopCamera()
    if not Cam then return end
    RenderScriptCams(false, true, 800, true, true)
    DestroyCam(Cam, false)
    Cam, CamPos, CamEntity = nil, nil, nil
end

-- BUFFLE ---------------------------------------------------------------------------
-- Supprime l'entité pour de bon : prend le contrôle réseau, fondu, puis suppression (avec un 2e essai).
local function Despawn(entity)
    if not DoesEntityExist(entity) then return end
    if not NetworkHasControlOfEntity(entity) then
        NetworkRequestControlOfEntity(entity)
        local limit = GetGameTimer() + 1000
        while DoesEntityExist(entity) and not NetworkHasControlOfEntity(entity) and GetGameTimer() < limit do Wait(0) end
    end
    local fade = tonumber(Config.Buffalo.fadeMs) or 0
    if fade > 0 then
        local t0 = GetGameTimer()
        while DoesEntityExist(entity) and GetGameTimer() - t0 < fade do
            Try(SetEntityAlpha, entity, math.max(0, math.floor(255 * (1.0 - (GetGameTimer() - t0) / fade))), false)
            Wait(0)
        end
    end
    for _ = 1, 3 do
        if not DoesEntityExist(entity) then break end
        SetEntityAsMissionEntity(entity, true, true)
        DeleteEntity(entity)
        Wait(100)
    end
end

local function DeleteLater(entity, delay)
    Leftover[entity] = true
    SetTimeout(delay, function()
        CreateThread(function()
            Despawn(entity)
            Leftover[entity] = nil
        end)
    end)
end

local function SpawnBuffalo()
    local hash, name = FirstValidModel(Config.Buffalo.models)
    if not hash then
        return nil, 'Aucun modèle de buffle valide (Config.Buffalo.models).'
    end
    if not LoadModel(hash, 6000) then
        return nil, ('Le modèle %s n\'a pas pu être chargé.'):format(name)
    end

    local c = Config.Arena.center
    local z = c.z
    for _ = 1, 15 do
        RequestCollisionAtCoord(c.x, c.y, c.z)
        local found, gz = GetGroundZFor_3dCoord(c.x, c.y, c.z + 20.0, false)
        if found then z = gz break end
        Wait(100)
    end

    local ped = CreatePed(hash, c.x, c.y, z, Config.Arena.heading, true, true, false, false)
    if not ped or ped == 0 or not DoesEntityExist(ped) then
        SetModelAsNoLongerNeeded(hash)
        return nil, 'Le buffle n\'a pas pu apparaître.'
    end
    Citizen.InvokeNative(0x283978A15512B2FE, ped, true) -- SetRandomOutfitVariation : sans ça le ped reste invisible
    SetEntityAsMissionEntity(ped, true, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    Try(SetPedFleeAttributes, ped, 0, false)
    Try(SetPedCanRagdoll, ped, false)
    Try(function() SetNetworkIdCanMigrate(NetworkGetNetworkIdFromEntity(ped), false) end)
    SetModelAsNoLongerNeeded(hash)
    return ped, nil, z, name
end

local function ReleaseBuffalo(buffalo)
    if not DoesEntityExist(buffalo) then return end
    FreezeEntityPosition(buffalo, false)
    ClearPedTasks(buffalo)
    SetEntityInvincible(buffalo, true)
    Try(TaskWanderStandard, buffalo, 10.0, 10)
    DeleteLater(buffalo, math.max(0, (tonumber(Config.Buffalo.cleanupMs) or 0) - (tonumber(Config.Buffalo.fadeMs) or 0)))
end

-- MONTE (en selle, animation de base du jeu) ---------------------------------------------
-- Met le joueur en selle. true = il est bien sur le cheval ; sinon on retombe sur le mode « attaché + pose ».
-- Plusieurs méthodes essayées dans l'ordre ; chaque essai est écrit dans la console F8 (utile si ça échoue).
local function MountPlayer(state)
    local ped, horse = state.ped, state.buffalo
    local seat = Config.Mount.seat or -1

    local function wait(ms)
        local limit = GetGameTimer() + ms
        while GetGameTimer() < limit and not OnMount(ped, horse) do Wait(50) end
        return OnMount(ped, horse)
    end

    local attempts = {
        { 'SetPedOntoMount(..., true)',  function() NativeCall('SetPedOntoMount', 0x028F76B6E78246EB, false, ped, horse, seat, true) end, 1200 },
        { 'SetPedOntoMount(..., false)', function() NativeCall('SetPedOntoMount', 0x028F76B6E78246EB, false, ped, horse, seat, false) end, 1200 },
        -- le cavalier monte « à pied » ; le délai court force le placement en selle
        { 'TaskMountAnimal',             function() NativeCall('TaskMountAnimal', 0x92DB0739813C5186, false, ped, horse, 1500, seat, 2.0, 1, 0, 0) end, 4500 },
    }
    for i, a in ipairs(attempts) do
        a[2]()
        local ok = wait(a[3])
        print(('[sunny_rodeo] monte, essai %d (%s) -> %s'):format(i, a[1], ok and 'OK' or 'échec'))
        if ok then return true end
    end
    ClearPedTasksImmediately(ped)
    return false
end

-- Descente de selle sans chute : tâche de descente du jeu, sinon on force.
local function ForceDismount(state)
    local ped, horse = state.ped, state.buffalo
    if not OnMount(ped, horse) then return end
    NativeCall('TaskDismountAnimal', 0x48E92D3DDE23C23A, false, ped, 0, 0, 0, 0, 0)
    local limit = GetGameTimer() + 1800
    while GetGameTimer() < limit and OnMount(ped, horse) do Wait(50) end
    if OnMount(ped, horse) then
        ClearPedTasksImmediately(ped)
        Wait(100)
    end
end

-- SIEGE (mode de secours : attaché + pose) ------------------------------------------
local function SeatBone(buffalo)
    local b = Config.Seat.bone
    if type(b) == 'string' then
        local idx = Try(GetEntityBoneIndexByName, buffalo, b)
        return (idx and idx ~= -1) and idx or 0
    end
    return tonumber(b) or 0
end

local function AttachSeat(state, lean)
    local s = Config.Seat
    AttachEntityToEntity(state.ped, state.buffalo, state.bone,
        s.offset.x, s.offset.y, s.offset.z,
        s.rotation.x, s.rotation.y + (lean or 0.0), s.rotation.z,
        false, false, false, true, 2, true)
end

local function PlayPose(ped, dict, name)
    RequestAnimDict(dict)
    local limit = GetGameTimer() + 1000
    while not HasAnimDictLoaded(dict) and GetGameTimer() < limit do Wait(0) end
    if not HasAnimDictLoaded(dict) then return false end
    TaskPlayAnim(ped, dict, name, 4.0, -4.0, -1, 1, 0, false, false, false)
    return true
end

local function ApplyPose(state)
    for _, anim in ipairs(Config.Seat.anims or {}) do
        if PlayPose(state.ped, anim.dict, anim.name) then return true end
    end
    return false
end

-- DIFFICULTE -----------------------------------------------------------------------
local function Difficulty(sec)
    local R = Config.Ride
    local p = Clamp(sec / R.RampSeconds, 0.0, 1.0)
    local len = math.min(R.SeqMax, R.SeqStart + math.floor(sec / R.SeqEvery))
    local window = Lerp(R.BaseStart, R.BaseMin, p) + len * Lerp(R.PerArrowStart, R.PerArrowMin, p)
    local gap = Lerp(R.GapStart, R.GapMin, p)
    return len, math.floor(window), math.floor(gap), p
end

-- CAPTURE (cheval sauvage) ---------------------------------------------------------------------
-- Une fois le joueur en selle, le cheval est marqué « sauvage » : le jeu joue alors SON animation de cheval sauvage
-- qu'on monte (cabrage, ruades, il s'agite tout seul). On ne lui donne aucun ordre pendant ce temps (Config.Mount.wild).
local function HorseSpeed(horse)
    return tonumber(Try(GetEntitySpeed, horse)) or 0.0
end

local function TamingState(horse)
    return NativeCall('_GET_HORSE_TAMING_STATE', 0x454AD4DA6C41B5BD, true, horse)
end

local function Agitate(state)
    NativeCall('_HORSE_AGITATE', 0xBAE08F00021BFFB2, false, state.buffalo, false)
end

local function StartWild(state)
    local horse = state.buffalo
    NativeCall('_SET_ANIMAL_IS_WILD', 0xAEB97D84CDF3C00B, false, horse, true)
    NativeCall('SET_MIN_TIME_BEFORE_HORSE_BUCKING', 0x506CE71FB6E8CF5E, false, horse, 0)
    Try(SetBlockingOfNonTemporaryEvents, horse, false)         -- sinon le cheval ignore ce qui le fait réagir
    Try(SetPedCanBeKnockedOffVehicle, state.ped, 1)            -- 1 = jamais : le cheval ne jette pas seul le cavalier
    Agitate(state)
    state.wild, state.wildWas = true, true
    state.wildSlow, state.wildTries = 0.0, 0
    state.wildAt = GetGameTimer()
    state.wildLog = { state.wildAt + 2000, state.wildAt + 6000 }
    print('[sunny_rodeo] capture : cheval marqué sauvage (le jeu joue son animation de cheval sauvage)')
end

-- Arrête la capture (fin du tour, ou plan B) : le cheval redevient calme, le cavalier peut de nouveau être jeté.
local function StopWild(state)
    state.wild = false
    if not state.wildWas then return end
    if state.buffalo and DoesEntityExist(state.buffalo) then
        NativeCall('_SET_ANIMAL_IS_WILD', 0xAEB97D84CDF3C00B, false, state.buffalo, false)
        Try(SetBlockingOfNonTemporaryEvents, state.buffalo, true)
    end
    Try(SetPedCanBeKnockedOffVehicle, state.ped, 0)
end

-- MOUVEMENT DU BUFFLE -----------------------------------------------------------------
-- Cage invisible : polygone convexe (Config.Arena.cage.points). Chaque côté a une normale tournée vers
-- l'intérieur ; un point est dans la cage s'il est à au moins `margin` de chaque côté.
local function Cage()
    local c = Config.Arena.cage
    local pts = c and c.points
    if not pts or #pts < 3 then return nil end
    local n, area, cx, cy = #pts, 0.0, 0.0, 0.0
    local minx, maxx, miny, maxy = math.huge, -math.huge, math.huge, -math.huge
    for i = 1, n do
        local a, b = pts[i], pts[i % n + 1]
        area = area + (a.x * b.y - b.x * a.y)
        cx, cy = cx + a.x, cy + a.y
        minx, maxx = math.min(minx, a.x), math.max(maxx, a.x)
        miny, maxy = math.min(miny, a.y), math.max(maxy, a.y)
    end
    local sign = area >= 0 and 1.0 or -1.0 -- sens de rotation des points : la normale intérieure en dépend
    local edges = {}
    for i = 1, n do
        local a, b = pts[i], pts[i % n + 1]
        local ex, ey = b.x - a.x, b.y - a.y
        local len = math.sqrt(ex * ex + ey * ey)
        if len > 0.001 then
            edges[#edges + 1] = { ax = a.x, ay = a.y, nx = -ey / len * sign, ny = ex / len * sign }
        end
    end
    return {
        edges = edges, pts = pts, margin = c.margin or 0.8,
        cx = cx / n, cy = cy / n, minx = minx, maxx = maxx, miny = miny, maxy = maxy,
    }
end

-- Repousse (x, y) à l'intérieur : à au moins `margin` de chaque côté. Renvoie x, y, et true si le point a bougé.
local function CagePush(g, x, y, margin)
    local pushed = false
    for _ = 1, 4 do
        local moved = false
        for _, e in ipairs(g.edges) do
            local d = (x - e.ax) * e.nx + (y - e.ay) * e.ny
            if d < margin then
                x, y = x + e.nx * (margin - d), y + e.ny * (margin - d)
                moved = true
            end
        end
        if not moved then break end
        pushed = true
    end
    return x, y, pushed
end

-- Ramène l'animal dans la cage s'il en sort (il glisse le long du bord). true = il a touché le bord.
local function Confine(state)
    local g = Cage()
    if not g then return false end
    local e = state.buffalo
    local pos = GetEntityCoords(e)
    local nx, ny, pushed = CagePush(g, pos.x, pos.y, g.margin)
    if pushed then SetEntityCoordsNoOffset(e, nx, ny, pos.z, false, false, false) end
    return pushed
end

-- Destination tirée au hasard, à l'intérieur avec une marge de plus, et pas trop près de l'animal.
local function PickTarget(state)
    local g = Cage()
    local pos = GetEntityCoords(state.buffalo)
    if not g then
        local c = Config.Arena.center
        return c.x, c.y
    end
    local bestX, bestY
    for _ = 1, 25 do
        local x = g.minx + math.random() * (g.maxx - g.minx)
        local y = g.miny + math.random() * (g.maxy - g.miny)
        local _, _, outside = CagePush(g, x, y, g.margin + 1.0)
        if not outside then
            bestX, bestY = x, y
            if #(vector2(x, y) - vector2(pos.x, pos.y)) > 4.5 then break end
        end
    end
    return bestX or g.cx, bestY or g.cy
end

-- Le cheval frôle-t-il un bord (1 m avant le mur) ? Sert à lui donner une autre destination AVANT qu'il ne bute.
local function NearWall(pos)
    local g = Cage()
    if not g then return false end
    local _, _, close = CagePush(g, pos.x, pos.y, g.margin + 1.0)
    return close
end

-- Capture : le cheval va où son animation l'emmène. Près d'un bord de la cage, on le fait PIVOTER vers l'intérieur
-- avant qu'il touche : sinon la cage le repousse à chaque image et il reste collé au mur, quasi immobile.
-- Renvoie true si le cheval est près d'un bord (à moins de Config.Wild.steerRange de sa limite).
local function SteerWild(state, dt)
    local g = Cage()
    if not g then return false end
    local e = state.buffalo
    local pos = GetEntityCoords(e)
    local speed = HorseSpeed(e)
    -- plus il va vite, plus tôt il doit commencer à tourner
    local range = math.max(tonumber(Config.Wild.steerRange) or 4.0, speed * 0.9 + 1.5)
    local nearest, nd
    for _, ed in ipairs(g.edges) do
        local d = (pos.x - ed.ax) * ed.nx + (pos.y - ed.ay) * ed.ny - g.margin -- distance à la limite (négatif = dépassée)
        if not nd or d < nd then nd, nearest = d, ed end
    end
    if not nearest or nd > range then return false end

    local cur = GetEntityHeading(e)
    local h = math.rad(cur)
    -- > 0 : le cheval regarde vers l'intérieur ; <= 0 : vers le mur (ou le longe)
    local facing = -math.sin(h) * nearest.nx + math.cos(h) * nearest.ny
    if facing > 0.35 then return true end

    local want = math.deg(math.atan(-(g.cx - pos.x), g.cy - pos.y))          -- cap (GTA) vers le centre de l'enclos
    local diff = ((want - cur + 180.0) % 360.0) - 180.0
    local urgency = 1.0 - Clamp(nd / range, 0.0, 1.0)                        -- 0 loin du mur, 1 collé
    -- vitesse de pivotement : au moins steerRate, et assez vite pour avoir fini de tourner AVANT de toucher le mur
    local tHit = math.max(0.15, nd / math.max(0.5, speed * -facing))
    local rate = Clamp(math.max((tonumber(Config.Wild.steerRate) or 140.0) * (0.4 + 0.6 * urgency), math.abs(diff) / tHit * 1.3), 0.0, 420.0)
    SetEntityHeading(e, (cur + Clamp(diff, -rate * dt, rate * dt)) % 360.0)
    return true
end

-- Cheval coincé contre une barrière (immobile près d'un bord) : on le décolle de 1,5 m vers le centre, face au centre.
local function UnstickWild(state)
    local g = Cage()
    if not g then return end
    local e = state.buffalo
    local pos = GetEntityCoords(e)
    local dx, dy = g.cx - pos.x, g.cy - pos.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len < 0.1 then return end
    SetEntityCoordsNoOffset(e, pos.x + dx / len * 1.5, pos.y + dy / len * 1.5, pos.z, false, false, false)
    SetEntityHeading(e, math.deg(math.atan(-dx, dy)) % 360.0)
    Agitate(state)
    print('[sunny_rodeo] capture : cheval coincé contre un bord, on le décolle')
end

local function DriveBuffalo(state, p)
    local x, y = PickTarget(state)
    state.tx, state.ty = x, y
    local z = GroundAt(x, y, state.groundZ)
    local speed = Lerp(Config.Bucking.speedStart, Config.Bucking.speedMax, p)
    if state.mounted and Config.Mount.driveWith == 'rider' then
        -- le cavalier reçoit l'ordre, le cheval qu'il monte suit
        Try(TaskGoToCoordAnyMeans, state.ped, x, y, z, speed, 0, false, 0, 0.0)
    else
        TaskGoStraightToCoord(state.buffalo, x, y, z, speed, 8000, 0.0, 0.5)
    end
    Try(SetPedDesiredMoveBlendRatio, state.buffalo, speed)
end

local function Hop(state, mult)
    -- en selle, un saut forcé par-dessus l'animation du jeu donne un rendu saccadé : pas de saut
    if state.mounted or not DoesEntityExist(state.buffalo) then return end
    local v = GetEntityVelocity(state.buffalo)
    SetEntityVelocity(state.buffalo, v.x, v.y, Config.Bucking.hopPower * (mult or 1.0))
end

-- MOUVEMENTS DE CHEVAL SAUVAGE (cabrage, ruades, pirouette) -----------------------------------
local function WildGap(p)
    local W = Config.Wild
    return Lerp(W.gapStart, W.gapMin, p) * (0.7 + math.random() * 0.6)
end

local function PickWildMove()
    local total = 0
    for _, m in pairs(Config.Wild.moves) do total = total + (m.weight or 0) end
    if total <= 0 then return nil end
    local roll = math.random() * total
    for name, m in pairs(Config.Wild.moves) do
        roll = roll - (m.weight or 0)
        if roll <= 0 and (m.weight or 0) > 0 then return name end
    end
end

-- Remet le buffle à plat (on ne touche plus à son inclinaison ensuite).
local function EndMove(state)
    local mv = state.move
    if not mv then return end
    state.move = nil
    -- on ne remet à plat que si on l'a incliné (jamais en selle : le jeu gère l'animation)
    if not state.mounted and Config.Wild.tilt and DoesEntityExist(state.buffalo) then
        SetEntityRotation(state.buffalo, 0.0, 0.0, GetEntityHeading(state.buffalo), 2, true)
    end
end

-- Lance un mouvement. force = remplace celui en cours (erreur du joueur).
local function StartMove(state, name, force)
    local W = Config.Wild
    local def = W.enabled and name and W.moves[name]
    if not def or state.wild then return false end -- en capture, c'est le jeu qui fait bucker le cheval
    if state.move and not force then return false end
    if state.move then EndMove(state) end
    if not DoesEntityExist(state.buffalo) then return false end

    local now = GetGameTimer()
    local _, _, _, p = Difficulty((now - state.startAt) / 1000.0)
    state.move = {
        def = def, startAt = now, cycle = -1,
        h0 = GetEntityHeading(state.buffalo),
        dir = math.random() < 0.5 and -1.0 or 1.0,
    }
    state.nextWild = now + def.ms + WildGap(p)
    -- cabrage / dérapage / etc. : action de cheval de BASE du jeu, jouée avec le joueur en selle
    local native = state.mounted and def.action
    if def.stop then
        ClearPedTasks(state.buffalo)
        if native then NativeCall('TaskHorseAction', 0xA09CFD29100F06C3, false, state.buffalo, def.action, 0, 0)
        else Try(TaskStandStill, state.buffalo, def.ms) end
        state.nextMove = now + def.ms + 250 -- pas de nouvelle destination pendant l'arrêt
    elseif native then
        NativeCall('TaskHorseAction', 0xA09CFD29100F06C3, false, state.buffalo, def.action, 0, 0)
    end
    state.move.native = native
    return true
end

-- Appelée à chaque image : incline / fait pivoter le buffle selon l'avancement du mouvement.
local function UpdateMove(state, now)
    local mv = state.move
    if not mv then return end
    if not DoesEntityExist(state.buffalo) then state.move = nil return end
    local m = mv.def
    local t = Clamp((now - mv.startAt) / m.ms, 0.0, 1.0)
    if t >= 1.0 then return EndMove(state) end

    local cycles = math.max(1, m.repeats or 1)
    local cycle = math.min(cycles - 1, math.floor(t * cycles))
    local frac = t * cycles - cycle
    local env = math.sin(math.pi * Clamp(frac, 0.0, 1.0)) ^ 0.7
    if cycle ~= mv.cycle then
        mv.cycle = cycle
        -- pas de saut par-dessus une action native (le cabrage du jeu a sa propre animation)
        if not mv.native then Hop(state, m.hop or 1.0) end
    end

    -- En selle, le jeu anime tout (cabrage, dérapage) : on ne force rien.
    -- Hors selle : pivotement forcé ; inclinaison (pitch / roll) seulement si Config.Wild.tilt (souvent saccadé).
    local tilt = (not state.mounted) and Config.Wild.tilt
    local turning = (m.turn or 0.0) ~= 0.0 and not mv.native
    local heading
    if turning then
        local s = t * t * (3.0 - 2.0 * t)
        heading = (mv.h0 + m.turn * mv.dir * s) % 360.0
    end

    if tilt then
        local pitch = (m.pitch or 0.0) * env
        local roll = (m.roll or 0.0) * env * ((cycle % 2 == 0) and 1.0 or -1.0) * mv.dir
        SetEntityRotation(state.buffalo, pitch, roll, heading or GetEntityHeading(state.buffalo), 2, true)
    elseif turning then
        SetEntityHeading(state.buffalo, heading)
    end
end

-- INTERFACE DU TOUR -----------------------------------------------------------------
-- Temps RESTANT de la manche = durée fixe moins le temps écoulé et les pénalités des erreurs (jamais négatif).
local function LeftMs(state, now)
    return math.max(0, Config.Ride.MaxSeconds * 1000 - ((now or GetGameTimer()) - state.startAt) - state.penalty)
end

local function PushState(state, feedback, penaltyMs)
    local now = GetGameTimer()
    Send('state', {
        left = LeftMs(state, now),
        grip = state.grip,
        score = state.score,
        fb = feedback,
        pen = penaltyMs,
    })
    state.lastUi = now
end

local function NewChallenge(state, elapsedMs)
    local len, window, _, _ = Difficulty(elapsedMs / 1000.0)
    local seq = {}
    for i = 1, len do seq[i] = DIRS[math.random(1, 4)] end
    state.nextId = state.nextId + 1
    local now = GetGameTimer()
    state.challenge = { id = state.nextId, startedAt = now, deadline = now + window, window = window }
    -- le buffle se cabre avant chaque séquence
    state.push = (math.random() < 0.5 and -1 or 1) * Config.Lean.failPush * 0.5
    local list = Config.Wild.onChallenge
    if not (list and #list > 0 and StartMove(state, list[math.random(1, #list)])) then
        Hop(state, 1.3)
    end
    Send('challenge', { id = state.nextId, seq = seq, window = window })
end

local function ResolveChallenge(state, ok, info)
    local R = Config.Ride
    local now = GetGameTimer()
    local ch = state.challenge
    if not ch then return end
    state.challenge = nil
    local _, _, gap = Difficulty((now - state.startAt) / 1000.0)
    state.nextAt = now + gap

    local fb, pen
    if ok then
        local fast = info and info < ch.window * 0.5
        state.grip = Clamp(state.grip + R.GripGain + (fast and R.GripFastGain or 0), 0.0, R.GripStart)
        state.score = state.score + 1
        fb = fast and 'fast' or 'ok'
    else
        state.grip = state.grip - (info == 'timeout' and R.GripTimeout or R.GripWrong)
        state.push = (state.push >= 0 and 1 or -1) * Config.Lean.failPush
        if state.wild then Agitate(state) -- capture : le cheval s'énerve
        elseif not StartMove(state, Config.Wild.onMistake, true) then Hop(state, 1.7) end
        fb = info == 'timeout' and 'timeout' or 'wrong'
        -- une erreur RETIRE du temps au chrono (borné à ce qu'il reste)
        pen = math.min(info == 'timeout' and R.TimeoutPenaltyMs or R.FailPenaltyMs, LeftMs(state, now))
        state.penalty = state.penalty + pen
        state.mistakes = state.mistakes + 1
    end
    PushState(state, fb, pen)
end

-- FIN DE TOUR ------------------------------------------------------------------------
local function Cleanup(state, immediate)
    if not state or state.cleaned then return end
    state.cleaned = true
    SetNuiFocus(false, false)
    Send('hideAll')
    StopCamera()

    local ped = PlayerPedId()
    StopWild(state) -- remet le cheval calme et le cavalier « jetable » comme avant
    DetachEntity(ped, true, true)
    -- encore en selle (erreur, arrêt de la ressource...) : on descend avant de supprimer le cheval
    if OnMount(ped, state.buffalo) then ClearPedTasksImmediately(ped) end
    if state.buffalo and DoesEntityExist(state.buffalo) then
        if immediate then DeleteEntity(state.buffalo)
        elseif not state.released then ReleaseBuffalo(state.buffalo) end
    end
    if IsScreenFadedOut() or IsScreenFadingOut() then DoScreenFadeIn(400) end
    if state.protect and not immediate then
        SetTimeout(Config.Fall.protectMs, function() SetEntityInvincible(PlayerPedId(), false) end)
    else
        SetEntityInvincible(ped, false)
    end
    Ride = nil
end

-- Joueur en selle : chute = le cheval jette son cavalier (action de base 2), sinon descente normale.
local function DismountMounted(state, fall)
    local ped, horse = state.ped, state.buffalo
    if state.reason == 'dead' or not DoesEntityExist(horse) then return end
    local side = state.push >= 0 and 1.0 or -1.0
    StopWild(state) -- fin de la capture AVANT de jeter / faire descendre le cavalier

    if fall then
        state.protect = true
        NativeCall('TaskHorseAction', 0xA09CFD29100F06C3, false, horse, 2, 0, 0)
        local limit = GetGameTimer() + 2200
        while GetGameTimer() < limit and OnMount(ped, horse) do Wait(50) end
        if OnMount(ped, horse) then
            ClearPedTasksImmediately(ped)
            Wait(0)
        end
        -- si le jeu ne l'a pas mis à terre, on le fait tomber comme dans le mode de secours
        if not Try(IsPedRagdoll, ped) then
            SetPedToRagdoll(ped, Config.Fall.ragdollMs, Config.Fall.ragdollMs, 0, false, false, false)
            local h = math.rad(GetEntityHeading(horse))
            local power = Config.Fall.throwSpeed
            SetEntityVelocity(ped, math.cos(h) * side * power, math.sin(h) * side * power, power * 0.6)
        end
        ReleaseBuffalo(horse)
        state.released = true
    else
        ForceDismount(state)
        ReleaseBuffalo(horse)
        state.released = true
        CamEntity = ped
    end
end

local function Dismount(state)
    local ped = state.ped
    local reason = state.reason
    -- chute quand la prise lâche, et aussi à la fin du chrono (Config.Fall.onTimeUp) ; « lâcher prise » volontaire = descente calme
    local fall = reason == 'fall' or reason == 'dead' or (reason == 'max' and Config.Fall.onTimeUp ~= false)
    if state.mounted then return DismountMounted(state, fall) end
    DetachEntity(ped, true, true)
    ClearPedTasksImmediately(ped)
    if reason == 'dead' or not DoesEntityExist(state.buffalo) then return end

    local side = state.push >= 0 and 1.0 or -1.0
    ReleaseBuffalo(state.buffalo)
    state.released = true
    -- après une chute la caméra reste sur le buffle, sinon elle suit le joueur
    if not fall then CamEntity = ped end
    if fall then
        state.protect = true
        Wait(0)
        SetPedToRagdoll(ped, Config.Fall.ragdollMs, Config.Fall.ragdollMs, 0, false, false, false)
        local h = math.rad(GetEntityHeading(state.buffalo))
        -- vecteur latéral du buffle (à droite = +1)
        local rx, ry = math.cos(h), math.sin(h)
        local power = Config.Fall.throwSpeed
        SetEntityVelocity(ped, rx * side * power, ry * side * power, power * 0.6)
    else
        local p = GetOffsetFromEntityInWorldCoords(state.buffalo, 1.8, -0.6, 0.0)
        SetEntityCoords(ped, p.x, p.y, p.z, false, false, false, false)
    end
end

local function ShowResult(state)
    local ms = state.ms
    local payload = { token = state.token, ms = ms, combos = state.score, reason = state.reason }

    local answered, response = false, nil
    QBCore:TriggerCallback('sunny_rodeo:server:Finish', function(res)
        answered, response = true, res
    end, payload)
    local limit = GetGameTimer() + 8000
    while not answered and GetGameTimer() < limit do Wait(50) end

    state.resultOpen = true
    Send('result', {
        server = response or { ok = false, error = 'Pas de réponse du serveur.' },
        reason = state.reason,
        ms = ms,
        combos = state.score,
        penalty = state.penalty,
        mistakes = state.mistakes,
    })
    local deadline = GetGameTimer() + 20000
    local last = GetGameTimer()
    while state.resultOpen and GetGameTimer() < deadline and not state.cleaned do
        Wait(0)
        local now = GetGameTimer()
        UpdateCamera(math.min(0.1, (now - last) / 1000.0))
        last = now
    end
end

-- TOUR ---------------------------------------------------------------------------------
local function RunRide(session)
    local R = Config.Ride
    local ped = PlayerPedId()
    local state = {
        token = session.token, ped = ped,
        grip = R.GripStart, score = 0,
        challenge = nil, nextId = 0, nextAt = 0, startAt = 0, lastUi = 0,
        lean = 0.0, push = 0.0, ended = false, reason = nil, ms = 0,
        quit = false, resultOpen = false, cleaned = false,
        move = nil, nextMove = 0, nextWild = 0, nextBounce = 0,
        penalty = 0, mistakes = 0,
    }
    Ride = state

    DoScreenFadeOut(500)
    while not IsScreenFadedOut() do Wait(0) end

    local buffalo, err, groundZ, animalName = SpawnBuffalo()
    if not buffalo then
        TriggerServerEvent('sunny_rodeo:server:Cancel', session.token)
        Cleanup(state, true)
        Notify(err, false)
        return
    end
    state.buffalo, state.groundZ = buffalo, groundZ
    state.horse = animalName ~= nil and animalName:find('horse', 1, true) ~= nil
    state.bone = SeatBone(buffalo)
    Confine(state) -- si le point d'apparition est hors de la cage, on le ramène dedans

    SetEntityInvincible(ped, true)
    local bp = GetEntityCoords(buffalo)
    SetEntityCoords(ped, bp.x, bp.y, bp.z + 1.5, false, false, false, false)
    Wait(500) -- le cheval doit être bien posé, et NON gelé, pour qu'on puisse le monter
    -- avec un cheval : vraiment en selle (animation de monte de base) ; sinon, ou si ça échoue : attaché + pose
    if Config.Mount.native and state.horse then
        state.mounted = MountPlayer(state)
    end
    if not state.mounted then
        AttachSeat(state, 0.0)
        ApplyPose(state)
    end
    FreezeEntityPosition(buffalo, true) -- immobile pendant le compte à rebours
    print(('[sunny_rodeo] %s, mode de monte : %s'):format(tostring(animalName), state.mounted and 'EN SELLE (natif)' or 'attaché + pose'))
    StartCamera(buffalo)
    SetNuiFocus(true, false)
    Send('rideStart', {
        max = R.MaxSeconds, arena = Config.Arena.name,
        sound = Config.UI.Sound, volume = Config.UI.Volume,
        failPenalty = R.FailPenaltyMs, timeoutPenalty = R.TimeoutPenaltyMs,
    })
    DoScreenFadeIn(700)

    for i = Config.Countdown, 1, -1 do
        Send('countdown', i)
        Wait(1000)
    end
    Send('countdown', 0)
    FreezeEntityPosition(buffalo, false)

    local function End(reason)
        if state.ended then return end
        state.ended = true
        state.reason = reason
        state.ms = math.min(R.MaxSeconds * 1000, GetGameTimer() - state.startAt)
    end

    state.startAt = GetGameTimer()
    -- capture : le cheval devient « sauvage » et le jeu joue son animation de cheval sauvage qu'on monte
    if state.mounted and Config.Mount.wild then StartWild(state) end
    state.nextAt = state.startAt + R.FirstChallengeMs
    local nextHop, lastFrame = state.startAt + 1500, state.startAt
    state.nextMove = 0
    state.nextWild = state.startAt + 3000

    while not state.ended do
        Wait(0)
        local now = GetGameTimer()
        local dt = math.min(0.1, (now - lastFrame) / 1000.0)
        lastFrame = now
        local elapsed = now - state.startAt
        local sec = elapsed / 1000.0

        if state.cleaned then break end
        if not DoesEntityExist(buffalo) or IsEntityDead(buffalo) then End('error') break end
        if IsEntityDead(ped) then End('dead') break end
        if state.quit then End('quit') break end
        if LeftMs(state, now) <= 0 then End('max') break end

        local _, _, _, p = Difficulty(sec)

        -- déplacement : nouvelle destination régulièrement, retour au centre si le buffle sort de l'arène
        -- cage invisible : l'animal ne peut pas sortir ; quand il touche un bord, il choisit une autre destination
        -- (pendant un mouvement qui l'arrête, il ne reçoit pas de nouvelle destination)
        -- Une nouvelle destination n'est donnée que si la précédente est atteinte, si le cheval frôle un bord,
        -- ou après un long délai : relancer l'ordre sans cesse fait redémarrer l'animation de course (« reboot »).
        local halted = state.move and state.move.def.stop
        local bounced = Confine(state)
        local pos = GetEntityCoords(buffalo)
        local arrived = state.tx ~= nil and #(vector2(pos.x, pos.y) - vector2(state.tx, state.ty)) < 2.0
        local nearWall = bounced or NearWall(pos)
        if (nearWall or arrived) and not halted and now >= state.nextBounce then
            state.nextMove = now
            state.nextBounce = now + 1200
        end
        if now >= state.nextMove and not state.wild then -- en capture, aucun ordre : c'est le jeu qui fait bouger le cheval
            DriveBuffalo(state, p)
            state.nextMove = now + math.random(4500, 7000)
        end

        -- capture : le cheval bouge-t-il vraiment ? Sinon on le relance une fois, puis on repasse sur les mouvements du script.
        if state.wild then
            for i = #state.wildLog, 1, -1 do
                if now >= state.wildLog[i] then
                    table.remove(state.wildLog, i)
                    print(('[sunny_rodeo] capture : vitesse %.1f m/s, état de domptage %s'):format(HorseSpeed(buffalo), tostring(TamingState(buffalo))))
                end
            end
            -- près d'un bord il ralentit normalement le temps de pivoter : on laisse deux fois plus de temps
            local atWall = SteerWild(state, dt)
            local slow = HorseSpeed(buffalo) < 0.6
            -- coincé contre un bord : on le décolle vite (avant de compter une panne)
            if atWall and slow then state.wallSlow = (state.wallSlow or 0.0) + dt * 1000 else state.wallSlow = 0.0 end
            if state.wallSlow > (Config.Wild.unstickMs or 1500) then
                state.wallSlow = 0.0
                UnstickWild(state)
            end
            if slow then state.wildSlow = state.wildSlow + dt * 1000 * (atWall and 0.4 or 1.0) else state.wildSlow = 0.0 end
            if state.wildSlow > (Config.Wild.stuckMs or 3500) then
                state.wildSlow = 0.0
                state.wildTries = state.wildTries + 1
                if state.wildTries == 1 then
                    print('[sunny_rodeo] capture : le cheval ne bouge pas, on le relance')
                    Agitate(state)
                else
                    print('[sunny_rodeo] capture : sans effet, retour aux mouvements du script (Config.Mount.wild = false pour ne plus essayer)')
                    StopWild(state)
                    state.nextMove = 0
                    state.nextWild = now + 500
                end
            end
        end

        -- mouvement spontané de cheval sauvage, de plus en plus fréquent
        if Config.Wild.enabled and not state.move and now >= state.nextWild then
            if not StartMove(state, PickWildMove()) then state.nextWild = now + 1500 end
        end
        UpdateMove(state, now)

        -- sauts spontanés (hors mouvement, qui a déjà les siens)
        if now >= nextHop then
            if not state.move then Hop(state, 0.6 + math.random() * 0.5) end
            nextHop = now + math.random(Config.Bucking.hopMin, Config.Bucking.hopMax)
        end

        -- en selle, le jeu anime le cavalier ; s'il n'est plus sur le cheval (jeté par le jeu), le tour est fini
        if state.mounted then
            if OnMount(ped, buffalo) then
                state.offSince = nil
                -- cavalier coincé à l'envers / en ragdoll sur le cheval (ex. après un choc contre une barrière) : c'est une chute
                local ragdoll = Try(IsPedRagdoll, ped)
                local flipped = Try(IsEntityUpsideDown, ped)
                if ragdoll == true or ragdoll == 1 or flipped == true or flipped == 1 then
                    state.flipSince = state.flipSince or now
                    if now - state.flipSince > (Config.Wild.riderFlipMs or 1000) then
                        print('[sunny_rodeo] cavalier à l\'envers / sans équilibre sur le cheval : chute')
                        End('fall') break
                    end
                else
                    state.flipSince = nil
                end
            else
                state.offSince = state.offSince or now
                if now - state.offSince > 700 then End('fall') break end
            end
        end

        -- inclinaison du cavalier (mode de secours « attaché ») : balancement + secousses
        if Config.Lean.enabled and not state.mounted then
            local instability = 1.0 - state.grip / R.GripStart
            local sway = math.sin(sec * 2.1) * (4.0 + instability * Config.Lean.swayMax)
            state.push = state.push * (1.0 - Clamp(dt * 2.2, 0.0, 1.0))
            local target = sway + state.push
            state.lean = state.lean + (target - state.lean) * Clamp(dt * 7.0, 0.0, 1.0)
            AttachSeat(state, state.lean)
        end

        UpdateCamera(dt)

        -- séquences de flèches
        if not state.challenge and now >= state.nextAt then
            NewChallenge(state, elapsed)
        elseif state.challenge and now > state.challenge.deadline + R.AnswerGraceMs then
            ResolveChallenge(state, false, 'timeout')
        end

        -- la prise s'use avec le temps
        state.grip = state.grip - (R.DrainBase + R.DrainPerMin * (sec / 60.0)) * dt
        if state.grip <= 0.0 then
            state.grip = 0.0
            PushState(state)
            End('fall')
            break
        end

        if now - state.lastUi >= 100 then PushState(state) end
    end

    if not state.reason then End('error') end
    EndMove(state)
    Send('rideEnd')
    Dismount(state)
    if not state.cleaned then ShowResult(state) end
    Cleanup(state, false)
end

local function StartRide()
    if Ride or Busy or BoardOpen then return end
    local ped = PlayerPedId()
    if IsEntityDead(ped) then return Notify('Tu ne peux pas monter dans cet état.', false) end
    if OnMount(ped) or Try(IsPedInAnyVehicle, ped, false) then
        return Notify('Descends de ta monture avant de monter sur le buffle.', false)
    end

    Busy = true
    QBCore:TriggerCallback('sunny_rodeo:server:Start', function(res)
        if not res or not res.ok then
            Busy = false
            return Notify(res and res.error or 'Pas de réponse du serveur.', false)
        end
        CreateThread(function()
            local ok, e = pcall(RunRide, res)
            if not ok then
                print(('[sunny_rodeo] erreur pendant le tour : %s'):format(tostring(e)))
                TriggerServerEvent('sunny_rodeo:server:Cancel', res.token)
                Cleanup(Ride, true)
                Ride = nil
                Notify('Le tour a été interrompu par une erreur.', false)
            end
            Busy = false
        end)
    end)
end

-- CLASSEMENT ---------------------------------------------------------------------------
local function CloseBoard()
    if not BoardOpen then return end
    BoardOpen = false
    SetNuiFocus(false, false)
    Send('hideAll')
end

local function OpenBoard()
    if Ride or Busy or BoardOpen then return end
    Busy = true
    QBCore:TriggerCallback('sunny_rodeo:server:Board', function(res)
        Busy = false
        if not res or not res.ok then
            return Notify(res and res.error or 'Pas de réponse du serveur.', false)
        end
        if BoardOpen or Ride then return end
        BoardOpen = true
        SetNuiFocus(true, true)
        Send('board', res)
    end, { sort = 'combo', period = 'all' })
end

-- NUI ------------------------------------------------------------------------------------
RegisterNUICallback('close', function(_, cb)
    cb('ok')
    if Ride then
        Ride.resultOpen = false
    else
        CloseBoard()
    end
end)

RegisterNUICallback('boardData', function(data, cb)
    if not BoardOpen then return cb({ ok = false }) end
    QBCore:TriggerCallback('sunny_rodeo:server:Board', function(res)
        cb(res or { ok = false, error = 'Pas de réponse du serveur.' })
    end, type(data) == 'table' and data or {})
end)

RegisterNUICallback('answer', function(data, cb)
    cb('ok')
    local state = Ride
    if not state or state.ended or not state.challenge or type(data) ~= 'table' then return end
    if data.id ~= state.challenge.id then return end
    if data.ok == true then
        ResolveChallenge(state, true, GetGameTimer() - state.challenge.startedAt)
    else
        ResolveChallenge(state, false, 'wrong')
    end
end)

RegisterNUICallback('quit', function(_, cb)
    cb('ok')
    if Ride and not Ride.ended then Ride.quit = true end
end)

-- MAITRE DU RODEO : personnage, zone ox_target, blip -------------------------------------------
local function SpawnDesk()
    if not Config.Desk.npc then return end
    local hash = FirstValidModel(Config.Desk.models)
    if not hash or not LoadModel(hash, 5000) then return end
    local d = Config.Desk.coords
    local ped = CreatePed(hash, d.x, d.y, d.z - 1.0, d.w, false, false, false, false)
    if not ped or ped == 0 then return end
    Citizen.InvokeNative(0x283978A15512B2FE, ped, true)
    SetEntityAsMissionEntity(ped, true, true)
    SetEntityInvincible(ped, true)
    SetBlockingOfNonTemporaryEvents(ped, true)
    Wait(300)
    FreezeEntityPosition(ped, true)
    SetModelAsNoLongerNeeded(hash)
    DeskPed = ped
end

local function DeleteDesk()
    if DeskPed and DoesEntityExist(DeskPed) then DeleteEntity(DeskPed) end
    DeskPed = nil
end

CreateThread(function()
    local d = Config.Desk.coords
    local pos = vector3(d.x, d.y, d.z)
    while true do
        local dist = #(GetEntityCoords(PlayerPedId()) - pos)
        if dist < 80.0 and not (DeskPed and DoesEntityExist(DeskPed)) then
            DeskPed = nil
            SpawnDesk()
        elseif dist > 110.0 and DeskPed then
            DeleteDesk()
        end
        Wait(2000)
    end
end)

local function AddDeskZone()
    local d = Config.Desk.coords
    local price = tonumber(Config.Price) or 0
    local rideLabel = price > 0 and ('Faire du rodéo (%s $)'):format(price) or 'Faire du rodéo (gratuit)'
    DeskZone = exports.ox_target:addSphereZone({
        name = 'sunny_rodeo_desk',
        coords = vector3(d.x, d.y, d.z + 0.3),
        radius = Config.Desk.radius,
        debug = Config.Debug,
        options = {
            {
                name = 'sunny_rodeo_ride',
                icon = 'fa-solid fa-hat-cowboy',
                label = rideLabel,
                distance = Config.Desk.distance,
                canInteract = function() return not Ride and not Busy end,
                onSelect = StartRide,
            },
            {
                name = 'sunny_rodeo_board',
                icon = 'fa-solid fa-trophy',
                label = 'Voir le classement du rodéo',
                distance = Config.Desk.distance,
                canInteract = function() return not Ride and not Busy end,
                onSelect = OpenBoard,
            },
        },
    })
end

local function SetupTarget()
    CreateThread(function()
        local waited = 0
        while GetResourceState('ox_target') ~= 'started' and waited < 15000 do
            Wait(500)
            waited = waited + 500
        end
        if GetResourceState('ox_target') ~= 'started' then
            print('[sunny_rodeo] ox_target n\'est pas démarré : le maître du rodéo est inutilisable (commande /rodeotop pour le classement).')
            return
        end
        Wait(500)
        local ok, err = pcall(AddDeskZone)
        if not ok then print(('[sunny_rodeo] ox_target : zone impossible (%s)'):format(tostring(err))) end
    end)
end

AddEventHandler('onClientResourceStart', function(resource)
    if resource == 'ox_target' then
        DeskZone = nil
        SetupTarget()
    end
end)
SetupTarget()

CreateThread(function()
    local b = Config.Blip
    if not b or not b.enabled then return end
    local d = Config.Desk.coords
    local sprite = type(b.sprite) == 'string' and joaat(b.sprite) or b.sprite
    DeskBlip = N_0x554d9d53f696d002(1664425300, vector3(d.x, d.y, d.z))
    SetBlipSprite(DeskBlip, sprite, 1)
    SetBlipScale(DeskBlip, b.scale or 0.2)
    Citizen.InvokeNative(0x9CB1A1623062F402, DeskBlip, CreateVarString(10, 'LITERAL_STRING', b.label or 'Rodéo'))
end)

-- COMMANDES -------------------------------------------------------------------------------
RegisterCommand('rodeotop', function() OpenBoard() end, false)

-- Donne la position actuelle à coller dans config.lua (Arena.center / Desk.coords).
RegisterCommand('rodeopos', function()
    local ped = PlayerPedId()
    local c = GetEntityCoords(ped)
    local text = ('vector4(%.2f, %.2f, %.2f, %.2f)'):format(c.x, c.y, c.z, GetEntityHeading(ped))
    print('[sunny_rodeo] ' .. text)
    TriggerEvent('chat:addMessage', { args = { 'Rodéo', text } })
    Notify('Position affichée dans le chat et la console F8.', true)
end, false)

-- Nombre saisi dans le chat (virgule ou point) ; nil si ce n'est pas un nombre.
local function Num(s)
    return tonumber((tostring(s or ''):gsub(',', '.'))) -- parenthèses : gsub renvoie 2 valeurs, tonumber prendrait la 2e comme base
end

-- Cage invisible : contour rouge pour la vérifier / la refaire en jeu.
--   /rodeocage         afficher / masquer le contour (rouge = les coins que tu as donnés, vert = limite réelle du centre de l'animal)
--   /rodeocage clear   effacer tous les coins
--   /rodeocage add     ajouter ta position comme coin (dans l'ordre, en faisant le tour)
local CageShow = false
local drawLine = rawget(_G, 'DrawLine') or function(...) Citizen.InvokeNative(0x2A32FAA57B937173, ...) end

CreateThread(function()
    while true do
        local g = CageShow and Cage()
        if g then
            local z = GetEntityCoords(PlayerPedId()).z
            local n = #g.pts
            for i = 1, n do
                local a, b = g.pts[i], g.pts[i % n + 1]
                for _, dz in ipairs({ -1.0, 0.0, 1.5 }) do
                    drawLine(a.x + 0.0, a.y + 0.0, z + dz, b.x + 0.0, b.y + 0.0, z + dz, 255, 40, 40, 255)
                end
                drawLine(a.x + 0.0, a.y + 0.0, z - 1.0, a.x + 0.0, a.y + 0.0, z + 1.5, 255, 40, 40, 255)
            end
            -- limite réelle du centre de l'animal (les coins rentrés de `margin`)
            local inner = {}
            for i = 1, n do
                local x, y = CagePush(g, g.pts[i].x, g.pts[i].y, g.margin)
                inner[i] = { x + 0.0, y + 0.0 }
            end
            for i = 1, n do
                local a, b = inner[i], inner[i % n + 1]
                drawLine(a[1], a[2], z, b[1], b[2], z, 40, 220, 40, 255)
            end
            Wait(0)
        else
            Wait(500)
        end
    end
end)

RegisterCommand('rodeocage', function(_, args)
    local cage = Config.Arena.cage
    local function report()
        local parts = {}
        for i, p in ipairs(cage.points) do parts[i] = ('vector2(%.4f, %.4f)'):format(p.x, p.y) end
        local text = 'points = { ' .. table.concat(parts, ', ') .. ' }'
        print('[sunny_rodeo] ' .. text)
        TriggerEvent('chat:addMessage', { args = { 'Rodéo', text } })
    end
    if args[1] == 'clear' then
        cage.points = {}
        CageShow = true
        TriggerEvent('chat:addMessage', { args = { 'Rodéo', 'Coins effacés. Va à chaque coin de l\'enclos, dans l\'ordre, et tape /rodeocage add (3 minimum).' } })
    elseif args[1] == 'add' then
        local c = GetEntityCoords(PlayerPedId())
        cage.points[#cage.points + 1] = vector2(c.x, c.y)
        CageShow = true
        report()
    else
        CageShow = not CageShow
        if CageShow and not Cage() then
            TriggerEvent('chat:addMessage', { args = { 'Rodéo', 'Aucune cage définie (3 coins minimum) : /rodeocage add à chaque coin.' } })
        end
    end
end, false)

-- Qui reçoit l'ordre de courir quand le joueur est en selle : /rodeodrive horse|rider (prend effet tout de suite)
RegisterCommand('rodeodrive', function(_, args)
    local mode = args[1]
    if mode == 'horse' or mode == 'rider' then
        Config.Mount.driveWith = mode
        if Ride then Ride.nextMove = 0 end
    end
    TriggerEvent('chat:addMessage', { args = { 'Rodéo', ('driveWith = %s  (usage : /rodeodrive horse|rider)'):format(Config.Mount.driveWith) } })
end, false)

-- Capture (cheval sauvage, animation du jeu) : /rodeowild on|off  (prend effet tout de suite pendant un tour)
RegisterCommand('rodeowild', function(_, args)
    local mode = args[1]
    if mode == 'on' or mode == 'off' then
        Config.Mount.wild = mode == 'on'
        if Ride and Ride.mounted and not Ride.ended then
            if Config.Mount.wild then StartWild(Ride) else StopWild(Ride); Ride.nextMove = 0 end
        end
    end
    TriggerEvent('chat:addMessage', { args = { 'Rodéo', ('capture (animation sauvage du jeu) = %s  (usage : /rodeowild on|off)'):format(Config.Mount.wild and 'on' or 'off') } })
end, false)

-- Réglage du siège en jeu (mode de secours attaché) : /rodeoseat x y z [rx ry rz]
RegisterCommand('rodeoseat', function(_, args)
    local n = {}
    for i = 1, 6 do n[i] = Num(args[i]) end
    if n[1] and n[2] and n[3] then
        Config.Seat.offset = vector3(n[1], n[2], n[3])
        if n[4] and n[5] and n[6] then Config.Seat.rotation = vector3(n[4], n[5], n[6]) end
        if Ride and Ride.buffalo then AttachSeat(Ride, Ride.lean) end
    end
    local o, r = Config.Seat.offset, Config.Seat.rotation
    local text = ('offset = vector3(%.2f, %.2f, %.2f), rotation = vector3(%.1f, %.1f, %.1f)'):format(o.x, o.y, o.z, r.x, r.y, r.z)
    print('[sunny_rodeo] ' .. text)
    TriggerEvent('chat:addMessage', { args = { 'Rodéo', text } })
end, false)

-- Test d'une animation de pose : /rodeopose <dict> <nom>
RegisterCommand('rodeopose', function(_, args)
    if not args[1] or not args[2] then
        return TriggerEvent('chat:addMessage', { args = { 'Rodéo', 'Usage : /rodeopose <dict> <nom> (pendant un tour)' } })
    end
    Config.Seat.anims = { { dict = args[1], name = args[2] } }
    if Ride and Ride.ped then
        local ok = ApplyPose(Ride)
        TriggerEvent('chat:addMessage', { args = { 'Rodéo', ok and 'Animation jouée.' or 'Animation introuvable.' } })
    end
end, false)

-- NETTOYAGE ---------------------------------------------------------------------------------
AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if BoardOpen then SetNuiFocus(false, false) end
    if Ride then Cleanup(Ride, true) end
    StopCamera()
    DeleteDesk()
    for entity in pairs(Leftover) do
        if DoesEntityExist(entity) then DeleteEntity(entity) end
    end
    if DeskBlip then pcall(RemoveBlip, DeskBlip) end
    if GetResourceState('ox_target') == 'started' and DeskZone then
        pcall(function() exports.ox_target:removeZone(DeskZone) end)
    end
end)
