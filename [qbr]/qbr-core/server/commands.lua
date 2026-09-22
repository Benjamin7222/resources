local CommandList = {}
local IgnoreList = { -- Ignore old perm levels while keeping backwards compatibility
    ['god'] = true, -- We don't need to create an ace because god is allowed all commands
    ['user'] = true -- We don't need to create an ace because builtin.everyone
}

CreateThread(function() -- Add ace to node for perm checking
    for k,v in pairs(QBConfig.Permissions) do
        ExecuteCommand(('add_ace qbcore.%s %s allow'):format(v, v))
    end
end)

-- Register & Refresh Commands

local function AddCommand(name, help, arguments, argsrequired, callback, permission)
    local restricted = true -- Default to restricted for all commands
    if not permission then permission = 'user' end -- some commands don't pass permission level
    if permission == 'user' then restricted = false end -- allow all users to use command
    RegisterCommand(name, callback, restricted) -- Register command within fivem
    if not IgnoreList[permission] then -- only create aces for extra perm levels
        ExecuteCommand(('add_ace qbcore.%s command.%s allow'):format(permission, name))
    end
    CommandList[name:lower()] = {
        name = name:lower(),
        permission = tostring(permission:lower()),
        help = help,
        arguments = arguments,
        argsrequired = argsrequired,
        callback = callback
    }
end
exports('AddCommand', AddCommand)

function RefreshCommands(source)
    local src = source
    local Player = GetPlayer(src)
    local suggestions = {}
    if Player then
        for command, info in pairs(CommandList) do
            local hasPerm = IsPlayerAceAllowed(tostring(src), 'command.'..command)
            if hasPerm then
                suggestions[#suggestions + 1] = {
                    name = '/' .. command,
                    help = info.help,
                    params = info.arguments
                }
            else
                TriggerClientEvent('chat:removeSuggestion', src, '/'..command)
            end
        end
        TriggerClientEvent('chat:addSuggestions', src, suggestions)
    end
end
exports('RefreshCommands', RefreshCommands)

-- Teleport

AddCommand('tp', 'Se téléporter à un joueur ou à des coordonnées (Admin)', { { name = 'id/x', help = 'ID du joueur ou position X' }, { name = 'y', help = 'Position Y' }, { name = 'z', help = 'Position Z' } }, false, function(source, args)
    local src = source
    if args[1] and not args[2] and not args[3] then
        local target = GetPlayerPed(tonumber(args[1]))
        if target ~= 0 then
            local coords = GetEntityCoords(target)
            TriggerClientEvent('QBCore:Command:TeleportToPlayer', src, coords)
        else
            TriggerClientEvent('QBCore:Notify', src, 9, Lang:t('error.not_online'), 5000, 0, 'mp_lobby_textures', 'cross', 'COLOR_WHITE')
        end
    else
        if args[1] and args[2] and args[3] then
            local x = tonumber((args[1]:gsub(",",""))) + .0
            local y = tonumber((args[2]:gsub(",",""))) + .0
            local z = tonumber((args[3]:gsub(",",""))) + .0
            if (x ~= 0) and (y ~= 0) and (z ~= 0) then
                TriggerClientEvent('QBCore:Command:TeleportToCoords', src, x, y, z)
            else
                TriggerClientEvent('QBCore:Notify', src, 9, Lang:t('error.wrong_format'), 5000, 0, 'mp_lobby_textures', 'cross', 'COLOR_WHITE')
            end
        else
            TriggerClientEvent('QBCore:Notify', src, 9, Lang:t('error.missing_args'), 5000, 0, 'mp_lobby_textures', 'cross', 'COLOR_WHITE')
        end
    end
end, 'admin')

AddCommand('tpm', 'Se téléporter au marqueur (Admin)', {}, false, function(source)
    local src = source
    TriggerClientEvent('QBCore:Command:GoToMarker', src)
end, 'mod')

AddCommand('togglepvp', 'Activer/désactiver le PVP sur le serveur (Admin)', {}, false, function(source)
    local pvp_state = QBConfig.EnablePVP
    QBConfig.EnablePVP = not pvp_state
    TriggerClientEvent('QBCore:Client:PvpHasToggled', -1, QBConfig.EnablePVP)
end, 'god')

-- -- Permissions

AddCommand('addpermission', 'Donner des permissions à un joueur (God)', { { name = 'id', help = 'ID du joueur' }, { name = 'permission', help = 'Niveau de permission' } }, true, function(source, args)
    local src = source
    local Player = GetPlayer(tonumber(args[1]))
    local permission = tostring(args[2]):lower()
    if Player then
        AddPermission(Player.PlayerData.source, permission)
    else
        TriggerClientEvent('QBCore:Notify', src, 9, Lang:t('error.not_online'), 5000, 0, 'mp_lobby_textures', 'cross', 'COLOR_WHITE')
    end
end, 'god')

AddCommand('removepermission', 'Retirer les permissions d\'un joueur (God)', { { name = 'id', help = 'ID du joueur' }, { name = 'permission', help = 'Niveau de permission' } }, true, function(source, args)
    local src = source
    local Player = GetPlayer(tonumber(args[1]))
    local permission = tostring(args[2]):lower()
    if Player then
        RemovePermission(Player.PlayerData.source, permission)
    else
        TriggerClientEvent('QBCore:Notify', src, 9, Lang:t('error.not_online'), 5000, 0, 'mp_lobby_textures', 'cross', 'COLOR_WHITE')
    end
end, 'god')

-- Vehicle

AddCommand('car', 'Faire apparaître un véhicule (Admin)', { { name = 'model', help = 'Nom du modèle du véhicule' } }, true, function(source, args)
    local src = source
    TriggerClientEvent('QBCore:Command:SpawnVehicle', src, args[1])
end, 'admin')

AddCommand('dv', 'Supprimer un véhicule (Admin)', {}, false, function(source)
    local src = source
    TriggerClientEvent('QBCore:Command:DeleteVehicle', src)
end, 'mod')

AddCommand('horse', 'Faire apparaître un cheval (Admin)', { { name = 'model', help = 'Nom du modèle du cheval' } }, true, function(source, args)
    local src = source
    TriggerClientEvent('QBCore:Command:SpawnHorse', src, args[1])
end, 'admin')

AddCommand('coords', 'Afficher vos coordonnées actuelles', {}, false, function(source)
    local src = source
    TriggerClientEvent('QBCore:Command:GetCoords', src)
end, 'user')

-- Money

AddCommand('givemoney', 'Donner de l\'argent à un joueur (Admin)', { { name = 'id', help = 'ID du joueur' }, { name = 'moneytype', help = 'Type d\'argent (cash, bank, crypto)' }, { name = 'amount', help = 'Montant d\'argent' } }, true, function(source, args)
    local src = source
    local Player = GetPlayer(tonumber(args[1]))
    if Player then
        Player.Functions.AddMoney(tostring(args[2]), tonumber(args[3]))
    else
        TriggerClientEvent('QBCore:Notify', src, 9, Lang:t('error.not_online'), 5000, 0, 'mp_lobby_textures', 'cross', 'COLOR_WHITE')
    end
end, 'god')

AddCommand('setmoney', 'Définir l\'argent d\'un joueur (Admin)', { { name = 'id', help = 'ID du joueur' }, { name = 'moneytype', help = 'Type d\'argent (cash, bank, crypto)' }, { name = 'amount', help = 'Montant d\'argent' } }, true, function(source, args)
    local src = source
    local Player = GetPlayer(tonumber(args[1]))
    if Player then
        Player.Functions.SetMoney(tostring(args[2]), tonumber(args[3]))
    else
        TriggerClientEvent('QBCore:Notify', src, 9, Lang:t('error.not_online'), 5000, 0, 'mp_lobby_textures', 'cross', 'COLOR_WHITE')
    end
end, 'god')

-- Xp Commands

AddCommand("givexp", "Donner de l'xp à un joueur (Admin)", {{name="id", help="ID du joueur"},{name="skill", help="Type de compétence (mining, etc)"}, {name="amount", help="Quantité d'xp"}}, true, function(source, args)
	local Player = GetPlayer(tonumber(args[1]))
	if Player then
		if Player.PlayerData.metadata["xp"][tostring(args[2])] then
			Player.Functions.AddXp(tostring(args[2]), tonumber(args[3]))
			TriggerClientEvent('QBCore:Notify', source, 9, Lang:t('info.xp_added'), 5000, 0, 'hud_textures', 'check', 'COLOR_WHITE')
		else
			TriggerClientEvent('QBCore:Notify', source, 9, Lang:t('error.no_skill'), 5000, 0, 'mp_lobby_textures', 'cross', 'COLOR_WHITE')
		end
	else
		TriggerClientEvent('QBCore:Notify', source, 9, Lang:t('error.not_online'), 5000, 0, 'mp_lobby_textures', 'cross', 'COLOR_WHITE')
	end
end, 'god')

AddCommand("removexp", "Retirer de l'xp à un joueur (Admin)", {{name="id", help="ID du joueur"},{name="skill", help="Type de compétence (mining, etc)"}, {name="amount", help="Quantité d'xp"}}, true, function(source, args)
	local Player = GetPlayer(tonumber(args[1]))
	if Player then
		if Player.PlayerData.metadata["xp"][tostring(args[2])] then
			Player.Functions.RemoveXp(tostring(args[2]), tonumber(args[3]))
			TriggerClientEvent('QBCore:Notify', source, 9, Lang:t('info.xp_removed'), 5000, 0, 'hud_textures', 'check', 'COLOR_WHITE')
		else
			TriggerClientEvent('QBCore:Notify', source, 9, Lang:t('error.no_skill'), 5000, 0, 'mp_lobby_textures', 'cross', 'COLOR_WHITE')
		end
	else
		TriggerClientEvent('QBCore:Notify', source, 9, Lang:t('error.not_online'), 5000, 0, 'mp_lobby_textures', 'cross', 'COLOR_WHITE')
	end
end, 'god')

AddCommand("xp", "Voir combien d'xp vous avez", {{name="skill", help="Type de compétence (mining, etc)"}}, true, function(source, args)
	local Player = GetPlayer(source)
	local Xp = Player.PlayerData.metadata["xp"][tostring(args[1])]
	if Player then
		if Xp then
			TriggerClientEvent('QBCore:Notify', source, 9, Lang:t('info.xp_info', {value = Xp, value2 = tostring(args[1])}), 5000, 0, 'hud_textures', 'check', 'COLOR_WHITE')
		else
			TriggerClientEvent('QBCore:Notify', source, 9, Lang:t('error.no_skill'), 5000, 0, 'mp_lobby_textures', 'cross', 'COLOR_WHITE')
		end
	end
end, 'god')

AddCommand("level", "Voir votre niveau", {{name="skill", help="Type de compétence (mining, etc)"}}, true, function(source, args)
	local Player = GetPlayer(source)
	local Level = Player.PlayerData.metadata["levels"][tostring(args[1])]
	if Player then
		if Level then
			TriggerClientEvent('QBCore:Notify', source, 9, Lang:t('info.level_info', {value = Level, value2 = tostring(args[1])}), 5000, 0, 'hud_textures', 'check', 'COLOR_WHITE')
		else
			TriggerClientEvent('QBCore:Notify', source, 9, Lang:t('error.no_skill'), 5000, 0, 'mp_lobby_textures', 'cross', 'COLOR_WHITE')
		end
	end
end, 'god')

-- Job

AddCommand('job', 'Voir votre métier', {}, false, function(source)
    local src = source
    local PlayerJob = GetPlayer(src).PlayerData.job
    TriggerClientEvent('QBCore:Notify', src, 9, Lang:t('info.job_info', {value = PlayerJob.label, value2 = PlayerJob.grade.name, value3 = PlayerJob.onduty}), 5000, 0, 'toasts_mp_generic', 'butcher_table_production', 'COLOR_WHITE')
end, 'user')

AddCommand('setjob', 'Définir le métier d\'un joueur (Admin)', { { name = 'id', help = 'ID du joueur' }, { name = 'job', help = 'Nom du métier' }, { name = 'grade', help = 'Grade' } }, true, function(source, args)
    local src = source
    local function reply(message)
        if src == 0 then
            print('[setjob] ' .. message)
        else
            TriggerClientEvent('chat:addMessage', src, { args = { 'Setjob', message } })
        end
    end

    local playerId = tonumber(args[1])
    local grade = tonumber(args[3])
    if not playerId or playerId < 1 or playerId % 1 ~= 0 or not args[2] or not grade or grade < 0 or grade % 1 ~= 0 then
        reply('Utilisation : /setjob ID metier grade (exemple : /setjob 1 police 0)')
        return
    end

    local job = args[2]:lower()
    local jobData = QBShared.Jobs[job]
    if not jobData then
        reply('Metier inconnu : ' .. job .. '. Consulte qbr-core/shared/jobs.lua.')
        return
    end
    local gradeKey = string.format('%.0f', grade)
    if not jobData.grades[gradeKey] then
        reply('Grade inexistant pour le metier ' .. job .. ' : ' .. gradeKey)
        return
    end

    local Player = GetPlayer(playerId)
    if not Player then
        reply(Lang:t('error.not_online'))
        return
    end
    if not Player.Functions.SetJob(job, gradeKey) then
        reply('Impossible de modifier le metier.')
        return
    end
    reply(('Metier du joueur %s : %s, grade %s.'):format(playerId, jobData.label, gradeKey))
end, 'admin')

-- Gang

AddCommand('gang', 'Voir votre gang', {}, false, function(source)
    local src = source
    local PlayerGang = GetPlayer(source).PlayerData.gang
    TriggerClientEvent('QBCore:Notify', src, 9, Lang:t('info.gang_info', {value = PlayerGang.label, value2 = PlayerGang.grade.name}), 5000, 0, 'hud_textures', 'check', 'COLOR_WHITE')
end, 'user')

AddCommand('setgang', 'Définir le gang d\'un joueur (Admin)', { { name = 'id', help = 'ID du joueur' }, { name = 'gang', help = 'Nom du gang' }, { name = 'grade', help = 'Grade' } }, true, function(source, args)
    local src = source
    local Player = GetPlayer(tonumber(args[1]))
    if Player then
        Player.Functions.SetGang(tostring(args[2]), tonumber(args[3]))
    else
        TriggerClientEvent('QBCore:Notify', src, 9, Lang:t('error.not_online'), 5000, 0, 'mp_lobby_textures', 'cross', 'COLOR_WHITE')
    end
end, 'admin')

-- Inventory (should be in qb-inventory?)

AddCommand('clearinv', 'Vider l\'inventaire d\'un joueur (Admin)', { { name = 'id', help = 'ID du joueur' } }, false, function(source, args)
    local src = source
    local playerId = args[1] or src
    local Player = GetPlayer(tonumber(playerId))
    if Player then
        Player.Functions.ClearInventory()
    else
        TriggerClientEvent('QBCore:Notify', src, 9, Lang:t('error.not_online'), 5000, 0, 'mp_lobby_textures', 'cross', 'COLOR_WHITE')
    end
end, 'god')

-- Out of Character Chat

AddCommand('ooc', 'Message de chat HRP (hors RP)', {}, false, function(source, args)
    local src = source
    local message = table.concat(args, ' ')
    local Players = GetPlayers()
    local Player = GetPlayer(src)
    for k, v in pairs(Players) do
        if v == src then
            TriggerClientEvent('chat:addMessage', v, {
                color = { 0, 0, 255},
                multiline = true,
                args = {'OOC | '.. GetPlayerName(src), message}
            })
        elseif #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(GetPlayerPed(v))) < 20.0 then
            TriggerClientEvent('chat:addMessage', v, {
                color = { 0, 0, 255},
                multiline = true,
                args = {'OOC | '.. GetPlayerName(src), message}
            })
        elseif HasPermission(v, 'admin') then
            if IsOptin(v) then
                TriggerClientEvent('chat:addMessage', v, {
                    color = { 0, 0, 255},
                    multiline = true,
                    args = {'Proxmity OOC | '.. GetPlayerName(src), message}
                })
                TriggerEvent('qbr-log:server:CreateLog', 'ooc', 'OOC', 'white', '**' .. GetPlayerName(src) .. '** (CitizenID: ' .. Player.PlayerData.citizenid .. ' | ID: ' .. src .. ') **Message:** ' .. message, false)
            end
        end
    end
end, 'user')
