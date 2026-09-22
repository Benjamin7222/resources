local GangaccountGangs = {}

CreateThread(function()
	Wait(500)
	local gangmenu = MySQL.query.await('SELECT * FROM management_menu WHERE menu_type = "gang"', {})
	if not gangmenu then
		return
	end
	for k,v in pairs(gangmenu) do
		local k = tostring(v.job_name)
		local v = tonumber(v.amount)
		if k and v then
			GangaccountGangs[k] = v
		end
	end
end)

-- UTIL

-- Returns the player only if he is the boss of his gang (checked server side, never trust the client)
local function GetBossPlayer(src)
	local Player = exports['qbr-core']:GetPlayer(src)
	if Player and Player.PlayerData.gang and Player.PlayerData.gang.isboss then
		return Player
	end
	return nil
end

-- Returns a positive whole number or nil
local function ValidAmount(amount)
	amount = tonumber(amount)
	if not amount or amount <= 0 or amount ~= math.floor(amount) then
		return nil
	end
	return amount
end

-- Insert the account if it does not exist yet, so the balance is saved even when the SQL was never imported
local function SaveAccount(gang)
	MySQL.query.await('INSERT INTO management_menu (job_name, amount, menu_type) VALUES (?, ?, "gang") ON DUPLICATE KEY UPDATE amount = VALUES(amount)', { gang, GangaccountGangs[gang] })
end

local function NotifyError(src, text)
	TriggerClientEvent('QBCore:Notify', src, 9, text, 5000, 0, 'mp_lobby_textures', 'cross', 'COLOR_WHITE')
end

local function NotifySuccess(src, text)
	TriggerClientEvent('QBCore:Notify', src, 9, text, 5000, 0, 'hud_textures', 'check', 'COLOR_WHITE')
end

RegisterNetEvent("qbr-gangmenu:server:withdrawMoney", function(amount)
	local src = source
	local xPlayer = GetBossPlayer(src)
	if not xPlayer then return end
	local gang = xPlayer.PlayerData.gang.name
	amount = ValidAmount(amount)

	if not GangaccountGangs[gang] then
		GangaccountGangs[gang] = 0
	end

	if amount and GangaccountGangs[gang] >= amount then
		GangaccountGangs[gang] = GangaccountGangs[gang] - amount
		xPlayer.Functions.AddMoney("cash", amount, 'Boss menu withdraw')
	else
		NotifyError(src, "Montant invalide !")
		TriggerClientEvent('qbr-gangmenu:client:OpenMenu', src)
		return
	end

	SaveAccount(gang)
	TriggerEvent('qbr-log:server:CreateLog', 'gangmenu', 'Withdraw Money', 'yellow', xPlayer.PlayerData.charinfo.firstname .. ' ' .. xPlayer.PlayerData.charinfo.lastname .. ' successfully withdrew $' .. amount .. ' (' .. gang .. ')', false)
	NotifySuccess(src, "Vous avez retiré : $" ..amount)
	TriggerClientEvent('qbr-gangmenu:client:OpenMenu', src)
end)

RegisterNetEvent("qbr-gangmenu:server:depositMoney", function(amount)
	local src = source
	local xPlayer = GetBossPlayer(src)
	if not xPlayer then return end
	local gang = xPlayer.PlayerData.gang.name
	amount = ValidAmount(amount)

	if not GangaccountGangs[gang] then
		GangaccountGangs[gang] = 0
	end

	if amount and xPlayer.Functions.RemoveMoney("cash", amount) then
		GangaccountGangs[gang] = GangaccountGangs[gang] + amount
	else
		NotifyError(src, "Montant invalide !")
		TriggerClientEvent('qbr-gangmenu:client:OpenMenu', src)
		return
	end

	SaveAccount(gang)
	TriggerEvent('qbr-log:server:CreateLog', 'gangmenu', 'Deposit Money', 'yellow', xPlayer.PlayerData.charinfo.firstname .. ' ' .. xPlayer.PlayerData.charinfo.lastname .. ' successfully deposited $' .. amount .. ' (' .. gang .. ')', false)
	NotifySuccess(src, "Vous avez déposé : $" ..amount)
	TriggerClientEvent('qbr-gangmenu:client:OpenMenu', src)
end)

-- Server side only (used by other resources with TriggerEvent), NOT callable from a client
AddEventHandler("qbr-gangmenu:server:addaccountGangMoney", function(accountGang, amount)
	amount = ValidAmount(amount)
	if not accountGang or not amount then return end
	if not GangaccountGangs[accountGang] then
		GangaccountGangs[accountGang] = 0
	end

	GangaccountGangs[accountGang] = GangaccountGangs[accountGang] + amount
	SaveAccount(accountGang)
end)

-- Server side only, NOT callable from a client
AddEventHandler("qbr-gangmenu:server:removeaccountGangMoney", function(accountGang, amount)
	amount = ValidAmount(amount)
	if not accountGang or not amount then return end
	if not GangaccountGangs[accountGang] then
		GangaccountGangs[accountGang] = 0
	end

	if GangaccountGangs[accountGang] >= amount then
		GangaccountGangs[accountGang] = GangaccountGangs[accountGang] - amount
	end

	SaveAccount(accountGang)
end)

-- A player can only read the balance of his own gang
exports['qbr-core']:CreateCallback('qbr-gangmenu:server:GetAccount', function(source, cb)
	local Player = exports['qbr-core']:GetPlayer(source)
	if not Player then return cb(0) end
	cb(GetaccountGang(Player.PlayerData.gang.name))
end)

-- Export
function GetaccountGang(accountGang)
	return GangaccountGangs[accountGang] or 0
end

-- Get Employees (only for the boss, and only for his own gang)
exports['qbr-core']:CreateCallback('qbr-gangmenu:server:GetEmployees', function(source, cb)
	local Boss = GetBossPlayer(source)
	if not Boss then return cb({}) end
	local gangname = Boss.PlayerData.gang.name
	local employees = {}
	if not GangaccountGangs[gangname] then
		GangaccountGangs[gangname] = 0
	end
	local players = MySQL.query.await("SELECT citizenid, gang, charinfo FROM `players` WHERE JSON_UNQUOTE(JSON_EXTRACT(`gang`, '$.name')) = ?", { gangname })
	if players and players[1] ~= nil then
		for key, value in pairs(players) do
			local isOnline = exports['qbr-core']:GetPlayerByCitizenId(value.citizenid)

			if isOnline then
				employees[#employees+1] = {
				empSource = isOnline.PlayerData.citizenid,
				grade = isOnline.PlayerData.gang.grade,
				isboss = isOnline.PlayerData.gang.isboss,
				name = '🟢' .. isOnline.PlayerData.charinfo.firstname .. ' ' .. isOnline.PlayerData.charinfo.lastname
				}
			else
				local gangData = json.decode(value.gang)
				local charinfo = json.decode(value.charinfo)
				employees[#employees+1] = {
				empSource = value.citizenid,
				grade = gangData.grade,
				isboss = gangData.isboss,
				name = '❌' .. charinfo.firstname .. ' ' .. charinfo.lastname
				}
			end
		end
	end
	cb(employees)
end)

-- Grade Change
RegisterNetEvent('qbr-gangmenu:server:GradeUpdate', function(data)
	local src = source
	local Player = GetBossPlayer(src)
	if not Player or type(data) ~= 'table' then return end
	local gang = Player.PlayerData.gang.name
	local Employee = exports['qbr-core']:GetPlayerByCitizenId(data.cid)
	local grade = tonumber(data.grado)
	grade = grade and tostring(math.floor(grade))
	local gangGrades = exports['qbr-core']:GetGangs()[gang].grades
	if Employee and Employee.PlayerData.gang.name == gang then
		if grade and gangGrades[grade] and Employee.Functions.SetGang(gang, grade) then
			NotifySuccess(src, "Promotion réussie !")
			TriggerClientEvent('QBCore:Notify', Employee.PlayerData.source, 9, "Vous avez été promu au grade " .. gangGrades[grade].name .. ".", 5000, 0, 'hud_textures', 'check', 'COLOR_WHITE')
		else
			NotifyError(src, "Ce grade n'existe pas.")
		end
	else
		NotifyError(src, "Ce civil n'est pas en ville.")
	end
	TriggerClientEvent('qbr-gangmenu:client:OpenMenu', src)
end)

-- Fire Member
RegisterNetEvent('qbr-gangmenu:server:FireMember', function(target)
	local src = source
	local Player = GetBossPlayer(src)
	if not Player or type(target) ~= 'string' then return end
	local gang = Player.PlayerData.gang.name
	local Employee = exports['qbr-core']:GetPlayerByCitizenId(target)
	if target == Player.PlayerData.citizenid then
		NotifyError(src, "Vous ne pouvez pas vous exclure vous-même du gang !")
	elseif Employee then
		if Employee.PlayerData.gang.name ~= gang then
			NotifyError(src, "Cette personne n'est pas dans votre gang.")
		elseif Employee.Functions.SetGang("none", '0') then
			TriggerEvent("qbr-log:server:CreateLog", "gangmenu", "Gang Fire", "orange", Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname .. ' successfully fired ' .. Employee.PlayerData.charinfo.firstname .. " " .. Employee.PlayerData.charinfo.lastname .. " (" .. gang .. ")", false)
			NotifySuccess(src, "Membre du gang renvoyé !")
			TriggerClientEvent('QBCore:Notify', Employee.PlayerData.source , 9, "Vous avez été exclu du gang !", 2000, 0, 'mp_lobby_textures', 'cross')
		else
			NotifyError(src, "Erreur.")
		end
	else
		local player = MySQL.query.await('SELECT * FROM players WHERE citizenid = ? LIMIT 1', {target})
		if player and player[1] ~= nil then
			local offlineGang = json.decode(player[1].gang)
			if not offlineGang or offlineGang.name ~= gang then
				NotifyError(src, "Cette personne n'est pas dans votre gang.")
			else
				local newGang = {}
				newGang.name = "none"
				newGang.label = "No Affiliation"
				newGang.payment = 0
				newGang.onduty = true
				newGang.isboss = false
				newGang.grade = {}
				newGang.grade.name = nil
				newGang.grade.level = 0
				MySQL.query.await('UPDATE players SET gang = ? WHERE citizenid = ?', {json.encode(newGang), target})
				local charinfo = json.decode(player[1].charinfo)
				NotifySuccess(src, "Membre du gang renvoyé !")
				TriggerEvent("qbr-log:server:CreateLog", "gangmenu", "Gang Fire", "orange", Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname .. ' successfully fired ' .. charinfo.firstname .. " " .. charinfo.lastname .. " (" .. gang .. ")", false)
			end
		else
			NotifyError(src, "Ce civil n'est pas en ville.")
		end
	end
	TriggerClientEvent('qbr-gangmenu:client:OpenMenu', src)
end)

-- Recruit Player
RegisterNetEvent('qbr-gangmenu:server:HireMember', function(recruit)
	local src = source
	local Player = GetBossPlayer(src)
	if not Player then return end
	local Target = exports['qbr-core']:GetPlayer(recruit)
	-- The target must be close to the boss, like in the hire menu list
	if Target and Target.PlayerData.source ~= src and #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(GetPlayerPed(Target.PlayerData.source))) < 10 then
		if Target.Functions.SetGang(Player.PlayerData.gang.name, 0) then
			NotifySuccess(src, "Vous avez embauché " .. (Target.PlayerData.charinfo.firstname .. ' ' .. Target.PlayerData.charinfo.lastname) .. " comme " .. Player.PlayerData.gang.label .. "")
			NotifySuccess(Target.PlayerData.source, "Vous avez été recruté comme " .. Player.PlayerData.gang.label .. "")
			TriggerEvent('qbr-log:server:CreateLog', 'gangmenu', 'Recruit', 'yellow', (Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname).. ' successfully recruited ' .. Target.PlayerData.charinfo.firstname .. ' ' .. Target.PlayerData.charinfo.lastname .. ' (' .. Player.PlayerData.gang.name .. ')', false)
		end
	end
	TriggerClientEvent('qbr-gangmenu:client:OpenMenu', src)
end)

-- Get closest player sv
exports['qbr-core']:CreateCallback('qbr-gangmenu:getplayers', function(source, cb)
	local src = source
	local players = {}
	local PlayerPed = GetPlayerPed(src)
	local pCoords = GetEntityCoords(PlayerPed)
	for k, v in pairs(exports['qbr-core']:GetPlayers()) do
		local targetped = GetPlayerPed(v)
		local tCoords = GetEntityCoords(targetped)
		local dist = #(pCoords - tCoords)
		if PlayerPed ~= targetped and dist < 10 then
			local ped = exports['qbr-core']:GetPlayer(v)
			players[#players+1] = {
			id = v,
			coords = GetEntityCoords(targetped),
			name = ped.PlayerData.charinfo.firstname .. " " .. ped.PlayerData.charinfo.lastname,
			citizenid = ped.PlayerData.citizenid,
			sources = GetPlayerPed(ped.PlayerData.source),
			sourceplayer = ped.PlayerData.source
			}
		end
	end
		table.sort(players, function(a, b)
			return a.name < b.name
		end)
	cb(players)
end)
