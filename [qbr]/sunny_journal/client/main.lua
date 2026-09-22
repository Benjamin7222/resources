local isOpen = false
local newspaperProp = nil
local isReading = false


local ANIM_DICT = "amb_camp@world_camp_sean_lean_barrel@read_paper@male_a@wip_base"
local ANIM_NAME = "wip_base"
local PROP_MODEL = "p_cs_newspaper_02x_noanim"

local function LoadAnimDict(dict)
    if HasAnimDictLoaded(dict) then
        return true
    end

    RequestAnimDict(dict)

    local timeout = 5000
    local startTime = GetGameTimer()

    while not HasAnimDictLoaded(dict) do
        Wait(10)

        if GetGameTimer() - startTime > timeout then
            print("^1[sunny_journal] Impossible de charger l'animation : " .. dict .. "^0")
            return false
        end
    end

    return true
end

local function LoadModel(model)
    local hash = joaat(model)

    if HasModelLoaded(hash) then
        return true
    end

    RequestModel(hash)

    local timeout = 5000
    local startTime = GetGameTimer()

    while not HasModelLoaded(hash) do
        Wait(10)

        if GetGameTimer() - startTime > timeout then
            print("^1[sunny_journal] Impossible de charger le prop : " .. model .. "^0")
            return false
        end
    end

    return true
end

local function DeleteNewspaper()
    if newspaperProp and DoesEntityExist(newspaperProp) then
        DeleteEntity(newspaperProp)
    end

    newspaperProp = nil
end

local function StartReadingJournal()
    if isReading then return end

    local ped = PlayerPedId()

    -- Charge l'animation
    if not LoadAnimDict(ANIM_DICT) then
        return
    end

    -- Charge le journal
    if not LoadModel(PROP_MODEL) then
        return
    end

    -- Crée le journal
    local coords = GetEntityCoords(ped)

    newspaperProp = CreateObject(
        joaat(PROP_MODEL),
        coords.x,
        coords.y,
        coords.z,
        true,
        true,
        false
    )

    -- Attache le journal au joueur
    AttachEntityToEntity(
        newspaperProp,
        ped,
        GetEntityBoneIndexByName(ped, "PH_R_Hand"),
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        0.0,
        true,
        true,
        false,
        true,
        1,
        true
    )

    SetModelAsNoLongerNeeded(joaat(PROP_MODEL))

    -- Lance l'animation
    TaskPlayAnim(
        ped,
        ANIM_DICT,
        ANIM_NAME,
        8.0,
        -8.0,
        -1,
        1,
        0.0,
        false,
        false,
        false
    )

    isReading = true
end

local function StopReadingJournal()
    if not isReading and not newspaperProp then
        return
    end

    local ped = PlayerPedId()

    -- Arrête l'animation
    ClearPedTasks(ped)

    -- Supprime le journal
    DeleteNewspaper()

    isReading = false
end


local function OpenUI(message)

    if isOpen then return end

    isOpen = true

    SetNuiFocus(true, true)

    SendNUIMessage(message)

end

local function CloseUI()

    isOpen = false

    SetNuiFocus(false, false)

    -- Arrête la lecture
    StopReadingJournal()

end



RegisterNetEvent('sunny_journal:client:OpenEditor', function()

    -- Si on était en train de lire
    StopReadingJournal()

    OpenUI({
        action = 'openEditor'
    })

end)



RegisterNetEvent('sunny_journal:client:OpenReader', function(journal)

    -- Lance l'animation
    StartReadingJournal()

    -- Ouvre le journal
    OpenUI({
        action = 'openReader',
        journal = journal
    })

end)


RegisterNUICallback('close', function(_, cb)

    CloseUI()

    cb('ok')

end)


local function BridgeServerCallback(nuiName, serverName)

    RegisterNUICallback(nuiName, function(data, cb)

        exports['qbr-core']:TriggerCallback(serverName, function(result)

            cb(result or {
                ok = false,
                error = 'Pas de réponse du serveur.'
            })

        end, data)

    end)

end

BridgeServerCallback('list', 'sunny_journal:server:List')
BridgeServerCallback('get', 'sunny_journal:server:Get')
BridgeServerCallback('save', 'sunny_journal:server:Save')
BridgeServerCallback('publish', 'sunny_journal:server:Publish')
BridgeServerCallback('delete', 'sunny_journal:server:Delete')
BridgeServerCallback('print', 'sunny_journal:server:Print')



AddEventHandler('onResourceStop', function(resource)

    if resource ~= GetCurrentResourceName() then
        return
    end

    -- Ferme le NUI
    if isOpen then
        SetNuiFocus(false, false)
    end

    -- Nettoyage animation + prop
    StopReadingJournal()

end)


