local passed = 0
local function check(value, label)
    assert(value, label)
    passed = passed + 1
    print('  [OK] ' .. label)
end
local nextHandle, activeGroups, paused, driver = 0, {}, false, true
local held, tapped = {}, nil
local keys, labels = {}, {}
Citizen = {
    ResultAsInteger = function() return 0 end,
    InvokeNative = function(hash, ...)
        local args = { ... }
        if hash == 0x04F97DE45A519419 then nextHandle = nextHandle + 1; return nextHandle end
        if hash == 0xB5352B7494A08258 then keys[args[1]] = args[2] end
        if hash == 0x5DD02A8318420DD7 then labels[args[1]] = args[2] end
        if hash == 0xC65A45D4453C2627 then activeGroups[#activeGroups + 1] = args[1] end
        return 0
    end,
}
GetRandomIntInRange = function() nextHandle = nextHandle + 1; return nextHandle end
IsPauseMenuActive = function() return paused end
IsControlJustPressed = function(_, key) return tapped == key end
IsControlPressed = function(_, key) return held[key] == true end
IsDisabledControlPressed = function() return false end
Sunny.VarString = function(s) return s end
Sunny.UI = { open = false }
Sunny.Actions = {}
Sunny.Missions = { Tick = function() end, OnTrainLost = function() end }
local D = Config.Driving
local Train, P, J = Sunny.Train, Sunny.Prompts, Sunny.Junctions
J.Scan = function() end
P.Create('junction', Config.Junctions.keys, 'Aiguillage', false)
Train.DrivingPrompts(true)
check(keys[P.list.drive_forward.prompt] == D.forwardKeys[1], 'prompt avancer utilise la touche configurée')
check(keys[P.list.drive_back.prompt] == D.backKeys[1], 'prompt freiner / reculer utilise la touche configurée')
check(keys[P.list.drive_cruise.prompt] == D.cruiseKey, 'prompt régulateur utilise la touche configurée')
check(keys[P.list.drive_whistle.prompt] == D.whistle.key, 'prompt sifflet utilise la touche configurée')
check(P.list.junction.group == P.list.drive_forward.group and #activeGroups == 1, 'un seul groupe natif pour la conduite et les aiguillages')
check(not P.list.junction.visible, 'aiguillage masqué sans intersection à portée')
J.current = { distance = 50, enabled = false, locked = false }
Train.DrivingPrompts(true)
check(P.list.junction.visible, 'aiguillage visible à proximité')
J.pending = true
Train.DrivingPrompts(true)
check(not P.list.junction.visible, 'aiguillage masqué pendant la requête serveur')
J.pending = false
ENTITIES[1234] = { pos = vector3(0, 0, 0) }
Train.entity, Train.netId, Train.maxSpeed = 1234, 77, 20.0
Train.IsDriver = function() return driver end
local switches, whistles = 0, {}
J.Toggle = function() switches = switches + 1 end
Train.Whistle = function(seq) whistles[#whistles + 1] = seq end
Train.StartLoop()
local loop = THREADS[#THREADS].co

--- Simule `ms` millisecondes de conduite avec les touches `hold` maintenues
--- et `tap` appuyée à la première frame.
local function drive(ms, hold, tap)
    held = {}
    for _, k in ipairs(hold or {}) do held[k] = true end
    tapped = tap
    local elapsed = 0
    repeat
        NOW_MS = NOW_MS + 100
        elapsed = elapsed + 100
        local ok, why = coroutine.resume(loop)
        assert(ok, why)
        tapped = nil
    until elapsed >= ms
end
drive(100) -- première itération : initialise l'horloge de la boucle

drive(2000, { D.forwardKeys[1] })
check(math.abs(Train.speed - 2 * D.acceleration) < 0.01 and Train.action == 'forward', 'W maintenu : le train accélère')
drive(5000, { D.forwardKeys[1] })
local cruising = Train.speed
drive(2000)
check(Train.speed < cruising and Train.action == 'coast', 'W relâché sans régulateur : le train ralentit sur l\'erre')
drive(100, {}, D.cruiseKey)
cruising = Train.speed
check(Train.cruise and labels[P.list.drive_cruise.prompt] == 'Régulateur : couper', 'régulateur activé à la vitesse actuelle')
drive(5000)
check(math.abs(Train.speed - cruising) < 0.001 and Train.StateLabel() == 'Régulateur', 'régulateur : vitesse maintenue sans touche')
drive(1000, { D.forwardKeys[1] })
check(Train.cruise and Train.cruiseSpeed > cruising, 'W avec régulateur : la vitesse maintenue augmente')
drive(100, { D.backKeys[1] })
check(not Train.cruise, 'S coupe le régulateur')
drive(3200, { D.backKeys[1] })
check(Train.speed == 0.0 and Train.action == 'brake', 'S maintenu : le train freine jusqu\'à l\'arrêt')
drive(D.reverseDelay + 1500, { D.backKeys[1] })
check(Train.speed < 0 and Train.action == 'reverse' and whistles[#whistles] == D.whistle.onReverse, 'S toujours maintenu à l\'arrêt : marche arrière (sifflet de recul)')
drive(20000, { D.backKeys[1] })
check(Train.speed >= -D.reverseMaxSpeed - 0.001 and Train.MovingDirection() == -1, 'marche arrière plafonnée')
drive(8000, { D.forwardKeys[1] })
check(Train.speed >= 0, 'W en marche arrière : freine puis repart en avant')
Train.speed = 0.0
drive(100, {}, D.cruiseKey)
check(not Train.cruise, 'régulateur refusé à l\'arrêt')
check(keys[P.list.drive_back.prompt] == 0x25493EB3, 'prompt S : contrôle véhicule sans axe partagé avec W')
Train.speed = 5.0
drive(1000, { D.backKeys[2] })
check(Train.speed < 5.0 and Train.action == 'brake', 'S (contrôle à pied) freine aussi')
Train.speed = 0.0
check(not P.list.drive_park.visible, 'remisage masqué hors voyage libre / hors gare')
Sunny.Missions.CanPark = function() return true end
drive(100)
check(P.list.drive_park.visible and keys[P.list.drive_park.prompt] == D.cabHoldKey, 'remisage proposé à l\'arrêt en gare (F maintenu)')
Sunny.Missions.CanPark = nil
drive(100)
check(not P.list.drive_park.visible, 'remisage masqué dès qu\'il n\'est plus possible')

Sunny.UI.open = true
local before = Train.speed
drive(1000, { D.forwardKeys[1] })
check(Train.speed <= before and not P.list.drive_forward.visible, 'registre ouvert : commandes et prompts suspendus')
Sunny.UI.open = false
paused = true
drive(100, {}, Config.Junctions.keys[2])
check(switches == 0 and not P.list.junction.visible, 'menu pause : aiguillage inactif et masqué')
paused = false
drive(100, {}, Config.Junctions.keys[2])
check(switches == 1 and P.list.junction.visible, 'changement de voie depuis le groupe de conduite')
local count = #whistles
drive(100, {}, D.whistle.key)
check(#whistles == count + 1 and whistles[#whistles] == D.whistle.manual, 'touche du prompt sifflet fonctionnelle')

drive(6000, { D.forwardKeys[1] })
Train.locked = true
drive(8000, { D.forwardKeys[1] })
check(not P.list.drive_forward.visible and Train.speed == 0.0, 'arrêt imposé : prompts masqués et traction refusée')
Train.locked = false
driver = false
drive(100)
check(not P.list.drive_forward.visible and not P.list.junction.visible, 'sortie de cabine masque les prompts')
Train.entity = nil
drive(100)
check(coroutine.status(loop) == 'dead', 'fin de conduite nettoie son affichage')
print(('==== %d vérifications conduite réussies ===='):format(passed))
