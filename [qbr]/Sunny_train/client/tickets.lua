-- ============================================================================
--  Sunny_train - Client : guichet & billets
-- ============================================================================

local TicketOffice = {}
Sunny.TicketOffice = TicketOffice

--- Ouvre le guichet d'une gare (tarifs calculés par le serveur).
function TicketOffice.Open(stationKey)
    CreateThread(function()
        local res = Sunny.Request('tickets:office', { station = stationKey })
        if not res.ok then return Sunny.HandleResult(res) end
        Sunny.Departures.ApplySnapshot(res.data.live)
        Sunny.UI.Open('tickets', res.data)
    end)
end

-- Utilisation de l'item billet : le serveur renvoie la vue vérifiée.
RegisterNetEvent('sunny_train:client:showTicket', function(ticket)
    if type(ticket) ~= 'table' then return end
    Sunny.UI.Open('ticket', { ticket = ticket })
end)
