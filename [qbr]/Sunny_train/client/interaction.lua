-- ============================================================================
--  Sunny_train - Client : interactions
--
--  Prompts natifs RedM (créés une seule fois, affichés à la demande) et
--  détection de proximité des bureaux / guichets.
--  Boucle à Wait dynamique : scan lent quand le joueur est loin de toute
--  gare, plus rapide à l'approche, par frame uniquement à portée d'un point.
-- ============================================================================

local Prompts = { list = {} }
Sunny.Prompts = Prompts

local L = Sunny.L

--- Crée un prompt (dans son propre groupe, ou dans celui d'un autre prompt).
---@param id string
---@param key number|number[] contrôle (plusieurs : chaque touche est affichée)
---@param label string
---@param hold boolean maintien requis
---@param sharedWith? string id d'un prompt existant dont on partage le groupe
function Prompts.Create(id, key, label, hold, sharedWith)
    local group = sharedWith and Prompts.list[sharedWith] and Prompts.list[sharedWith].group or GetRandomIntInRange(0, 0xFFFFFF)
    local prompt = Citizen.InvokeNative(0x04F97DE45A519419, Citizen.ResultAsInteger())                     -- PromptRegisterBegin
    for _, k in ipairs(type(key) == 'table' and key or { key }) do
        Citizen.InvokeNative(0xB5352B7494A08258, prompt, k)                        -- PromptSetControlAction
    end
    Citizen.InvokeNative(0x5DD02A8318420DD7, prompt, Sunny.VarString(label))        -- PromptSetText
    Citizen.InvokeNative(0x8A0FB4D03A630D21, prompt, true)                         -- PromptSetEnabled
    Citizen.InvokeNative(0x71215ACCFDE075EE, prompt, true)                         -- PromptSetVisible
    if hold then
        Citizen.InvokeNative(0x94073D5CA3F16B7B, prompt, Config.Interaction.holdDuration or 1200) -- _UI_PROMPT_SET_HOLD_MODE (durée ms)
    else
        Citizen.InvokeNative(0xCC6656799977741B, prompt, true)                     -- PromptSetStandardMode
    end
    Citizen.InvokeNative(0x2F11D3A254169EA4, prompt, group, 0)                     -- PromptSetGroup
    Citizen.InvokeNative(0xF7AA2696A22AD8B9, prompt)                               -- PromptRegisterEnd
    Prompts.list[id] = { prompt = prompt, group = group, hold = hold, lastFire = 0, visible = true }
end

--- Affiche / masque un prompt (appel natif uniquement si l'état change).
function Prompts.SetVisible(id, visible)
    local p = Prompts.list[id]
    if not p or p.visible == visible then return end
    p.visible = visible
    Citizen.InvokeNative(0x71215ACCFDE075EE, p.prompt, visible)                    -- _UI_PROMPT_SET_VISIBLE
    Citizen.InvokeNative(0x8A0FB4D03A630D21, p.prompt, visible)                    -- _UI_PROMPT_SET_ENABLED
end

local function completed(p)
    if not p.visible then return false end
    local done
    if p.hold then
        done = Citizen.InvokeNative(0xE0F65F0640EF0617, p.prompt, Citizen.ResultAsInteger()) == 1
    else
        done = Citizen.InvokeNative(0xC92AC953F0A982AE, p.prompt, 0, Citizen.ResultAsInteger()) == 1
    end
    if not done then return false end
    local now = GetGameTimer()
    if now - p.lastFire < 1200 then return false end -- anti double-déclenchement
    p.lastFire = now
    return true
end

local function groupTitle(p, title)
    if p.title ~= title then
        p.title, p.titleString = title, Sunny.VarString(title)
    end
    return p.titleString
end

--- Affiche un groupe de prompts pour cette frame ; renvoie l'id validé ou nil.
function Prompts.ShowGroup(ids, title)
    local first = Prompts.list[ids[1]]
    if not first then return nil end
    Citizen.InvokeNative(0xC65A45D4453C2627, first.group, groupTitle(first, title), 1, 0, 0, 0) -- _UI_PROMPT_SET_ACTIVE_GROUP_THIS_FRAME
    for _, id in ipairs(ids) do
        local p = Prompts.list[id]
        if p and completed(p) then return id end
    end
    return nil
end

-- Affichage seul : les commandes de conduite gardent leur détection par appui,
-- sans le délai anti-double-clic des interactions de gare.
function Prompts.DisplayGroup(id, title)
    local p = Prompts.list[id]
    if p then
        Citizen.InvokeNative(0xC65A45D4453C2627, p.group, groupTitle(p, title), 1, 0, 0, 0)
    end
end

--- Le prompt vient-il d'être validé (groupe affiché via DisplayGroup) ?
function Prompts.Completed(id)
    local p = Prompts.list[id]
    return p ~= nil and completed(p)
end

function Prompts.ShareGroup(id, anchor)
    local p, group = Prompts.list[id], Prompts.list[anchor]
    if p and group and p.group ~= group.group then
        Citizen.InvokeNative(0x2F11D3A254169EA4, p.prompt, group.group, 0)
        p.group = group.group
    end
end

--- Affiche le prompt pour cette frame. Renvoie true s'il vient d'être validé.
function Prompts.Show(id, title)
    return Prompts.ShowGroup({ id }, title) == id
end

--- Change le libellé d'un prompt existant.
function Prompts.SetText(id, label)
    local p = Prompts.list[id]
    if not p then return end
    Citizen.InvokeNative(0x5DD02A8318420DD7, p.prompt, Sunny.VarString(label))      -- _UI_PROMPT_SET_TEXT
end

function Prompts.DeleteAll()
    for id, p in pairs(Prompts.list) do
        Citizen.InvokeNative(0x00EDE88D4D13CF59, p.prompt)                         -- PromptDelete
        Prompts.list[id] = nil
    end
end

-- ----------------------------------------------------------------------------
--  Points d'interaction des gares
-- ----------------------------------------------------------------------------

local points = {}

local function buildPoints()
    points = {}
    for key, station in pairs(Config.Stations) do
        if station.office then
            points[#points + 1] = {
                kind = 'office', station = key, coords = station.office.coords,
                radius = station.office.radius or 1.8, title = station.label,
            }
        end
        -- Le guichet sert aussi de point d'accès au registre pour le personnel.
        if station.ticketDesk then
            points[#points + 1] = {
                kind = 'desk', station = key, coords = station.ticketDesk.coords,
                radius = station.ticketDesk.radius or 1.8, title = station.label,
            }
        end
    end
end

local function onInteract(point, promptId)
    if promptId == 'office' or promptId == 'desk_staff' then
        Sunny.Company.Open()
    elseif promptId == 'desk' then
        Sunny.TicketOffice.Open(point.station)
    end
end

CreateThread(function()
    buildPoints()
    Prompts.Create('office', Config.Interaction.key, L('prompt_office'), false)
    Prompts.Create('desk', Config.Interaction.key, L('prompt_desk'), false)
    Prompts.Create('desk_staff', Config.Interaction.staffKey, L('prompt_office'), false, 'desk')

    local isEmployee, nextJobCheck = false, 0
    while true do
        if not Sunny.Target.UsePrompts() then
            Wait(1500) -- ox_target gère les gares : aucun scan de proximité ici.
        else
        local sleep = Config.Interaction.scanInterval
        local ped = PlayerPedId()
        local pos = GetEntityCoords(ped)
        local now = GetGameTimer()

        if now >= nextJobCheck then
            isEmployee = Sunny.IsEmployee()
            nextJobCheck = now + 5000
        end

        local nearest, nearestDist = nil, math.huge
        for i = 1, #points do
            local point = points[i]
            if point.kind ~= 'office' or isEmployee then
                local d = #(pos - point.coords)
                if d < nearestDist then nearest, nearestDist = point, d end
            end
        end

        -- Avec ox_target actif (mode 'target'), bureaux et guichets passent par le target.
        if not Sunny.Target.UsePrompts() then nearest = nil end

        if nearest and nearestDist < Config.Interaction.nearDistance then
            sleep = 250
            if nearestDist <= nearest.radius and not Sunny.UI.open and not IsPedInAnyVehicle(ped, false) then
                sleep = 0
                local ids
                if nearest.kind == 'desk' then
                    local station = Config.Stations[nearest.station]
                    Prompts.SetVisible('desk', Config.Tickets.enabled and station.services and station.services.tickets == true)
                    Prompts.SetVisible('desk_staff', isEmployee)
                    ids = { 'desk', 'desk_staff' }
                else
                    ids = { 'office' }
                end
                local fired = Prompts.ShowGroup(ids, nearest.title)
                if fired then onInteract(nearest, fired) end
            end
        end

        Wait(sleep)
        end
    end
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Prompts.DeleteAll()
end)
