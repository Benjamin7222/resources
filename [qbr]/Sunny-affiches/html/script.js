const RESOURCE = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'Sunny-affiches';
const $ = (id) => document.getElementById(id);

function el(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
}

async function post(name, data) {
    try {
        const response = await fetch(`https://${RESOURCE}/${name}`, {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(data || {}),
        });
        return await response.json();
    } catch (e) {
        return { ok: false, error: 'Pas de réponse du serveur.' };
    }
}

const state = {
    open: false, board: null, countries: [], country: null, cats: [], counts: {},
    current: null, posters: [], limits: {}, busy: false, gen: 0,
    detail: null, editing: null, expandedGroup: null,
    journal: { enabled: false }, editions: [], editionToken: 0,
};

/* ---------- journal : argent, caisse ---------- */

const money = (cents) => '$' + ((Number(cents) || 0) / 100).toFixed(2);
const journalOn = () => !!(state.journal && state.journal.enabled);
const isJournalCat = (key) => journalOn() && key === state.journal.category;

// Bouton « Récupérer l'argent du journal » : visible seulement s'il y a de l'argent dans la caisse.
function renderWallet() {
    const wallet = journalOn() ? Number(state.journal.wallet) || 0 : 0;
    const btn = $('btn-collect');
    btn.classList.toggle('hidden', !state.journal.canCollect || wallet <= 0);
    btn.textContent = 'Récupérer l\'argent du journal (' + money(wallet) + ')';

    // exemplaires invendus d'affiches supprimées ou expirées, mis de côté pour ce journaliste
    const returns = journalOn() ? Number(state.journal.returns) || 0 : 0;
    const claim = $('btn-claim');
    claim.classList.toggle('hidden', returns <= 0);
    claim.textContent = 'Récupérer mes exemplaires invendus (' + returns + ')';
}

const copies = (n) => n + ' exemplaire' + (n > 1 ? 's' : '');

/* ---------- utilitaires ---------- */

let toastTimer = null;
function toast(text, kind) {
    const node = $('toast');
    node.textContent = text;
    node.className = 'toast ' + (kind || '');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => node.classList.add('hidden'), 3500);
}

function safeUrl(url) {
    return typeof url === 'string' && /^https?:\/\//i.test(url);
}

function catOf(key) {
    return state.cats.find((c) => c.key === key);
}

function countryOf(key) {
    return state.countries.find((c) => c.key === key);
}

function catsHere() {
    return state.cats.filter((c) => c.countries[state.country]);
}

function creatableHere() {
    return catsHere().filter((c) => c.create[state.country]);
}

function countFor(country, catKey) {
    return (state.counts[country] && state.counts[country][catKey]) || 0;
}

function makeImage(url, wrapper) {
    const img = document.createElement('img');
    img.alt = '';
    img.draggable = false;
    img.addEventListener('error', () => {
        img.remove();
        wrapper.classList.add('broken');
    });
    if (safeUrl(url)) img.src = url;
    else wrapper.classList.add('broken');
    return img;
}

function confirmDialog(text) {
    return new Promise((resolve) => {
        $('confirm-text').textContent = text;
        $('confirm').classList.remove('hidden');
        const done = (value) => {
            $('confirm').classList.add('hidden');
            $('confirm-yes').onclick = null;
            $('confirm-no').onclick = null;
            resolve(value);
        };
        $('confirm-yes').onclick = () => done(true);
        $('confirm-no').onclick = () => done(false);
    });
}

/* ---------- pays, catégories, liste ---------- */

function renderCountries() {
    const nav = $('countries');
    nav.replaceChildren();
    for (const country of state.countries) {
        const btn = el('button', 'country' + (country.key === state.country ? ' active' : ''));
        btn.appendChild(el('span', 'label', country.label));
        btn.appendChild(el('span', 'count', String(country.count)));
        btn.addEventListener('click', () => selectCountry(country.key));
        nav.appendChild(btn);
    }
}

function renderCats() {
    const nav = $('cats');
    nav.replaceChildren();
    const here = catsHere();
    const seenGroups = new Set();
    for (const cat of here) {
        if (cat.group) {
            if (seenGroups.has(cat.group)) continue;
            seenGroups.add(cat.group);
            const groupCats = here.filter((c) => c.group === cat.group);
            const groupHasCurrent = groupCats.some((c) => c.key === state.current);
            const expanded = state.expandedGroup === cat.group || groupHasCurrent;

            const btn = el('button', 'cat group' + (groupHasCurrent ? ' active' : '') + (expanded ? ' expanded' : ''));
            btn.style.setProperty('--cat', cat.color || '#b59b6b');
            btn.appendChild(el('span', 'chevron', expanded ? '▾' : '▸'));
            btn.appendChild(el('span', 'label', cat.groupLabel || cat.group));
            if (groupCats.some((c) => c.create[state.country])) {
                const can = el('span', 'can', 'Publier');
                can.title = 'Tu peux afficher dans au moins une mairie';
                btn.appendChild(can);
            }
            const total = groupCats.reduce((sum, c) => sum + countFor(state.country, c.key), 0);
            btn.appendChild(el('span', 'count', String(total)));
            btn.addEventListener('click', () => {
                state.expandedGroup = state.expandedGroup === cat.group ? null : cat.group;
                renderCats();
            });
            nav.appendChild(btn);

            if (expanded) {
                for (const sub of groupCats) {
                    const subBtn = el('button', 'cat sub' + (sub.key === state.current ? ' active' : ''));
                    subBtn.style.setProperty('--cat', sub.color || cat.color || '#b59b6b');
                    subBtn.appendChild(el('span', 'label', sub.label));
                    if (sub.create[state.country]) {
                        const can = el('span', 'can', 'Publier');
                        can.title = 'Tu peux afficher dans cette catégorie';
                        subBtn.appendChild(can);
                    }
                    subBtn.appendChild(el('span', 'count', String(countFor(state.country, sub.key))));
                    subBtn.addEventListener('click', () => selectCategory(sub.key));
                    nav.appendChild(subBtn);
                }
            }
            continue;
        }

        const btn = el('button', 'cat' + (cat.key === state.current ? ' active' : ''));
        btn.style.setProperty('--cat', cat.color || '#b59b6b');
        btn.appendChild(el('span', 'label', cat.label));
        if (cat.create[state.country]) {
            const can = el('span', 'can', 'Publier');
            can.title = 'Tu peux afficher dans cette catégorie';
            btn.appendChild(can);
        }
        btn.appendChild(el('span', 'count', String(countFor(state.country, cat.key))));
        btn.addEventListener('click', () => selectCategory(cat.key));
        nav.appendChild(btn);
    }
}

function renderPosters() {
    const cat = catOf(state.current);
    const list = $('posters');
    list.replaceChildren();
    if (!cat) return;

    $('c-label').textContent = cat.label + ' — ' + (countryOf(state.country) || {}).label;
    $('c-desc').textContent = cat.desc || '';
    if (!cat.create[state.country]) {
        const available = state.countries.filter((country) => cat.countries[country.key] && cat.create[country.key]);
        if (available.length) {
            $('c-desc').textContent += ' Pour publier dans cette catégorie, sélectionne l’onglet : ' + available.map((country) => country.label).join(', ') + '.';
        }
    }
    $('btn-new').classList.toggle('hidden', creatableHere().length === 0);
    $('readonly').classList.toggle('hidden', creatableHere().length > 0);

    const query = $('search').value.trim().toLowerCase();
    const shown = state.posters.filter((p) => !query
        || [p.title, p.author].some((v) => (v || '').toLowerCase().includes(query)));

    $('c-count').textContent = query
        ? shown.length + ' sur ' + state.posters.length
        : shown.length + ' affiche' + (shown.length > 1 ? 's' : '');

    let index = 0;
    for (const poster of shown) {
        const card = el('article', 'poster' + (poster.pinned ? ' pinned' : ''));
        card.style.setProperty('--cat', cat.color || '#b59b6b');
        card.style.setProperty('--rot', (((poster.id * 37) % 9) - 4) * 0.6 + 'deg');
        card.style.setProperty('--i', String(Math.min(index++, 14)));
        card.tabIndex = 0;
        card.setAttribute('role', 'button');
        card.setAttribute('aria-label', poster.title);

        const imgWrap = el('div', 'poster-img');
        if (poster.url) {
            imgWrap.appendChild(makeImage(poster.url, imgWrap));
        } else {
            imgWrap.classList.add('text');
            imgWrap.textContent = poster.title;
        }
        card.appendChild(imgWrap);

        if (poster.url) card.appendChild(el('div', 'poster-title', poster.title));
        card.appendChild(el('div', 'poster-meta', poster.published));
        if (poster.journal) {
            const inStock = poster.journal.stock > 0;
            card.appendChild(el('div', 'poster-sale' + (inStock ? '' : ' out'), inStock ? 'En vente : ' + money(poster.journal.price) : 'Épuisé'));
        }
        if (poster.pinned) card.appendChild(el('span', 'pin-tag', 'Épinglée'));

        const open = () => openDetail(poster, shown);
        card.addEventListener('click', open);
        card.addEventListener('keydown', (event) => {
            if (event.key === 'Enter' || event.key === ' ') {
                event.preventDefault();
                open();
            }
        });
        list.appendChild(card);
    }

    const empty = $('empty');
    if (shown.length === 0) {
        empty.textContent = query ? 'Aucune affiche ne correspond à ta recherche.' : 'Aucune affiche dans cette catégorie pour le moment.';
        empty.classList.remove('hidden');
    } else {
        empty.classList.add('hidden');
    }
}

function recountCountry(countryKey) {
    const info = countryOf(countryKey);
    if (!info) return;
    info.count = state.cats
        .filter((c) => c.countries[countryKey])
        .reduce((sum, c) => sum + countFor(countryKey, c.key), 0);
}

async function loadCategory(country, key) {
    const gen = ++state.gen;
    $('posters').classList.add('loading');
    const res = await post('list', { country, category: key });
    if (gen !== state.gen) return false;
    $('posters').classList.remove('loading');
    if (!res.ok) { toast(res.error || 'Impossible de charger la catégorie.', 'error'); return false; }

    state.country = country;
    state.current = key;
    state.posters = res.posters || [];
    if (res.journal) { state.journal = res.journal; renderWallet(); }
    state.counts[country] = state.counts[country] || {};
    state.counts[country][key] = state.posters.length;
    recountCountry(country);
    renderCountries();
    renderCats();
    renderPosters();
    return true;
}

async function selectCategory(key) {
    if (key === state.current) return;
    $('search').value = '';
    await loadCategory(state.country, key);
}

async function selectCountry(country) {
    if (country === state.country) return;
    const cats = state.cats.filter((c) => c.countries[country]);
    if (cats.length === 0) return;
    // garde la même catégorie si elle contient des affiches dans ce pays, sinon la première qui en contient
    const keep = cats.find((c) => c.key === state.current);
    const filled = cats.find((c) => countFor(country, c.key) > 0);
    $('search').value = '';
    const target = keep && countFor(country, keep.key) > 0 ? keep : (filled || keep || cats[0]);
    await loadCategory(country, target.key);
}

/* ---------- ouverture / fermeture ---------- */

// Métier du joueur dans l'en-tête : sert aussi à repérer le nom technique à mettre dans Config.Jobs.
function renderMe() {
    const me = state.me;
    const node = $('b-me');
    if (!me || !me.job) {
        node.classList.add('hidden');
        return;
    }
    node.replaceChildren();
    node.appendChild(el('span', 'me-main', (me.gradeName ? me.gradeName + ' — ' : '') + (me.label || me.job)));
    let tech = me.job + ' · grade ' + me.grade;
    if (me.admin) tech += ' · admin (tous les droits)';
    node.appendChild(el('span', 'me-tech', tech));
    node.title = 'Nom technique du métier à écrire dans Config.Jobs : ' + me.job;
    node.classList.remove('hidden');
}

function openBoard(data) {
    state.open = true;
    state.busy = false;
    state.board = data.board;
    state.countries = data.countries || [];
    state.country = data.country;
    state.cats = data.categories || [];
    state.counts = data.counts || {};
    state.current = data.current;
    state.posters = data.posters || [];
    state.limits = data.limits || {};
    state.journal = data.journal || { enabled: false };
    renderWallet();

    const board = $('board');
    board.classList.remove('hidden', 'bg', 'nobg');
    board.classList.add(data.background === false ? 'nobg' : 'bg');

    $('b-city').textContent = data.board.name;
    state.me = data.me || null;
    renderMe();
    $('search').value = '';
    renderCountries();
    renderCats();
    renderPosters();
}

function hideAll() {
    for (const id of ['board', 'detail', 'form-modal', 'zoom', 'confirm']) {
        $(id).classList.add('hidden');
    }
}

function closeBoard() {
    if (!state.open) return;
    state.open = false;
    hideAll();
    post('close');
}

/* ---------- fiche détaillée ---------- */

function closeDetail() {
    $('detail').classList.add('hidden');
    state.detail = null;
}

// Affiche précédente / suivante dans la liste affichée.
function stepDetail(delta) {
    const list = state.detailList || [];
    const index = list.findIndex((p) => state.detail && p.id === state.detail.id);
    const next = list[index + delta];
    if (next) openDetail(next, list);
}

// Bloc « Journal en vente » de la fiche : édition, prix, stock, achat ; ajout de stock pour l'auteur.
function renderDetailJournal(poster) {
    const j = poster.journal;
    $('detail-journal').classList.toggle('hidden', !j);
    if (!j) return;

    const meta = $('detail-jmeta');
    meta.replaceChildren();
    const add = (label, value) => {
        meta.appendChild(el('dt', '', label));
        meta.appendChild(el('dd', '', value));
    };
    add('Édition', 'n°' + j.edition + (j.title ? ' — ' + j.title : ''));
    add('Prix', money(j.price));
    add('En vente', copies(j.stock));
    if (j.mine) {
        add('Vendus', String(j.sold));
        add('Dans ton inventaire', copies(j.owned || 0));
    }

    const buy = $('detail-buy');
    buy.disabled = j.stock <= 0;
    buy.textContent = j.stock > 0 ? 'Acheter le journal (' + money(j.price) + ')' : 'Épuisé';

    $('detail-stock').classList.toggle('hidden', !j.mine);
    $('stock-hint').textContent = '(' + (state.journal.maxStock || 100) + ' maximum en vente)';
    $('stock-add').disabled = (j.owned || 0) <= 0;
    $('stock-take').disabled = j.stock <= 0;
}

// Met à jour une affiche en place (achat, stock) puis réaffiche la liste et la fiche.
function applyPosterUpdate(poster, fresh) {
    if (!fresh) return;
    Object.assign(poster, fresh);
    renderPosters();
    openDetail(poster, state.detailList);
}

function openDetail(poster, list) {
    state.detail = poster;
    state.detailList = list && list.length ? list : [poster];
    const cat = catOf(poster.category);
    const box = $('detail');
    box.style.setProperty('--cat', (cat && cat.color) || '#5c3a22');

    const imgWrap = $('detail-img');
    imgWrap.replaceChildren();
    imgWrap.classList.remove('broken');
    imgWrap.classList.toggle('hidden', !poster.url);
    box.firstElementChild.classList.toggle('no-img', !poster.url);
    if (poster.url) {
        imgWrap.appendChild(makeImage(poster.url, imgWrap));
        imgWrap.appendChild(el('span', 'zoom-hint', 'Cliquer pour agrandir'));
    }

    $('detail-cat').textContent = cat ? cat.label : poster.category;
    $('detail-title').textContent = poster.title;

    const meta = $('detail-meta');
    meta.replaceChildren();
    const add = (label, value, cls) => {
        if (!value) return;
        meta.appendChild(el('dt', '', label));
        meta.appendChild(el('dd', cls || '', value));
    };
    add('Pays', (countryOf(poster.country) || {}).label);
    add('Auteur', poster.anonymous ? 'Anonyme' : poster.author);
    add('Publiée le', poster.published);
    if (poster.updated) add('Modifiée le', poster.updated);

    renderDetailJournal(poster);

    $('detail-pin').textContent = poster.pinned ? 'Retirer l\'épingle' : 'Épingler';
    $('detail-pin').classList.toggle('hidden', !poster.canPin);
    $('detail-edit').classList.toggle('hidden', !poster.canEdit);
    $('detail-delete').classList.toggle('hidden', !poster.canDelete);

    const total = state.detailList.length;
    const position = state.detailList.findIndex((p) => p.id === poster.id);
    $('detail-nav').classList.toggle('hidden', total < 2);
    $('detail-pos').textContent = (position + 1) + ' / ' + total;
    $('detail-prev').disabled = position <= 0;
    $('detail-next').disabled = position >= total - 1;
    box.classList.remove('hidden');
}

$('detail-prev').addEventListener('click', () => stepDetail(-1));
$('detail-next').addEventListener('click', () => stepDetail(1));

$('detail-close').addEventListener('click', closeDetail);
$('detail').addEventListener('click', (event) => { if (event.target === $('detail')) closeDetail(); });
/* ---------- zoom sur l'image ---------- */

const ZOOM_MAX = 8;
const zoom = { s: 1, x: 0, y: 0, drag: null, moved: false };

function applyZoom() {
    const img = $('zoom-img');
    img.style.transform = 'translate(' + zoom.x + 'px, ' + zoom.y + 'px) scale(' + zoom.s + ')';
    img.classList.toggle('zoomed', zoom.s > 1.001);
    $('zoom-level').textContent = Math.round(zoom.s * 100) + ' %';
}

// Garde l'image à l'écran : pas de décalage quand elle n'est pas agrandie.
function clampZoom() {
    const img = $('zoom-img');
    zoom.s = Math.min(ZOOM_MAX, Math.max(1, zoom.s));
    const maxX = (img.offsetWidth * (zoom.s - 1)) / 2;
    const maxY = (img.offsetHeight * (zoom.s - 1)) / 2;
    zoom.x = Math.min(maxX, Math.max(-maxX, zoom.x));
    zoom.y = Math.min(maxY, Math.max(-maxY, zoom.y));
    if (zoom.s <= 1.001) { zoom.x = 0; zoom.y = 0; }
}

// Zoome autour d'un point de l'écran : le point sous le curseur reste fixe.
function zoomBy(factor, clientX, clientY) {
    const rect = $('zoom-img').getBoundingClientRect();
    const centerX = rect.left + rect.width / 2 - zoom.x;
    const centerY = rect.top + rect.height / 2 - zoom.y;
    const dx = (clientX == null ? centerX : clientX) - centerX;
    const dy = (clientY == null ? centerY : clientY) - centerY;
    const next = Math.min(ZOOM_MAX, Math.max(1, zoom.s * factor));
    const ratio = next / zoom.s;
    zoom.x = dx - ratio * (dx - zoom.x);
    zoom.y = dy - ratio * (dy - zoom.y);
    zoom.s = next;
    clampZoom();
    applyZoom();
}

function resetZoom() {
    zoom.s = 1; zoom.x = 0; zoom.y = 0; zoom.drag = null; zoom.moved = false;
    applyZoom();
}

function openZoom(url) {
    $('zoom-img').src = url;
    resetZoom();
    $('zoom').classList.remove('hidden');
}

function closeZoom() {
    $('zoom').classList.add('hidden');
    zoom.drag = null;
}

$('detail-img').addEventListener('click', () => {
    if (state.detail && safeUrl(state.detail.url)) openZoom(state.detail.url);
});

$('zoom').addEventListener('wheel', (event) => {
    event.preventDefault();
    zoomBy(Math.exp(-event.deltaY * 0.0018), event.clientX, event.clientY);
}, { passive: false });

$('zoom-img').addEventListener('mousedown', (event) => {
    if (event.button !== 0 || zoom.s <= 1.001) return;
    event.preventDefault();
    zoom.drag = { x: event.clientX, y: event.clientY, ox: zoom.x, oy: zoom.y };
    zoom.moved = false;
    $('zoom-img').classList.add('dragging');
});

document.addEventListener('mousemove', (event) => {
    if (!zoom.drag) return;
    const dx = event.clientX - zoom.drag.x;
    const dy = event.clientY - zoom.drag.y;
    if (Math.abs(dx) + Math.abs(dy) > 3) zoom.moved = true;
    zoom.x = zoom.drag.ox + dx;
    zoom.y = zoom.drag.oy + dy;
    clampZoom();
    applyZoom();
});

document.addEventListener('mouseup', () => {
    if (!zoom.drag) return;
    zoom.drag = null;
    $('zoom-img').classList.remove('dragging');
});

$('zoom-img').addEventListener('dblclick', (event) => {
    if (zoom.s > 1.001) resetZoom();
    else zoomBy(3, event.clientX, event.clientY);
});

// Clic sur le fond : ferme (mais pas à la fin d'un glissé).
$('zoom').addEventListener('click', (event) => {
    if (zoom.moved) { zoom.moved = false; return; }
    if (event.target === $('zoom')) closeZoom();
});

$('zoom-in').addEventListener('click', () => zoomBy(1.4));
$('zoom-out').addEventListener('click', () => zoomBy(1 / 1.4));
$('zoom-fit').addEventListener('click', resetZoom);
$('zoom-close').addEventListener('click', closeZoom);

$('detail-delete').addEventListener('click', async () => {
    const poster = state.detail;
    if (!poster || state.busy) return;
    const unsold = poster.journal ? Number(poster.journal.stock) || 0 : 0;
    const warning = unsold > 0
        ? ' Les ' + copies(unsold) + ' invendu' + (unsold > 1 ? 's' : '') + ' seront mis de côté : le journaliste les récupère avec le bouton « Récupérer mes exemplaires invendus ».'
        : '';
    if (!await confirmDialog('Supprimer l\'affiche « ' + poster.title + ' » ?' + warning)) return;

    state.busy = true;
    const res = await post('delete', { id: poster.id });
    state.busy = false;
    if (res.ok) {
        closeDetail();
        toast(res.parked > 0 ? 'Affiche supprimée : ' + copies(res.parked) + ' mis de côté pour le journaliste.' : 'Affiche supprimée.', 'ok');
    } else {
        toast(res.error || 'Suppression impossible.', 'error');
    }
    loadCategory(state.country, state.current);
});

$('detail-edit').addEventListener('click', () => {
    if (state.detail) openForm(state.detail);
});

$('detail-pin').addEventListener('click', async () => {
    const poster = state.detail;
    if (!poster || state.busy) return;

    state.busy = true;
    const res = await post('pin', { id: poster.id, pinned: !poster.pinned });
    state.busy = false;
    if (res.ok) {
        closeDetail();
        toast(res.pinned ? 'Affiche épinglée en haut de la catégorie.' : 'Épingle retirée.', 'ok');
    } else {
        toast(res.error || 'Impossible de modifier l\'épingle.', 'error');
    }
    loadCategory(state.country, state.current);
});

/* ---------- journal : acheter, stock, caisse ---------- */

// Après une erreur (épuisé, prix changé...) : recharge la liste et remet la fiche à jour.
async function resyncDetail(poster) {
    await loadCategory(state.country, state.current);
    const fresh = state.posters.find((p) => p.id === poster.id);
    if (fresh) openDetail(fresh, state.posters);
    else closeDetail();
}

$('detail-buy').addEventListener('click', async () => {
    const poster = state.detail;
    if (!poster || !poster.journal || state.busy) return;
    const label = poster.journal.title || poster.title;
    if (!await confirmDialog('Acheter « ' + label + ' » pour ' + money(poster.journal.price) + ' ?')) return;

    state.busy = true;
    const res = await post('buy', { id: poster.id, price: poster.journal.price });
    state.busy = false;
    if (!res.ok) {
        toast(res.error || 'Achat impossible.', 'error');
        return resyncDetail(poster);
    }
    if (res.wallet != null && journalOn()) { state.journal.wallet = res.wallet; renderWallet(); }
    applyPosterUpdate(poster, res.poster);
    toast('Journal acheté : tu le trouveras dans ton inventaire.', 'ok');
});

$('stock-add').addEventListener('click', async () => {
    const poster = state.detail;
    if (!poster || !poster.journal || state.busy) return;
    const amount = Math.floor(Number($('stock-amount').value));
    if (!(amount >= 1)) return toast('Indique un nombre d\'exemplaires (1 minimum).', 'error');

    state.busy = true;
    const res = await post('stock', { id: poster.id, amount });
    state.busy = false;
    if (!res.ok) return toast(res.error || 'Ajout impossible.', 'error');
    applyPosterUpdate(poster, res.poster);
    toast(copies(amount) + ' retiré' + (amount > 1 ? 's' : '') + ' de ton inventaire et mis en vente.', 'ok');
});

$('stock-take').addEventListener('click', async () => {
    const poster = state.detail;
    if (!poster || !poster.journal || state.busy) return;
    const amount = Math.floor(Number($('stock-amount').value));
    if (!(amount >= 1)) return toast('Indique un nombre d\'exemplaires (1 minimum).', 'error');

    state.busy = true;
    const res = await post('take', { id: poster.id, amount });
    state.busy = false;
    if (!res.ok) return toast(res.error || 'Impossible de reprendre ces exemplaires.', 'error');
    applyPosterUpdate(poster, res.poster);
    toast(copies(res.given) + ' remis dans ton inventaire' + (res.given < res.requested ? ' (le reste est resté en vente).' : '.'), 'ok');
});

$('btn-claim').addEventListener('click', async () => {
    if (state.busy || !journalOn()) return;
    state.busy = true;
    const res = await post('claim', {});
    state.busy = false;
    if (!res.ok) return toast(res.error || 'Impossible de récupérer les exemplaires.', 'error');
    state.journal.returns = res.returns || 0;
    renderWallet();
    toast(copies(res.given) + ' remis dans ton inventaire' + (res.remaining > 0 ? ' (' + res.remaining + ' à récupérer plus tard : inventaire plein).' : '.'), 'ok');
    if (state.detail) await resyncDetail(state.detail);
    else await loadCategory(state.country, state.current);
});

$('btn-collect').addEventListener('click', async () => {
    if (state.busy || !journalOn() || !state.journal.canCollect) return;
    state.busy = true;
    const res = await post('collect', { country: state.country });
    state.busy = false;
    if (!res.ok) return toast(res.error || 'Impossible de récupérer l\'argent.', 'error');
    state.journal.wallet = res.wallet || 0;
    renderWallet();
    toast('Tu as récupéré ' + money(res.collected) + ' des ventes de ton journal.', 'ok');
});

/* ---------- formulaire ---------- */

function daysLabel(days) {
    if (days === 0) return 'Indéfiniment';
    if (days === -1) return 'Conserver l\'expiration actuelle';
    return days + ' jour' + (days > 1 ? 's' : '');
}

function fillDurations(catKey, editing) {
    const cat = catOf(catKey);
    const select = $('f-days');
    select.replaceChildren();
    const values = editing ? [-1].concat(cat.durations) : cat.durations.slice();
    for (const days of values) {
        const option = el('option', '', daysLabel(days));
        option.value = String(days);
        select.appendChild(option);
    }
    select.value = String(editing ? -1 : cat.defaultDays);

    // indication sous le libellé : durée maximale en jours, et « ou indéfiniment » si proposé
    const positive = cat.durations.filter((d) => d > 0);
    const hint = positive.length
        ? positive.reduce((max, d) => Math.max(max, d), 0) + ' jours maximum'
        : '';
    $('f-days-hint').textContent = '(' + [hint, cat.durations.includes(0) ? 'ou indéfiniment' : ''].filter(Boolean).join(', ') + ')';
}

// Case « Publier anonymement » : seulement à la création, dans les catégories qui l'autorisent.
function updateAnonymousField() {
    const cat = catOf($('f-category').value);
    const show = !state.editing && !!(cat && cat.anonymous);
    $('f-anon-field').classList.toggle('hidden', !show);
    if (!show) $('f-anon').checked = false;
}

function updatePreview() {
    const url = $('f-url').value.trim();
    const box = $('f-preview');
    box.replaceChildren();
    if (!safeUrl(url)) {
        box.appendChild(el('span', '', 'Aperçu'));
        return;
    }
    const img = document.createElement('img');
    img.addEventListener('error', () => box.replaceChildren(el('span', '', 'Image introuvable')));
    img.src = url;
    box.appendChild(img);
}

function updateTitleCount() {
    $('f-count').textContent = '(' + $('f-title').value.length + ' / ' + (state.limits.title || 60) + ')';
}

/* ---------- formulaire : journal lié ---------- */

const journalEdition = () => state.editions.find((e) => e.id === $('f-edition').value) || null;

function updateStockHint() {
    const edition = journalEdition();
    const owned = edition ? Number(edition.owned) || 0 : 0;
    const maximum = Math.min(owned, state.journal.maxStock || 100);
    $('f-stock').max = String(maximum);
    $('f-stock-hint').textContent = '(' + copies(owned) + ' dans ton inventaire, ' + maximum + ' maximum en vente)';
}

// Choisir une édition : sa première page devient l'affiche, le titre, le prix et le stock sont proposés.
function applyEdition() {
    const edition = journalEdition();
    const title = $('f-title');
    $('f-price-row').classList.toggle('hidden', !edition);
    $('f-url').disabled = !!edition;

    if (edition) {
        $('f-url').value = edition.cover;
        if (!title.value.trim() || title.dataset.auto === '1') {
            title.value = (edition.title + ' n°' + edition.edition).slice(0, state.limits.title || 60);
            title.dataset.auto = '1';
        }
        if (!$('f-price').value) $('f-price').value = ((state.journal.defaultPrice || 200) / 100).toFixed(2);
        const maximum = Math.min(Number(edition.owned) || 0, state.journal.maxStock || 100);
        $('f-stock').value = String(Math.min(Number($('f-stock').value || 10), maximum));
        updateStockHint();
    } else {
        // retour à une affiche simple : on libère l'image et on retire le titre proposé
        if (state.editions.some((e) => e.cover === $('f-url').value)) $('f-url').value = '';
        if (title.dataset.auto === '1') { title.value = ''; title.dataset.auto = ''; }
    }
    updatePreview();
    updateTitleCount();
}

// Affiche ou masque la section « Journal lié » selon la catégorie ; charge les éditions du journaliste.
async function updateJournalForm(poster) {
    const token = ++state.editionToken;
    state.editions = [];
    const editing = !!poster;
    const show = isJournalCat($('f-category').value) && (!editing || !!poster.journal);
    $('f-journal').classList.toggle('hidden', !show);
    if (!show) { $('f-url').disabled = false; return; }

    const select = $('f-edition');
    select.replaceChildren();
    $('f-journal-note').textContent = '';

    if (editing) {
        // affiche déjà liée : l'édition ne change plus, seul le prix peut être ajusté par l'auteur
        const option = el('option', '', 'n°' + poster.journal.edition + ' — ' + poster.journal.title);
        option.value = '';
        select.appendChild(option);
        select.disabled = true;
        $('f-price-row').classList.remove('hidden');
        $('f-stock-field').classList.add('hidden');
        $('f-price').value = (poster.journal.price / 100).toFixed(2);
        $('f-price').disabled = !poster.journal.mine;
        $('f-url').disabled = true;
        return;
    }

    select.disabled = false;
    $('f-price').disabled = false;
    $('f-stock-field').classList.remove('hidden');
    $('f-price-row').classList.add('hidden');
    $('f-url').disabled = false;
    const none = el('option', '', 'Aucun (affiche simple)');
    none.value = '';
    select.appendChild(none);
    $('f-journal-note').textContent = 'Chargement de tes éditions…';

    const res = await post('editions', { country: state.country });
    if (token !== state.editionToken) return;
    if (!res.ok) {
        $('f-journal-note').textContent = res.error || 'Impossible de charger tes éditions.';
        return;
    }
    state.editions = res.editions || [];
    for (const edition of state.editions) {
        const option = el('option', '', 'n°' + edition.edition + ' — ' + edition.title + ' (' + copies(Number(edition.owned) || 0) + ' sur toi)');
        option.value = edition.id;
        select.appendChild(option);
    }
    $('f-journal-note').textContent = state.editions.length
        ? 'Les exemplaires mis en vente sont retirés de ton inventaire. Imprime-les d’abord auprès de ta rédaction.'
        : 'Aucune édition publiée pour ta rédaction.';
}

function openForm(poster) {
    const creatable = creatableHere();
    const editing = !!poster;
    if (!editing && creatable.length === 0) return;

    state.editing = editing ? poster.id : null;
    const countryLabel = (countryOf(state.country) || {}).label;
    $('form-heading').textContent = (editing ? 'Modifier l\'affiche' : 'Nouvelle affiche') + ' — ' + countryLabel;
    $('f-submit').textContent = editing ? 'Enregistrer' : 'Publier';

    const catSelect = $('f-category');
    catSelect.replaceChildren();
    const options = editing ? [catOf(poster.category)] : creatable;
    for (const cat of options) {
        const option = el('option', '', cat.label);
        option.value = cat.key;
        catSelect.appendChild(option);
    }
    const preferred = creatable.find((c) => c.key === state.current);
    catSelect.value = editing ? poster.category : (preferred ? preferred.key : creatable[0].key);
    catSelect.disabled = editing;

    $('f-title').maxLength = state.limits.title || 60;
    $('f-title').value = editing ? poster.title : '';
    $('f-url').value = editing ? poster.url : '';

    fillDurations(catSelect.value, editing);
    $('f-anon').checked = false;
    updateAnonymousField();
    $('f-title').dataset.auto = '';
    $('f-url').disabled = false;
    $('f-price').value = '';
    $('f-stock').value = '';
    state.editions = [];
    updateJournalForm(editing ? poster : null);
    updatePreview();
    updateTitleCount();
    $('f-error').classList.add('hidden');
    $('f-submit').disabled = false;
    $('form-modal').classList.remove('hidden');
    $('f-title').focus();
}

function closeForm() {
    $('form-modal').classList.add('hidden');
    state.editing = null;
    state.editionToken++;
    state.editions = [];
    $('f-url').disabled = false;
}

async function submitForm(event) {
    if (event) event.preventDefault();
    if (state.busy) return;
    const showError = (text) => {
        $('f-error').textContent = text;
        $('f-error').classList.remove('hidden');
    };

    const url = $('f-url').value.trim();
    if (!$('f-title').value.trim()) return showError('Le titre est obligatoire.');
    if (url && !safeUrl(url)) return showError('Le lien de l\'image doit commencer par http:// ou https://.');

    const editing = state.editing;

    // journal lié : édition choisie (création) ou prix (affiche déjà liée)
    const journalVisible = !$('f-journal').classList.contains('hidden');
    const edition = !editing && journalVisible ? journalEdition() : null;
    let price;
    let stock;
    if (journalVisible && (edition || editing) && !$('f-price').disabled) {
        price = Number($('f-price').value);
        const min = (state.journal.minPrice || 0) / 100;
        const max = (state.journal.maxPrice || 0) / 100;
        if (!(price >= min && price <= max)) return showError('Le prix doit être compris entre ' + min.toFixed(2) + ' et ' + max.toFixed(2) + ' $.');
    }
    if (edition) {
        stock = Math.floor(Number($('f-stock').value || 0));
        const maxStock = state.journal.maxStock || 100;
        if (!(stock >= 0 && stock <= maxStock)) return showError('Le stock doit être compris entre 0 et ' + maxStock + ' exemplaires.');
        if (stock > (Number(edition.owned) || 0)) return showError('Tu ne possèdes pas assez d’exemplaires de cette édition dans ton inventaire.');
    }

    state.busy = true;
    $('f-submit').disabled = true;
    const res = await post('save', {
        id: editing || undefined,
        country: state.country,
        category: $('f-category').value,
        title: $('f-title').value.trim(),
        url,
        days: Number($('f-days').value),
        anonymous: !editing && $('f-anon').checked ? true : undefined,
        journal_id: edition ? edition.id : undefined,
        price,
        stock,
    });
    state.busy = false;
    $('f-submit').disabled = false;

    if (!res.ok) return showError(res.error || 'Enregistrement impossible.');

    closeForm();
    closeDetail();
    toast(editing ? 'Affiche modifiée.' : 'Affiche publiée.', 'ok');
    $('search').value = '';
    await loadCategory(res.country || state.country, res.category);
}

$('btn-new').addEventListener('click', () => openForm(null));
$('f-cancel').addEventListener('click', closeForm);
$('form').addEventListener('submit', submitForm);
$('f-url').addEventListener('input', updatePreview);
$('f-title').addEventListener('input', () => { $('f-title').dataset.auto = ''; updateTitleCount(); });
$('f-edition').addEventListener('change', applyEdition);
$('f-category').addEventListener('change', () => {
    fillDurations($('f-category').value, false);
    updateAnonymousField();
    updateJournalForm(null);
});

/* ---------- entrées ---------- */

$('search').addEventListener('input', renderPosters);
$('btn-close').addEventListener('click', closeBoard);

window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data) return;
    if (data.action === 'open') openBoard(data.data);
    else if (data.action === 'close') { state.open = false; hideAll(); }
});

const isOpen = (id) => !$(id).classList.contains('hidden');

document.addEventListener('keydown', (event) => {
    const typing = event.target && ['INPUT', 'TEXTAREA', 'SELECT'].includes(event.target.tagName);

    // Échap dans la recherche : efface d'abord le texte
    if (event.key === 'Escape' && event.target === $('search') && $('search').value) {
        event.preventDefault();
        $('search').value = '';
        renderPosters();
        return;
    }

    const close = event.key === 'Escape' || (event.key === 'Backspace' && !typing);
    if (!close) {
        if (isOpen('zoom') && !typing) {
            if (event.key === '+' || event.key === '=') zoomBy(1.4);
            else if (event.key === '-') zoomBy(1 / 1.4);
            else if (event.key === '0') resetZoom();
            return;
        }
        if (event.key === 'Enter' && isOpen('confirm')) $('confirm-yes').click();
        const overlay = isOpen('confirm') || isOpen('zoom') || isOpen('form-modal');
        if (!typing && !overlay && isOpen('detail') && (event.key === 'ArrowLeft' || event.key === 'ArrowRight')) {
            event.preventDefault();
            stepDetail(event.key === 'ArrowLeft' ? -1 : 1);
        } else if (!typing && !overlay && !isOpen('detail') && isOpen('board') && /^[1-9]$/.test(event.key)) {
            const country = state.countries[Number(event.key) - 1];
            if (country) selectCountry(country.key);
        }
        return;
    }
    event.preventDefault();

    if (!$('confirm').classList.contains('hidden')) $('confirm-no').click();
    else if (!$('zoom').classList.contains('hidden')) closeZoom();
    else if (!$('form-modal').classList.contains('hidden')) closeForm();
    else if (!$('detail').classList.contains('hidden')) closeDetail();
    else closeBoard();
});
