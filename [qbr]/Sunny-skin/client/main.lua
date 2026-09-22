-- Sunny-skin : /reloadskin (ou /fixskin) recharge l'apparence du personnage depuis la base.
-- Sert quand on ne voit qu'une tête (corps invisible) ou que la tenue ne s'est pas chargée.
-- Utilise les mêmes fonctions que qbr-clothing / qbr-multicharacter au moment de choisir un personnage.

local QBCore = exports['qbr-core']

local COMMANDS = { 'reloadskin', 'fixskin' }
local COOLDOWN_MS = 4000
local busyUntil = 0

local function Notify(text, success)
    if success then
        TriggerEvent('QBCore:Notify', 9, text, 5000, 0, 'hud_textures', 'check', 'COLOR_WHITE')
    else
        TriggerEvent('QBCore:Notify', 9, text, 6000, 0, 'mp_lobby_textures', 'cross', 'COLOR_WHITE')
    end
end

-- Le champ `skin` (choix du corps) à 0 ou absent = aucun torse ni jambes posés : on ne voit que la tête.
-- On le remet à 1 (et on garantit un visage et des yeux) avant de recharger.
local function Sanitize(skin)
    local fixed = {}
    if type(skin) == 'table' then
        for k, v in pairs(skin) do fixed[k] = v end
    end
    local changed = {}
    for _, key in ipairs({ 'skin', 'heads', 'eyes' }) do
        if (tonumber(fixed[key]) or 0) < 1 then
            fixed[key] = 1
            changed[#changed + 1] = key
        end
    end
    return fixed, changed
end

local function Try(fn, ...)
    local ok, result = pcall(fn, ...)
    if ok then return result end
end

local function Reload()
    local pdata = QBCore:GetPlayerData()
    local cid = pdata and pdata.citizenid
    if not cid then error('Aucun personnage chargé.', 0) end

    local ped = PlayerPedId()
    local model = GetEntityModel(ped)
    if model ~= joaat('mp_male') and model ~= joaat('mp_female') then
        error('Ton modèle n\'est pas mp_male / mp_female : impossible de recharger l\'apparence.', 0)
    end

    local data, answered = nil, false
    QBCore:TriggerCallback('qbr-multicharacter:server:getSkin', function(res)
        data, answered = res, true
    end, cid)
    local limit = GetGameTimer() + 6000
    while not answered and GetGameTimer() < limit do Wait(50) end
    if not answered then error('Le serveur ne répond pas, réessaie.', 0) end
    if not data then
        error('Aucune apparence enregistrée pour ce personnage : passe par un magasin de vêtements.', 0)
    end

    -- sorti d'une éventuelle pièce d'essayage restée active, corps visible
    if Try(NetworkIsInTutorialSession) then Try(NetworkEndTutorialSession) end
    Try(SetEntityVisible, ped, true)
    Try(ResetEntityAlpha, ped)

    local skin, changed = Sanitize(data.skin)
    exports['qbr-clothing']:loadSkin(ped, skin)
    Wait(500)
    exports['qbr-clothing']:loadClothes(ped, data.clothes, false)
    Wait(300)

    -- rafraîchit les composants du personnage
    Citizen.InvokeNative(0xCC8CA3E88256E58F, ped, 0, 1, 1, 1, 0)

    -- des valeurs invalides ont été corrigées : on enregistre la version corrigée (sauvegarde officielle de
    -- qbr-clothing), sinon la tête seule reviendrait à la prochaine connexion
    if #changed > 0 then
        TriggerServerEvent('qbr-clothing:server:saveSkin', model, json.encode(skin), json.encode(data.clothes or {}))
    end
    return changed
end

local function Run()
    local now = GetGameTimer()
    if now < busyUntil then
        return Notify('Patiente quelques secondes avant de recharger à nouveau.', false)
    end
    busyUntil = now + 30000 -- garde-fou si un chargement reste bloqué ; ramené à COOLDOWN_MS à la fin

    CreateThread(function()
        local ok, result = pcall(Reload)
        busyUntil = GetGameTimer() + COOLDOWN_MS
        if ok then
            if result and #result > 0 then
                print(('[Sunny-skin] valeurs invalides corrigées et enregistrées : %s'):format(table.concat(result, ', ')))
                Notify('Apparence rechargée et corrigée. Si tu n\'as pas de vêtements, passe par un magasin de vêtements.', true)
            else
                Notify('Apparence rechargée.', true)
            end
        else
            print('[Sunny-skin] ' .. tostring(result))
            Notify(tostring(result), false)
        end
    end)
end

for _, name in ipairs(COMMANDS) do
    RegisterCommand(name, Run, false)
    TriggerEvent('chat:addSuggestion', '/' .. name, 'Recharge ton apparence (corps, visage, tenue) si tu ne vois qu\'une tête')
end
