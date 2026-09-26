-- ============================================================================
--  Sunny_train - Client : train
--  Mise en voie, conduite (avancer / freiner-reculer / régulateur), sifflet,
--  suppression.
--  Toutes les natives de train ci-dessous ont été vérifiées dans la base
--  RDR3 (alloc8or/rdr3-nativedb-data) : nom, hash et signature.
--  La boucle de conduite ne tourne à chaque frame QUE lorsque le joueur est
--  aux commandes ; sinon elle dort 500 ms.
-- ============================================================================

local Train = {
    entity = nil,
    netId = nil,
    maxSpeed = 20.0,
    speed = 0.0,         -- vitesse commandée signée (négative = marche arrière)
    cruise = false,      -- régulateur actif
    cruiseSpeed = 0.0,   -- vitesse maintenue par le régulateur
    action = 'idle',     -- dernière commande : forward, brake, reverse, cruise, coast, idle
    locked = false,      -- immobilisé (arrêt en gare, braquage)
    noFuel = false,      -- tender vide : le train ne peut pas avancer
}
Sunny.Train = Train

local drive = Config.Driving
local Utils = Sunny.Utils

local GAME_MAX_SPEED = 29.9 -- plafond moteur (_SET_TRAIN_MAX_SPEED : 30.0 max)

-- Natives de train RDR3 (vérifiées)
local N = {
    GET_NUM_CARS_FROM_TRAIN_CONFIG  = 0x635423D55CA84FC8, -- (Hash trainConfig) -> int
    GET_TRAIN_MODEL_FROM_CONFIG     = 0x8DF5F6A19F99F0D5, -- (Hash trainConfig, int carIndex) -> Hash
    IS_POSITION_VALID_FOR_TRAIN     = 0xF05DFAF1ADFEF2CD, -- (Hash config, x, y, z, BOOL direction, BOOL p5) -> BOOL
    CREATE_MISSION_TRAIN            = 0xC239DBD9A57D2A71, -- (Hash config, x, y, z, BOOL direction, BOOL passengers, BOOL p6, BOOL conductor) -> Vehicle
    HAS_TRAIN_LOADED                = 0xBD3C4A2ED509205E, -- (Vehicle train) -> BOOL
    SET_TRAIN_SPEED                 = 0xDFBA6BBFF7CCAFBB, -- (Vehicle train, float speed)
    SET_TRAIN_CRUISE_SPEED          = 0x01021EB2E96B793C, -- (Vehicle train, float speed)
    SET_TRAIN_MAX_SPEED             = 0x9F29999DFDF2AEB8, -- (Vehicle train, float speed) max 30.0
    SET_TRAIN_REVERSE_ENABLED       = 0x06A09A6E0C6D2A84, -- (Vehicle train, BOOL enable)
    SET_TRAIN_STOPS_FOR_STATIONS    = 0x4182C037AA1F0091, -- (Vehicle train, BOOL toggle)
    TRIGGER_TRAIN_WHISTLE           = 0xCFE122EC635CC2B2, -- (Vehicle train, char* sequence, BOOL mute, BOOL p3)
    GET_TRAIN_CARRIAGE_TRAILER_NUM  = 0x60B7D1DCC312697D, -- (Vehicle train) -> int
    GET_TRAIN_CARRIAGE              = 0xD0FB093A4CDB932C, -- (Vehicle train, int trailerNumber) -> Vehicle
    DELETE_MISSION_TRAIN            = 0x0D3630FB07E8B570, -- (Vehicle* train)
}
Train.Natives = N

--- Applique une vitesse signée (négative = marche arrière), plafonnée par le jeu.
local lastMax = nil -- évite de renvoyer _SET_TRAIN_MAX_SPEED à vitesse stable
local function applySpeed(speed)
    if not Train.entity then return end
    local mag = math.min(math.abs(speed), GAME_MAX_SPEED)
    local signed = speed < 0 and -mag or mag
    local max = math.min(mag + 0.1, GAME_MAX_SPEED)
    if max ~= lastMax then
        lastMax = max
        Citizen.InvokeNative(N.SET_TRAIN_MAX_SPEED, Train.entity, max)
    end
    Citizen.InvokeNative(N.SET_TRAIN_CRUISE_SPEED, Train.entity, signed + 0.0)
    Citizen.InvokeNative(N.SET_TRAIN_SPEED, Train.entity, signed + 0.0)
end

function Train.Exists()
    return Train.entity ~= nil and DoesEntityExist(Train.entity)
end

function Train.GetSpeed()
    if not Train.Exists() then return 0.0 end
    return GetEntitySpeed(Train.entity)
end

function Train.IsDriver()
    return Train.Exists() and GetPedInVehicleSeat(Train.entity, -1) == PlayerPedId()
end

--- Joue une séquence de sifflet (ACKNOWLEDGE, CROSSING, MOVING, NEXT_STATION...).
function Train.Whistle(sequence)
    if not sequence or not Train.Exists() then return end
    Citizen.InvokeNative(N.TRIGGER_TRAIN_WHISTLE, Train.entity, sequence, false, false)
end

--- Précharge les modèles de wagons d'une configuration de train.
local function loadTrainModels(hash)
    local count = Citizen.InvokeNative(N.GET_NUM_CARS_FROM_TRAIN_CONFIG, hash, Citizen.ResultAsInteger())
    if not count or count <= 0 then return nil end
    local models = {}
    for i = 0, count - 1 do
        local model = Citizen.InvokeNative(N.GET_TRAIN_MODEL_FROM_CONFIG, hash, i, Citizen.ResultAsInteger())
        if model and model ~= 0 and not models[model] then
            if not Sunny.LoadModel(model, 10000) then
                print(('^1[Sunny_train] Modèle de wagon introuvable : %s^7'):format(tostring(model)))
                for m in pairs(models) do SetModelAsNoLongerNeeded(m) end
                return nil
            end
            models[model] = true
        end
    end
    return models
end

--- Met un train en voie. Renvoie l'entité et son netId, ou nil.
---@param data table données renvoyées par le serveur (run:start)
function Train.Spawn(data)
    local hash = Utils.ResolveHash(data.model)
    local d = data.depot
    local direction = data.direction == true

    local models = loadTrainModels(hash)
    if not models then
        print(('^1[Sunny_train] Configuration de train invalide : %s^7'):format(tostring(data.model)))
        return nil
    end

    -- Le moteur replace les coordonnées sur la voie la plus proche.
    local valid = Citizen.InvokeNative(N.IS_POSITION_VALID_FOR_TRAIN, hash, d.x, d.y, d.z, direction, false, Citizen.ResultAsInteger())
    if valid ~= 1 then
        print(('^3[Sunny_train] Dépôt (%.1f, %.1f, %.1f) signalé invalide pour ce train, tentative quand même.^7'):format(d.x, d.y, d.z))
    end

    -- Aiguillages imposés par la ligne (avant la mise en voie).
    for _, j in ipairs(data.junctions or {}) do
        Sunny.Junctions.Apply(Utils.ResolveHash(j.track), j.index, j.enabled ~= false, false)
    end

    local entity = Citizen.InvokeNative(N.CREATE_MISSION_TRAIN, hash, d.x, d.y, d.z,
        direction, data.passengers == true, true, false, Citizen.ResultAsInteger())

    for model in pairs(models) do SetModelAsNoLongerNeeded(model) end
    if not entity or entity == 0 or not DoesEntityExist(entity) then return nil end

    local deadline = GetGameTimer() + (drive.loadTimeout or 6000)
    while Citizen.InvokeNative(N.HAS_TRAIN_LOADED, entity, Citizen.ResultAsInteger()) ~= 1 and GetGameTimer() < deadline do
        Wait(50)
    end

    SetEntityAsMissionEntity(entity, true, true)
    if not NetworkGetEntityIsNetworked(entity) then NetworkRegisterEntityAsNetworked(entity) end
    local netId = NetworkGetNetworkIdFromEntity(entity)
    SetNetworkIdExistsOnAllMachines(netId, true)
    Citizen.InvokeNative(N.SET_TRAIN_STOPS_FOR_STATIONS, entity, drive.trainStopsForStations == true)
    Citizen.InvokeNative(N.SET_TRAIN_REVERSE_ENABLED, entity, drive.allowReverse ~= false)

    Train.entity = entity
    Train.netId = netId
    Train.maxSpeed = math.min(data.maxSpeed or 20.0, GAME_MAX_SPEED)
    Train.speed = 0.0
    Train.cruise, Train.cruiseSpeed, Train.action = false, 0.0, 'idle'
    Train.locked = false
    Train.noFuel = false
    lastMax = nil
    applySpeed(0.0)

    if drive.teleportIntoCab then
        SetPedIntoVehicle(PlayerPedId(), entity, -1)
    end
    Train.StartLoop()
    return entity, netId
end

--- Supprime un train et tous ses wagons.
function Train.DeleteEntity(entity)
    if not entity or entity == 0 or not DoesEntityExist(entity) then return end
    SetEntityAsMissionEntity(entity, true, true)
    -- DELETE_MISSION_TRAIN retire la locomotive et ses wagons.
    Citizen.InvokeNative(N.DELETE_MISSION_TRAIN, Citizen.PointerValueIntInitialized(entity))
    if not DoesEntityExist(entity) then return end

    -- Repli : wagon par wagon (si le train n'est pas une « mission train » locale).
    local cars = Citizen.InvokeNative(N.GET_TRAIN_CARRIAGE_TRAILER_NUM, entity, Citizen.ResultAsInteger()) or 0
    for i = cars, 1, -1 do
        local car = Citizen.InvokeNative(N.GET_TRAIN_CARRIAGE, entity, i, Citizen.ResultAsInteger())
        if car and car ~= 0 and car ~= entity and DoesEntityExist(car) then
            SetEntityAsMissionEntity(car, true, true)
            DeleteEntity(car)
        end
    end
    DeleteEntity(entity)
end

--- Libère le train courant (supprimé après `delay` secondes).
function Train.Release(delay)
    local entity = Train.entity
    Train.entity, Train.netId = nil, nil
    Train.locked, Train.cruise = false, false
    Sunny.Junctions.Reset()
    if not entity then return end
    if (delay or 0) <= 0 then
        Train.DeleteEntity(entity)
        return
    end
    Citizen.InvokeNative(N.SET_TRAIN_SPEED, entity, 0.0)
    Citizen.InvokeNative(N.SET_TRAIN_CRUISE_SPEED, entity, 0.0)
    SetTimeout(delay * 1000, function()
        local ped = PlayerPedId()
        if DoesEntityExist(entity) and GetVehiclePedIsIn(ped, false) == entity then
            TaskLeaveVehicle(ped, entity, 0, 0)
            Wait(1500)
        end
        Train.DeleteEntity(entity)
    end)
end

function Train.Lock(state)
    Train.locked = state == true
end

local ACTION_LABELS = {
    forward = 'Traction',
    brake   = 'Freinage',
    reverse = 'Marche arrière',
    coast   = "Sur l'erre",
    idle    = "À l'arrêt",
}

--- Libellé de l'état de conduite (plaque de conduite, titre des prompts).
function Train.StateLabel()
    if Train.cruise then return 'Régulateur' end
    return ACTION_LABELS[Train.action] or ACTION_LABELS.idle
end

--- Sens de marche : 1 = avant, -1 = arrière.
function Train.MovingDirection()
    if Train.speed < -0.05 then return -1 end
    if Train.speed > 0.05 then return 1 end
    return Train.action == 'reverse' and -1 or 1
end

--- Active le régulateur à la vitesse actuelle (refusé à l'arrêt) ou le coupe.
function Train.SetCruise(state)
    state = state == true and math.abs(Train.speed) > (drive.stopSpeed or 0.9)
    Train.cruise = state
    Train.cruiseSpeed = state and Train.speed or 0.0
end

-- ----------------------------------------------------------------------------
--  Boucle de conduite
-- ----------------------------------------------------------------------------
local loopRunning = false
local stoppedSince = nil -- instant de l'arrêt, S maintenu (délai avant marche arrière)

--- Rapproche la vitesse de `target` d'au plus `rate * dt`.
local function approach(target, rate, dt)
    local delta = target - Train.speed
    local step = rate * dt
    if math.abs(delta) <= step then Train.speed = target
    else Train.speed = Train.speed + (delta > 0 and step or -step) end
end

--- Une des touches de la liste est-elle maintenue ? En cabine, le jeu peut
--- désactiver certains contrôles de déplacement : on lit aussi leur état désactivé.
local function anyPressed(keys)
    for _, key in ipairs(keys) do
        if IsControlPressed(0, key) or IsDisabledControlPressed(0, key) then return true end
    end
    return false
end

--- Commandes ponctuelles : régulateur, sifflet.
local function handleButtons()
    if IsControlJustPressed(0, drive.cruiseKey) then Train.SetCruise(not Train.cruise) end
    local w = drive.whistle
    if w and w.key and IsControlJustPressed(0, w.key) then Train.Whistle(w.manual) end
end

--- Vitesse de la frame selon les touches maintenues (W / S).
local function updateSpeed(dt, controls)
    if Train.locked or Train.noFuel then
        Train.cruise, stoppedSince = false, nil
        Train.action = math.abs(Train.speed) > 0.05 and 'brake' or 'idle'
        approach(0.0, drive.lockBraking or 4.5, dt)
        return
    end

    local forward = controls and anyPressed(drive.forwardKeys)
    local back = controls and anyPressed(drive.backKeys)
    local reverseMax = drive.allowReverse ~= false and math.min(drive.reverseMaxSpeed or 5.0, Train.maxSpeed) or 0.0

    if back then
        -- Freine ; une fois arrêté, S toujours maintenu, recule.
        Train.cruise = false
        if Train.speed > 0.05 or reverseMax <= 0 then
            stoppedSince = nil
            Train.action = 'brake'
            approach(0.0, drive.braking, dt)
        elseif Train.speed < -0.05 or GetGameTimer() - (stoppedSince or GetGameTimer()) >= (drive.reverseDelay or 0) then
            if Train.speed > -0.05 and Train.action ~= 'reverse' and drive.whistle then Train.Whistle(drive.whistle.onReverse) end
            Train.action = 'reverse'
            approach(-reverseMax, drive.acceleration, dt)
        else
            stoppedSince = stoppedSince or GetGameTimer()
            Train.action = 'brake'
            Train.speed = 0.0
        end
    elseif forward then
        stoppedSince = nil
        if Train.speed < -0.05 then
            Train.action = 'brake'
            approach(0.0, drive.braking, dt)
        else
            Train.action = 'forward'
            approach(Train.maxSpeed, drive.acceleration, dt)
            -- W avec le régulateur actif : la vitesse maintenue suit.
            if Train.cruise then Train.cruiseSpeed = Train.speed end
        end
    else
        stoppedSince = nil
        if Train.cruise then
            Train.action = 'cruise'
            approach(Train.cruiseSpeed, drive.acceleration, dt)
        else
            Train.action = math.abs(Train.speed) > 0.05 and 'coast' or 'idle'
            approach(0.0, drive.coasting or 0.25, dt)
        end
    end
end

local drivingPromptIds = { 'drive_forward', 'drive_back', 'drive_cruise', 'drive_whistle' }
local cruiseShown = nil
function Train.DrivingPrompts(active)
    local p = Sunny.Prompts
    if not p.list.drive_forward then
        p.Create('drive_forward', drive.forwardKeys[1], 'Avancer', false)
        p.Create('drive_back', drive.backKeys[1], 'Freiner / reculer', false, 'drive_forward')
        p.Create('drive_cruise', drive.cruiseKey, 'Régulateur', false, 'drive_forward')
        if drive.whistle and drive.whistle.key then
            p.Create('drive_whistle', drive.whistle.key, 'Sifflet', false, 'drive_forward')
        end
        p.Create('drive_park', drive.cabHoldKey, Sunny.L('prompt_park'), true, 'drive_forward')
    end
    p.ShareGroup('junction', 'drive_forward')
    if cruiseShown ~= Train.cruise then
        cruiseShown = Train.cruise
        p.SetText('drive_cruise', Train.cruise and 'Régulateur : couper' or 'Régulateur : maintenir la vitesse')
    end
    local controls = active and drive.mode == 'assisted'
    for _, id in ipairs(drivingPromptIds) do
        p.SetVisible(id, controls == true)
    end
    -- Remisage : voyage libre, train arrêté au dépôt ou au quai d'une gare.
    local Missions = Sunny.Missions
    local park = active and Missions.CanPark ~= nil and Missions.CanPark()
    p.SetVisible('drive_park', park == true)
    if park and p.Completed('drive_park') then
        CreateThread(Missions.Finish)
    end
    local junction = Sunny.Junctions.current
    local switch = active and junction and not junction.locked and not Sunny.Junctions.pending
    p.SetVisible('junction', switch == true)
    if active and (controls or switch) then
        local title = 'Conduite — ' .. Train.StateLabel()
        if switch then
            title = title .. ' — ' .. Sunny.L('junction_title', math.floor(junction.distance), Sunny.Junctions.Label(junction.enabled))
        end
        p.DisplayGroup('drive_forward', title)
    end
end

function Train.StartLoop()
    if loopRunning then return end
    loopRunning = true
    CreateThread(function()
        local lastTick = GetGameTimer()
        local lastStationCheck, lastJunctionScan = 0, 0
        while Train.entity do
            local now = GetGameTimer()
            local dt = math.min((now - lastTick) / 1000.0, 0.5)
            lastTick = now
            local sleep = 500

            if not DoesEntityExist(Train.entity) then
                Sunny.Missions.OnTrainLost()
                break
            end

            local driving = Train.IsDriver()
            if driving and drive.mode == 'assisted' then
                sleep = 0
                local controls = not Train.locked and not Sunny.UI.open and not IsPauseMenuActive()
                if controls then handleButtons() end
                updateSpeed(dt, controls)
                applySpeed(Train.speed)
            elseif Train.locked or Train.noFuel then
                Train.speed = 0.0
                applySpeed(0.0)
            end

            -- Aiguillages : recherche périodique, prompt par frame à l'approche.
            if driving then
                sleep = 0
                if now - lastJunctionScan >= Config.Junctions.scanInterval then
                    lastJunctionScan = now
                    Sunny.Junctions.Scan(Train.entity, Train.MovingDirection())
                end
                Train.DrivingPrompts(not Train.locked and not Sunny.UI.open and not IsPauseMenuActive())
                Sunny.Junctions.Frame(true)
            elseif Sunny.Junctions.current then
                Sunny.Junctions.Reset()
            end
            if not driving then Train.DrivingPrompts(false) end

            if now - lastStationCheck >= drive.stationCheckInterval then
                lastStationCheck = now
                Sunny.Missions.Tick()
            end
            Wait(sleep)
        end
        Train.DrivingPrompts(false)
        loopRunning = false
    end)
end

--- Train Sunny_train (liste publiée par le serveur) auquel appartient une
--- entité : locomotive ou n'importe quel wagon. Renvoie entry, locomotive.
function Train.FindInList(list, entity)
    if type(list) ~= 'table' or not entity or entity == 0 then return nil end
    for _, entry in ipairs(list) do
        if NetworkDoesNetworkIdExist(entry.netId) then
            local engine = NetworkGetEntityFromNetworkId(entry.netId)
            if engine ~= 0 and DoesEntityExist(engine) then
                if engine == entity then return entry, engine end
                local cars = Citizen.InvokeNative(N.GET_TRAIN_CARRIAGE_TRAILER_NUM, engine, Citizen.ResultAsInteger()) or 0
                for i = 1, cars do
                    if Citizen.InvokeNative(N.GET_TRAIN_CARRIAGE, engine, i, Citizen.ResultAsInteger()) == entity then
                        return entry, engine
                    end
                end
            end
        end
    end
    return nil
end

-- Admin : aucun train Sunny_train suivi près de lui → supprime le train le
-- plus proche, quel qu'il soit (train bloqué, fantôme...).
RegisterNetEvent('sunny_train:client:adminDespawnNearest', function()
    local pos = GetEntityCoords(PlayerPedId())
    local best, bestDist = nil, 80.0
    local ok, pool = pcall(GetGamePool, 'CVehicle')
    for _, veh in ipairs(ok and pool or {}) do
        -- IS_THIS_MODEL_A_TRAIN
        if Citizen.InvokeNative(0xFC08C8F8C1EDF174, GetEntityModel(veh), Citizen.ResultAsInteger()) == 1 then
            local d = #(pos - GetEntityCoords(veh))
            if d < bestDist then best, bestDist = veh, d end
        end
    end
    if not best then return Sunny.Notify('Aucun train à proximité.', 'error') end
    NetworkRequestControlOfEntity(best)
    local deadline = GetGameTimer() + 1500
    while not NetworkHasControlOfEntity(best) and GetGameTimer() < deadline do Wait(50) end
    if Train.entity == best then Train.Release(0) else Train.DeleteEntity(best) end
    Sunny.Notify('Train supprimé.', 'success')
end)

RegisterNetEvent('sunny_train:client:deleteTrain', function(netId, delay)
    if Train.netId == netId then
        Train.Release(delay)
        return
    end
    if NetworkDoesNetworkIdExist(netId) then
        local entity = NetworkGetEntityFromNetworkId(netId)
        SetTimeout((delay or 0) * 1000, function() Train.DeleteEntity(entity) end)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    if Train.entity then Train.DeleteEntity(Train.entity) end
end)
