-- ============================================================================
--  Sunny_train - Client : gares
--  Blips, recherche de gare, affichage de debug des points configurés.
-- ============================================================================

local Stations = {
    blips = {},
    debug = false,
}
Sunny.Stations = Stations

--- Gare la plus proche d'une position.
function Stations.Nearest(pos)
    local best, bestDist = nil, math.huge
    for key, station in pairs(Config.Stations) do
        local d = #(pos - station.coords)
        if d < bestDist then best, bestDist = key, d end
    end
    return best, bestDist
end

--- Tableau des départs d'une gare (consultable par tous, sans serveur).
function Stations.OpenBoard(stationKey)
    local station = Config.Stations[stationKey]
    if not station then return end
    if Config.Tickets.enabled and station.services and station.services.tickets then
        return Sunny.TicketOffice.Open(stationKey)
    end
    Sunny.UI.Open('board', { station = stationKey })
end

function Stations.CreateBlips()
    local cfg = Config.Interaction.blips
    if not cfg.enabled then return end
    for key, station in pairs(Config.Stations) do
        if station.blip ~= false then
            Stations.blips[key] = Sunny.CreateBlip(station.coords, cfg.sprite, 'Gare — ' .. station.label, cfg.scale)
        end
    end
end

function Stations.RemoveBlips()
    for key, blip in pairs(Stations.blips) do
        if DoesBlipExist(blip) then RemoveBlip(blip) end
        Stations.blips[key] = nil
    end
end

-- ----------------------------------------------------------------------------
--  Debug : marqueurs des points configurés (/sunnytrain_debug, ACE requise)
-- ----------------------------------------------------------------------------

local function drawText3D(coords, text)
    local onScreen, x, y = GetScreenCoordFromWorldCoord(coords.x, coords.y, coords.z)
    if not onScreen then return end
    Citizen.InvokeNative(0xA1253A3C870B6843, 0.30, 0.30)          -- _BG_SET_TEXT_SCALE
    Citizen.InvokeNative(0x50A41AD966910F03, 255, 230, 180, 230)  -- _SET_TEXT_COLOR
    Citizen.InvokeNative(0xD79334A4BB99BAD1, Sunny.VarString(text), x - 0.04, y) -- _DISPLAY_TEXT
end

local function drawMarker(coords, radius, r, g, b)
    -- DRAW_MARKER (cylindre)
    Citizen.InvokeNative(0x2A32FAA57B937173, 0x94FDAE17, coords.x, coords.y, coords.z - 1.0,
        0.0, 0.0, 0.0, 0.0, 0.0, 0.0, radius * 2.0, radius * 2.0, 0.6, r, g, b, 90, false, false, 2, false, nil, nil, false)
end

function Stations.ToggleDebug()
    Stations.debug = not Stations.debug
    Sunny.Notify('Debug Sunny_train : ' .. (Stations.debug and 'activé' or 'désactivé'), 'info')
    if not Stations.debug then return end
    CreateThread(function()
        while Stations.debug do
            local pos = GetEntityCoords(PlayerPedId())
            for key, st in pairs(Config.Stations) do
                if #(pos - st.coords) < 250.0 then
                    if st.office then
                        drawMarker(st.office.coords, st.office.radius, 200, 160, 60)
                        drawText3D(st.office.coords + vector3(0, 0, 1.0), key .. ' : bureau')
                    end
                    if st.ticketDesk then
                        drawMarker(st.ticketDesk.coords, st.ticketDesk.radius, 60, 160, 200)
                        drawText3D(st.ticketDesk.coords + vector3(0, 0, 1.0), key .. ' : guichet')
                    end
                    if st.platform then
                        drawMarker(st.platform.coords, 1.5, 200, 60, 60)
                        drawText3D(st.platform.coords + vector3(0, 0, 1.5), ('%s : quai (rayon %.0f m)'):format(key, st.platform.radius))
                    end
                    if st.depot then
                        drawMarker(st.depot.coords, 1.5, 60, 200, 60)
                        drawText3D(st.depot.coords + vector3(0, 0, 1.5), key .. ' : dépôt')
                    end
                end
            end
            Wait(0)
        end
    end)
end

CreateThread(function()
    Stations.CreateBlips()
end)

AddEventHandler('onResourceStop', function(resource)
    if resource ~= GetCurrentResourceName() then return end
    Stations.debug = false
    Stations.RemoveBlips()
end)
