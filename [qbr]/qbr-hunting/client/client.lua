local sharedItems = exports['qbr-core']:GetItems()

--------------------------------------------------------------------
--- FUNCTIONS
--------------------------------------------------------------------

local function DeleteCarryItem(data)
    DeleteEntity(data[2])
    TriggerServerEvent('qbr-hunting:server:SellCarryItems', data[1])
end

local function TradeCarryItem(data)
    local itemData, entity = table.unpack(data)
    local MenuItem = {
        {
            header = 'Échange : '..itemData.name,
            isMenuHeader = true
        },
        {
            header = 'Sell',
            txt = 'Sell For $'..itemData.butcher.cash,
            params = {
                isAction = true,
                event = DeleteCarryItem,
                args = {itemData.butcher.cash, entity}
            }
        }
    }
    for k, v in pairs(itemData.butcher.items) do
        MenuItem[#MenuItem+1] = {
            header = 'Échanger',
            txt = 'Échanger contre '..v..' '..sharedItems[k]['label'],
            params = {
                isAction = true,
                event = DeleteCarryItem,
                args = {{item = k, amount = v}, entity}
            }
        }
    end
    exports['qbr-menu']:openMenu(MenuItem)
end

local function SelectSaleAmount(data)
    local dialog = exports['qbr-input']:ShowInput({
        header = 'Objet : '..sharedItems[data[1]]['label']..' $'..data[4]..' l\'unité',
        submitText = "Valider la vente",
        inputs = {
            {
                text = "Quantité totale disponible : "..data[3],
                name = "amount",
                type = "number",
                isRequired = true
            },
        },
    })
    if not dialog then return end
    dialog.data = data
    TriggerServerEvent('qbr-hunting:server:SellInvItems', dialog)
end

local function OpenShop()
    local MenuItems = {
        {
            header = 'Salon de chasse',
            isMenuHeader = true
        }
    }
    local holding = Citizen.InvokeNative(0xD806CD2A4F2C2996, PlayerPedId())
    if holding then
        local CarryItem = Config.Items['Pickup'][GetEntityModel(holding)]
        if CarryItem?.butcher then
            MenuItems[#MenuItems+1] = {
                header = "Objet : "..CarryItem.name,
                params = {
                    isAction = true,
                    event = TradeCarryItem,
                    args = {CarryItem, holding}
                }
            }
        end
    else
        for k, v in pairs(Config.Items['Inv']) do
            local amount, slot = exports['qbr-inventory']:GetItemAmount(k)
            if amount then
                MenuItems[#MenuItems+1] = {
                    header = 'Objet : '..sharedItems[k]['label'],
                    icon = k,
                    params = {
                        isAction = true,
                        event = SelectSaleAmount,
                        args = {k, slot, amount, v}
                    }
                }
            end
        end
    end
    exports['qbr-menu']:openMenu(MenuItems)
end

--------------------------------------------------------------------
--- EVENTS
--------------------------------------------------------------------

AddEventHandler('QBCore:Event:Looted', function(data)
    if data.ped ~= PlayerPedId() or data.complete == 0 then return end
    local animal = GetEntityModel(data.target)
    local Animalitem = Config.Items['Pickup'][animal]?.skin
    if not Animalitem then return end
    Animalitem.quality = Citizen.InvokeNative(0x88EFFED5FE8B0B4A, data.target)
    TriggerServerEvent('qbr-hunting:server:AnimalItem', Animalitem)
    Wait(200)
    local holding = Citizen.InvokeNative(0xD806CD2A4F2C2996, PlayerPedId())
    if holding then DeleteEntity(holding) end
end)

--------------------------------------------------------------------
--- THREADS
--------------------------------------------------------------------

CreateThread(function()
    local location = Config.Butchers
    if location.PedModel then
        RequestModel(location.PedModel)
        while not HasModelLoaded(location.PedModel) do Wait(0) end
    end
    for k, v in pairs(location['Locations']) do
        local coords = v.xyz
        if location.PedModel then
            local npc = CreatePed(location.PedModel, v, false, true, true, true)
            Citizen.InvokeNative(0x283978A15512B2FE, npc, true)
            SetEntityCanBeDamaged(npc, false)
            SetEntityInvincible(npc, true)
            FreezeEntityPosition(npc, true)
            SetBlockingOfNonTemporaryEvents(npc, true)
            coords = coords + GetEntityForwardVector(npc) * 2.0
            PlaceObjectOnGroundProperly(npc)
            SetEntityLodDist(npc, 50)
        end
        if location.Blip then
            local blip = Citizen.InvokeNative(0x554D9D53F696D002, 1664425300, v.xyz)
            SetBlipSprite(blip, location.Blip, true) -- Blip Texture
            Citizen.InvokeNative(0x9CB1A1623062F402, blip, 'Butcher') -- Name of Blip
        end
        exports['qbr-core']:createPrompt('Hunting:'..k, coords, 0xF3830D8E, 'Parler au boucher', {
            type = 'callback', event = OpenShop
        })
    end
    SetModelAsNoLongerNeeded(location.PedModel)
end)