-- ============================================================================
--  Sunny_train - Client : pont NUI
--
--  - Ouverture / fermeture avec gestion stricte du focus (jamais bloqué)
--  - Callbacks NUI -> actions Lua (liste blanche Sunny.Actions)
--  - Navigation manette : lue côté jeu tant que la NUI est ouverte
--    (la manette n'est pas transmise au navigateur), relayée à la NUI.
--  - HUD de conduite (sans focus) mis à jour uniquement sur changement.
-- ============================================================================

local UI = {
    open = false,
    view = nil,
    lastHud = nil,
}
Sunny.UI = UI

--- Actions appelables depuis la NUI : [nom] = function(payload) -> result
Sunny.Actions = {}

local staticData = nil
local function getStatic()
    if not staticData then staticData = Sunny.Utils.PublicData() end
    -- L'heure du jeu change : on la rafraîchit à chaque ouverture.
    staticData.clock = { h = GetClockHours(), m = GetClockMinutes() }
    staticData.live = Sunny.Departures and Sunny.Departures.CurrentSnapshot() or nil
    return staticData
end

-- ----------------------------------------------------------------------------
--  Lecture manette pendant que la NUI a le focus
-- ----------------------------------------------------------------------------
local function startInputThread()
    local pad = Config.UI.gamepad
    local token = UI.token
    CreateThread(function()
        local held, nextRepeat = nil, 0
        while UI.open and UI.token == token do
            DisableAllControlActions(0)
            local ped = PlayerPedId()
            if IsEntityDead(ped) then
                UI.Close(true)
                break
            end

            -- IS_USING_KEYBOARD_AND_MOUSE : au clavier, la NUI gère elle-même.
            if pad.enabled and Citizen.InvokeNative(0xA571D46727E2B718, 0, Citizen.ResultAsInteger()) ~= 1 then
                local now = GetGameTimer()
                local dir = nil
                if IsDisabledControlPressed(0, pad.up) then dir = 'up'
                elseif IsDisabledControlPressed(0, pad.down) then dir = 'down' end

                if dir then
                    if held ~= dir then
                        held, nextRepeat = dir, now + pad.repeatDelay
                        SendNUIMessage({ action = 'nav', dir = dir })
                    elseif now >= nextRepeat then
                        nextRepeat = now + pad.repeatRate
                        SendNUIMessage({ action = 'nav', dir = dir })
                    end
                else
                    held = nil
                end

                if IsDisabledControlJustPressed(0, pad.accept) then
                    SendNUIMessage({ action = 'nav', dir = 'select' })
                elseif IsDisabledControlJustPressed(0, pad.cancel) then
                    SendNUIMessage({ action = 'nav', dir = 'back' })
                end
            end
            Wait(0)
        end
    end)
end

-- ----------------------------------------------------------------------------
--  Ouverture / fermeture
-- ----------------------------------------------------------------------------

---@param view 'company'|'tickets'|'ticket'|'report'
function UI.Open(view, data)
    UI.token = (UI.token or 0) + 1
    if UI.open then
        -- Changement de vue sans relâcher le focus.
        UI.view = view
        SendNUIMessage({ action = 'open', view = view, data = data, static = getStatic() })
        return
    end
    UI.open = true
    UI.view = view
    SendNUIMessage({ action = 'open', view = view, data = data, static = getStatic() })
    SetNuiFocus(true, true)
    startInputThread()
end

--- Ferme l'interface après `ms` si elle est toujours ouverte sur la même session.
function UI.CloseSoon(ms)
    local token = UI.token
    SetTimeout(ms, function()
        if UI.open and UI.token == token then UI.Close() end
    end)
end

--- Ferme l'interface et rend immédiatement les contrôles.
---@param instant? boolean pas d'animation de fermeture
function UI.Close(instant)
    local wasOpen = UI.open
    UI.open = false
    UI.view = nil
    SetNuiFocus(false, false)
    if wasOpen or instant then
        SendNUIMessage({ action = 'close', instant = instant == true })
    end
end

-- ----------------------------------------------------------------------------
--  Callbacks NUI
-- ----------------------------------------------------------------------------

RegisterNUICallback('close', function(_, cb)
    UI.open = false
    UI.view = nil
    SetNuiFocus(false, false)
    cb({ ok = true })
end)

RegisterNUICallback('sound', function(data, cb)
    local s = Config.UI.sounds
    local name = data and s[data.name]
    if name then Sunny.PlaySound(name) end
    cb({ ok = true })
end)

RegisterNUICallback('action', function(data, cb)
    local name = type(data) == 'table' and data.name
    local handler = name and Sunny.Actions[name]
    if not handler then
        cb({ ok = false, error = Sunny.L('error_invalid') })
        return
    end
    CreateThread(function()
        local ok, result = pcall(handler, type(data.payload) == 'table' and data.payload or {})
        if not ok then
            print('^1[Sunny_train] NUI action ' .. tostring(name) .. ' : ' .. tostring(result) .. '^7')
            result = { ok = false, error = Sunny.L('error_generic') }
        end
        cb(result or { ok = true })
    end)
end)

-- ----------------------------------------------------------------------------
--  HUD de conduite (sans focus)
-- ----------------------------------------------------------------------------

--- Met à jour la plaque de conduite ; n'envoie rien si rien n'a changé.
function UI.Hud(data)
    local encoded = data and json.encode(data) or 'nil'
    if encoded == UI.lastHud then return end
    UI.lastHud = encoded
    SendNUIMessage({ action = 'hud', data = data })
end

-- Actions génériques relayées telles quelles au serveur (validées là-bas).
for _, name in ipairs({
    'company:context', 'missions:board', 'run:summary',
    'fleet:list', 'fleet:restore', 'fleet:retire', 'control:punch', 'tickets:buy', 'tickets:office',
    'free:board', 'departure:options', 'departure:create', 'departure:cancel', 'fleet:catalogue', 'fleet:buy', 'fleet:sell',
}) do
    Sunny.Actions[name] = function(payload)
        local result = Sunny.Request(name, payload)
        return result
    end
end

Sunny.Actions['ui:close'] = function()
    UI.Close()
    return { ok = true }
end
