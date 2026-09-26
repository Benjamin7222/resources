-- Une destination annoncée ne doit pas immobiliser une circulation libre.
local M, T = Sunny.Missions, Sunny.Train
local hud, notices, locks, speed = nil, 0, 0, 0
PlayerPedId = function() return 'ped1' end
PEDS[1].pos = vector3(100, 100, 0)
T.GetSpeed = function() return speed end
T.IsDriver = function() return true end
T.Lock = function() locks = locks + 1 end
Sunny.Notify = function() notices = notices + 1 end
Sunny.UI.Hud = function(data) hud = data end
Sunny.Junctions.HudInfo = function() return nil end
M.run = {
    id = 999, free = true, state = 'enroute', nextIndex = 2,
    trainLabel = 'Fret', routeLabel = 'Saint Denis → Annesburg',
    needsCoal = true, coal = 38,
    stations = {
        { label = 'Saint Denis', platform = { x = 0, y = 0, z = 0 }, radius = 30 },
        { label = 'Annesburg', platform = { x = 100, y = 100, z = 0 }, radius = 30 },
    },
}
M.Tick()
assert(M.run.state == 'enroute' and M.run.destinationReached and locks == 0, 'arrêt à destination sans immobilisation ni fin forcée')
assert(hud.free == true and hud.coal == 38, 'mode libre et charbon transmis au HUD')
M.Tick()
assert(notices == 1, 'arrivée annoncée une seule fois')
PEDS[1].pos = vector3(2000, 100, 0)
speed = 10
M.Tick()
assert(M.run.state == 'enroute' and locks == 0 and hud.speed > 0, 'poursuite vers une autre ville autorisée')
M.Clear()
assert(hud == nil, 'plaque masquée à la fin du voyage')
print('==== 5 vérifications circulation libre réussies ====')
