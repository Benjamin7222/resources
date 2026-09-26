-- Scénarios de test serveur Sunny_train
local passed, failed = 0, 0
local function check(cond, label, extra)
    if cond then passed = passed + 1; print('  [OK]   ' .. label)
    else failed = failed + 1; print('  [FAIL] ' .. label .. (extra and (' -> ' .. tostring(extra)) or '')) end
end

local reqId = 0
local function req(src, name, payload)
    NOW_MS = NOW_MS + 3100 -- respecte l'anti-spam
    reqId = reqId + 1
    LOG.responses[src] = nil
    FireServer('sunny_train:server:request', src, reqId, name, payload or {})
    return LOG.responses[src]
end
local function err(r) return r and r.error or 'nil' end

local S = Config.Stations
local function at(v, dx) return vector3(v.x + (dx or 0), v.y, v.z) end

-- Démarrage ---------------------------------------------------------------
Advance(1)
print('\n== Démarrage')
check(Sunny.Srv.ready, 'serveur prêt (BDD + validation config)')
check(ITEMS.train_ticket ~= nil, 'item billet déclaré via qbr-core AddItem')
check(USABLE.train_ticket ~= nil, 'item billet utilisable enregistré')
check(DB.fleet.western_passenger and DB.fleet.western_passenger.condition == 100, 'flotte initialisée en BDD')
check(#Sunny.Utils.ValidateConfig() == 0, 'configuration cohérente')

-- Mise en place v2 : la flotte de test possède tous les trains sauf le Pullman
-- (acheté plus loin), et chaque wagon contient du charbon.
check(not Config.Trains.handcar and Sunny.Fleet.IsOwned('western_freight') and not Sunny.Fleet.IsOwned('western_passenger'),
    'flotte de départ : seuls les trains « starter » sont possédés')
for key in pairs(Config.Trains) do
    if key ~= 'pullman_palace' then Sunny.Fleet.data[key].owned = true end
end
function Stock(trainKey, items) Sunny.Hold.Put(Sunny.Hold.Id(trainKey), items, 50) end
function HoldCount(trainKey, item) return Sunny.Hold.Count(Sunny.Hold.Read(Sunny.Hold.Id(trainKey)), item) end
for key, train in pairs(Config.Trains) do
    if train.fuel ~= false then Stock(key, { { item = 'train_coal', amount = 200 } }) end
end
check(HoldCount('western_passenger', 'train_coal') == 200, 'charbon chargé dans les wagons de test (coffres qbr-inventory)')


-- Joueurs -----------------------------------------------------------------
MakePlayer(1, 'DRV1', 'chemindefer', 5, 0, at(S.blackwater.office.coords))
MakePlayer(2, 'PAX2', 'unemployed', 0, 10, at(S.blackwater.ticketDesk.coords))
MakePlayer(3, 'CIV3', 'unemployed', 0, 0, vector3(0, 0, 0))

print('\n== Permissions & service')
local r = req(3, 'company:context')
check(r and not r.ok, 'un civil ne peut pas ouvrir le registre', err(r))
r = req(1, 'missions:board', { station = 'blackwater' })
check(r and r.ok, 'missions accessibles sans prise de service', err(r))
check(Sunny.Srv.IsOnService(1), 'cheminot toujours actif')
check(PLAYERS[1].PlayerData.job.onduty == false, 'actions ferroviaires indépendantes du duty QBR')
check(not Sunny.Srv.handlers['service:toggle'], 'aucune bascule de service exposée')
r = req(1, 'company:context')
check(r.ok and r.data.station == 'blackwater' and r.data.perms.maintenance and r.data.perms.restore, 'contexte : gare détectée + droits par grade')

print('\n== Tableau des missions')
r = req(1, 'missions:board', { station = 'blackwater' })
check(r.ok, 'tableau des missions', err(r))
local wp
for _, t in ipairs(r.data.trains) do if t.key == 'western_passenger' then wp = t end end
check(wp and wp.available, 'train western_passenger disponible')
local ht
for _, t in ipairs(r.data.trains) do if t.key == 'heartlands_express' then ht = t end end
check(ht and not ht.available, 'heartlands_express indisponible à Blackwater (aucun départ)')
r = req(1, 'missions:board', { station = 'saint_denis' })
check(not r.ok, 'tableau refusé loin du bureau demandé', err(r))

print('\n== Démarrage de run : validations')
r = req(1, 'run:start', { station = 'blackwater', train = 'western_passenger', mission = 'heartlands_mail' })
check(not r.ok, 'mission d\'une autre ligne refusée', err(r))
r = req(1, 'run:start', { station = 'blackwater', train = 'western_freight', mission = 'west_passengers' })
check(not r.ok, 'type de mission incompatible refusé', err(r))
r = req(1, 'run:start', { station = 'blackwater', train = 'western_passenger', mission = 'west_return_passengers' })
check(not r.ok and r.error:find('Riggs'), 'départ depuis une autre gare refusé', err(r))
-- Mission de test sur la Traversée de la Vallée (arrêt intermédiaire à Riggs Station).
Config.Missions.valley_test = { label = 'Test Vallée', type = 'passengers', route = 'valley', reward = 350, rewardPerStop = 50,
    timeLimit = 20, onTimeBonus = 75, hardTimeout = 45, canBeRobbed = true, robberyLoot = 1.0 }
PEDS[1].pos = at(S.valentine.office.coords)
r = req(1, 'run:start', { station = 'valentine', train = 'western_passenger', mission = 'valley_test', reward = 999999 })
check(r.ok and r.data.runId, 'ordre de mission signé (champ reward client ignoré)', err(r))
local runId = r.data.runId
local r2 = req(1, 'run:start', { station = 'valentine', train = 'western_passenger', mission = 'valley_test' })
check(not r2.ok, 'second run simultané refusé')

print('\n== Accès personnel au guichet')
MakePlayer(9, 'DRV9', 'Chemindefer', 0, 0, at(S.emerald_station.ticketDesk.coords))
local c9 = req(9, 'company:context')
check(c9.ok and c9.data.station == 'emerald_station', 'registre accessible depuis le guichet (gare sans bureau)', err(c9))
check(c9.ok, 'job « Chemindefer » reconnu (casse ignorée)')
local c3 = req(3, 'company:context')
check(not c3.ok and c3.error:find('unemployed') and c3.error:find('chemindefer'), 'refus explicite : job lu et jobs autorisés', err(c3))

print('\n== Mise en voie & progression')
ENTITIES[500] = { pos = at(S.valentine.depot.coords), vel = vector3(0, 0, 0) }
NETIDS[100] = 500
r = req(1, 'run:spawned', { runId = runId, netId = 100 })
check(r.ok and r.data.state == 'ready', 'train enregistré (entité vérifiée près du dépôt)', err(r))
check(#GlobalState.sunnyTrainRobbable == 1, 'convoi publié comme braquable')

local function moveDriver(pos) PEDS[1].pos = pos; ENTITIES[500].pos = pos; PEDS[1].vehicle = 500 end

r = req(1, 'run:arrive', { runId = runId, index = 2 })
check(not r.ok and r.error == Sunny.L('run_not_at_station'), 'arrivée refusée hors du quai', err(r))
moveDriver(at(S.riggs_station.platform.coords))
local flagsBefore = #LOG.flags
r = req(1, 'run:arrive', { runId = runId, index = 2 })
check(not r.ok and r.error == Sunny.L('run_too_fast'), 'téléportation détectée (temps de parcours impossible)', err(r))
check(#LOG.flags > flagsBefore, 'tentative journalisée')
Advance(65)
r = req(1, 'run:arrive', { runId = runId, index = 3 })
check(not r.ok, 'saut de gare refusé (mauvais index)')
r = req(1, 'run:arrive', { runId = runId, index = 2 })
check(r.ok and r.data.dwell == 45, 'arrêt à Riggs Station validé (arrêt 45 s)', err(r))
r = req(1, 'run:depart', { runId = runId })
check(not r.ok, 'départ anticipé refusé')
Advance(45)
r = req(1, 'run:depart', { runId = runId })
check(r.ok, 'départ autorisé après le temps d\'arrêt', err(r))
r = req(1, 'run:finish', { runId = runId })
check(not r.ok, 'fin de mission refusée avant le terminus')
moveDriver(at(S.blackwater.platform.coords))
Advance(40)
r = req(1, 'run:arrive', { runId = runId, index = 3 })
check(r.ok and r.data.terminus, 'terminus atteint', err(r))

print('\n== Fin de mission & prime serveur')
local cashBefore = PLAYERS[1].PlayerData.money.cash
r = req(1, 'run:finish', { runId = runId, reward = 1e9 })
local expected = 350 + 50 + 75
check(r.ok and r.data.reward == expected, ('prime calculée côté serveur = %d'):format(expected), r and r.data and r.data.reward)
check(PLAYERS[1].PlayerData.money.cash - cashBefore == expected, 'argent versé une seule fois')
r = req(1, 'run:finish', { runId = runId })
check(not r.ok, 'double validation refusée')
check(DB.fleet.western_passenger.condition == 94, 'usure du train appliquée (-6 %)', DB.fleet.western_passenger.condition)
check(not Sunny.Runs.IsTrainInUse('western_passenger'), 'train libéré')

print('\n== Événements forgés')
flagsBefore = #LOG.flags
LOG.responses[1] = nil
FireServer('sunny_train:server:request', 1, 999, 'giveMoney', { amount = 100000 })
check(LOG.responses[1] == nil and #LOG.flags > flagsBefore, 'requête inconnue ignorée et journalisée')
FireServer('sunny_train:server:request', 1, 'x', {}, {})
check(true, 'requête malformée ignorée sans erreur')
r = req(1, 'run:finish', { runId = 12345 })
check(not r.ok, 'fin de run arbitraire refusée')

print('\n== Billets')
local ticketDeparture = Sunny.Departures.Create({ station = 'blackwater', destination = 'annesburg', departAt = os.time() + 600, byCitizen = 'DRV1' })
r = req(2, 'tickets:office', { station = 'blackwater' })
check(r.ok and #r.data.departures == 1 and #r.data.departures[1].stops > 0, 'guichet : départ programmé et gares desservies', r and r.data and #r.data.departures)
MakePlayer(77, 'LATE77', 'unemployed', 0, 100, S.blackwater.ticketDesk.coords)
local late = req(77, 'tickets:office', { station = 'blackwater' })
check(late.ok and #late.data.departures == 1 and late.data.departures[1].id == ticketDeparture.id
    and late.data.live.list[1].id == ticketDeparture.id, 'nouveau joueur : billets et tableau déjà programmés renvoyés ensemble')
local U = Sunny.Utils
print('    Tarifs 3e classe depuis Saint Denis :')
for _, d in ipairs(U.Destinations('saint_denis')) do
    print(('      %-16s %6.1f km  $%5.2f  %s'):format(d.to, d.trip.km, U.TicketPrice('saint_denis', d.to, 'third'), U.TripLabel(d.trip)))
end
check(U.TicketPrice('saint_denis', 'annesburg', 'third') < U.TicketPrice('saint_denis', 'valentine', 'third'), 'Saint Denis : Annesburg moins cher que Valentine')
check(U.TicketPrice('saint_denis', 'valentine', 'third') < U.TicketPrice('saint_denis', 'blackwater', 'third'), 'Saint Denis : Valentine moins cher que Blackwater')
check(U.Trip('saint_denis', 'blackwater').connected and #U.Trip('saint_denis', 'blackwater').lines >= 2, 'Saint Denis → Blackwater passe par plusieurs lignes')
check(U.TicketPrice('blackwater', 'riggs_station', 'first') > U.TicketPrice('blackwater', 'riggs_station', 'third'), 'la classe multiplie le prix')
check(U.TicketPrice('annesburg', 'saint_denis', 'third') == U.TicketPrice('saint_denis', 'annesburg', 'third'), 'même prix dans les deux sens')
local sdbw = U.Trip('saint_denis', 'blackwater')
check(#sdbw.lines == 2, 'Saint Denis → Blackwater : 2 lignes (sans changement inutile) : ' .. U.TripLabel(sdbw))
check(U.LineCoversTrip('valley', sdbw) and U.LineCoversTrip('heartlands', sdbw), 'contrôle : billet valable sur chaque ligne du trajet')
check(U.LineCoversTrip('valley_return', sdbw) and U.LineCoversTrip('west_return', U.Trip('blackwater', 'riggs_station')), 'contrôle : valable aussi sur la ligne de sens inverse')
check(not U.LineCoversTrip('northern', sdbw), 'contrôle : non valable sur une ligne hors trajet')
r = req(2, 'tickets:buy', { departure = ticketDeparture.id, station = 'saint_denis', to = 'annesburg', class = 'third' })
check(not r.ok, 'achat refusé loin du guichet')
r = req(2, 'tickets:buy', { departure = ticketDeparture.id, station = 'blackwater', to = 'blackwater', class = 'third' })
check(not r.ok, 'billet vers sa propre gare refusé')
r = req(2, 'tickets:buy', { departure = ticketDeparture.id, station = 'blackwater', to = 'riggs_station', class = 'second', price = 0 })
check(r.ok, 'billet acheté', err(r))
local expected = U.TicketPrice('blackwater', 'riggs_station', 'second')
check(math.abs(PLAYERS[2].PlayerData.money.cash - (10 - expected)) < 0.001, ('prix serveur débité ($%.2f)'):format(expected), PLAYERS[2].PlayerData.money.cash)
check(r.data.ticket.routeLabel ~= '', 'lignes du trajet sur le billet : ' .. tostring(r.data.ticket.routeLabel))
local serial = r.data.ticket.serial
check(DB.tickets[serial] ~= nil, 'billet enregistré en BDD : ' .. tostring(serial))
check(DB.tickets[serial].departure_id == ticketDeparture.id and DB.tickets[serial].depart_at == ticketDeparture.departAt,
    'billet rattaché au départ en BDD')
check(DB.tickets[serial].expires_at == ticketDeparture.departAt + 10800, 'validité : 3 heures après le départ prévu')
local noDeparture = req(2, 'tickets:buy', { station = 'blackwater', to = 'riggs_station', class = 'third' })
check(not noDeparture.ok and noDeparture.error == Sunny.L('ticket_no_departure'), 'achat sans départ refusé')
local originalScalar = MySQL.scalar.await
local cashBeforeRace = PLAYERS[2].PlayerData.money.cash
MySQL.scalar.await = function(sql, p)
    local result = originalScalar(sql, p)
    if sql:find('SELECT COUNT') then ticketDeparture.status = 'cancelled' end
    return result
end
local race = req(2, 'tickets:buy', { departure = ticketDeparture.id, station = 'blackwater', to = 'riggs_station', class = 'third' })
MySQL.scalar.await = originalScalar
check(not race.ok and race.error == Sunny.L('ticket_no_departure') and PLAYERS[2].PlayerData.money.cash == cashBeforeRace,
    'départ annulé pendant lecture BDD : aucun débit')
ticketDeparture.status = 'departed'
local sold = req(2, 'tickets:buy', { departure = ticketDeparture.id, station = 'blackwater', to = 'riggs_station', class = 'third' })
check(not sold.ok and sold.error == Sunny.L('ticket_no_departure'), 'train parti : vente refusée')
ticketDeparture.status = 'scheduled'
local item = PLAYERS[2].PlayerData.items[1]
check(item and item.name == 'train_ticket' and item.info.serial == serial, 'item billet remis avec ses informations')
r = req(2, 'tickets:buy', { departure = ticketDeparture.id, station = 'blackwater', to = 'annesburg', class = 'first' })
check(not r.ok and r.error == Sunny.L('ticket_no_money'), ('argent insuffisant refusé (Annesburg 1re : $%.2f)'):format(U.TicketPrice('blackwater', 'annesburg', 'first')), err(r))

print('\n== Contrôle')
PEDS[1].pos = at(PEDS[2].pos, 1.5)
r = req(1, 'control:check', { target = 3 })
check(not r.ok, 'contrôle refusé si voyageur éloigné')
r = req(1, 'control:check', { target = 2 })
check(r.ok and #r.data.tickets == 1 and r.data.tickets[1].status == 'valid', 'billet valide détecté', err(r))
Sunny.Runs.byId[99999] = { src = 1, netId = 0, departureId = ticketDeparture.id + 1000 }
local mismatch = req(1, 'control:check', { target = 2 })
check(mismatch.ok and mismatch.data.tickets[1].warning and mismatch.data.tickets[1].warning:find('Billet pour le départ de'),
    'contrôle : avertissement pour un autre départ')
Sunny.Runs.byId[99999] = nil
r = req(2, 'control:check', { target = 1 })
check(not r.ok, 'un voyageur ne peut pas contrôler')
-- Le billet à retirer est au second emplacement, derrière un autre billet.
PLAYERS[2].PlayerData.items = {
    [1] = { name = 'train_ticket', amount = 1, slot = 1, info = { serial = 'OTHER' } },
    [2] = { name = 'train_ticket', amount = 1, slot = 2, info = item.info },
}
r = req(1, 'control:punch', { target = 2, serial = serial })
check(r.ok and r.data.ticket.status == 'used', 'billet poinçonné')
check(PLAYERS[2].PlayerData.items[2] == nil and PLAYERS[2].PlayerData.items[1].info.serial == 'OTHER',
    'poinçonnage : seul le billet sélectionné est retiré')
r = req(1, 'control:punch', { target = 2, serial = serial })
check(not r.ok, 'double compostage refusé')
PLAYERS[2].PlayerData.items = {}
PLAYERS[2].Functions.AddItem('train_ticket', 1, nil, item.info)
PLAYERS[2].Functions.AddItem('train_ticket', 1, nil, { serial = 'SP-ZZ0000', from = 'blackwater', to = 'valentine' })
PLAYERS[2].Functions.AddItem('train_ticket', 1, nil, { serial = serial, from = 'blackwater', to = 'valentine' })
r = req(1, 'control:check', { target = 2 })
local statuses = {}
for _, t in ipairs(r.data.tickets) do statuses[#statuses + 1] = t.status end
table.sort(statuses)
check(table.concat(statuses, ',') == 'forged,forged,used', 'faux billets détectés (inconnu + données modifiées)', table.concat(statuses, ','))
DB.tickets[serial].used_at = nil
DB.tickets[serial].expires_at = os.time() - 1
PLAYERS[2].PlayerData.items = { PLAYERS[2].PlayerData.items[1] }
r = req(1, 'control:check', { target = 2 })
check(r.data.tickets[1].status == 'expired', 'billet périmé détecté')
PLAYERS[3].PlayerData.items = {}
PEDS[3].pos = at(PEDS[1].pos, 1)
r = req(1, 'control:check', { target = 3 })
check(r.ok and #r.data.tickets == 0, 'absence de billet gérée')

print('\n== Maintenance')
PEDS[1].pos = at(S.blackwater.office.coords)
r = req(1, 'fleet:begin', { kind = 'repair', train = 'western_passenger', repair = 'routine' })
check(not r.ok and r.error == Sunny.L('maint_need_inspection'), 'réparation sans inspection refusée', err(r))
r = req(1, 'fleet:begin', { kind = 'inspect', train = 'western_passenger' })
check(r.ok, 'inspection commencée', err(r))
r = req(1, 'fleet:finish')
check(not r.ok, 'inspection instantanée refusée (durée serveur)')
r = req(1, 'fleet:begin', { kind = 'inspect', train = 'western_passenger' })
NOW_MS = NOW_MS + 6000
r = req(1, 'fleet:finish')
check(r.ok and r.data.report and #r.data.report == 5, 'rapport d\'inspection', err(r))
r = req(1, 'fleet:begin', { kind = 'repair', train = 'western_passenger', repair = 'routine' })
check(not r.ok and r.error:find('Charbon'), 'matériel manquant signalé', err(r))
PLAYERS[1].Functions.AddItem('coal', 2); PLAYERS[1].Functions.AddItem('metalscrap', 1)
r = req(1, 'fleet:begin', { kind = 'repair', train = 'western_passenger', repair = 'routine' })
check(r.ok, 'réparation commencée', err(r))
NOW_MS = NOW_MS + 8000
r = req(1, 'fleet:finish')
check(r.ok and r.data.train.condition == 100, 'réparation appliquée (94 -> 100)', err(r))
local left = 0
for _, it in pairs(PLAYERS[1].PlayerData.items) do left = left + it.amount end
check(left == 0, 'items consommés dans l\'inventaire existant')
PEDS[3].pos = at(S.blackwater.office.coords)
PLAYERS[3].PlayerData.job = { name = 'chemindefer', grade = { level = 0 }, onduty = true }
r = req(3, 'fleet:begin', { kind = 'inspect', train = 'western_passenger' })
check(not r.ok and r.error == Sunny.L('error_no_permission'), 'grade insuffisant pour la maintenance')
local Srv = Sunny.Srv
local function can(grade, action) PLAYERS[3].PlayerData.job.grade.level = grade return Srv.Can(3, action) end
check(can(0, 'drive') and can(0, 'control') and can(0, 'schedule'), 'grade 0 : service, conduite, contrôle')
check(not can(1, 'maintenance') and can(2, 'maintenance'), 'maintenance à partir du grade 2')
check(not can(3, 'restore') and can(4, 'restore') and can(5, 'restore'), 'remise en service : grade 4 et patron (5)')
PLAYERS[3].PlayerData.job = { name = 'unemployed', grade = { level = 0 }, onduty = true }
r = req(1, 'fleet:retire', { train = 'western_freight' })
check(r.ok and r.data.train.state == 'out_of_service', 'train retiré du service')
r = req(1, 'missions:board', { station = 'blackwater' })
local wf
for _, t in ipairs(r.data.trains) do if t.key == 'western_freight' then wf = t end end
check(wf and not wf.available, 'train hors service non sélectionnable')
r = req(1, 'run:start', { station = 'blackwater', train = 'western_freight', mission = 'west_freight' })
check(not r.ok, 'run refusé sur train hors service', err(r))
r = req(1, 'fleet:restore', { train = 'western_freight' })
check(r.ok and r.data.train.state == 'operational', 'train remis en service')

print('\n== Braquage')
r = req(1, 'run:start', { station = 'blackwater', train = 'western_passenger', mission = 'west_passengers' })
check(not r.ok and r.error:find('mission'), 'cooldown entre deux missions', err(r))
Advance(125)
r = req(1, 'run:start', { station = 'blackwater', train = 'western_passenger', mission = 'west_passengers' })
check(r.ok, 'nouvelle mission après cooldown', err(r))
runId = r.data.runId
ENTITIES[501] = { pos = at(S.blackwater.depot.coords), vel = vector3(0, 0, 0) }
NETIDS[101] = 501
r = req(1, 'run:spawned', { runId = runId, netId = 101 })
PEDS[1].pos = at(S.blackwater.depot.coords); PEDS[1].vehicle = 501
MakePlayer(6, 'ROB6', 'unemployed', 0, 0, at(S.blackwater.depot.coords, 4))
PEDS[6].weapon = GetHashKey('WEAPON_REVOLVER_CATTLEMAN')
r = req(6, 'robbery:start', { runId = runId })
check(not r.ok and r.error == Sunny.L('rob_min_police'), 'police insuffisante', err(r))
MakePlayer(4, 'POL4', 'police', 0, 0, vector3(0, 0, 0)); PLAYERS[4].PlayerData.job.onduty = true
MakePlayer(5, 'POL5', 'police', 0, 0, vector3(0, 0, 0)); PLAYERS[5].PlayerData.job.onduty = true
r = req(1, 'robbery:start', { runId = runId })
check(not r.ok, 'le conducteur ne peut pas braquer son convoi')
r = req(4, 'robbery:start', { runId = runId })
check(not r.ok, 'job blacklisté (police) refusé')
PEDS[6].weapon = GetHashKey('WEAPON_UNARMED')
r = req(6, 'robbery:start', { runId = runId })
check(not r.ok and r.error == Sunny.L('rob_need_weapon'), 'arme requise', err(r))
PEDS[6].weapon = GetHashKey('WEAPON_REVOLVER_CATTLEMAN')
ENTITIES[501].vel = vector3(10, 0, 0)
r = req(6, 'robbery:start', { runId = runId })
check(not r.ok and r.error == Sunny.L('rob_too_fast'), 'train en mouvement refusé', err(r))
ENTITIES[501].vel = vector3(0, 0, 0)
local dispatched = 0
for _, e in ipairs(LOG.client) do if e.name == 'sunny_train:client:dispatchFallback' then dispatched = dispatched + 1 end end
r = req(6, 'robbery:start', { runId = runId })
check(r.ok, 'braquage lancé', err(r))
check(Sunny.Runs.GetById(runId).state == 'robbery', 'run interrompu (état robbery)')
local after = 0
for _, e in ipairs(LOG.client) do if e.name == 'sunny_train:client:dispatchFallback' then after = after + 1 end end
check(after - dispatched == 2, 'dispatch transmis aux 2 policiers en service')
r = req(1, 'run:cancel')
check(not r.ok, 'abandon impossible pendant l\'attaque')
check(#GlobalState.sunnyTrainRobbable == 0, 'convoi retiré de la liste braquable')
local robberCash = PLAYERS[6].PlayerData.money.cash
Advance(95)
check(PLAYERS[6].PlayerData.money.cash > robberCash, 'butin versé au braqueur : $' .. (PLAYERS[6].PlayerData.money.cash - robberCash))
local run = Sunny.Runs.GetById(runId)
check(run and run.robbed and run.state == 'ready', 'run repris avec pénalité (mode penalty)')
local r3 = req(6, 'robbery:start', { runId = runId })
check(not r3.ok, 'convoi déjà dévalisé non rebraquable')

print('\n== Braquage avorté (braqueur hors zone)')
Sunny.Robbery.lastGlobal = 0
Sunny.Robbery.trainCooldowns = {}
run.robbed = false
r = req(6, 'robbery:start', { runId = runId })
check(r.ok, 'second braquage lancé (cooldowns réinitialisés pour le test)', err(r))
PEDS[6].pos = vector3(9999, 9999, 0)
local cash6 = PLAYERS[6].PlayerData.money.cash
Advance(3)
check(PLAYERS[6].PlayerData.money.cash == cash6 and Sunny.Runs.GetById(runId).state == 'ready', 'braquage annulé, aucun butin')

print('\n== Déconnexion')
Emit('playerDropped', 1)
check(Sunny.Runs.Get(1) == nil and not Sunny.Runs.IsTrainInUse('western_passenger'), 'run nettoyé à la déconnexion')
Advance(10)
check(ENTITIES[501] == nil, 'entité du train supprimée côté serveur (filet de sécurité)')
check(not Sunny.Runs.Get(1), 'aucun convoi conservé à la déconnexion')

print('\n== Watchdog')
MakePlayer(7, 'DRV7', 'chemindefer', 0, 0, at(S.blackwater.office.coords))

r = req(7, 'run:start', { station = 'blackwater', train = 'western_passenger', mission = 'west_passengers' })
check(r.ok, 'run assigné', err(r))
Advance(40)
check(Sunny.Runs.Get(7) == nil, 'run sans mise en voie annulé après spawnTimeout')

print('\n== Aiguillages')
MakePlayer(8, 'DRV8', 'chemindefer', 0, 0, at(S.blackwater.office.coords))

local oldWest = Sunny.Utils.ResolveHash('TRAINS_OLD_WEST01')
local jr = req(8, 'junction:set', { track = oldWest, index = 2, enabled = true })
check(not jr.ok and jr.error == Sunny.L('junction_no_run'), 'aiguillage refusé sans convoi en circulation', err(jr))
Sunny.Robbery.lastGlobal = 0
jr = req(8, 'run:start', { station = 'blackwater', train = 'western_passenger', mission = 'west_passengers' })
check(jr.ok, 'run pour tests aiguillage', err(jr))
local rid = jr.data.runId
ENTITIES[502] = { pos = at(S.blackwater.depot.coords), vel = vector3(0, 0, 0) }
NETIDS[102] = 502
PEDS[8].pos = at(S.blackwater.depot.coords); PEDS[8].vehicle = 502
req(8, 'run:spawned', { runId = rid, netId = 102 })
local before = #LOG.client
jr = req(8, 'junction:set', { track = oldWest, index = 2, enabled = true })
check(jr.ok, 'aiguillage basculé par le conducteur', err(jr))
local bc = 0
for i = before + 1, #LOG.client do local e = LOG.client[i] if e.name == 'sunny_train:client:junction' and e.target == -1 and e.args[3] == true then bc = bc + 1 end end
check(bc == 1, 'position diffusée à tous les joueurs')
jr = req(8, 'junction:set', { track = 123456, index = 2, enabled = true })
check(not jr.ok, 'voie inconnue refusée')
jr = req(8, 'junction:set', { track = oldWest, index = -3, enabled = true })
check(not jr.ok, 'index négatif refusé')
jr = req(8, 'junction:set', { track = oldWest, index = 1.5, enabled = true })
check(not jr.ok, 'index non entier refusé')
PEDS[8].vehicle = 0
jr = req(8, 'junction:set', { track = oldWest, index = 2, enabled = false })
check(not jr.ok, 'refusé hors de la cabine')
jr = req(3, 'junction:set', { track = oldWest, index = 2, enabled = false })
check(not jr.ok, 'un autre joueur ne peut pas manoeuvrer')
jr = req(1, 'junction:state')
check(jr.ok and #jr.data == 1 and jr.data[1].enabled == true and jr.data[1].index == 2, 'état restitué aux joueurs qui se connectent')
check(Sunny.Utils.ResolveHash('0x10461E19') == 0x10461E19 and Sunny.Utils.ResolveHash(0x8EAC625C) == Sunny.Utils.Signed32(0x8EAC625C), 'résolution des hash de train (hex / nombre)')

print('\n== Voyage libre')
local A = Sunny.Departures
local function lastClient(name, target)
    for i = #LOG.client, 1, -1 do
        local e = LOG.client[i]
        if e.name == name and (target == nil or e.target == target) then return e end
    end
end
MakePlayer(10, 'DRV10', 'chemindefer', 0, 0, at(S.valentine.ticketDesk.coords))
local fr = req(10, 'free:board', { station = 'valentine' })
check(fr.ok, 'voyage accessible dès le grade 0 sans prise de service', err(fr))

fr = req(10, 'free:board', { station = 'valentine' })
check(fr.ok and fr.data.hasDepot and #fr.data.destinations == 6, 'voyage : 6 destinations reliées depuis Valentine', err(fr))
local freight
for _, t in ipairs(fr.data.trains) do if t.key == 'lemoyne_freight' then freight = t end end
check(freight and freight.available, 'tous les trains disponibles pour un voyage (y compris fret)')
PEDS[10].pos = at(S.emerald_station.ticketDesk.coords)
local fe = req(10, 'run:startFree', { station = 'emerald_station', train = 'heartlands_express', destination = 'saint_denis', delay = 0 })
check(not fe.ok and fe.error == Sunny.L('free_no_depot'), 'gare sans dépôt : mise en voie refusée', err(fe))
PEDS[10].pos = at(S.valentine.ticketDesk.coords)
fe = req(10, 'run:startFree', { station = 'valentine', train = 'heartlands_express', destination = 'valentine', delay = 0 })
check(not fe.ok, 'destination identique refusée')
fe = req(10, 'run:startFree', { station = 'valentine', train = 'heartlands_express', destination = 'saint_denis', delay = 3 })
check(not fe.ok, 'délai d\'annonce hors liste refusé')
fe = req(10, 'run:startFree', { station = 'valentine', train = 'heartlands_express', destination = 'saint_denis', delay = 5, reward = 5000 })
check(fe.ok and fe.data.free and #fe.data.stations == 4, 'voyage libre Valentine → Saint Denis (4 gares sur le chemin)', err(fe))
local fid = fe.data.runId
ENTITIES[510] = { pos = at(S.valentine.depot.coords), vel = vector3(0, 0, 0) }
NETIDS[110] = 510
PEDS[10].pos = at(S.valentine.depot.coords); PEDS[10].vehicle = 510
local before = #LOG.client
fe = req(10, 'run:spawned', { runId = fid, netId = 110 })
check(fe.ok and fe.data.free and fe.data.destinationLabel == 'Saint Denis', 'train mis en voie (voyage)', err(fe))
local notice = lastClient('sunny_train:client:departureNotice', -1)
check(notice and notice.args[1].destinationLabel == 'Saint Denis' and notice.args[1].stationLabel == 'Valentine'
    and notice.args[1].departAt - notice.args[1].now >= 295 and notice.args[1].train == Config.Trains.heartlands_express.label, 'avis aux voyageurs envoyé à tous (départ dans 5 min)')
local mine
for _, e in ipairs(A.Snapshot().list) do if e.destination == 'saint_denis' and e.station == 'valentine' then mine = e end end
check(mine and mine.atPlatform and mine.by ~= nil, 'annonce en direct : embarquement, mécanicien indiqué')
fe = req(10, 'run:departed', { runId = fid })
for _, e in ipairs(A.Snapshot().list) do if e.id == mine.id then mine = e end end
check(fe.ok and mine.departed, 'départ effectif : le tableau passe à « Parti »')
local cash10 = PLAYERS[10].PlayerData.money.cash
PEDS[10].pos = vector3(900, 300, 90)
fe = req(10, 'run:finish', { runId = fid })
check(not fe.ok and Sunny.Runs.IsTrainInUse('heartlands_express'), 'remisage refusé en pleine voie', err(fe))
PEDS[10].pos = at(S.saint_denis.platform.coords)
NOW_MS = NOW_MS + 3100 -- respecte l'anti-spam
fe = req(10, 'run:finish', { runId = fid })
check(fe.ok and fe.data.reward == 0 and PLAYERS[10].PlayerData.money.cash == cash10, 'remisage au quai d\'une gare, sans prime (champ reward ignoré)', err(fe))
check(not Sunny.Runs.IsTrainInUse('heartlands_express') and (Sunny.Runs.cooldowns['DRV10'] or 0) <= os.time(), 'train libéré, aucune pénalité')

print('\n== Départs programmés')
PEDS[10].pos = at(S.valentine.ticketDesk.coords)
local slot = A.Slots()[1].at
local an = req(10, 'departure:create', { station = 'valentine', destination = 'annesburg', departAt = slot })
check(an.ok, 'grade 0 : programmation sans train précisé', err(an))
an = req(10, 'departure:create', { station = 'valentine', destination = 'rhodes', departAt = slot })
check(not an.ok and an.error == Sunny.L('dep_slot_taken', A.TimeLabel(slot)), 'créneau déjà pris refusé', err(an))
an = req(10, 'departure:create', { station = 'valentine', destination = 'rhodes', departAt = slot + 1 })
check(not an.ok, 'heure hors grille refusée')
an = req(10, 'departure:create', { station = 'saint_denis', destination = 'rhodes', departAt = slot })
check(not an.ok and an.error == Sunny.L('error_too_far'), 'programmation refusée loin de la gare')
an = req(3, 'departure:create', { station = 'valentine', destination = 'rhodes', departAt = slot })
check(not an.ok, 'un civil ne peut pas programmer')
local list = req(3, 'departure:list')
check(list.ok and #list.data.list >= 2, 'liste publique consultable par tous')
local scheduled
for _, d in pairs(A.list) do if d.by == 'DRV10' and not d.auto then scheduled = d end end
local scheduledId = scheduled.id
A.list = {}; A.byRun = {}; A.Load()
scheduled = A.Get(scheduledId)
check(scheduled and scheduled.departAt == slot and not scheduled.trainKey, 'rechargement BDD : horaire et train non précisé conservés')
an = req(3, 'departure:cancel', { id = scheduledId })
check(not an.ok, 'annulation par un civil refusée')
local claimed = req(10, 'run:startFree', { station = 'valentine', train = 'heartlands_express', departure = scheduledId, destination = 'rhodes' })
check(claimed.ok and Sunny.Runs.Get(10).destination == 'annesburg', 'prise en charge : destination imposée', err(claimed))
check(not A.IsAvailable(scheduled), 'départ réservé avant apparition du train')
MakePlayer(11, 'DRV11', 'chemindefer', 0, 0, at(S.valentine.ticketDesk.coords))

local double = req(11, 'run:startFree', { station = 'valentine', train = 'western_freight', departure = scheduledId })
check(not double.ok and double.error == Sunny.L('dep_invalid'), 'second conducteur : même départ refusé avant apparition')
an = req(10, 'departure:cancel', { id = scheduledId })
check(not an.ok and an.error == Sunny.L('dep_in_progress'), 'annulation refusée pendant la mise en voie')
Sunny.Runs.Close(Sunny.Runs.Get(10), 'finished', 'test', 0)
check(A.IsAvailable(scheduled), 'échec de mise en voie : départ manuel à nouveau disponible')
claimed = req(10, 'run:startFree', { station = 'valentine', train = 'heartlands_express', departure = scheduledId })
ENTITIES[512] = { pos = at(S.valentine.depot.coords), vel = vector3(0, 0, 0) }
NETIDS[112] = 512
PEDS[10].pos = at(S.valentine.depot.coords); PEDS[10].vehicle = 512
local spawned = req(10, 'run:spawned', { runId = claimed.data.runId, netId = 112 })
check(spawned.ok and A.byRun[claimed.data.runId] == scheduledId and scheduled.trainKey == 'heartlands_express',
    'mise en voie : conserve le départ programmé et précise le train')
Sunny.Runs.Close(Sunny.Runs.Get(10), 'finished', 'test', 0)
check(A.IsAvailable(scheduled), 'remisage à quai : départ manuel disponible')
PEDS[10].pos = at(S.valentine.ticketDesk.coords)
local wrongTrain = req(10, 'run:startFree', { station = 'valentine', train = 'western_freight', departure = scheduledId })
check(not wrongTrain.ok and wrongTrain.error == Sunny.L('dep_wrong_train', Config.Trains.heartlands_express.label), 'train prévu imposé')
an = req(10, 'departure:cancel', { id = scheduledId })
check(an.ok and not A.Get(scheduledId) and DB.departures[scheduledId].status == 'cancelled', 'annulation persistée')
Advance(Config.Departures.keepDeparted * 60 + 20)
local stillDeparted = false
for _, e in ipairs(A.Snapshot().list) do if e.departed then stillDeparted = true end end
check(not stillDeparted, 'départs partis retirés du tableau')

print('\n== Voyage annulé avant départ / cabine abandonnée')
PEDS[10].pos = at(S.valentine.ticketDesk.coords)
fe = req(10, 'run:startFree', { station = 'valentine', train = 'heartlands_express', destination = 'annesburg', delay = 2 })
fid = fe.data and fe.data.runId
ENTITIES[511] = { pos = at(S.valentine.depot.coords), vel = vector3(0, 0, 0) }
NETIDS[111] = 511
PEDS[10].pos = at(S.valentine.depot.coords); PEDS[10].vehicle = 511
req(10, 'run:spawned', { runId = fid, netId = 111 })
local boarding = 0
for _, e in ipairs(A.Snapshot().list) do if e.destination == 'annesburg' and e.auto then boarding = boarding + 1 end end
check(boarding == 1, 'annonce du voyage vers Annesburg publiée')
PEDS[10].vehicle = 0
Advance(Config.FreeTravel.exitCabGrace + 15)
check(Sunny.Runs.Get(10) == nil, 'cabine abandonnée : train remisé automatiquement')
boarding = 0
for _, e in ipairs(A.Snapshot().list) do if e.destination == 'annesburg' and e.auto then boarding = boarding + 1 end end
check(boarding == 0, 'départ annulé : annonce retirée du tableau')
local closed = lastClient('sunny_train:client:runClosed', 10)
check(closed and closed.args[1].reason == 'finished', 'remisage automatique sans échec ni pénalité')

print('\n== Acquisitions (patron)')
ITEMS.corn = { name = 'train_crate_corn', label = 'Maïs' }
ITEMS.tobacco = { name = 'train_crate_tobacco', label = 'Tabac' }
MakePlayer(20, 'BOSS20', 'chemindefer', 5, 0, at(S.blackwater.ticketDesk.coords))
MakePlayer(21, 'EMP21', 'chemindefer', 0, 0, at(S.blackwater.ticketDesk.coords))

local b = req(20, 'fleet:catalogue')
check(b.ok and #b.data.trains == 7 and b.data.trains[1].key == 'engine_only' and b.data.trains[7].key == 'pullman_palace',
    'catalogue sans draisine : 7 trains')
local owned = req(21, 'missions:board', { station = 'blackwater' })
local seesPullman = false
for _, t in ipairs(owned.data.trains) do if t.key == 'pullman_palace' then seesPullman = true end end
check(not seesPullman, 'train non acheté absent du tableau des missions')
b = req(21, 'fleet:buy', { train = 'pullman_palace' })
check(not b.ok and b.error == Sunny.L('error_no_permission'), 'un employé ne peut pas acheter')
b = req(20, 'fleet:buy', { train = 'pullman_palace' })
check(not b.ok and b.error:find('Fonds insuffisants'), 'société sans fonds : achat refusé', err(b))
DB.society.chemindefer = 20000
b = req(20, 'fleet:buy', { train = 'pullman_palace' })
check(b.ok and Sunny.Fleet.IsOwned('pullman_palace'), 'Pullman acheté par le patron', err(b))
check(DB.society.chemindefer == 6000, 'prix débité du compte de la société (qbr-management)', DB.society.chemindefer)
check(DB.fleet.pullman_palace and DB.fleet.pullman_palace.owned == 1, 'propriété enregistrée en base')
b = req(20, 'fleet:buy', { train = 'pullman_palace' })
check(not b.ok, 'double achat refusé')
b = req(20, 'fleet:sell', { train = 'western_freight' })
check(not b.ok, 'train fourni au départ non revendable')
b = req(20, 'fleet:sell', { train = 'pullman_palace' })
check(b.ok and not Sunny.Fleet.IsOwned('pullman_palace') and DB.society.chemindefer == 13000, 'revente à 50 % créditée à la société', DB.society.chemindefer)

print('\n== Wagon (inventaire du train)')
local h = req(21, 'hold:open', { train = 'western_freight' })
check(h.ok and h.data.stash == 'sunnytrain_western_freight' and h.data.slots == 30, 'wagon ouvert au dépôt (coffre qbr-inventory)', err(h))
local h2 = req(20, 'hold:open', { train = 'western_freight' })
check(not h2.ok and h2.error == Sunny.L('hold_busy'), 'wagon déjà ouvert par un autre employé', err(h2))
local r0 = req(20, 'run:start', { station = 'blackwater', train = 'western_freight', mission = 'west_freight' })
check(not r0.ok and r0.error == Sunny.L('hold_busy'), 'mission refusée pendant que le wagon est ouvert (anti-duplication)', err(r0))
FireServer('inventory:server:SaveInventory', 21, 'stash', 'sunnytrain_western_freight')
Advance(2)
check(not Sunny.Hold.IsOpen('sunnytrain_western_freight'), 'fermeture du wagon suivie')
h = req(21, 'hold:open', { train = 'pullman_palace' })
check(not h.ok, 'wagon d\'un train non possédé inaccessible')
PEDS[21].pos = vector3(0, 0, 0)
h = req(21, 'hold:open', { train = 'western_freight' })
check(not h.ok and h.error == Sunny.L('hold_too_far'), 'wagon inaccessible loin du dépôt et du train')
PEDS[21].pos = at(S.blackwater.ticketDesk.coords)

print('\n== Cargaison des missions')
local r = req(20, 'run:start', { station = 'blackwater', train = 'western_freight', mission = 'west_freight' })
check(not r.ok and r.error:find('Caisse de maïs 0/20'), 'cargaison manquante détaillée', err(r))
Stock('western_freight', { { item = 'train_crate_corn', amount = 25 }, { item = 'train_crate_tobacco', amount = 10 } })
r = req(20, 'run:start', { station = 'blackwater', train = 'western_freight', mission = 'west_freight' })
check(r.ok, 'ordre signé avec cargaison chargée', err(r))
check(HoldCount('western_freight', 'train_crate_corn') == 5 and HoldCount('western_freight', 'train_crate_tobacco') == 0, 'cargaison prélevée du wagon (reste 5 maïs)')
r = req(20, 'run:cancel')
check(r.ok and HoldCount('western_freight', 'train_crate_corn') == 25 and HoldCount('western_freight', 'train_crate_tobacco') == 10, 'annulation avant départ : cargaison restituée au wagon')
Sunny.Runs.cooldowns.BOSS20 = 0

print('\n== Charbon')
local coal = HoldCount('western_freight', 'train_coal')
Sunny.Hold.Take(Sunny.Hold.Id('western_freight'), { { item = 'train_coal', amount = coal } })
r = req(20, 'run:start', { station = 'blackwater', train = 'western_freight', mission = 'west_freight' })
check(not r.ok and r.error:find('Charbon'), 'sans charbon : mise en voie refusée', err(r))
Stock('western_freight', { { item = 'train_coal', amount = 3 } })
r = req(20, 'run:start', { station = 'blackwater', train = 'western_freight', mission = 'west_freight' })
check(r.ok, 'charbon suffisant : mise en voie', err(r))
local runId = r.data.runId
ENTITIES[520] = { pos = at(S.blackwater.depot.coords), vel = vector3(0, 0, 0) }
NETIDS[120] = 520
PEDS[20].pos = at(S.blackwater.depot.coords); PEDS[20].vehicle = 520
r = req(20, 'run:spawned', { runId = runId, netId = 120 })
check(r.ok and r.data.coal == 3 and r.data.needsCoal, 'charbon transmis au conducteur (plaque de conduite)')
check(#GlobalState.sunnyTrains >= 1, 'train publié pour ox_target (ouvrir le wagon)')
-- 1 km parcouru en cabine : 2 charbons (coalPerKm = 2)
local start = S.blackwater.depot.coords
for i = 1, 10 do
    PEDS[20].pos = vector3(start.x + i * 100, start.y, start.z)
    Advance(Config.Fuel.checkInterval + 1)
end
check(HoldCount('western_freight', 'train_coal') == 1, 'charbon consommé au kilomètre (3 → 1)', HoldCount('western_freight', 'train_coal'))
for i = 11, 16 do
    PEDS[20].pos = vector3(start.x + i * 100, start.y, start.z)
    Advance(Config.Fuel.checkInterval + 1)
end
local fuelEvt
for i = #LOG.client, 1, -1 do if LOG.client[i].name == 'sunny_train:client:fuel' then fuelEvt = LOG.client[i] break end end
check(fuelEvt and fuelEvt.args[1].empty == true and Sunny.Runs.Get(20).noFuel, 'tender vide : train immobilisé')
PEDS[20].pos = vector3(start.x + 1600, start.y + 5000, start.z)
Advance(Config.Fuel.checkInterval + 1)
check(HoldCount('western_freight', 'train_coal') == 0, 'aucune consommation fantôme une fois vide')
Stock('western_freight', { { item = 'train_coal', amount = 10 } })
Sunny.Hold.open['sunnytrain_western_freight'] = { src = 20, at = os.time() }
FireServer('inventory:server:SaveInventory', 20, 'stash', 'sunnytrain_western_freight')
Advance(2)
check(not Sunny.Runs.Get(20).noFuel and Sunny.Runs.Get(20).coal == 10, 'charbon rechargé via le wagon : le train repart')

print('\n== Commande admin')
PEDS[22] = nil
MakePlayer(22, 'ADM22', 'unemployed', 0, 0, at(S.blackwater.depot.coords, 30))
local closedBefore = 0
ENTITIES[520].pos = at(S.blackwater.depot.coords, 28) -- le train de ce scénario est le plus proche
COMMANDS[Config.Commands.despawn](22, {})
check(Sunny.Runs.Get(20) == nil and not Sunny.Runs.IsTrainInUse('western_freight'), 'admin : train le plus proche retiré')
local closedEvt
for i = #LOG.client, 1, -1 do if LOG.client[i].name == 'sunny_train:client:runClosed' and LOG.client[i].target == 20 then closedEvt = LOG.client[i] break end end
check(closedEvt and closedEvt.args[1].message == Sunny.L('admin_despawned'), 'conducteur prévenu du retrait administratif')
COMMANDS[Config.Commands.despawn](22, {})
local nearestEvt = LOG.client[#LOG.client]
check(nearestEvt.name == 'sunny_train:client:adminDespawnNearest' or nearestEvt.name == 'sunny_train:client:notify', 'aucun run proche : suppression du train le plus proche côté client')
Sunny.Runs.cooldowns.BOSS20 = 0

print('\n== Items ferroviaires et service automatique')
check(COMMAND_PERMISSIONS.trainitems == 'admin', 'commande du kit réservée aux administrateurs QBR')
COMMANDS.trainitems(22, {})
for _, entry in ipairs(Config.RailTestKit) do
    check(Sunny.Bridge.CountItem(22, entry.item) == entry.amount, 'kit remis : ' .. entry.item)
end
local delivered = Sunny.Bridge.CountItem(22, Config.Fuel.item)
local originalAdd = PLAYERS[22].Functions.AddItem
PLAYERS[22].Functions.AddItem = function() return false end
COMMANDS.trainitems(22, {})
PLAYERS[22].Functions.AddItem = originalAdd
check(Sunny.Bridge.CountItem(22, Config.Fuel.item) == delivered, 'kit : aucun ajout fictif si inventaire plein')
local previousJob = PLAYERS[10].PlayerData.job
PLAYERS[10].PlayerData.job = { name = 'unemployed', grade = { level = 0 }, onduty = true }
check(not Sunny.Srv.IsOnService(10) and not Sunny.Srv.Can(10, 'control'), 'changement de métier : droits retirés immédiatement')
PLAYERS[10].PlayerData.job = previousJob

print('\n== Poinçonnage interrompu pendant la requête SQL')
DB.tickets[serial].used_at = nil
DB.tickets[serial].expires_at = os.time() + 3600
PLAYERS[2].PlayerData.items = { { name = 'train_ticket', amount = 1, slot = 1, info = item.info } }
PEDS[1].pos = at(PEDS[2].pos, 1)
local realUpdate = MySQL.update.await
MySQL.update.await = function(sql, p)
    local result = realUpdate(sql, p)
    if sql:find('SET `used_at` = %?') then
        PLAYERS[2].PlayerData.items = { { name = 'train_ticket', amount = 1, slot = 1, info = { serial = 'OTHER' } } }
    end
    return result
end
local interrupted = req(1, 'control:punch', { target = 2, serial = serial })
MySQL.update.await = realUpdate
check(not interrupted.ok and not DB.tickets[serial].used_at, 'billet déplacé : poinçonnage annulé en BDD')
check(PLAYERS[2].PlayerData.items[1].info.serial == 'OTHER', 'billet remplacé pendant SQL : autre billet conservé')

print(('\n==== %d réussis, %d échoués ===='):format(passed, failed))
TEST_FAILED = failed
