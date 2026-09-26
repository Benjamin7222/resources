-- ============================================================================
--  Sunny_train - Client : intégration ox_target
--
--  Passent par ox_target :
--    - guichet de chaque gare : achat de billet, tableau des départs, et pour
--      le personnel : registre de la compagnie (maintenance incluse)
--    - bureau dédié (si configuré) : registre
--    - joueurs : contrôle des titres de transport (contrôleur)
--    - wagons d'un convoi braquable : braquage
--  Restent en prompts natifs (incompatibles avec un target) : conduite,
--  aiguillages, sifflet, fin de trajet en cabine.
--
--  ox_target (fork RSG) ne charge son module framework que si rsg-core est
--  présent : sur QBR les filtres `groups` sont inopérants, les droits sont
--  donc vérifiés par `canInteract` (et toujours revérifiés par le serveur).
-- ============================================================================

local Target = {
    ready = false,
    zones = {},
}
Sunny.Target = Target

local L = Sunny.L
local cfg = Config.Target

local OPTION_CONTROL = 'sunny_train_control'
local OPTION_ROBBERY = 'sunny_train_robbery'
local OPTION_HOLD = 'sunny_train_hold'

local function ox()
    return exports[cfg.resource]
end

--- ox_target est-il utilisé en ce moment ?
function Target.Active()
    return cfg.mode ~= 'prompt' and Target.ready
end

--- Les prompts natifs des bureaux / guichets / braquage doivent-ils s'afficher ?
function Target.UsePrompts()
    return cfg.mode ~= 'target' or not Target.ready
end

local function hasAction(action)
    local job, grade = Sunny.GetJob()
    return Sunny.Utils.HasJobAccess(Config.Permissions.actions[action], job, grade)
end

local function uiFree()
    return not Sunny.UI.open
end

-- ----------------------------------------------------------------------------
--  Mise en place
-- ----------------------------------------------------------------------------

--- Option du personnel (registre) — suffixe pour des noms uniques par zone.
local function staffOptions(key, suffix)
    return {
        {
            name = ('sunny_train_office_%s_%s'):format(key, suffix),
            icon = cfg.icons.office,
            label = 'Registre de la compagnie',
            distance = cfg.distance,
            canInteract = function() return uiFree() and Sunny.IsEmployee() end,
            onSelect = function() Sunny.Company.Open() end,
        },
    }
end

local function addStationZones()
    for key, station in pairs(Config.Stations) do
        -- Bureau dédié (facultatif).
        if station.office then
            Target.zones[#Target.zones + 1] = ox():addSphereZone({
                name = 'sunny_train_office_zone_' .. key,
                coords = station.office.coords,
                radius = cfg.zoneRadius,
                debug = Config.Debug,
                options = staffOptions(key, 'office'),
            })
        end

        -- Guichet : billets + horaires pour tous, registre pour le personnel.
        if station.ticketDesk then
            local options = {}
            options[#options + 1] = {
                name = 'sunny_train_board_' .. key,
                icon = cfg.icons.board,
                label = 'Départs et billets',
                distance = cfg.distance,
                canInteract = uiFree,
                onSelect = function() Sunny.Stations.OpenBoard(key) end,
            }
            for _, opt in ipairs(staffOptions(key, 'desk')) do options[#options + 1] = opt end
            Target.zones[#Target.zones + 1] = ox():addSphereZone({
                name = 'sunny_train_desk_zone_' .. key,
                coords = station.ticketDesk.coords,
                radius = cfg.zoneRadius,
                debug = Config.Debug,
                options = options,
            })
        end
    end
end

local function addGlobalOptions()
    -- Contrôle d'un voyageur (joueur visé).
    ox():addGlobalPlayer({
        {
            name = OPTION_CONTROL,
            icon = cfg.icons.control,
            label = 'Vérifier les billets',
            distance = cfg.playerDistance,
            canInteract = function() return uiFree() and hasAction('control') end,
            onSelect = function(data)
                local entity = type(data) == 'table' and data.entity or data
                local player = entity and NetworkGetPlayerIndexFromPed(entity)
                if not player or player == -1 then return end
                Sunny.Controller.Check(GetPlayerServerId(player))
            end,
        },
    })

    -- Wagon de chargement d'un train de la compagnie en circulation (charbon, marchandises).
    if Config.Hold.enabled then
        ox():addGlobalVehicle({
            {
                name = OPTION_HOLD,
                icon = cfg.icons.hold,
                label = 'Ouvrir le stockage',
                distance = cfg.trainDistance,
                canInteract = function(entity)
                    return uiFree() and Sunny.IsEmployee() and Sunny.Train.FindInList(GlobalState.sunnyTrains, entity) ~= nil
                end,
                onSelect = function(data)
                    local entity = type(data) == 'table' and data.entity or data
                    local entry = Sunny.Train.FindInList(GlobalState.sunnyTrains, entity)
                    if entry then Sunny.HoldClient.Open(entry.train) end
                end,
            },
        })
    end

    -- Braquage : n'importe quel wagon d'un convoi déclaré braquable.
    if Config.Robbery.enabled then
        ox():addGlobalVehicle({
            {
                name = OPTION_ROBBERY,
                icon = cfg.icons.robbery,
                label = L('rob_prompt'),
                distance = cfg.trainDistance,
                canInteract = function(entity)
                    return uiFree() and Sunny.RobberyClient.EntryForEntity(entity) ~= nil
                end,
                onSelect = function(data)
                    local entity = type(data) == 'table' and data.entity or data
                    local entry, engine = Sunny.RobberyClient.EntryForEntity(entity)
                    if entry then Sunny.RobberyClient.Try(entry, engine) end
                end,
            },
        })
    end
end

function Target.Setup()
    if Target.ready then return end
    addStationZones()
    addGlobalOptions()
    Target.ready = true
    Sunny.Utils.Debug('ox_target : ' .. #Target.zones .. ' zones créées')
end

function Target.Clear()
    if GetResourceState(cfg.resource) == 'started' then
        for _, id in ipairs(Target.zones) do pcall(function() ox():removeZone(id) end) end
        pcall(function() ox():removeGlobalPlayer(OPTION_CONTROL) end)
        pcall(function() ox():removeGlobalVehicle(OPTION_ROBBERY) end)
        pcall(function() ox():removeGlobalVehicle(OPTION_HOLD) end)
    end
    Target.zones = {}
    Target.ready = false
end

local function trySetup()
    CreateThread(function()
        local waited = 0
        while GetResourceState(cfg.resource) ~= 'started' and waited < 15000 do
            Wait(500)
            waited = waited + 500
        end
        if GetResourceState(cfg.resource) ~= 'started' then
            print(('[Sunny_train] %s n\'est pas démarré : repli sur les prompts natifs.'):format(cfg.resource))
            return
        end
        Wait(500)
        local ok, e = pcall(Target.Setup)
        if not ok then
            Target.Clear()
            print(('^1[Sunny_train] ox_target : mise en place impossible (%s), repli sur les prompts natifs.^7'):format(tostring(e)))
        end
    end)
end

if cfg.mode ~= 'prompt' then
    trySetup()

    -- ox_target redémarré : ses données sont perdues, on les recrée.
    AddEventHandler('onClientResourceStart', function(resource)
        if resource == cfg.resource then
            Target.zones = {}
            Target.ready = false
            trySetup()
        end
    end)

    AddEventHandler('onClientResourceStop', function(resource)
        if resource == cfg.resource then
            Target.zones = {}
            Target.ready = false
        end
    end)
end

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Target.Clear()
end)
