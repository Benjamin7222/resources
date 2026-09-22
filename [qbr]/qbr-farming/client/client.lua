local ActivePlants, CurrentPlants, CurrentZone = {}, {}

---------------------------------------------------------------------
---- FUNCTIONS
---------------------------------------------------------------------

local function LoadAnimation(dict)
    RequestAnimDict(dict)
    while not HasAnimDictLoaded(dict) do Wait(0) end
    return dict
end

local function PickCrops(zone, index)
    local entity = CurrentPlants[index]
    local dict = LoadAnimation("script_story@gua3@unapproved")
    TaskPlayAnim(PlayerPedId(), dict, "gardener_plant@male@enter", 8.0, -0.5, -1, 0, 0, true, 0, false, 0, false)
    RemoveAnimDict(dict)
    Wait(5000)
end

local function CreatePickPrompt()
    CropPrompt = PromptRegisterBegin()
    PromptSetControlAction(CropPrompt, `INPUT_MELEE_ATTACK`)
    PromptSetText(CropPrompt, CreateVarString(10, 'LITERAL_STRING', 'Pick Crop'))
    PromptSetHoldMode(CropPrompt, 1000)
    PromptSetPriority(CropPrompt, 0)
    PromptSetEnabled(CropPrompt, true)
    PromptSetVisible(CropPrompt, true)
    PromptRegisterEnd(CropPrompt)
end

local function InsideZoneThread(zone)
    CreateThread(function()
        local ped, zone = PlayerPedId(), zone
        while CurrentZone do
            if ActivePlants[zone] and next(ActivePlants[zone]) then
                local coords = GetEntityCoords(ped)
                for k, data in pairs(ActivePlants[zone]) do
                    if data then
                        local distance = #(data.coords - coords)
                        if not CurrentPlants[k] then
                            CurrentPlants[k] = CreateObjectNoOffset(data.hash, data.coords)
                        else
                            SetEntityCoordsNoOffset(CurrentPlants[k], data.coords)
                        end
                        if distance < 1.5 then
                            if GetEntityHeightAboveGround(CurrentPlants[k]) < 0.5 then
                                while distance < 1.5 do
                                    distance = #(data.coords - GetEntityCoords(ped))
                                    if not CropPrompt then
                                        CreatePickPrompt()
                                    end
                                    if PromptHasHoldModeCompleted(CropPrompt) then
                                        TriggerServerEvent('qbr-farming:server:GetCrop', zone, k, GetEntityModel(CurrentPlants[k]))
                                        PromptDelete(CropPrompt)
                                        PickCrops()
                                        CropPrompt = nil
                                        break
                                    end
                                    Wait(100)
                                end
                            end
                        else
                            if CropPrompt then
                                PromptDelete(CropPrompt)
                                CropPrompt = nil
                            end
                        end
                    elseif CurrentPlants[k] then
                        DeleteEntity(CurrentPlants[k])
                        CurrentPlants[k] = nil
                    end
                end
            elseif next(CurrentPlants) then
                for i=1, #CurrentPlants do
                    DeleteEntity(CurrentPlants[i])
                end
                CurrentPlants = {}
            end
            Wait(1000)
        end
    end)
end

---------------------------------------------------------------------
---- EVENTS
---------------------------------------------------------------------

RegisterNetEvent('qbr-farming:client:PlaceSeed', function(data)
    if not CurrentZone then return end
    local dict = LoadAnimation("script_story@gua3@unapproved")
    TaskPlayAnim(PlayerPedId(), dict, "gardener_plant@male@enter", 8.0, -0.5, -1, 0, 0, true, 0, false, 0, false)
    RemoveAnimDict(dict)
    Wait(5000)
    TriggerServerEvent('qbr-farming:server:PlantSeed', data, CurrentZone)
end)

---------------------------------------------------------------------
---- THREADS
---------------------------------------------------------------------

CreateThread(function()
    local Zones = {}
    local Handler
    for i=1, #Config.FarmingZones do
        local current = Config.FarmingZones[i]
        if current.blip then
            local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, current.coords)
            SetBlipSprite(blip, current.blip, 52)
            SetBlipScale(blip, 0.2)
            Citizen.InvokeNative(0x9CB1A1623062F402, blip, 'Farming Field')
        end
        Zones[i] = BoxZone:Create(current.coords.xyz, current.dim.x, current.dim.y, {
            name = 'FarmingZone:'..i,
            heading = current.coords.w,
            minZ = current.coords.z - 5,
            maxZ = current.coords.z + 3,
            debugPoly = Config.Debug
        })
        Zones[i]:onPlayerInOut(function(inside)
            CurrentZone = inside and i or nil
            if inside then
                ActivePlants[i] = GlobalState['FarmingZone:'..i] or {}
                Handler = AddStateBagChangeHandler('FarmingZone:'..i, 'global', function(_, _, value)
                    ActivePlants[i] = value
                end)
                InsideZoneThread(i)
            else
                RemoveStateBagChangeHandler(Handler)
                if next(CurrentPlants) then
                    for i=1, #CurrentPlants do
                        DeleteEntity(CurrentPlants[i])
                    end
                    CurrentPlants = {}
                end
            end
        end)
    end
end)