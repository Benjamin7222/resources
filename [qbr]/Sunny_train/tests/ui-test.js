const puppeteer = require('puppeteer-core');
const path = require('path');

const WEB = process.argv[2] || path.join(__dirname, '..', 'web');
const OUT = path.join(__dirname, 'shots');
require('fs').mkdirSync(OUT, { recursive: true });

const MOCK = `
window.GetParentResourceName = () => 'Sunn_train';
window.__posts = [];
const route = (key, label, list, dur) => ({ key, label, duration: dur, departures: ['06:00','10:00','14:00'], color: '#7b2d1d',
  stations: list.map((s, i) => ({ id: s[0], label: s[1], stop: s[2], eta: s[3] })) });
window.__static = {
  company: { name: 'Sunny Pacific', fullName: 'Sunny Pacific Railroad Company', motto: 'Service Ferroviaire', founded: 'Fondée en 1869', year: 1899 },
  stations: {
    blackwater: { key: 'blackwater', label: 'Blackwater', region: 'Great Plains', hasDepot: true,
      destinations: [ { to: 'riggs_station', label: 'Riggs Station', region: 'Big Valley', km: 0.8, via: "Ligne de l'Ouest" },
                      { to: 'saint_denis', label: 'Saint Denis', region: 'Bayou Nwa', km: 7.3, via: 'Traversée de la Vallée › Grande Ligne des Heartlands' } ],
      board: [
      { minutes: 360, time: '06:00', route: 'west', routeLabel: "Ligne de l'Ouest", destination: "Bard's Crossing" },
      { minutes: 600, time: '10:00', route: 'west', routeLabel: "Ligne de l'Ouest", destination: "Bard's Crossing" },
      { minutes: 845, time: '14:05', route: 'west', routeLabel: "Ligne de l'Ouest", destination: "Bard's Crossing" } ] },
    riggs_station: { key: 'riggs_station', label: 'Riggs Station', region: 'Big Valley', board: [] },
  },
  routes: {
    west: route('west', "Ligne de l'Ouest", [['blackwater','Blackwater',0,0],['riggs_station','Riggs Station',45,25],['bard_crossing',"Bard's Crossing",0,55]], 12),
    heartlands: route('heartlands', 'Grande Ligne des Heartlands', [['valentine','Valentine',0,0],['emerald_station','Emerald Station',45,40],['rhodes','Rhodes',45,95],['saint_denis','Saint Denis',0,140]], 20),
  },
  missionTypes: {}, classes: [
    { id: 'third', label: 'Troisième classe', multiplier: 1, description: 'Banquettes de bois.' },
    { id: 'second', label: 'Seconde classe', multiplier: 1.6, description: 'Sièges rembourrés.' },
    { id: 'first', label: 'Première classe', multiplier: 2.5, description: 'Voiture-salon.' } ],
  trainStates: { operational: 'Opérationnel', needs_maintenance: 'Maintenance nécessaire', damaged: 'Endommagé', out_of_service: 'Hors service' },
  runStates: {}, use24h: true, browserGamepad: false, clock: { h: 13, m: 58 }, announceDelays: [2, 5, 10, 15], live: [],
};
const train = (key, label, cond, state, extra = {}) => ({ key, label, description: 'Voitures de voyageurs.', condition: cond, state,
  manualOut: false, inUse: false, routes: ["Ligne de l'Ouest"], routeKeys: ['west'], serviceTypes: ['Transport de passagers'],
  allowMissions: true, allowFreeRun: true, allowRobbery: true, maxSpeed: 18, inspectionValid: false, available: true, ...extra });
window.__fleet = { trains: [ train('western_passenger', 'Western Passenger n°7', 72, 'operational'),
  train('western_freight', "Fret de l'Ouest n°12", 24, 'damaged', { available: false, reason: 'Endommagé' }) ],
  repairs: [ { id: 'routine', label: 'Entretien courant', description: 'Graissage.', restore: 20, duration: 400, items: [ { label: 'Charbon', amount: 2, have: 3 } ] },
             { id: 'overhaul', label: 'Révision complète', description: 'Remise à neuf.', restore: 100, duration: 400, items: [ { label: 'Fer', amount: 6, have: 1 } ] } ],
  atDepot: true, onService: true, requireInspection: true, inspectDuration: 400, canMaintain: true, canRestore: true, restoreMin: 60 };
const ticket = { serial: 'SP-KD4821', holder: 'Arthur', fromLabel: 'Blackwater', toLabel: 'Riggs Station', routeLabel: "Ligne de l'Ouest",
  classLabel: 'Seconde classe', price: '4.00', issued: '26/09/1899 — 14:02', expires: '26/09/1899 — 17:02', status: 'valid', statusLabel: 'Valable', valid: true };
window.__ticket = ticket;
const H = {
  'tickets:office': () => ({ ok: true, data: window.__officeData }),
  'service:toggle': () => ({ ok: true, message: 'Service pris.', data: { onService: true } }),
  'missions:board': () => ({ ok: true, data: { station: 'blackwater', cooldown: 0, fuelMin: 2, trains: window.__fleet.trains,
     missions: [ { key: 'west_passengers', label: "Omnibus de l'Ouest", description: 'Desservir Riggs Station.', type: 'passengers', typeLabel: 'Transport de passagers',
       route: 'west', routeLabel: "Ligne de l'Ouest", originLabel: 'Blackwater', terminusLabel: "Bard's Crossing", reward: 350, rewardPerStop: 50, onTimeBonus: 75, timeLimit: 20,
       canBeRobbed: true, fromHere: true, trains: ['western_passenger'],
       company: window.__cargoMission ? 'Comptoir agricole de Blackwater' : '',
       cargo: window.__cargoMission ? [ { item: 'corn', label: 'Maïs', amount: 20 }, { item: 'tobacco', label: 'Tabac', amount: 10 } ] : [] },
       { key: 'west_return', label: 'Omnibus retour', type: 'passengers', typeLabel: 'Transport de passagers', route: 'west', routeLabel: "Ligne de l'Ouest",
       originLabel: "Bard's Crossing", terminusLabel: 'Blackwater', reward: 350, rewardPerStop: 50, onTimeBonus: 75, timeLimit: 20, fromHere: false, trains: ['western_passenger'] } ],
     freeRuns: [ { route: 'west', label: "Ligne de l'Ouest", terminusLabel: "Bard's Crossing" } ] } }),
  'run:start': () => ({ ok: true, close: true, message: "Ordre de mission signé : Omnibus de l'Ouest." }),
  'fleet:list': () => ({ ok: true, data: window.__fleet }),
  'fleet:work': (p) => new Promise((r) => setTimeout(() => r({ ok: true, message: 'Inspection consignée au registre.',
     data: { train: { ...window.__fleet.trains[0], inspectionValid: true }, inspector: 'Arthur Morgan',
       report: [ { label: 'Chaudière & foyer', value: 70, state: 'operational' }, { label: 'Freins à air', value: 41, state: 'needs_maintenance' } ] } }), 500)),
  'control:check': () => ({ ok: true, data: { target: 2, passenger: 'Arthur Morgan', line: "Ligne de l'Ouest",
     tickets: [ ticket, { ...ticket, serial: 'SP-ZZ0000', status: 'forged', statusLabel: 'Faux billet', valid: false } ] } }),
  'control:punch': () => ({ ok: true, message: 'Billet composté.', data: { ticket: { ...ticket, status: 'used', punched: true, valid: false } } }),
  'tickets:buy': () => ({ ok: true, message: 'Billet n°SP-KD4821 délivré.', data: { ticket } }),
  'run:summary': () => ({ ok: true, data: null }),
  'free:board': () => ({ ok: true, data: { station: 'blackwater', hasDepot: true, delays: [0, 2, 5, 10], trains: window.__fleet.trains,
     destinations: [ { to: 'riggs_station', label: 'Riggs Station', region: 'Big Valley', km: 0.8, routeLabel: "Ligne de l'Ouest", stops: 1 },
                     { to: 'saint_denis', label: 'Saint Denis', region: 'Bayou Nwa', km: 7.3, routeLabel: 'Traversée de la Vallée › Grande Ligne des Heartlands', stops: 4 } ] } }),
  'run:startFree': () => ({ ok: true, close: true, message: 'Train mis en voie à destination de Saint Denis. Bon voyage !' }),
  'departure:create': () => ({ ok: true, message: 'Départ programmé.' }),
  'departure:options': () => ({ ok: true, data: { trains: [], slots: [ { at: 1800000300, label: '08:05', inMinutes: 5 }, { at: 1800000600, label: '08:10', inMinutes: 10 } ] } }),
  'fleet:catalogue': () => ({ ok: true, data: { canBuy: true, balance: '13000.00', account: 'society', sellRatio: 0.5, trains: [
     { key: 'engine_only', label: 'Locomotive de manœuvre n°1', tier: 1, category: 'Locomotive', price: 250, owned: true, starter: true, holdSlots: 5, holdWeight: 50000, maxSpeed: 7, needsCoal: false, coalPerKm: 0, routes: ["Ligne de l'Ouest"], serviceTypes: ['Transport de marchandises'], allowMissions: true, description: 'Locomotive avec tender.' },
     { key: 'western_freight', label: "Fret de l'Ouest n°12", tier: 3, category: 'Fret', price: 2500, owned: true, starter: true, holdSlots: 30, holdWeight: 1500000, maxSpeed: 15, needsCoal: true, coalPerKm: 2, routes: ["Ligne de l'Ouest"], serviceTypes: ['Transport de marchandises'], allowMissions: true, description: 'Wagons couverts.' },
     { key: 'pullman_palace', label: 'Pullman Palace Express', tier: 8, category: 'Luxe', price: 14000, owned: false, starter: false, holdSlots: 20, holdWeight: 600000, maxSpeed: 24, needsCoal: true, coalPerKm: 2.6, routes: ['Grande Ligne des Heartlands'], serviceTypes: ['Transport de passagers'], allowMissions: true, description: 'Voitures-salons, boiseries et velours.' } ] } }),
  'fleet:buy': () => ({ ok: true, message: 'Pullman Palace Express acquis pour 14000.00 $.' }),
  'hold:open': () => ({ ok: true, replaced: true }),
};
window.fetch = async (url, opts) => {
  const endpoint = url.split('/').pop();
  const body = JSON.parse(opts.body || '{}');
  window.__posts.push({ endpoint, body });
  let res = { ok: true };
  if (endpoint === 'action') res = H[body.name] ? await H[body.name](body.payload) : { ok: false, error: 'mock: ' + body.name };
  if (endpoint === 'action' && body.name === 'missions:board' && window.__deliveryBoard) res = { ok: true, data: window.__deliveryBoard };
  return { json: async () => res };
};
window.__static.live = { now: 1800000000, tz: 7200, list: [
  { id: 1, station: 'blackwater', destination: 'rhodes', destinationLabel: 'Rhodes', timeLabel: '10:05', departAt: 1800000300 },
  { id: 2, station: 'blackwater', destination: 'riggs_station', destinationLabel: 'Riggs Station', timeLabel: '10:30', departAt: 1800001800 },
  { id: 3, station: 'blackwater', destination: 'saint_denis', destinationLabel: 'Saint Denis', timeLabel: '11:00', departAt: 1800003600 }
] };
window.__errors = [];
window.addEventListener('message', (e) => {
  if (e.data.action === 'open' && e.data.view === 'tickets') window.__officeData = e.data.data;
});
window.addEventListener('error', (e) => window.__errors.push(e.message));
`;

let passed = 0, failed = 0;
const check = (c, label, extra) => { if (c) { passed++; console.log('  [OK]   ' + label); } else { failed++; console.log('  [FAIL] ' + label + (extra !== undefined ? ' -> ' + JSON.stringify(extra) : '')); } };
const sleep = (ms) => new Promise((r) => setTimeout(r, ms));

(async () => {
    const browser = await puppeteer.launch({ executablePath: process.env.CHROME_PATH || 'C:/Program Files/Google/Chrome/Application/chrome.exe', headless: 'new', args: ['--allow-file-access-from-files'] });
    const page = await browser.newPage();
    const consoleErrors = [];
    page.on('console', (m) => { if (m.type() === 'error' && !/fonts\.g/.test(m.text())) consoleErrors.push(m.text()); });
    page.on('pageerror', (e) => consoleErrors.push(e.message));
    await page.setViewport({ width: 1920, height: 1080 });
    await page.evaluateOnNewDocument(MOCK);
    await page.goto('file:///' + WEB.replace(/\\/g, '/') + '/index.html', { waitUntil: 'load', timeout: 20000 }).catch(() => {});
    await sleep(800);

    const send = (msg) => page.evaluate((m) => window.postMessage(m, '*'), msg);
    const openCompany = (extra = {}) => send({ action: 'open', view: 'company', static: null, data: {
        name: 'Arthur Morgan', job: 'Compagnie ferroviaire', grade: 'Mécanicien', onService: true, station: 'blackwater', run: null,
        perms: { service: true, drive: true, control: true, maintenance: true, restore: true }, ...extra } });
    const posts = () => page.evaluate(() => window.__posts.splice(0));
    const q = (sel) => page.evaluate((s) => { const e = document.querySelector(s); return e ? e.textContent.trim() : null; }, sel);
    const count = (sel) => page.evaluate((s) => document.querySelectorAll(s).length, sel);
    const selected = () => page.evaluate(() => { const e = document.querySelector('.page.current .entry.selected .text'); return e && e.textContent.trim(); });
    const key = async (k) => { await page.keyboard.press(k); await sleep(320); };
    const crumbs = () => page.evaluate(() => document.querySelector('#crumbs').textContent);
    const appHidden = () => page.evaluate(() => document.querySelector('#app').classList.contains('hidden'));

    // ------------------------------------------------------------------
    console.log('\n== Ouverture & menu principal');
    await page.evaluate((s) => { window.__staticMsg = s; }, null);
    await page.evaluate(() => window.postMessage({ action: 'open', view: 'company', static: window.__static, data: {
        name: 'Arthur Morgan', job: 'Compagnie ferroviaire', grade: 'Mécanicien', onService: true, station: 'blackwater', run: null,
        perms: { service: true, drive: true, control: true, maintenance: true, restore: true } } }, '*'));
    await sleep(600);
    check(!(await appHidden()), 'interface visible après ouverture');
    const labels = await page.evaluate(() => [...document.querySelectorAll('.page.current .entry .text')].map((e) => e.textContent.trim()));
    check(labels.join('|') === 'Prendre une mission|Consulter les trajets|Horaires|Informations du train|Maintenance|Quitter', 'entrées du menu principal', labels);
    check(await count('.page.current .entry.disabled') === 0, 'missions immédiatement accessibles');
    check((await selected()) === 'Prendre une mission', 'première entrée sélectionnée');
    check((await q('#companyName')) === 'Sunny Pacific', 'nom de la compagnie depuis la config');
    await page.screenshot({ path: path.join(OUT, '01-menu-1080p.png') });

    console.log('\n== Navigation clavier');
    await key('ArrowDown');
    check((await selected()) === 'Consulter les trajets', 'flèche bas saute l\'entrée désactivée');
    await key('ArrowUp'); await key('ArrowUp');
    check((await selected()) === 'Quitter', 'navigation circulaire');
    await key('ArrowDown'); await key('ArrowDown');
    await key('Enter');
    check((await crumbs()).includes('Lignes'), 'Entrée ouvre la page des lignes', await crumbs());
    check(await count('.page.leave-left') + await count('.page.enter-right') >= 0, 'transition de page');
    await key('Enter');
    check(await count('.page.current .track .stop') >= 3, 'tracé de ligne avec gares');
    await page.screenshot({ path: path.join(OUT, '02-ligne.png') });
    await key('Backspace'); await key('Backspace');
    check((await crumbs()).trim() === 'Registre', 'Retour arrière jusqu\'à la racine', await crumbs());

    console.log('\n== Navigation manette (relayée par Lua)');
    check((await selected()) === 'Consulter les trajets', 'sélection restaurée au retour');
    await send({ action: 'nav', dir: 'down' }); await sleep(150);
    check((await selected()) === 'Horaires', 'D-Pad bas');
    check(await page.evaluate(() => document.body.classList.contains('pad')), 'aide des touches bascule en mode manette');
    await send({ action: 'nav', dir: 'select' }); await sleep(400);
    check((await crumbs()).includes('Horaires'), 'A = sélectionner');
    await send({ action: 'nav', dir: 'select' }); await sleep(400);
    check(await count('.live-board tbody tr') === 3, 'tableau des départs');
    const firstStatus = await q('.live-board tbody tr:first-child .status');
    check(firstStatus === 'Dans 7 min' || firstStatus === 'Embarquement', 'statut calculé depuis l\'heure serveur', firstStatus);
    await page.screenshot({ path: path.join(OUT, '03-horaires.png') });
    await send({ action: 'nav', dir: 'back' }); await sleep(350);
    await send({ action: 'nav', dir: 'back' }); await sleep(350);
    check((await crumbs()).trim() === 'Registre', 'B = retour');
    await key('ArrowUp');

    console.log('\n== Mission sans prise de service');
    check(await count('[data-act="service"]') === 0, 'aucun bouton de prise ou fin de service');
    check(await count('[data-act="control"]') === 0, 'contrôle réservé au ciblage du voyageur');
    await page.click('[data-act="mission"]'); await sleep(500);
 await sleep(200);
    check((await crumbs()).includes('Matériel'), 'registre du matériel roulant');
    check(await count('.page.current .entry.disabled') === 1, 'train endommagé non sélectionnable');
    await key('Enter');
    check((await crumbs()).includes('Missions'), 'ordres de mission du train');
    check(await count('.page.current .section-label') === 3, 'sections : cette gare / libre / autres');
    await page.screenshot({ path: path.join(OUT, '04-missions.png') });
    await key('Enter');
    check((await q('.doc-head .title')) === 'Ordre de mission', 'ordre de mission affiché');
    await page.screenshot({ path: path.join(OUT, '05-ordre.png') });
    await posts();
    await key('Enter'); await sleep(200);
    check(await count('.stamp.animate') === 1, 'tampon « Approuvé »');
    await page.screenshot({ path: path.join(OUT, '06-approuve.png') });
    await sleep(1300);
    const p1 = await posts();
    const startCall = p1.find((p) => p.endpoint === 'action' && p.body.name === 'run:start');
    check(startCall && startCall.body.payload.train === 'western_passenger' && startCall.body.payload.mission === 'west_passengers' && startCall.body.payload.reward === undefined,
        'intention envoyée sans montant', startCall && startCall.body.payload);
    check(p1.some((p) => p.endpoint === 'close'), 'NUI fermée après signature (focus rendu)');
    check(await appHidden(), 'interface masquée');

    console.log('\n== ESC ferme depuis une sous-page');
    await page.evaluate(() => window.postMessage({ action: 'open', view: 'company', static: window.__static, data: {
        name: 'A', onService: true, station: 'blackwater', perms: { service: true, drive: true, maintenance: true, restore: true, control: true } } }, '*'));
    await sleep(500);
    await key('ArrowDown'); await key('ArrowDown'); await key('Enter');
    await posts();
    await key('Escape');
    const p2 = await posts();
    check(p2.filter((p) => p.endpoint === 'close').length === 1, 'ESC envoie exactement un « close »');
    await sleep(300);
    check(await appHidden(), 'fermeture animée terminée');
    await key('ArrowDown');
    check((await posts()).length === 0, 'aucune entrée traitée une fois fermé');

    console.log('\n== Maintenance');
    await page.evaluate(() => window.postMessage({ action: 'open', view: 'company', static: window.__static, data: {
        name: 'A', onService: true, station: 'blackwater', perms: { service: true, drive: true, maintenance: true, restore: true, control: true } } }, '*'));
    await sleep(500);
    for (let attempt = 0; (await selected()) !== 'Maintenance' && attempt < 25; attempt++) await key('ArrowDown');
    await key('Enter'); await sleep(200);
    await key('Enter'); await sleep(1200);
    check(await count('.gauge') === 1, 'jauge d\'état');
    const needle = await page.evaluate(() => document.querySelector('.gauge .needle').style.transform);
    check(needle === 'rotate(39.6deg)', 'aiguille positionnée (72 %)', needle);
    await page.screenshot({ path: path.join(OUT, '07-maintenance.png') });
    const repairDisabled = await page.evaluate(() => [...document.querySelectorAll('.page.current .entry')].find((e) => e.textContent.includes('Réparer')).classList.contains('disabled'));
    check(repairDisabled, 'réparation bloquée sans inspection');
    await key('Enter'); await sleep(250);
    check(await count('.work .tube') === 1, 'barre de travaux');
    await page.screenshot({ path: path.join(OUT, '08-travaux.png') });
    await sleep(900);
    check(await count('.report-grid') === 1, 'rapport d\'inspection affiché après travaux');
    const repairNow = await page.evaluate(() => [...document.querySelectorAll('.page.current .entry')].find((e) => e.textContent.includes('Réparer')).classList.contains('disabled'));
    check(!repairNow, 'réparation débloquée après inspection');

    console.log('\n== Contrôle depuis le joueur ciblé');
    await key('Escape'); await sleep(300);
    await page.evaluate(() => window.postMessage({ action: 'open', view: 'control', static: window.__static,
        data: { target: 2, passenger: 'Arthur Morgan', tickets: [window.__ticket] } }, '*'));
    await sleep(400);
    check(await count('.ticket') === 1, 'un billet : affiché directement au cheminot');
    check((await selected()) === 'Poinçonner le billet', 'bouton poinçonner disponible');
    await posts(); await key('Enter'); await sleep(400);
    const punch = (await posts()).find(p => p.body?.name === 'control:punch');
    check(punch && punch.body.payload.target === 2 && punch.body.payload.serial === 'SP-KD4821', 'poinçonnage adressé au voyageur ciblé et au bon billet');
    check((await q('.ticket .stamp')) === 'POINÇONNÉ' && await count('.ticket .punch') === 1, 'billet poinçonné affiché');
    check(await count('[data-act="punch"]') === 0, 'double poinçonnage impossible dans la NUI');
    check((await q('.page.current')).includes('retiré de l’inventaire'), 'retrait du billet confirmé');
    await page.screenshot({ path: path.join(OUT, '09-controle.png') });

    console.log('\n== Guichet');
    await page.evaluate(() => window.postMessage({ action: 'open', view: 'tickets', static: window.__static, data: {
        station: 'blackwater', money: '10.00', validity: 180, departures: [ { id: 1, destination: 'rhodes', destinationLabel: 'Rhodes', timeLabel: '10:05', departAt: 1800000300, via: 'Heartlands', stops: [
          { to: 'rhodes', label: 'Rhodes', region: 'Scarlett Meadows', routeLabel: 'Grande Ligne des Heartlands', km: 1.5, connected: true, prices: [ { id: 'third', label: 'Troisième classe', price: '1.90' }, { id: 'second', label: 'Seconde classe', price: '3.05' }, { id: 'first', label: 'Première classe', price: '4.75' } ] },
          { to: 'annesburg', label: 'Annesburg', region: 'Roanoke Ridge', routeLabel: 'Embranchement du Nord', km: 2.7, connected: true, prices: [ { id: 'third', label: 'Troisième classe', price: '2.60' }, { id: 'second', label: 'Seconde classe', price: '4.15' }, { id: 'first', label: 'Première classe', price: '6.50' } ] },
          { to: 'valentine', label: 'Valentine', region: 'Heartlands', routeLabel: 'Grande Ligne des Heartlands', km: 5.0, connected: true, prices: [ { id: 'third', label: 'Troisième classe', price: '4.00' }, { id: 'second', label: 'Seconde classe', price: '6.40' }, { id: 'first', label: 'Première classe', price: '10.00' } ] },
          { to: 'blackwater', label: 'Blackwater', region: 'Great Plains', routeLabel: 'Grande Ligne des Heartlands › Traversée de la Vallée', km: 7.3, connected: true, prices: [ { id: 'third', label: 'Troisième classe', price: '5.40' }, { id: 'second', label: 'Seconde classe', price: '8.65' }, { id: 'first', label: 'Première classe', price: '13.50' } ] } ] } ] } }, '*'));
    await sleep(500);
    check((await crumbs()).trim() === 'Départs et billets', 'tableau et billetterie réunis');
    check(await count('.page.current .entry') === 4, 'tableau : tous les départs programmés et fermer');
    await posts();
    await key('Enter');
    const officeCalls = await posts();
    check(officeCalls.some(p => p.body?.name === 'tickets:office') && !officeCalls.some(p => p.endpoint === 'close'), 'choix du départ : tarifs actualisés sans fermeture du menu');
    check(await count('.page.current .entry') === 4, 'guichet : gares desservies par le départ');
    check((await q('.page.current .entry .sub')).includes('1,5 km'), 'distance affichée sur chaque gare', await q('.page.current .entry .sub'));
    await page.screenshot({ path: path.join(OUT, '10-guichet.png') });
    await key('Enter'); await key('ArrowDown'); await key('Enter');
    check(await count('.ticket') === 1, 'aperçu du billet');
    await key('Enter'); await sleep(400);
    check((await q('.ticket .stamp')) === 'PAYÉ', 'billet délivré tamponné « Payé »');
    check((await q('.spine .facts')).includes('$6.95'), 'bourse mise à jour dans la colonne', await q('.spine .facts'));
    await page.screenshot({ path: path.join(OUT, '11-billet.png') });

    console.log('\n== Vues ox_target (tableau public, contrôle direct)');
    await page.evaluate(() => window.postMessage({ action: 'open', view: 'board', static: window.__static, data: { station: 'blackwater' } }, '*'));
    await sleep(500);
    check(await count('.live-board tbody tr') === 3 && (await selected()) === 'Fermer le tableau', 'tableau des départs public');
    await page.screenshot({ path: path.join(OUT, '14-tableau-public.png') });
    await posts();
    await key('Enter');
    check((await posts()).some((p) => p.endpoint === 'close'), 'tableau public : fermeture');
    await page.evaluate(() => window.postMessage({ action: 'open', view: 'control', static: window.__static, data: {
        target: 2, passenger: 'Arthur Morgan', line: null, tickets: [ window.__ticket ] } }, '*'));
    await sleep(500);
    check((await q('.spine .card-title')) === 'Contrôle des billets', 'contrôle direct du joueur visé');
    check(await count('.ticket') === 1, 'contrôle direct : billet consultable');
    await key('Escape'); await sleep(300);

    console.log('\n== Feuille de route, HUD, télégramme');
    await page.evaluate(() => window.postMessage({ action: 'open', view: 'report', static: window.__static, data: {
        reward: 475, lines: [ { label: 'Prime de mission', amount: 350 }, { label: 'Gares desservies (1)', amount: 50 }, { label: 'Ponctualité', amount: 75 } ],
        summary: { id: 3, mission: 'west_passengers', missionLabel: "Omnibus de l'Ouest", trainLabel: 'Western Passenger n°7', routeLabel: "Ligne de l'Ouest", elapsed: 734 } } }, '*'));
    await sleep(700);
    check((await q('.money-table tr.total td:last-child')) === '$475.00', 'total de la feuille de route');
    await send({ action: 'hud', data: { train: 'Western Passenger n°7', mission: 'Omnibus', route: "Ligne de l'Ouest", next: 'Riggs Station', distance: 1240,
        speed: 31, notch: 'Cran 4', junction: { distance: 86, label: 'Voie déviée', locked: false }, state: 'at_station', stateLabel: 'Arrêt en gare', countdown: 32, index: 2, total: 3, driving: true } });
    await sleep(400);
    check(!(await page.evaluate(() => document.querySelector('#hud').classList.contains('hidden'))), 'plaque de conduite affichée');
    await page.screenshot({ path: path.join(OUT, '12-rapport-hud.png') });
    await key('Enter'); await sleep(400);
    check(await appHidden() && !(await page.evaluate(() => document.querySelector('#hud').classList.contains('hidden'))), 'HUD reste visible sans focus après fermeture');
    await send({ action: 'toast', text: 'Le convoi est attaqué !', kind: 'warning', duration: 4000 });
    await sleep(400);
    await page.screenshot({ path: path.join(OUT, '13-hud-telegramme.png') });
    await send({ action: 'hud', data: null }); await sleep(100);
    check(await page.evaluate(() => document.querySelector('#hud').classList.contains('hidden')), 'HUD masqué en fin de run');


    console.log('\n== Voyage libre & annonces');
    await page.evaluate(() => window.postMessage({ action: 'open', view: 'company', static: window.__static, data: {
        name: 'Arthur Morgan', job: 'Compagnie de chemin de fer', grade: 'Apprenti cheminot', onService: true, station: 'blackwater', run: null,
        perms: { service: true, drive: true, control: true, freeTravel: true, schedule: true } } }, '*'));
    await sleep(600);
    const labels2 = await page.evaluate(() => [...document.querySelectorAll('.page.current .entry .text')].map((e) => e.textContent.trim()));
    check(labels2.includes('Sortir un train (voyage)') && labels2.includes('Programmer un départ'), 'menu : sortir un train + annoncer un départ', labels2);
    for (let attempt = 0; (await selected()) !== 'Sortir un train (voyage)' && attempt < 25; attempt++) await key('ArrowDown');
    await key('Enter'); await sleep(250);
    check((await crumbs()).includes('Voyage') && await count('.page.current .entry.disabled') === 1, 'voyage : liste des trains (endommagé grisé)');
    await key('Enter');
    check((await crumbs()).includes('Destination') && await count('.page.current .entry') === 2, 'voyage : choix de la destination');
    await key('ArrowDown'); await key('Enter');
    check((await q('.doc-head .title')) === 'Feuille de route — voyage', 'voyage : feuille de route');
    const goLabels = await page.evaluate(() => [...document.querySelectorAll('.page.current .entry .text')].map((e) => e.textContent.trim()));
    check(goLabels[0] === 'Partir immédiatement' && goLabels[2] === 'Annoncer le départ dans 5 min', 'voyage : départ immédiat ou annoncé', goLabels);
    await page.screenshot({ path: path.join(OUT, '15-voyage.png') });
    await posts();
    await key('ArrowDown'); await key('ArrowDown'); await key('Enter'); await sleep(200);
    check(await count('.stamp.animate') === 1, 'tampon « En voiture »');
    await sleep(1300);
    const vp = await posts();
    const sf = vp.find((p) => p.body && p.body.name === 'run:startFree');
    check(sf && sf.body.payload.destination === 'saint_denis' && sf.body.payload.delay === 5 && sf.body.payload.train === 'western_passenger', 'intention de voyage envoyée', sf && sf.body.payload);
    check(vp.some((p) => p.endpoint === 'close'), 'interface fermée après la mise en voie');

    // Avis et tableau : mêmes contrats que les messages Lua.
    const departure = { id: 1, station: 'blackwater', stationLabel: 'Blackwater', destination: 'saint_denis', destinationLabel: 'Saint Denis', timeLabel: '10:05', departAt: 1800000300, via: 'Heartlands' };
    await send({ action: 'notice', duration: 60000, notice: { ...departure, now: 1800000000, kind: 'created' } });
    await sleep(300);
    check((await q('#notices .notice-body')).startsWith('Un train de la compagnie partira'), 'annonce sans train : formulation correcte');
    await send({ action: 'notice', duration: 60000, notice: { ...departure, now: 1800000000, train: 'Heartlands Express', kind: 'boarding' } });
    await sleep(300);
    check((await q('#notices .notice:last-child .notice-body')).includes('Le Heartlands Express'), 'annonce avec nom du train');
    const live = { now: 1800000000, tz: 7200, list: [departure, { ...departure, id: 2, departed: true }] };
    await send({ action: 'live', live });
    await page.evaluate(() => window.postMessage({ action: 'open', view: 'board', static: { ...window.__static, live: undefined }, data: { station: 'blackwater' } }, '*'));
    await sleep(400);
    check(await count('.live-board tbody tr') === 2, 'tableau : départs programmés reçus');
    let statuses = await page.$$eval('.live-board td.status', nodes => nodes.map(n => n.textContent.trim()));
    check(statuses[0] === 'Embarquement' && statuses[1] === 'Parti', 'statuts embarquement et parti', statuses);
    await send({ action: 'live', live: { ...live, now: 1800000310, list: [departure] } });
    await sleep(300);
    check(await q('.live-board td.status') === 'Retardé', 'horaire dépassé sans train : retardé');
    await send({ action: 'live', live: { ...live, now: 1800000310, list: [{ ...departure, atPlatform: true }] } });
    await sleep(300);
    check(await q('.live-board td.status') === 'Départ imminent', 'horaire dépassé à quai : imminent');
    await send({ action: 'live', live: { ...live, list: [] } });
    await sleep(300);
    check(await count('.live-board td.status') === 0, 'annulation retirée du tableau ouvert');
    await key('Escape'); await sleep(300);

    // Programmation : destination, train non précisé, heure réelle.
    await page.evaluate(() => window.postMessage({ action: 'open', view: 'company', static: { ...window.__static, live: undefined }, data: {
        name: 'Arthur Morgan', onService: true, station: 'blackwater', perms: { schedule: true } } }, '*'));
    await sleep(400);
    await page.click('[data-act="schedule"]'); await sleep(400);
    check((await crumbs()).includes('Programmation'), 'programmation : choix de destination');
    await key('ArrowDown'); await key('Enter');
    check((await selected()) === 'Train non précisé', 'programmation sans train');
    await key('Enter');
    check(await count('.page.current .entry') === 2, 'créneaux reçus du serveur');
    await posts(); await key('Enter'); await sleep(300);
    const ap = (await posts()).find(p => p.body && p.body.name === 'departure:create');
    check(ap && ap.body.payload.destination === 'saint_denis' && ap.body.payload.departAt === 1800000300 && !ap.body.payload.train, 'programmation : intention envoyée avec epoch');
    check((await crumbs()).trim() === 'Registre', 'retour au registre après programmation');
    await key('Escape'); await sleep(300);

    console.log('\n== Flotte v2 : catalogue, wagon, cargaison, charbon');
    await page.evaluate(() => window.postMessage({ action: 'open', view: 'company', static: window.__static, data: {
        name: 'Directeur', onService: true, station: 'blackwater', perms: { purchase: true, drive: true, maintenance: true } } }, '*'));
    await sleep(500);
    for (let attempt = 0; (await selected()) !== 'Matériel & acquisitions' && attempt < 25; attempt++) await key('ArrowDown');
    await key('Enter'); await sleep(250);
    const cat = await page.evaluate(() => [...document.querySelectorAll('.page.current .entry .text')].map((e) => e.textContent.trim()));
    check(cat[0] === 'Locomotive de manœuvre n°1' && cat[2] === 'Pullman Palace Express', 'catalogue classé du plus modeste au plus luxueux', cat);
    check(await count('.page.current .entry .tag.ok') === 2, 'trains possédés marqués « Possédé »');
    await key('ArrowDown'); await key('ArrowDown'); await key('Enter');
    check((await q('.doc-head .no')).includes('Rang 8'), 'fiche du train de luxe');
    await page.screenshot({ path: path.join(OUT, '20-catalogue.png') });
    await key('Enter');
    check((await crumbs()).includes('Confirmation'), 'achat : confirmation');
    await posts();
    await key('ArrowUp'); await key('Enter'); await sleep(300);
    check((await posts()).some((p) => p.body && p.body.name === 'fleet:buy' && p.body.payload.train === 'pullman_palace'), 'achat demandé au serveur');
    await key('Escape'); await sleep(300);

    // Ordre de mission : cargaison manquante → signature bloquée
    await page.evaluate(() => {
        const t = window.__fleet.trains[0];
        Object.assign(t, { needsCoal: true, coal: 12, category: 'Fret', holdSummary: { coal: 12, corn: 8 }, hold: [ { item: 'coal', label: 'Charbon', amount: 12 }, { item: 'corn', label: 'Maïs', amount: 8 } ], holdSlots: 30, holdWeight: 1500000 });
    });
    await page.evaluate(() => { window.__cargoMission = true; });
    await page.evaluate(() => window.postMessage({ action: 'open', view: 'company', static: window.__static, data: {
        name: 'Arthur Morgan', onService: true, station: 'blackwater', perms: { drive: true } } }, '*'));
    await sleep(400);
    for (let attempt = 0; (await selected()) !== 'Prendre une mission' && attempt < 25; attempt++) await key('ArrowDown');
    await key('Enter'); await sleep(250); await key('Enter');
    await key('Enter');
    const signDisabled = await page.evaluate(() => [...document.querySelectorAll('.page.current .entry')].find((e) => e.textContent.includes('Signer')).classList.contains('disabled'));
    check(signDisabled && (await q('.page.current .entry.disabled .sub')).includes('Maïs 8/20'), 'cargaison incomplète : signature bloquée (Maïs 8/20)', await q('.page.current .entry.disabled .sub'));
    check(await count('.money-table.cargo tr.ko') === 2, 'tableau de cargaison : manquants en rouge');
    await page.screenshot({ path: path.join(OUT, '21-ordre-cargaison.png') });
    await posts();
    for (let attempt = 0; (await selected()) !== 'Ouvrir le stockage' && attempt < 25; attempt++) await key('ArrowDown');
    await key('Enter'); await sleep(200);
    check((await posts()).some((p) => p.body && p.body.name === 'hold:open'), 'ouvrir le wagon depuis l\'ordre de mission');
    await key('Escape'); await sleep(300);

    // Plaque de conduite : en haut à gauche, charbon, aide des touches
    await send({ action: 'hud', data: { train: "Fret de l'Ouest n°12", route: "Ligne de l'Ouest", next: 'Riggs Station', distance: 640, speed: 22, notch: 'Cran 3',
        state: 'enroute', stateLabel: 'En circulation', index: 2, total: 2, coal: 0, noFuel: true,
        hints: ['W / S : régulateur', "Espace : frein d'urgence", 'U : sifflet', 'J : aiguillage'] } });
    await sleep(400);
    const hudBox = await page.evaluate(() => { const r = document.querySelector('#hud').getBoundingClientRect(); return { x: r.x, y: r.y }; });
    check(hudBox.x < 100 && hudBox.y < 100, 'plaque de conduite en haut à gauche', hudBox);
    check((await q('#hud .h-state')).includes('Plus de charbon') && await count('#hud .h-hints') === 0, 'charbon épuisé signalé, touches retirées du HUD');
    await page.screenshot({ path: path.join(OUT, '22-hud-haut-gauche.png') });
    await send({ action: 'hud', data: { free: true, train: 'Convoi de marchandises', route: 'Saint Denis → Annesburg', next: 'Annesburg',
        distance: 2500, speed: 22, notch: 'Cran 3', state: 'enroute', stateLabel: 'En circulation', index: 2, total: 2, coal: 38 } });
    await sleep(150);
    check(!(await q('#hud')).includes('Annesburg') && await count('#hud .h-next') === 0 && await count('#hud .h-progress') === 0,
        'voyage libre : aucune destination figée, distance ou progression');
    check((await q('#hud')).includes('22 mph') && (await q('#hud .h-coal')).includes('38') && (await q('#hud')).includes('Cran 3'),
        'plaque libre conserve vitesse, régulateur et charbon');
    await page.screenshot({ path: path.join(OUT, '23-hud-circulation-libre.png') });
    await send({ action: 'hud', data: { free: true, train: 'Convoi', speed: 0, notch: 'Point mort', state: 'enroute', total: 2, index: 2, coal: 0, noFuel: true } });
    await sleep(150);
    check((await q('#hud .h-state.alert')).includes('Plus de charbon'), 'alerte de charbon conservée en voyage libre');
    await send({ action: 'hud', data: null });

    console.log('\n== Livraisons : contrat puis train et cooldown global');
    await page.evaluate(() => {
        window.__static.stations.saint_denis = { key: 'saint_denis', label: 'Saint Denis' };
        window.__static.routes.delivery = { key: 'delivery', label: 'Saint Denis → Annesburg', stations: [
            { id: 'saint_denis', label: 'Saint Denis', stop: 0 }, { id: 'annesburg', label: 'Annesburg', stop: 0 } ] };
        const base = { delivery: true, route: 'delivery', routeLabel: 'Saint Denis → Annesburg', originLabel: 'Saint Denis', terminusLabel: 'Annesburg',
            trains: ['western_freight'], fromHere: true, allowed: true, typeLabel: 'Fret', reward: 450, rewardPerStop: 0,
            onTimeBonus: 0, timeLimit: 0, cargo: [], company: 'Boucherie', cooldown: 0 };
        window.__deliveryBoard = { deliveries: true, station: 'saint_denis', startStation: 'saint_denis', fuelMin: 2, cooldown: 0,
            missions: [ { ...base, key: 'vegetables', label: 'Livrer des légumes', cooldown: 7200 }, { ...base, key: 'meat', label: 'Livrer de la viande' } ],
            trains: [ { ...window.__fleet.trains[1], available: true, condition: 100, state: 'operational', needsCoal: true, coal: 100 } ] };
        window.postMessage({ action: 'open', view: 'company', static: window.__static,
            data: { name: 'Conducteur', station: 'saint_denis', perms: { drive: true } } }, '*');
    });
    await sleep(400); await page.click('[data-act="mission"]'); await sleep(400);
    check((await crumbs()).includes('Livraisons'), 'liste des contrats avant le choix du train');
    check((await q('.page.current .entry.disabled')).includes('120 min'), 'cooldown global affiché sur la catégorie indisponible');
    await page.click('.page.current [data-act="refresh"]'); await sleep(350);
    check((await crumbs()).includes('Livraisons'), 'actualisation conserve la page des contrats');
    await page.click('.page.current [data-act="m:meat"]'); await sleep(350);
    check(await count('.page.current .entry') === 1, 'seul le train compatible est proposé');
    await key('Enter');
    check((await q('.page.current')).includes('Gare de livraison') && (await q('.page.current')).includes('Annesburg'), 'ordre distingue départ et livraison');
    check(!(await q('.page.current .track')).includes('+0 min') && !(await q('.page.current .track')).includes('undefined'), 'livraison sans horaires intermédiaires fictifs');
    await posts(); await page.click('.page.current [data-act="sign"]'); await sleep(1200);
    check((await posts()).some(p => p.body && p.body.name === 'run:start' && p.body.payload.mission === 'meat' && p.body.payload.station === 'saint_denis'), 'signature du contrat sélectionné depuis Saint Denis');
    await page.evaluate(() => { window.__deliveryBoard = null; });

    console.log('\n== Responsive');
    for (const [w, h] of [[1920, 1080], [2560, 1440], [3840, 2160], [1280, 1024], [3440, 1440], [1366, 768]]) {
        await page.setViewport({ width: w, height: h });
        await page.evaluate(() => window.postMessage({ action: 'open', view: 'company', static: window.__static, data: {
            name: 'Arthur Morgan', job: 'Compagnie', grade: 'Mécanicien', onService: true, station: 'blackwater', perms: { service: true, drive: true, control: true, maintenance: true, restore: true } } }, '*'));
        await sleep(700);
        const box = await page.evaluate(() => { const r = document.querySelector('.ledger').getBoundingClientRect(); return { x: r.x, y: r.y, w: r.width, h: r.height, fs: getComputedStyle(document.documentElement).fontSize }; });
        const fits = box.x >= 0 && box.y >= 0 && box.x + box.w <= w && box.y + box.h <= h;
        const overflow = await page.evaluate(() => { const p = document.querySelector('.page.current'); return p.scrollWidth > p.clientWidth + 1; });
        check(fits && !overflow, `${w}x${h} : registre dans l'écran (${Math.round(box.w)}x${Math.round(box.h)}, 1rem=${box.fs})`, box);
        await page.screenshot({ path: path.join(OUT, `res-${w}x${h}.png`) });
        await key('Escape'); await sleep(300);
    }

    const errs = await page.evaluate(() => window.__errors);
    check(errs.length === 0 && consoleErrors.length === 0, 'aucune erreur JavaScript', errs.concat(consoleErrors));

    console.log(`\n==== ${passed} réussis, ${failed} échoués ====`);
    await browser.close();
    process.exit(failed ? 1 : 0);
})().catch((e) => { console.error(e); process.exit(2); });
