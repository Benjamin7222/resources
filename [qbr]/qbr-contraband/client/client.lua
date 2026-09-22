local slots = Config.QuickSlots and 5 or exports['qbr-core']:GetConfig().Player.MaxInvSlots
local Entities = {}

-----------------------------------------------------------------------------
---- FUNCTIONS
-----------------------------------------------------------------------------

local function randomDecimal(min, max)
    local rand = min + math.random() * (max - min)
    local formatString = string.format("%.2f", rand)
    return tonumber(formatString)
end

local function CheckForItems()
    local items = exports['qbr-inventory']:GetSlotData(1, slots)
    for _, v in pairs(items) do
        if v and Config.Contraband[v.name] then
            return v
        end
    end
    return nil
end

local function CreatePrompt(name, group)
    PedPrompt = PromptRegisterBegin()
    PromptSetControlAction(PedPrompt, 0x80F28E95)
    PromptSetText(PedPrompt, CreateVarString(10, 'LITERAL_STRING', name))
    PromptSetEnabled(PedPrompt, true)
    PromptSetVisible(PedPrompt, true)
    PromptSetHoldMode(PedPrompt, 1500)
    if group then
        PromptSetGroup(PedPrompt, group)
    end
    PromptRegisterEnd(PedPrompt)
end

local function SellToPed(target)
    Entities[target] = true
    local item = CheckForItems()
    if not item then return end
    ClearPedTasks(target)
    local ped = PlayerPedId()
    TaskGoToEntity(target, ped, -1, 1.0, 1.0, 0.0)
    local count = 0
    while #(GetEntityCoords(ped) - GetEntityCoords(target)) > 1.5 do
        Wait(100)
        count += 1
        if count >= 250 then return end
    end
    TaskLookAtEntity(target, ped, 5500.0, 2048, 3)
    TaskTurnPedToFaceEntity(target, ped, 5500)
    while #(GetEntityCoords(ped) - GetEntityCoords(target)) <= 1.5 do
        if not PedPrompt then
            local sell = Config.Contraband[item.name]
            item.price = randomDecimal(sell.min, sell.max)
            item.amount = math.random(1, item.amount)
            CreatePrompt(item.name..' '..item.amount..' ( $'..item.price..' Each)')
        end
        if PromptHasHoldModeCompleted(PedPrompt) then
            PromptDelete(PedPrompt)
            PedPrompt = nil
            ClearPedTasksImmediately(target)
            return TriggerServerEvent('dk-sellcontraband:server:sell', item)
        end
        Wait(100)
    end
    if PedPrompt then
        PromptDelete(PedPrompt)
        PedPrompt = nil
    end
end

-----------------------------------------------------------------------------
---- THREADS
-----------------------------------------------------------------------------

CreateThread(function()
    local pid = PlayerId()
    while true do
        local retval, entity = GetPlayerTargetEntity(pid)
        if retval then
            if not PedPrompt then
                if IsEntityAPed(entity) and not IsPedAPlayer(entity) and not Citizen.InvokeNative(0x9A100F1CF4546629, entity) then
                    if not Entities[entity] then
                        local promptGroup = PromptGetGroupIdForTargetEntity(entity)
                        CreatePrompt('Offer Contraband', promptGroup)
                    end
                end
            elseif PromptHasHoldModeCompleted(PedPrompt) then
                PromptDelete(PedPrompt)
                PedPrompt = nil
                SellToPed(entity)
                Wait(5000)
            end
        elseif PedPrompt then
            PromptDelete(PedPrompt)
            PedPrompt = nil
        end
        Wait(500)
    end
end)