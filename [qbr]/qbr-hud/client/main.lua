local pid, isLoggedIn = PlayerId()
local sid, cid = GetPlayerServerId(pid)
local CurrentStatus = {}
local DefaultStatus = {
    ['thirst'] = 100,
    ['hunger'] = 100,
    ['stress'] = 0,
    ['armor'] = 0
}

----------------------------------------------------------------------------
---- FUNCTIONS
----------------------------------------------------------------------------

local function GetShakeIntensity(stresslevel)
    local retval = 0.05
    for k, v in pairs(Config.Intensity) do
        if stresslevel >= v.min and stresslevel <= v.max then
            retval = v.intensity
            break
        end
    end
    return retval
end

local function GetEffectInterval(stresslevel)
    local retval = 60000
    for k, v in pairs(Config.EffectInterval) do
        if stresslevel >= v.min and stresslevel <= v.max then
            retval = v.timeout
            break
        end
    end
    return retval
end

local function UpdateStatus(data)
    for k, v in pairs(data) do
        local StatusAmount = CurrentStatus[k]
        if StatusAmount + tonumber(v) < 0 then
            CurrentStatus[k] = 0
        elseif StatusAmount + tonumber(v) > 100 then
            CurrentStatus[k] = 100
        else
            CurrentStatus[k] = StatusAmount + tonumber(v)
        end
    end
    SetResourceKvp(cid, json.encode(CurrentStatus))
end
exports("UpdateStatus", UpdateStatus)

----------------------------------------------------------------------------
---- EVENTS & HANDLERS
----------------------------------------------------------------------------

AddStateBagChangeHandler('isLoggedIn', ('player:%s'):format(sid), function(_, _, value)
    isLoggedIn = value
    if not value then return end
    cid = exports['qbr-core']:GetPlayerData().citizenid
    local Data = GetResourceKvpString(cid)
    CurrentStatus = Data and json.decode(Data) or DefaultStatus
end)

----------------------------------------------------------------------------
---- THREADS
----------------------------------------------------------------------------

CreateThread(function()
    while true do
        Wait(750)
        if isLoggedIn then
            local hidden = IsPauseMenuActive() or Citizen.InvokeNative(0x74F1D22EFA71FAB8) or Citizen.InvokeNative(0x25B7A0206BDFAC76, `MAP`)
            local ped = PlayerPedId()
            SendNUIMessage({
                action = 'hudtick',
                show = not hidden,
                health = GetEntityHealth(ped) / 3, -- health in red dead is 300 so dividing by 3 makes it 100 here
                thirst = CurrentStatus.thirst,
                hunger = CurrentStatus.hunger,
                stress = CurrentStatus.stress,
                stamina = math.floor(Citizen.InvokeNative(0x775A1CA7893AA8B5, ped, Citizen.ResultAsFloat()) * 3),
                temp = math.round((GetTemperatureAtCoords(GetEntityCoords(ped))* 9/5) + 32),
				talking = MumbleIsPlayerTalking(pid),
                voice = MumbleGetTalkerProximity()
            })
        else
            SendNUIMessage({action = 'hudtick', show = false})
        end
    end
end)

CreateThread(function()
    for i=0, 5 do
        Citizen.InvokeNative(0xC116E6DF68DCE667, i, 2) --UitutorialSetRpgIconVisibility
    end
    Citizen.InvokeNative(0x4CC5F2FC1332577F, -1152968308) --`HUD_CTX_IN_FAST_TRAVEL_MENU`
    Citizen.InvokeNative(0x4CC5F2FC1332577F, 1058184710) -- hide skill cards
    Citizen.InvokeNative(0x4CC5F2FC1332577F, -66088566) -- HIDE MP MONEY
    local active = false
    while true do
        local ped = PlayerPedId()
        if not IsPedOnFoot(ped) then
            if not active then
                active = true
                SetMinimapType(1)
            end
        elseif active then
            active = false
            SetMinimapType(0)
        end
        Wait(1000)
    end
end)

CreateThread(function()
    local FoodUpdate, count = Config.UpdateInterval * (60 / 5), 0
    while true do
        if isLoggedIn then
            if CurrentStatus['hunger'] <= 0 or CurrentStatus['thirst'] <= 0 then
                local ped = PlayerPedId()
                local currentHealth = GetEntityHealth(ped)
                SetEntityHealth(ped, currentHealth - math.random(5, 10))
            end
            count += 1
            if count >= FoodUpdate then
                count = 0
                UpdateStatus({thirst = -4.2, hunger = -4.6})
            end
        end
        Wait(5000)
    end
end)

CreateThread(function()
    while true do
        local stress = CurrentStatus.stress or 0
        local ped = PlayerPedId()
        local interval = GetEffectInterval(stress)
        if stress >= 100 then
            local ShakeIntensity = GetShakeIntensity(stress)
            local FallRepeat = math.random(2, 4)
            local RagdollTimeout = (FallRepeat * 1750)
            ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', ShakeIntensity)
            if not IsPedRagdoll(ped) and IsPedOnFoot(ped) and not IsPedSwimming(ped) then
                SetPedToRagdollWithFall(ped, RagdollTimeout, RagdollTimeout, 1, GetEntityForwardVector(ped), 1.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0)
            end
            Wait(500)
            for i = 1, FallRepeat, 1 do
                Wait(750)
                DoScreenFadeOut(200)
                Wait(1000)
                DoScreenFadeIn(200)
                ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', ShakeIntensity)
            end
        elseif stress >= Config.MinimumStress then
            local ShakeIntensity = GetShakeIntensity(stress)
            ShakeGameplayCam('SMALL_EXPLOSION_SHAKE', ShakeIntensity)
        end
        Wait(interval)
    end
end)