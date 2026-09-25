CreateThread(function()
    local previousName, previousPlayers, previousMax
    while true do
        local name = Config.DiscordServerName
        if type(name) ~= 'string' or name == '' then
            name = GetConvar('sv_projectName', '')
            if name == '' then name = GetConvar('sv_hostname', 'Serveur RedM') end
        end
        name = name:gsub('%^%d', ''):gsub('[\r\n]', ' ')
        local players = #GetPlayers()
        local maxPlayers = GetConvarInt('sv_maxclients', 48)
        if name ~= previousName or players ~= previousPlayers or maxPlayers ~= previousMax then
            GlobalState['SmallResources:Presence'] = {
                name = name,
                players = players,
                maxPlayers = maxPlayers,
            }
            previousName, previousPlayers, previousMax = name, players, maxPlayers
        end
        Wait(15000)
    end
end)
