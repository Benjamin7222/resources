-- ============================================================================
--  Sunny_train - Adaptateur dispatch (serveur)
--  Sunny_train ne fournit AUCUN dispatch : ce fichier transmet simplement
--  l'alerte au système configuré (Config.Dispatch.system).
--  Le mode 'fallback' n'est qu'un télégramme de secours tant qu'aucun
--  dispatch n'est branché.
-- ============================================================================

local Dispatch = {}
Sunny.Dispatch = Dispatch

local cfg = Config.Dispatch

local senders = {
    none = function() end,

    event = function(data)
        if cfg.event.side == 'client' then
            for _, src in ipairs(Sunny.Bridge.GetPlayersWithJobs(data.jobs, true)) do
                TriggerClientEvent(cfg.event.name, src, data)
            end
        else
            TriggerEvent(cfg.event.name, data)
        end
    end,

    export = function(data)
        local resource = exports[cfg.export.resource]
        resource[cfg.export.method](resource, data)
    end,

    custom = function(data)
        if type(cfg.custom) == 'function' then cfg.custom(data) end
    end,

    fallback = function(data)
        for _, src in ipairs(Sunny.Bridge.GetPlayersWithJobs(data.jobs, true)) do
            TriggerClientEvent('sunny_train:client:dispatchFallback', src, data)
        end
    end,
}

--- Envoie une alerte au dispatch du serveur.
---@param data table { code, title, message, coords = vector3, train, mission, route }
function Dispatch.Send(data)
    if not cfg.enabled then return end
    local sender = senders[cfg.system]
    if not sender then
        print(('^1[Sunny_train] Dispatch : système inconnu "%s".^7'):format(tostring(cfg.system)))
        return
    end
    data.code = data.code or cfg.code
    data.jobs = data.jobs or cfg.jobs
    if data.coords then data.coords = Sunny.Utils.VecToTable(data.coords) end
    local ok, e = pcall(sender, data)
    if not ok then print('^1[Sunny_train] Dispatch : ' .. tostring(e) .. '^7') end
end
