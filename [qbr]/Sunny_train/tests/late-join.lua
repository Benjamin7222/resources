local D = Sunny.Departures
local snapshot = { now = 1800000400, tz = 7200, list = { { id = 555, station = 'blackwater' } } }
local oldRequest, calls = Sunny.Request, 0
Sunny.Request = function(name)
    assert(name == 'departure:list')
    calls = calls + 1
    if calls == 1 then return { ok = false, error = 'Personnage non chargé' } end
    return { ok = true, data = snapshot }
end
local initial = THREADS[#THREADS].co
assert(coroutine.resume(initial)) -- délai initial
assert(coroutine.resume(initial)) -- premier refus serveur
assert(coroutine.status(initial) == 'suspended' and calls == 1, 'échec initial : une nouvelle tentative reste prévue')
assert(coroutine.resume(initial))
assert(coroutine.status(initial) == 'dead' and D.snapshot.list[1].id == 555, 'connexion tardive : liste récupérée au deuxième essai')
local count = #THREADS
NET['QBCore:Client:OnPlayerLoaded']()
NET['QBCore:Client:OnPlayerLoaded']()
assert(#THREADS == count + 1, 'chargement personnage : une seule synchronisation en cours')
local loaded = THREADS[#THREADS].co
assert(coroutine.resume(loaded))
assert(coroutine.resume(loaded))
assert(calls == 3, 'nouveau personnage : synchronisation déclenchée')
D.ApplySnapshot({ list = {}, now = 0, tz = 0 })
Sunny.Request = function(name)
    assert(name == 'tickets:office')
    return { ok = true, data = { live = snapshot, departures = { { id = 555 } } } }
end
local opened = false
Sunny.UI = { Open = function(view, data)
    assert(view == 'tickets' and data.departures[1].id == D.CurrentSnapshot().list[1].id,
        'ouverture guichet : tableau mis à jour avant affichage')
    opened = true
end }
Sunny.TicketOffice.Open('blackwater')
assert(coroutine.resume(THREADS[#THREADS].co))
assert(opened, 'guichet ouvert avec les départs existants malgré un cache vide')
Sunny.Request = oldRequest
print('==== 5 vérifications connexion tardive réussies ====')
