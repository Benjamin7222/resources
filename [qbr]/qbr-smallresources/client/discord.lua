local lastPresence

local function UpdatePresence(info)
    if type(info) ~= 'table' or type(info.name) ~= 'string' then return end
    local text = ('%s | %d/%d joueurs'):format(info.name, info.players or 0, info.maxPlayers or 0)
    if text == lastPresence then return end
    SetRichPresence(text)
    lastPresence = text
end

AddStateBagChangeHandler('SmallResources:Presence', 'global', function(_, _, value)
    UpdatePresence(value)
end)

CreateThread(function()
    SetDiscordAppId(Config.DiscordAppId)
    lastPresence = nil
    -- Efface les anciens boutons ; aucun lien personnalise.
    SetDiscordRichPresenceAction(0, '', '')
    SetDiscordRichPresenceAction(1, '', '')
    UpdatePresence(GlobalState['SmallResources:Presence'])
end)
