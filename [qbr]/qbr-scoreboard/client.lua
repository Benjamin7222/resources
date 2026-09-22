Config.IllegalActions = GlobalState.IllegalActions or Config.IllegalActions
local scoreboardOpen = false
local PlayerOptin = {}

--------------------------------------------------------------------------------
---- FUNCTIONS
--------------------------------------------------------------------------------

local function GetPlayers()
    local players = {}
    for _, player in ipairs(GetActivePlayers()) do
        if GetPlayerPed(player) then
            table.insert(players, player)
        end
    end
    return players
end

local function DrawText3D(x, y, z, text)
	SetTextScale(0.35, 0.35)
    SetTextFont(4)
    SetTextProportional(true)
    SetTextColour(255, 255, 255, 215)
    SetTextEntry("STRING")
    SetTextCentre(true)
    AddTextComponentString(text)
    SetDrawOrigin(x,y,z, 0)
    DrawText(0.0, 0.0)
    local factor = (string.len(text)) / 370
    DrawRect(0.0, 0.0+0.0125, 0.017+ factor, 0.03, 0, 0, 0, 75)
    ClearDrawOrigin()
end

local function GetPlayersFromCoords(coords, distance)
    local players = GetPlayers()
    local closePlayers = {}
    if coords == nil then
		coords = GetEntityCoords(PlayerPedId())
    end
    if distance == nil then
        distance = 5.0
    end
    for _, player in pairs(players) do
		local target = GetPlayerPed(player)
		local targetCoords = GetEntityCoords(target)
		local targetdistance = #(targetCoords - vector3(coords.x, coords.y, coords.z))
		if targetdistance <= distance then
			table.insert(closePlayers, player)
		end
    end
    return closePlayers
end

--------------------------------------------------------------------------------
---- EVENTS & HANDLERS
--------------------------------------------------------------------------------

AddStateBagChangeHandler('IllegalActions', 'global', function(_, _, value)
    Config.IllegalActions = value
end)

--------------------------------------------------------------------------------
---- THREADS
--------------------------------------------------------------------------------

CreateThread(function()
    while true do
        Wait(3)
        if IsControlJustReleased(0, Config.OpenKey)  then  -- Config Keybind
            if not scoreboardOpen then
                exports['qbr-core']:TriggerCallback('qbr-scoreboard:server:GetPlayersArrays', function(playerList)
                    exports['qbr-core']:TriggerCallback('qbr-scoreboard:server:GetActivity', function(cops, ambulance)
						PlayerOptin = playerList
						Config.CurrentCops = cops
						SendNUIMessage({
							action = "open",
							players = GlobalState['Count:Players'],
							maxPlayers = Config.MaxPlayers,
							requiredCops = Config.IllegalActions,
							currentCops = Config.CurrentCops,
							currentAmbulance = ambulance
						})
						scoreboardOpen = true
                    end)
                end)
            else
                SendNUIMessage({action = "close"})
                scoreboardOpen = false
            end

            if scoreboardOpen then
                for _, player in pairs(GetPlayersFromCoords(GetEntityCoords(PlayerPedId()), 10.0)) do
                    local PlayerId = GetPlayerServerId(player)
                    local PlayerPed = GetPlayerPed(player)
                    local PlayerName = GetPlayerName(player)
                    local PlayerCoords = GetEntityCoords(PlayerPed)

                    if not PlayerOptin[PlayerId].permission then
                        DrawText3D(PlayerCoords.x, PlayerCoords.y, PlayerCoords.z + 1.0, '['..PlayerId..']')
                    end
                end
            end
        end
    end
end)
