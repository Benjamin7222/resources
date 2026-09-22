-------------------------------------------------------------------------
---- FUNCTIONS
-------------------------------------------------------------------------

local function OpenShop(shopType, shopName)
    exports['qbr-core']:TriggerCallback('qbr-shops:server:getLicenseStatus', function(result)
        local ShopItems = {}
        ShopItems.items = {}
        ShopItems.label = shopName
        if shopType == "weapon" then
            if result then
                ShopItems.items =  Config.Products[shopType]
            else
                for i = 1, #Config.Products[shopType] do
                    if not Config.Products[shopType][i].requiresLicense then
                        table.insert(ShopItems.items, Config.Products[shopType][i])
                    end
                end
            end
        else
            ShopItems.items = Config.Products[shopType]
        end
        ShopItems.slots = 30
        TriggerServerEvent("inventory:server:OpenInventory", "shop", "Itemshop_"..shopType, ShopItems) --Review later for visual correction
    end)
end

-------------------------------------------------------------------------
---- EVENTS & HANDLERS
-------------------------------------------------------------------------

RegisterNetEvent('qbr-shops:client:SetShopItems', function(shopType, shopProducts)
    Config.Products[shopType] = shopProducts
end)

RegisterNetEvent('qbr-shops:client:RestockShopItems', function(shopType, amount)
    if not Config.Products[shopType] then return end
    for k, v in pairs(Config.Products[shopType]) do
        Config.Products[shopType][k].amount = Config.Products[shopType][k].amount + amount
    end
end)

-------------------------------------------------------------------------
---- THREADS
-------------------------------------------------------------------------

CreateThread(function()
    for store, v in pairs(Config.Locations) do
        exports['qbr-core']:createPrompt(v.name, v.coords, 0xF3830D8E, 'Ouvrir : ' .. v.name, {
            type = 'callback',
            event = OpenShop,
            args = {v.products, v.name},
        })
        if v.blip then
            local StoreBlip = N_0x554d9d53f696d002(1664425300, v.coords)
            SetBlipSprite(StoreBlip, v.blip, 1)
            SetBlipScale(StoreBlip, 0.2)
        end
    end
end)
