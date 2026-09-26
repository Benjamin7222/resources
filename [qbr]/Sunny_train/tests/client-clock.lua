-- Les horloges avancent même si aucune liste de départs ne change.
SendNUIMessage = function() end
PlaySoundFrontend = function() end
local events = NET
events['sunny_train:client:departures']({ list = {}, now = 1800000000, tz = 7200 })
NOW_MS = NOW_MS + 120000
local current = Sunny.Departures.CurrentSnapshot()
assert(current.now == 1800000120, 'rouvrir le registre doit conserver les deux minutes écoulées')
assert(current.tz == 7200, 'fuseau conservé')
assert(Sunny.Departures.snapshot.now == 1800000000, 'snapshot source inchangé')
events['sunny_train:client:departures']({ list = {}, now = 1800000200, tz = 3600 })
NOW_MS = NOW_MS + 5000
assert(Sunny.Departures.CurrentSnapshot().now == 1800000205, 'nouvelle synchronisation')
print('==== 4 vérifications horloge client réussies ====')
