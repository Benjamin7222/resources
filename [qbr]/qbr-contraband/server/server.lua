RegisterNetEvent('dk-sellcontraband:server:sell', function(data)
    local src = source
    local Player = exports['qbr-core']:GetPlayer(src)
    if not Player then return end
    if Player.Functions.RemoveItem(data.name, data.amount, data.slot) then
        Player.Functions.AddMoney('cash', data.amount * data.price, "sold-contraband")
        TriggerClientEvent('inventory:client:ItemBox', src, data.name, "remove")
        --if math.random(1, 100) > 25 then return end
        --TriggerEvent('qbr-witness:server:WitnessAlert', GetEntityCoords(GetPlayerPed(src)), 'Someone\'s Selling Contraband')
    end
end)