local state = 'idle'
local bottles = {}
local targetTops = {}
local nextBottle = 1
local targetOrder = {}
local waveStarted = 0
local waveMovement = {}
local shots, wasShooting, previousWeapon, previousAmmo = 0, false, nil, nil
local finalDeadline
local score, endTime = 0, 0
local session, zone
local standBlip
local generation = 0
local lastShot = -1000
local preparationPed

local function StopPreparation()
    if preparationPed then
        ClearPedTasks(preparationPed)
        preparationPed = nil
    end
end

local function Notify(message)
    exports['qbr-core']:Notify(9, message, 5000, 0, 'hud_textures', 'check', 'COLOR_WHITE')
end

local function ClearBottles()
    for _, entity in pairs(bottles) do
        if DoesEntityExist(entity) then
            SetEntityAsMissionEntity(entity, true, true)
            DeleteObject(entity)
        end
    end
    bottles = {}
    targetTops = {}
    waveMovement = {}
    SendNUIMessage({ action = 'targetArrows', targets = {} })
end

local function CloseUI()
    SendNUIMessage({ action = 'close' })
    SetNuiFocus(false, false)
    SetNuiFocusKeepInput(false)
end

local function Reset()
    StopPreparation()
    generation = generation + 1
    state = 'idle'
    session = nil
    nextBottle = 1
    finalDeadline = nil
    ClearBottles()
    CloseUI()
end

local function Cancel(message)
    if session then
        TriggerServerEvent('Sunny-tiro:server:Cancel', session)
    elseif state == 'waiting' then
        TriggerServerEvent('Sunny-tiro:server:CancelPending', generation)
    end
    Reset()
    if message then Notify(message) end
end

local function LoadModel(model, token)
    local hash = type(model) == 'number' and model or joaat(model)
    if not IsModelValid(hash) then return nil end
    RequestModel(hash)
    local timeout = GetGameTimer() + Config.ModelLoadTimeout
    while not HasModelLoaded(hash) do
        if token ~= generation or GetGameTimer() >= timeout then
            SetModelAsNoLongerNeeded(hash)
            return nil
        end
        Wait(10)
    end
    return hash
end

local function SpawnWave(token)
    ClearBottles()
    local last = nextBottle == #Config.Bottles and nextBottle or math.min(nextBottle + 1, #Config.Bottles - 1)
    for position = nextBottle, last do
        local index = targetOrder[position]
        local data = Config.Bottles[index]
        local hash = LoadModel(data.Model or Config.BottleModel, token)
        if not hash then
            print(('[Sunny-tiro] Chargement impossible, bouteille %d (%s)'):format(index, tostring(data.Model or Config.BottleModel)))
            return false
        end
        if token ~= generation then SetModelAsNoLongerNeeded(hash) return false end
        if state == 'playing' and GetGameTimer() >= endTime then
            SetModelAsNoLongerNeeded(hash)
            return false
        end
        local p = data.Coords

        local entity = CreateObjectNoOffset(hash, p.x, p.y, p.z, false, false, false, false)
        SetModelAsNoLongerNeeded(hash)
        if not entity or entity == 0 or not DoesEntityExist(entity) then
            print(('[Sunny-tiro] Creation impossible, bouteille %d'):format(index))
            return false
        end
        bottles[index] = entity
        local _, maximum = GetModelDimensions(hash)
        targetTops[index] = maximum.z
        if data.Movement then
            local variation = Config.MovementVariation
            waveMovement[index] = {
                speed = variation.MinSpeed + math.random() * (variation.MaxSpeed - variation.MinSpeed),
                direction = math.random(0, 1) == 0 and -1 or 1
            }
        end
        SetEntityAsMissionEntity(entity, true, true)
        SetEntityHeading(entity, data.Heading or 0.0)
        SetEntityVisible(entity, true)
        SetEntityCollision(entity, true, true)
        FreezeEntityPosition(entity, true)
        ClearEntityLastDamageEntity(entity)
    end
    nextBottle = last + 1
    waveStarted = GetGameTimer()
    if last == #Config.Bottles and state == 'playing' then
        finalDeadline = math.min(endTime, waveStarted + Config.FinalTargetDuration * 1000)
        SendNUIMessage({ action = 'finalTarget', duration = Config.FinalTargetDuration })
    end
    return next(bottles) ~= nil
end

local function Finish()
    if state ~= 'playing' then return end
    state = 'finishing'
    ClearBottles()
    SendNUIMessage({ action = 'hideGame' })
    SendNUIMessage({ action = 'preparation', label = 'Enregistrement du resultat...', value = 'TERMINE' })
    TriggerServerEvent('Sunny-tiro:server:FinishGame', session, shots)
    local token = generation
    SetTimeout(15000, function()
        if generation == token and state == 'finishing' then
            Reset()
            Notify('Le resultat tarde a arriver. Consultez /tiroscores.')
        end
    end)
end

local function Start()
    if state ~= 'idle' then return end
    if IsEntityDead(PlayerPedId()) then return end
    if not IsPedOnFoot(PlayerPedId()) then
        Notify('Descendez de votre monture ou vehicule pour participer.')
        return
    end
    CloseUI()
    state = 'waiting'
    generation = generation + 1
    local token = generation
    TriggerServerEvent('Sunny-tiro:server:StartGame', token)
    SetTimeout(Config.SetupTimeout * 1000, function()
        if generation == token and state ~= 'idle' and state ~= 'playing' and state ~= 'finishing' then
            Cancel('Le stand ne repond pas ou les cibles ne sont pas disponibles.')
        end
    end)
end

local function PreparePlayer(token)
    local ped = PlayerPedId()
    local start = Config.PlayerStart
    local destination = vector3(start.x, start.y, start.z)
    preparationPed = ped
    state = 'walking'
    SendNUIMessage({ action = 'preparation', label = 'Rejoignez le pas de tir', value = 'EN PLACE' })

    TaskGoStraightToCoord(ped, start.x, start.y, start.z, Config.WalkSpeed, -1, start.w, Config.ArrivalRadius, 0)
    local deadline = GetGameTimer() + Config.WalkTimeout
    local countdownEnd, lastCount
    while token == generation do
        if PlayerPedId() ~= ped or IsEntityDead(ped) or not IsPedOnFoot(ped)
            or #(GetEntityCoords(ped) - Config.Start) > Config.PlayRadius then
            Cancel('Preparation annulee : restez a pied pres du stand.')
            return false
        end
        DisablePlayerFiring(PlayerId(), true)
        local distance = #(GetEntityCoords(ped) - destination)
        if state == 'walking' then
            if distance <= Config.ArrivalRadius then
                ClearPedTasks(ped)
                TaskAchieveHeading(ped, start.w, 1000)
                state = 'countdown'
                countdownEnd = GetGameTimer() + Config.Countdown * 1000
            elseif GetGameTimer() >= deadline then
                Cancel('Chemin bloque : rapprochez-vous du pas de tir et reessayez.')
                return false
            end
        end
        if state == 'countdown' then
            if distance > Config.ArrivalRadius + 0.75 then
                Cancel('Preparation annulee : vous avez quitte le pas de tir.')
                return false
            end
            local left = math.max(0, math.ceil((countdownEnd - GetGameTimer()) / 1000))
            if left ~= lastCount then
                lastCount = left
                SendNUIMessage({
                    action = 'preparation', label = 'Preparez-vous',
                    value = left > 0 and tostring(left) or 'PRET',
                    sound = left > 0 and 'countdown' or nil,
                    volume = Config.CountdownSoundVolume
                })
            end
            if left == 0 then return true end
        end
        Wait(0)
    end
    return false
end

RegisterNetEvent('Sunny-tiro:client:Approved', function(id, request, order)
    if state ~= 'waiting' or request ~= generation then
        TriggerServerEvent('Sunny-tiro:server:Cancel', id)
        return
    end
    session = id
    targetOrder = order
    state = 'loading'
    local token = generation
    nextBottle = 1
    local ok, spawned = pcall(SpawnWave, token)
    if token ~= generation then return end
    if not ok or not spawned then
        if not ok then print('[Sunny-tiro] Spawn: ' .. tostring(spawned)) end
        Cancel('Impossible de creer les bouteilles. Details dans la console F8.')
        return
    end
    if not PreparePlayer(token) then return end
    state = 'ready'
    TriggerServerEvent('Sunny-tiro:server:Ready', session)
end)

RegisterNetEvent('Sunny-tiro:client:Begin', function(id)
    if session ~= id or state ~= 'ready' then return end
    StopPreparation()
    state = 'playing'
    score = 0
    lastShot = -1000
    shots, wasShooting = 0, false
    previousWeapon = Citizen.InvokeNative(0x8425C5F057012DAB, PlayerPedId())
    previousAmmo = GetAmmoInPedWeapon(PlayerPedId(), previousWeapon)
    waveStarted = GetGameTimer()
    for _, entity in pairs(bottles) do ClearEntityLastDamageEntity(entity) end
    endTime = GetGameTimer() + Config.GameDuration * 1000
    SetNuiFocus(false, false)
    SendNUIMessage({
        action = 'startGame', duration = Config.GameDuration, score = 0,
        sound = 'start', volume = Config.CountdownSoundVolume,
        maxShots = Config.MaxShots,
        maxScore = #Config.Bottles, title = Config.Title, subtitle = Config.Subtitle
    })
end)

RegisterNetEvent('Sunny-tiro:client:Denied', function(message, request)
    if request ~= generation then return end
    if state == 'idle' or state == 'playing' or state == 'finishing' then return end
    Reset()
    Notify(message or 'Le stand est indisponible.')
end)

RegisterNetEvent('Sunny-tiro:client:Result', function(data)
    if state ~= 'finishing' or data.session ~= session then return end
    Reset()
    SendNUIMessage({
        action = 'result', score = data.score, maxScore = #Config.Bottles, elapsedMs = data.elapsedMs, shots = data.shots,
        newRecord = data.newRecord
    })
    SetNuiFocus(true, true)
end)

RegisterNetEvent('Sunny-tiro:client:Leaderboard', function(data)
    if state ~= 'idle' then return end
    data.action = 'leaderboard'
    data.maxScore = #Config.Bottles
    SendNUIMessage(data)
    SetNuiFocus(true, true)
end)

RegisterNetEvent('Sunny-tiro:client:Notice', Notify)

RegisterNUICallback('close', function(_, cb)
    CloseUI()
    cb('ok')
end)

local function OpenWelcome()
    if state ~= 'idle' then return end
    SendNUIMessage({ action = 'welcome', title = Config.Title, duration = Config.GameDuration,
        maxScore = #Config.Bottles, fee = Config.EntryFee, maxShots = Config.MaxShots,
        finalDuration = Config.FinalTargetDuration, arrowDuration = Config.TargetArrow.Duration })
    SetNuiFocus(true, true)
    SetNuiFocusKeepInput(false)
end

RegisterNUICallback('start', function(_, cb)
    Start()
    cb('ok')
end)

RegisterNUICallback('leaderboard', function(_, cb)
    if state == 'idle' then TriggerServerEvent('Sunny-tiro:server:Leaderboard') end
    cb('ok')
end)

RegisterNUICallback('welcome', function(_, cb)
    OpenWelcome()
    cb('ok')
end)

CreateThread(function()
    local lastTime = -1
    while true do
        if state == 'ready' then DisablePlayerFiring(PlayerId(), true) end
        if state == 'playing' then
            local ped = PlayerPedId()
            if IsEntityDead(ped) or #(GetEntityCoords(ped) - Config.Start) > Config.PlayRadius then
                Cancel('Partie annulee : vous avez quitte le stand ou vous etes mort.')
            elseif GetGameTimer() >= endTime or (finalDeadline and GetGameTimer() >= finalDeadline) then
                Finish()
            else
                local shooting = IsPedShooting(ped)
                local weapon = Citizen.InvokeNative(0x8425C5F057012DAB, ped)
                local ammo = GetAmmoInPedWeapon(ped, weapon)
                local ammoDropped = weapon == previousWeapon and previousAmmo and ammo < previousAmmo
                if shots < Config.MaxShots and shooting and
                    (not wasShooting or (ammoDropped and GetGameTimer() - lastShot > 100)) then
                    shots = shots + 1
                    lastShot = GetGameTimer()
                    SendNUIMessage({ action = 'shots', remaining = Config.MaxShots - shots })
                end
                wasShooting, previousWeapon, previousAmmo = shooting, weapon, ammo
                if shots >= Config.MaxShots then DisablePlayerFiring(PlayerId(), true) end
                local arrows = {}
                for index, entity in pairs(bottles) do
                    if not DoesEntityExist(entity) then
                        Cancel('Une cible a disparu. Relancez la partie.')
                        break
                    elseif GetGameTimer() - lastShot < 500 and HasEntityBeenDamagedByEntity(entity, ped, true, true) then
                        DeleteObject(entity)
                        bottles[index] = nil
                        targetTops[index] = nil
                        score = score + 1
                        TriggerServerEvent('Sunny-tiro:server:Hit', session, index)
                        SendNUIMessage({ action = 'score', score = score, maxScore = #Config.Bottles })
                    else
                        local data = Config.Bottles[index]
                        local movement = data.Movement
                        if movement then
                            local variation = waveMovement[index]
                            local elapsed = (GetGameTimer() - waveStarted) / 1000 * variation.speed
                            local offset = math.sin(elapsed * 2 * math.pi / math.max(0.1, movement.Period))
                                * movement.Amplitude * variation.direction
                            if movement.Axis == 'vertical' then
                                SetEntityCoordsNoOffset(entity, data.Coords.x, data.Coords.y,
                                    data.Coords.z + offset, false, false, false)
                            else

                                local angle = math.rad(Config.PlayerStart.w)
                                local z = data.Coords.z
                                if movement.Axis == 'combined' then
                                    z = z + (1 - math.cos(elapsed * 2 * math.pi
                                        / math.max(0.1, movement.VerticalPeriod))) * 0.5 * movement.VerticalAmplitude
                                end
                                SetEntityCoordsNoOffset(entity,
                                    data.Coords.x + math.cos(angle) * offset,
                                    data.Coords.y + math.sin(angle) * offset,
                                    z, false, false, false)
                            end
                        end
                        ClearEntityLastDamageEntity(entity)
                        local arrow = Config.TargetArrow
                        if arrow and arrow.Enabled and (arrow.Duration <= 0 or GetGameTimer() - waveStarted < arrow.Duration * 1000) then
                            local p = GetEntityCoords(entity)
                            local visible, x, y = GetScreenCoordFromWorldCoord(p.x, p.y,
                                p.z + targetTops[index] + arrow.Height)
                            if visible then
                                arrows[#arrows + 1] = { id = index, x = x, y = y }
                            end
                        end
                    end
                end
                if state == 'playing' then
                    SendNUIMessage({ action = 'targetArrows', targets = arrows })
                    local left = math.max(0, math.ceil(((finalDeadline or endTime) - GetGameTimer()) / 1000))
                    if left ~= lastTime then
                        lastTime = left
                        SendNUIMessage({ action = 'timer', time = left })
                    end
                    if score >= #Config.Bottles or (shots >= Config.MaxShots and GetGameTimer() - lastShot >= 500) then
                        Finish()
                    elseif next(bottles) == nil and shots < Config.MaxShots then
                        local token = generation
                        local ok, spawned = pcall(SpawnWave, token)

                        if token == generation and state == 'playing' then
                            if GetGameTimer() >= endTime then
                                Finish()
                            elseif not ok or not spawned then
                                if not ok then print('[Sunny-tiro] Spawn: ' .. tostring(spawned)) end
                                Cancel('Impossible de creer les cibles suivantes. Details dans F8.')
                            end
                        end
                    end
                end
            end
            Wait(0)
        else
            lastTime = -1
            Wait(state == 'ready' and 0 or 100)
        end
    end
end)

RegisterCommand('tiroscores', function()
    if state == 'idle' then TriggerServerEvent('Sunny-tiro:server:Leaderboard') end
end, false)

RegisterCommand('tirostop', function()
    if state ~= 'idle' then
        Cancel('Partie abandonnee.')
    else
        CloseUI()
    end
end, false)

CreateThread(function()
    zone = exports.ox_target:addSphereZone({
        coords = Config.Start, radius = 1.5, debug = Config.Debug,
        options = {
            {
                name = 'sunny_tiro_start', icon = 'fa-solid fa-crosshairs',
                label = ('Participer au Tiro Mexicano - %d $'):format(Config.EntryFee), distance = 2.0,
                canInteract = function() return state == 'idle' end,
                onSelect = function()

                    SetTimeout(200, OpenWelcome)
                end
            },
            {
                name = 'sunny_tiro_leaderboard', icon = 'fa-solid fa-ranking-star',
                label = 'Voir le classement', distance = 2.0,
                canInteract = function() return state == 'idle' end,
                onSelect = function() TriggerServerEvent('Sunny-tiro:server:Leaderboard') end
            }
        }
    })
    if Config.Blip.Enabled then
        local p = Config.Start
        standBlip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, p.x, p.y, p.z)
        SetBlipSprite(standBlip, Config.Blip.Sprite, 1)
        SetBlipScale(standBlip, Config.Blip.Scale)
        Citizen.InvokeNative(0x9CB1A1623062F402, standBlip, Config.Blip.Name)
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Reset()
    if standBlip then
        RemoveBlip(standBlip)
        standBlip = nil
    end
    if zone and GetResourceState('ox_target') == 'started' then
        exports.ox_target:removeZone(zone)
    end
end)
