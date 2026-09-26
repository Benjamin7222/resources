-- ============================================================================
--  Sunny_train - Client : contrôleur
--  Le client désigne seulement le voyageur visé avec ox_target ; le serveur vérifie permission,
--  distance et authenticité des billets.
-- ============================================================================

local Controller = {}
Sunny.Controller = Controller

local L = Sunny.L

--- Contrôle un voyageur précis et ouvre directement le résultat.
function Controller.Check(serverId)
    CreateThread(function()
        local res = Sunny.Request('control:check', { target = serverId })
        if not res.ok then return Sunny.HandleResult(res) end
        Sunny.UI.Open('control', res.data)
    end)
end
