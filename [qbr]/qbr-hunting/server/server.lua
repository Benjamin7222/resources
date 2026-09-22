RegisterNetEvent('qbr-hunting:server:AnimalItem', function(data)
    local src = source
    local Player = exports['qbr-core']:GetPlayer(src)
    if data.quality == nil or not Player then return end
    if Player.Functions.AddItem(data.item, data.amount or 1) then
        if data.quality then
            Player.Functions.AddXp('hunting', data.quality)
        end
    end
end)

RegisterNetEvent('qbr-hunting:server:SellInvItems', function(data)
    local src = source
    local Player = exports['qbr-core']:GetPlayer(src)
    local item, slot = table.unpack(data.data)
    if not (item and slot and Player) then return end
    local GiveItem = Config.Items['Inv'][item]
    if not GiveItem then return end
    if Player.Functions.RemoveItem(item, data.amount, slot) then
        Player.Functions.AddMoney('cash', GiveItem * data.amount, 'Sold-Hunting-Items')
    end
end)

RegisterNetEvent('qbr-hunting:server:SellCarryItems', function(data)
    local src = source
    local Player = exports['qbr-core']:GetPlayer(src)
    if not Player then return end
    if type(data) == 'table' then
        return Player.Functions.AddItem(data.item, data.amount)
    end
    Player.Functions.AddMoney('cash', tonumber(data), 'Sold-Hunting-Items')
end)