-- ============================================================================
--  Sunny_train - Client : maintenance
--  Travaux en deux temps : le serveur ouvre un chantier horodaté (begin) et
--  n'accepte la fin (finish) qu'une fois la durée réellement écoulée.
-- ============================================================================

local function startScenario(name)
    if not name then return end
    local ped = PlayerPedId()
    -- TASK_START_SCENARIO_IN_PLACE_HASH
    -- (ped, scenarioHash, duration, playEnterAnim, conditionalHash, heading, p6)
    Citizen.InvokeNative(0x524B54361229154F, ped, GetHashKey(name), -1, true, 0, GetEntityHeading(ped), false)
end

-- ----------------------------------------------------------------------------
--  Wagon de chargement : coffre de qbr-inventory (inventaire existant)
-- ----------------------------------------------------------------------------
Sunny.HoldClient = {}

function Sunny.HoldClient.Open(trainKey)
    CreateThread(function()
        local res = Sunny.Request('hold:open', { train = trainKey })
        if not res.ok then return Sunny.HandleResult(res) end
        Sunny.UI.Close()
        Wait(150)
        TriggerServerEvent('inventory:server:OpenInventory', 'stash', res.data.stash, { maxweight = res.data.weight, slots = res.data.slots })
        TriggerEvent('inventory:client:SetCurrentStash', res.data.stash)
    end)
end

Sunny.Actions['hold:open'] = function(payload)
    local res = Sunny.Request('hold:open', { train = payload.train })
    if not res.ok then return res end
    Sunny.UI.Close()
    CreateThread(function()
        Wait(150)
        TriggerServerEvent('inventory:server:OpenInventory', 'stash', res.data.stash, { maxweight = res.data.weight, slots = res.data.slots })
        TriggerEvent('inventory:client:SetCurrentStash', res.data.stash)
    end)
    return { ok = true, replaced = true }
end

---@param payload { kind: 'inspect'|'repair', train: string, repair?: string }
Sunny.Actions['fleet:work'] = function(payload)
    local begin = Sunny.Request('fleet:begin', payload)
    if not begin.ok then return begin end

    startScenario(begin.data.scenario)
    local finishAt = GetGameTimer() + begin.data.duration
    while GetGameTimer() < finishAt do
        -- Fermeture de l'interface = abandon du chantier.
        if not Sunny.UI.open then
            ClearPedTasks(PlayerPedId())
            Sunny.Request('fleet:cancelWork')
            return { ok = false }
        end
        Wait(100)
    end
    ClearPedTasks(PlayerPedId())
    return Sunny.Request('fleet:finish')
end
