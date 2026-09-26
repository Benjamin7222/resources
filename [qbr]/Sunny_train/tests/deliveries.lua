local passed = 0
local function check(value, label)
    assert(value, label)
    passed = passed + 1
    print('  [OK] ' .. label)
end
local function req(src, name, payload)
    NOW_MS = NOW_MS + 3100
    FireServer('sunny_train:server:request', src, NOW_MS, name, payload or {})
    return LOG.responses[src]
end
Advance(1)
check(Sunny.Srv.ready and #Sunny.Utils.ValidateConfig() == 0, 'configuration de production valide')
check(Config.Deliveries.cooldownScope == 'company', 'cooldown global par défaut')
local S, Runs, D = Config.Stations, Sunny.Runs, Sunny.Deliveries
local veg, meat = 'delivery_farm_vegetables', 'delivery_butcher_meat'
local train = 'western_freight'
local hold = Sunny.Hold.Id(train)
local function stock(item, amount) assert(Sunny.Hold.Put(hold, { { item = item, amount = amount } }, 50)) end
local function count(item) return Sunny.Hold.Count(Sunny.Hold.Read(hold), item) end
MakePlayer(1, 'DRIVER_A', 'chemindefer', 5, 0, S.saint_denis.office.coords)
MakePlayer(2, 'DRIVER_B', 'chemindefer', 5, 0, S.saint_denis.office.coords)
MakePlayer(3, 'CIVIL', 'unemployed', 0, 0, S.saint_denis.office.coords)
local payload = { station = 'saint_denis', train = train, mission = veg, reward = 999999 }
check(not req(3, 'run:start', payload).ok, 'civil refusé')
local board = req(1, 'missions:board', { station = 'saint_denis' })
check(board.ok and board.data.deliveries and #board.data.missions == 2, 'deux catégories de livraison proposées')
local available = false
for _, t in ipairs(board.data.trains) do if t.key == train then available = t.available end end
check(available, 'train de fret initial disponible à Saint Denis')
check(not req(1, 'run:start', payload).ok and D.Remaining(1, Config.Missions[veg]) == 0, 'charbon absent : aucun cooldown')
stock('train_coal', 100)
check(not req(1, 'run:start', payload).ok and D.Remaining(1, Config.Missions[veg]) == 0, 'cargaison absente : aucun cooldown')
stock('train_crate_corn', 40)
stock('animal_meat', 40)
for key, s in pairs(S) do
    if key ~= 'saint_denis' then
        PEDS[1].pos = Sunny.Utils.StaffPoints(s)[1].coords
        check(not req(1, 'run:start', { station = key, train = train, mission = veg }).ok, 'départ refusé à ' .. key)
    end
end
PEDS[1].pos = S.saint_denis.office.coords
local r = req(1, 'run:start', payload)
check(r.ok, 'contrat légumes signé à Saint Denis')
check(count('train_crate_corn') == 20, 'cargaison prélevée une fois')
check(D.Remaining(2, Config.Missions[veg]) > 7100, 'second joueur soumis aux deux heures globales')
check(D.Remaining(2, Config.Missions[meat]) == 0, 'viande indépendante des légumes')
local nested = nil
-- La réservation globale SQL refuse également une deuxième prise directe.
check(not D.Claim(2, Config.Missions[veg]), 'réservation SQL conditionnelle refuse un concurrent')
req(1, 'run:cancel')
check(count('train_crate_corn') == 40, 'annulation avant départ restitue le chargement')
check(not req(2, 'run:start', payload).ok, 'annuler ne permet pas de contourner le délai global')
board = req(2, 'missions:board', { station = 'saint_denis' })
local cooldown = 0
for _, m in ipairs(board.data.missions) do if m.key == veg then cooldown = m.cooldown end end
check(cooldown > 7100, 'délai communiqué au registre du second joueur')
-- Réinitialiser les états mémoire ne doit pas réinitialiser les délais SQL.
Runs.cooldowns = {}
check(D.Remaining(2, Config.Missions[veg]) > 7100, 'délai lu en base, indépendant des cooldowns en mémoire')
local mission = Config.Missions[meat]
mission.allowedJobs = { other_company = 0 }
check(not req(2, 'run:start', { station = 'saint_denis', train = train, mission = meat }).ok, 'restriction de job appliquée côté serveur')
mission.allowedJobs = nil
-- Simuler un second départ pendant l'attente SQL du wagon.
local read = Sunny.Hold.Read
Sunny.Hold.Read = function(id)
    Sunny.Hold.Read = read
    nested = req(2, 'run:startFree', { station = 'saint_denis', train = train, destination = 'annesburg', delay = 0 })
    return read(id)
end
r = req(1, 'run:start', { station = 'saint_denis', train = train, mission = meat })
Sunny.Hold.Read = read
check(r.ok and nested and not nested.ok, 'réservation train couvre aussi un voyage concurrent pendant SQL')
local run = Runs.Get(1)
PEDS[1].pos = S.saint_denis.depot.coords
local before = DB.nextDeparture
check(req(1, 'run:spawned', { runId = run.id, netId = 999 }).ok, 'mise en voie de la livraison')
check(DB.nextDeparture == before, 'aucun départ voyageurs supplémentaire pour le fret')
-- Parcours complet avec temps et positions serveur, puis paiement réel.
run.departed = true
for i = 2, #Config.Routes[run.route].stations do
    local stop = Config.Routes[run.route].stations[i]
    NOW_MS = NOW_MS + 600000
    PEDS[1].pos = S[stop.id].platform.coords
    check(req(1, 'run:arrive', { runId = run.id, index = i }).ok, 'arrivée à ' .. stop.id)
    if run.state == 'at_station' then
        NOW_MS = NOW_MS + 60000
        assert(req(1, 'run:depart', { runId = run.id }).ok)
    end
end
local wear, duplicate = Sunny.Fleet.Wear, nil
Sunny.Fleet.Wear = function(...)
    duplicate = req(1, 'run:finish', { runId = run.id })
    return wear(...)
end
r = req(1, 'run:finish', { runId = run.id })
Sunny.Fleet.Wear = wear
check(duplicate and not duplicate.ok, 'paiement concurrent refusé pendant la sauvegarde SQL')
check(r.ok and r.data.reward == 450 and PLAYERS[1].PlayerData.money.cash == 450, 'prix final configuré payé au terminus')
check(not req(1, 'run:finish', { runId = run.id }).ok, 'impossible de toucher deux fois la prime')
NOW_MS = NOW_MS + 7200000
PEDS[2].pos = S.saint_denis.office.coords
check(req(2, 'run:start', payload).ok, 'catégorie à nouveau disponible pour un autre joueur après deux heures')
print(('==== %d vérifications livraisons réussies ===='):format(passed))
