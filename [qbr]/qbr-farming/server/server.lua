local PlantObjects = {}

---------------------------------------------------------------------
---- EVENTS
---------------------------------------------------------------------

RegisterNetEvent('qbr-farming:server:GetCrop', function(zone, index, hash)
    local src = source
    local Player = exports['qbr-core']:GetPlayer(src)
    if not Player then return end
    if not Player.Functions.AddItem(Config.FarmingCrops[hash], math.random(4, 8)) then return end
    PlantObjects[zone][index] = false
    GlobalState['FarmingZone:'..zone] = PlantObjects[zone]
end)

RegisterNetEvent('qbr-farming:server:PlantSeed', function(data, zone)
    local src = source
    local Player = exports['qbr-core']:GetPlayer(src)
    if not Player then return end
    local name, slot, hash = table.unpack(data)
    if not Player.Functions.RemoveItem(name, 1, slot) then return end
    local coords = GetEntityCoords(GetPlayerPed(src))
    if not PlantObjects[zone] then PlantObjects[zone] = {} end
    PlantObjects[zone][#PlantObjects[zone]+1] = {tick = 1, coords = vector3(coords.x, coords.y, coords.z - 1.95), hash = hash}
    GlobalState['FarmingZone:'..zone] = PlantObjects[zone]
end)

---------------------------------------------------------------------
---- ITEMS
---------------------------------------------------------------------

for k, v in pairs(Config.FarmingCrops) do
    exports['qbr-core']:CreateUseableItem('seed_'..v, function(source, item)
        local src = source
        local data = {item.name, item.slot, k}
        TriggerClientEvent('qbr-farming:client:PlaceSeed', src, data)
    end)
end

---------------------------------------------------------------------
---- THREADS
---------------------------------------------------------------------

CreateThread(function()
    local timer = Config.Ticker * 60000
    while true do
        if next(PlantObjects) then
            for i=1, #PlantObjects do
                local change = false
                if PlantObjects[i] and next(PlantObjects[i]) then
                    for k=1, #PlantObjects[i] do
                        local current = PlantObjects[i]?[k]
                        if current and current.tick < 5 then
                            current.tick = current.tick + 1
                            local coords = current.coords
                            current.coords = vector3(coords.x, coords.y, coords.z + 0.25)
                            change = true
                        end
                    end
                    if change then
                        GlobalState['FarmingZone:'..i] = PlantObjects[i]
                    end
                end
            end
        end
        Wait(timer)
    end
end)
