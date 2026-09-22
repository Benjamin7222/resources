local Accounts = {}

CreateThread(function()
	Wait(500)
	local bossmenu = MySQL.query.await('SELECT * FROM management_menu WHERE menu_type = "boss"', {})
	if not bossmenu then
		return
	end
	for k,v in pairs(bossmenu) do
		local k = tostring(v.job_name)
		local v = tonumber(v.amount)
		if k and v then
			Accounts[k] = v
		end
	end
end)

-- UTIL

-- Returns the player only if he is the boss of his job (checked server side, never trust the client)
local function GetBossPlayer(src)
	local Player = exports['qbr-core']:GetPlayer(src)
	if Player and Player.PlayerData.job and Player.PlayerData.job.isboss then
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
local function SaveAccount(job)
	MySQL.query.await('INSERT INTO management_menu (job_name, amount, menu_type) VALUES (?, ?, "boss") ON DUPLICATE KEY UPDATE amount = VALUES(amount)', { job, Accounts[job] })
end

local function NotifyError(src, text)
	TriggerClientEvent('QBCore:Notify', src, 9, text, 5000, 0, 'mp_lobby_textures', 'cross', 'COLOR_WHITE')
end

local function NotifySuccess(src, text)
	TriggerClientEvent('QBCore:Notify', src, 9, text, 5000, 0, 'hud_textures', 'check', 'COLOR_WHITE')
end

RegisterNetEvent("qbr-bossmenu:server:withdrawMoney", function(amount)
	local src = source
	local xPlayer = GetBossPlayer(src)
	if not xPlayer then return end
	local job = xPlayer.PlayerData.job.name
	amount = ValidAmount(amount)

	if not Accounts[job] then
		Accounts[job] = 0
	end

	if amount and Accounts[job] >= amount then
		Accounts[job] = Accounts[job] - amount
		xPlayer.Functions.AddMoney("cash", amount)
	else
		NotifyError(src, "Montant invalide !")
		TriggerClientEvent('qbr-bossmenu:client:OpenMenu', src)
		return
	end

	SaveAccount(job)
	TriggerEvent('qbr-log:server:CreateLog', 'bossmenu', 'Withdraw Money', "blue", xPlayer.PlayerData.name.. "Withdrawal $" .. amount .. ' (' .. job .. ')', true)
	NotifySuccess(src, "Vous avez retiré : $" ..amount)
	TriggerClientEvent('qbr-bossmenu:client:OpenMenu', src)
end)

RegisterNetEvent("qbr-bossmenu:server:depositMoney", function(amount)
	local src = source
	local xPlayer = GetBossPlayer(src)
	if not xPlayer then return end
	local job = xPlayer.PlayerData.job.name
	amount = ValidAmount(amount)

	if not Accounts[job] then
		Accounts[job] = 0
	end

	if amount and xPlayer.Functions.RemoveMoney("cash", amount) then
		Accounts[job] = Accounts[job] + amount
	else
		NotifyError(src, "Montant invalide !")
		TriggerClientEvent('qbr-bossmenu:client:OpenMenu', src)
		return
	end

	SaveAccount(job)
	TriggerEvent('qbr-log:server:CreateLog', 'bossmenu', 'Deposit Money', "blue", xPlayer.PlayerData.name.. "Deposit $" .. amount .. ' (' .. job .. ')', true)
	NotifySuccess(src, "Vous avez déposé : $" ..amount)
	TriggerClientEvent('qbr-bossmenu:client:OpenMenu', src)
end)

-- Server side only (used by other resources with TriggerEvent), NOT callable from a client
AddEventHandler("qbr-bossmenu:server:addAccountMoney", function(account, amount)
	amount = ValidAmount(amount)
	if not account or not amount then return end
	if not Accounts[account] then
		Accounts[account] = 0
	end

	Accounts[account] = Accounts[account] + amount
	SaveAccount(account)
end)

-- Server side only, NOT callable from a client
AddEventHandler("qbr-bossmenu:server:removeAccountMoney", function(account, amount)
	amount = ValidAmount(amount)
	if not account or not amount then return end
	if not Accounts[account] then
		Accounts[account] = 0
	end

	if Accounts[account] >= amount then
		Accounts[account] = Accounts[account] - amount
	end

	SaveAccount(account)
end)

-- A player can only read the balance of his own job
exports['qbr-core']:CreateCallback('qbr-bossmenu:server:GetAccount', function(source, cb)
	local Player = exports['qbr-core']:GetPlayer(source)
	if not Player then return cb(0) end
	cb(GetAccount(Player.PlayerData.job.name))
end)

-- Export
function GetAccount(account)
	return Accounts[account] or 0
end

-- Get Employees (only for the boss, and only for his own job)
exports['qbr-core']:CreateCallback('qbr-bossmenu:server:GetEmployees', function(source, cb)
	local Boss = GetBossPlayer(source)
	if not Boss then return cb({}) end
	local jobname = Boss.PlayerData.job.name
	local employees = {}
	if not Accounts[jobname] then
		Accounts[jobname] = 0
	end
	local players = MySQL.query.await("SELECT citizenid, job, charinfo FROM `players` WHERE JSON_UNQUOTE(JSON_EXTRACT(`job`, '$.name')) = ?", { jobname })
	if players and players[1] ~= nil then
		for key, value in pairs(players) do
			local isOnline = exports['qbr-core']:GetPlayerByCitizenId(value.citizenid)

			if isOnline then
				employees[#employees+1] = {
				empSource = isOnline.PlayerData.citizenid,
				grade = isOnline.PlayerData.job.grade,
				isboss = isOnline.PlayerData.job.isboss,
				name = '🟢 ' .. isOnline.PlayerData.charinfo.firstname .. ' ' .. isOnline.PlayerData.charinfo.lastname
				}
			else
				local jobData = json.decode(value.job)
				local charinfo = json.decode(value.charinfo)
				employees[#employees+1] = {
				empSource = value.citizenid,
				grade = jobData.grade,
				isboss = jobData.isboss,
				name = '❌ ' .. charinfo.firstname .. ' ' .. charinfo.lastname
				}
			end
		end
		table.sort(employees, function(a, b)
            return a.grade.level > b.grade.level
        end)
	end
	cb(employees)
end)

-- Grade Change
RegisterNetEvent('qbr-bossmenu:server:GradeUpdate', function(data)
	local src = source
	local Player = GetBossPlayer(src)
	if not Player or type(data) ~= 'table' then return end
	local job = Player.PlayerData.job.name
	local Employee = exports['qbr-core']:GetPlayerByCitizenId(data.cid)
	local grade = tonumber(data.grado)
	grade = grade and tostring(math.floor(grade))
	local jobGrades = exports['qbr-core']:GetJobs()[job].grades
	if Employee and Employee.PlayerData.job.name == job then
		if grade and jobGrades[grade] and Employee.Functions.SetJob(job, grade) then
			NotifySuccess(src, "Promotion réussie !")
			TriggerClientEvent('QBCore:Notify', Employee.PlayerData.source, 9, "Vous avez été promu au grade " .. jobGrades[grade].name .. ".", 5000, 0, 'hud_textures', 'check')
		else
			NotifyError(src, "Ce grade n'existe pas.")
		end
	else
		NotifyError(src, "Ce civil n'est pas en ville.")
	end
	TriggerClientEvent('qbr-bossmenu:client:OpenMenu', src)
end)

-- Fire Employee
RegisterNetEvent('qbr-bossmenu:server:FireEmployee', function(target)
	local src = source
	local Player = GetBossPlayer(src)
	if not Player or type(target) ~= 'string' then return end
	local job = Player.PlayerData.job.name
	local Employee = exports['qbr-core']:GetPlayerByCitizenId(target)
	if target == Player.PlayerData.citizenid then
		NotifyError(src, "Vous ne pouvez pas vous licencier vous-même")
	elseif Employee then
		if Employee.PlayerData.job.name ~= job then
			NotifyError(src, "Cette personne ne travaille pas pour vous.")
		elseif Employee.Functions.SetJob("unemployed", '0') then
			TriggerEvent("qbr-log:server:CreateLog", "bossmenu", "Job Fire", "red", Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname .. ' successfully fired ' .. Employee.PlayerData.charinfo.firstname .. " " .. Employee.PlayerData.charinfo.lastname .. " (" .. job .. ")", false)
			NotifySuccess(src, "Employé licencié !")
			TriggerClientEvent('QBCore:Notify', Employee.PlayerData.source , 9, "Vous avez été licencié ! Bonne chance.", 5000, 0, 'mp_lobby_textures', 'cross', 'COLOR_WHITE')
		else
			NotifyError(src, "Erreur..")
		end
	else
		local player = MySQL.query.await('SELECT * FROM players WHERE citizenid = ? LIMIT 1', { target })
		if player and player[1] ~= nil then
			local offlineJob = json.decode(player[1].job)
			if not offlineJob or offlineJob.name ~= job then
				NotifyError(src, "Cette personne ne travaille pas pour vous.")
			else
				local unemployed = exports['qbr-core']:GetJobs()['unemployed']
				local newJob = {}
				newJob.name = "unemployed"
				newJob.label = unemployed.label
				newJob.payment = unemployed.grades['0'].payment
				newJob.onduty = true
				newJob.isboss = false
				newJob.grade = {}
				newJob.grade.name = unemployed.grades['0'].name
				newJob.grade.level = 0
				MySQL.query.await('UPDATE players SET job = ? WHERE citizenid = ?', { json.encode(newJob), target })
				local charinfo = json.decode(player[1].charinfo)
				NotifySuccess(src, "Employé licencié !")
				TriggerEvent("qbr-log:server:CreateLog", "bossmenu", "Job Fire", "red", Player.PlayerData.charinfo.firstname .. " " .. Player.PlayerData.charinfo.lastname .. ' successfully fired ' .. charinfo.firstname .. " " .. charinfo.lastname .. " (" .. job .. ")", false)
			end
		else
			NotifyError(src, "Ce civil n'est pas en ville.")
		end
	end
	TriggerClientEvent('qbr-bossmenu:client:OpenMenu', src)
end)

-- Recruit Player
RegisterNetEvent('qbr-bossmenu:server:HireEmployee', function(recruit)
	local src = source
	local Player = GetBossPlayer(src)
	if not Player then return end
	local Target = exports['qbr-core']:GetPlayer(recruit)
	-- The target must be close to the boss, like in the hire menu list
	if Target and Target.PlayerData.source ~= src and #(GetEntityCoords(GetPlayerPed(src)) - GetEntityCoords(GetPlayerPed(Target.PlayerData.source))) < 10 then
		if Target.Functions.SetJob(Player.PlayerData.job.name, 0) then
			NotifySuccess(src, "Vous avez embauché " .. (Target.PlayerData.charinfo.firstname .. ' ' .. Target.PlayerData.charinfo.lastname) .. " comme " .. Player.PlayerData.job.label .. "")
			NotifySuccess(Target.PlayerData.source, "Vous avez été embauché comme " .. Player.PlayerData.job.label .. "")
			TriggerEvent('qbr-log:server:CreateLog', 'bossmenu', 'Recruit', "lightgreen", (Player.PlayerData.charinfo.firstname .. ' ' .. Player.PlayerData.charinfo.lastname).. " successfully recruited " .. (Target.PlayerData.charinfo.firstname .. ' ' .. Target.PlayerData.charinfo.lastname) .. ' (' .. Player.PlayerData.job.name .. ')', true)
		end
	end
	TriggerClientEvent('qbr-bossmenu:client:OpenMenu', src)
end)

-- Get closest player sv
exports['qbr-core']:CreateCallback('qbr-bossmenu:getplayers', function(source, cb)
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
