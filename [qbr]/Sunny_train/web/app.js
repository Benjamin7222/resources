/* ==========================================================================
   Sunny_train — NUI
   Pile de pages (transitions avant / arrière), navigation clavier, manette
   (relayée par le Lua) et souris. Aucune donnée sensible n'est calculée ici :
   la NUI affiche et transmet des intentions, le serveur décide.
   ========================================================================== */
'use strict';

(() => {
    const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'Sunny_train';
    const $ = (sel, root = document) => root.querySelector(sel);

    const els = {
        app: $('#app'), pages: $('#pages'), crumbs: $('#crumbs'), spine: $('#spine'),
        telegraph: $('#telegraph'), hud: $('#hud'), toasts: $('#toasts'), robbery: $('#robbery'),
        companyName: $('#companyName'), companyMotto: $('#companyMotto'),
        notices: $('#notices'),
    };

    const S = {
        open: false,
        closing: false,
        token: 0,
        view: null,
        data: {},
        st: null,          // données statiques (config publique)
        stack: [],
        busy: false,
        board: null,       // tableau des missions
        fleet: null,       // registre du matériel
        reports: {},       // rapports d'inspection par train
        free: null,        // tableau du voyage libre
        catalogue: null,   // catalogue du matériel (patron)
        live: [],          // annonces de départ en direct
        liveAt: 0,         // Date.now() à la réception de la liste
    };

    // ----------------------------------------------------------------------
    //  Utilitaires
    // ----------------------------------------------------------------------
    const ESC_MAP = { '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' };
    const esc = (v) => String(v ?? '').replace(/[&<>"']/g, (c) => ESC_MAP[c]);
    const money = (v) => '$' + (typeof v === 'number' ? v.toFixed(2) : String(v ?? '0.00'));
    const ROMAN = ['I', 'II', 'III', 'IV', 'V', 'VI', 'VII', 'VIII', 'IX', 'X', 'XI', 'XII', 'XIII', 'XIV', 'XV', 'XVI', 'XVII', 'XVIII', 'XIX', 'XX'];
    const pad2 = (n) => String(n).padStart(2, '0');
    const duration = (s) => `${Math.floor(s / 60)} min ${pad2(Math.floor(s % 60))} s`;
    const stationLabel = (key) => (S.st && S.st.stations[key] ? S.st.stations[key].label : key || '—');
    const company = () => (S.st && S.st.company) || { name: 'Railroad', fullName: 'Railroad Company', motto: 'Service Ferroviaire', founded: '', year: 1899 };

    function clockText(minutes) {
        const h = Math.floor(minutes / 60) % 24, m = minutes % 60;
        if (!S.st || S.st.use24h !== false) return `${pad2(h)}:${pad2(m)}`;
        return `${((h + 11) % 12) + 1}:${pad2(m)} ${h < 12 ? 'AM' : 'PM'}`;
    }

    async function post(endpoint, data = {}) {
        try {
            const res = await fetch(`https://${RES}/${endpoint}`, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json; charset=UTF-8' },
                body: JSON.stringify(data),
            });
            return await res.json();
        } catch (e) {
            return { ok: false, error: 'Le télégraphe ne répond pas.' };
        }
    }

    const sfx = (name) => post('sound', { name });

    // ----------------------------------------------------------------------
    //  Composants HTML
    // ----------------------------------------------------------------------
    function tag(state, label) {
        return `<span class="tag ${esc(state)}">${esc(label)}</span>`;
    }

    function bar(value) {
        const v = Math.max(0, Math.min(100, Number(value) || 0));
        const cls = v < 30 ? 'low' : v < 60 ? 'mid' : '';
        return `<span class="bar ${cls}"><i style="width:${v}%"></i></span>`;
    }

    function trainStateTag(train) {
        const label = (S.st && S.st.trainStates[train.state]) || train.state;
        return tag(train.state, label);
    }

    /**
     * Entrée de registre.
     * @param {object} o { act, label, meta, metaHtml, sub, num, cls, disabled, reason }
     */
    function entry(o) {
        const sub = o.disabled && o.reason ? o.reason : o.sub;
        return `<button class="entry ${o.cls || ''} ${o.disabled ? 'disabled' : ''}" ${o.disabled ? '' : `data-act="${esc(o.act)}"`}>
            <span class="num">${o.num != null ? esc(o.num) : ''}</span>
            <span class="label"><span class="text">${esc(o.label)}</span></span>
            <span class="meta">${o.metaHtml != null ? o.metaHtml : esc(o.meta || '')}</span>
            ${sub ? `<span class="sub">${esc(sub)}</span>` : ''}
        </button>`;
    }

    function entries(list, numbered = true) {
        let n = 0;
        return `<div class="entries">${list.map((o) => entry({ ...o, num: o.num ?? (numbered ? `${ROMAN[n++] || n}.` : '') })).join('')}</div>`;
    }

    function field(k, v, cls = '') {
        return `<div class="field ${cls}"><span class="k">${esc(k)}</span><span class="v">${esc(v)}</span></div>`;
    }

    function track(stations, opts = {}) {
        return `<div class="track">${stations.map((s, i) => {
            const cls = s.served ? 'served' : s.current ? 'current' : '';
            const when = opts.eta ? `+${s.eta} min` : '';
            const extra = i > 0 && i < stations.length - 1 && s.stop > 0 ? `Arrêt ${s.stop} s` : i === 0 ? 'Départ' : i === stations.length - 1 ? 'Terminus' : 'Passage';
            return `<div class="stop ${cls}"><span class="name">${esc(s.label)}<span class="extra">${esc(extra)}</span></span><span class="when">${esc(when)}</span></div>`;
        }).join('')}</div>`;
    }

    function gauge(value) {
        const pt = (pct, r) => {
            const a = Math.PI - (pct / 100) * Math.PI;
            return `${(100 + r * Math.cos(a)).toFixed(1)} ${(100 - r * Math.sin(a)).toFixed(1)}`;
        };
        const arc = (from, to, color) => `<path d="M${pt(from, 80)} A80 80 0 0 1 ${pt(to, 80)}" fill="none" stroke="${color}" stroke-width="9"/>`;
        let ticks = '';
        for (let i = 0; i <= 100; i += 10) {
            ticks += `<line x1="${pt(i, 68).split(' ')[0]}" y1="${pt(i, 68).split(' ')[1]}" x2="${pt(i, 60).split(' ')[0]}" y2="${pt(i, 60).split(' ')[1]}" stroke="currentColor" stroke-width="${i % 50 === 0 ? 2.4 : 1.2}"/>`;
        }
        return `<svg class="gauge" viewBox="0 0 200 125" data-value="${Number(value) || 0}">
            <circle cx="100" cy="100" r="96" fill="none" stroke="currentColor" stroke-width="1" opacity=".35"/>
            ${arc(0, 30, '#962f1c')}${arc(30, 60, '#b0822f')}${arc(60, 100, '#2e4a32')}
            ${ticks}
            <text x="24" y="120" font-family="IM Fell English SC, serif" font-size="11" fill="currentColor">0</text>
            <text x="168" y="120" font-family="IM Fell English SC, serif" font-size="11" fill="currentColor">100</text>
            <text x="100" y="80" text-anchor="middle" font-family="IM Fell English SC, serif" font-size="10" letter-spacing="1.5" fill="currentColor">ÉTAT</text>
            <g class="needle" style="transform: rotate(-90deg)">
                <line x1="100" y1="100" x2="100" y2="30" stroke="#7b2a1b" stroke-width="3" stroke-linecap="round"/>
            </g>
            <circle cx="100" cy="100" r="8" fill="#b8914f" stroke="#6f5226" stroke-width="2"/>
        </svg>`;
    }

    // --- Départs programmés (heure réelle du serveur) -------------------
    const BELL = '<svg class="bell" viewBox="0 0 24 24" aria-hidden="true"><path d="M12 2.5c-.8 0-1.4.6-1.4 1.4v.6C7.9 5.2 6 7.6 6 10.5v4.2l-1.8 2.6h15.6L18 14.7v-4.2c0-2.9-1.9-5.3-4.6-6v-.6c0-.8-.6-1.4-1.4-1.4zM9.6 18.6a2.4 2.4 0 0 0 4.8 0z" fill="currentColor"/></svg>';

    const liveList = () => (S.live && S.live.list) || [];
    const liveFor = (station) => liveList().filter((e) => e.station === station);
    /** Heure du serveur (s) : dernière heure reçue + temps écoulé localement. */
    const serverNow = () => S.live && S.live.now
        ? S.live.now + (Date.now() - S.liveAt) / 1000 : Date.now() / 1000;
    /** Heure du serveur au format HH:MM (fuseau du serveur). */
    function serverClock(epoch) {
        const d = new Date((epoch + ((S.live && S.live.tz) || 0)) * 1000);
        return `${pad2(d.getUTCHours())}:${pad2(d.getUTCMinutes())}`;
    }
    /** Instant local (ms) correspondant à une heure du serveur. */
    const localUntil = (epoch) => Date.now() + (epoch - serverNow()) * 1000;

    /** Statut affiché d'un départ, recalculé à chaque seconde. */
    function departState(e) {
        if (e.departed) return { text: 'Parti', cls: 'gone' };
        const now = serverNow();
        const window = ((S.st && S.st.boardingWindow) || 10) * 60;
        if (now >= e.departAt) return e.atPlatform ? { text: 'Départ imminent', cls: 'soon' } : { text: 'Retardé', cls: 'late' };
        if (e.atPlatform || e.departAt - now <= window) return { text: 'Embarquement', cls: 'soon' };
        const min = Math.ceil((e.departAt - now) / 60);
        return { text: min < 60 ? `Dans ${min} min` : "À l'heure", cls: '' };
    }

    /** Compte à rebours d'un avis aux voyageurs. */
    function departText(untilMs) {
        const r = Math.round((untilMs - Date.now()) / 1000);
        if (r <= 0) return 'Départ imminent';
        if (r < 60) return `Départ dans ${r} s`;
        if (r < 3600) return `Départ dans ${Math.ceil(r / 60)} min`;
        return `Départ dans ${Math.floor(r / 3600)} h ${pad2(Math.ceil((r % 3600) / 60) % 60)}`;
    }

    function statusCell(e) {
        const st = departState(e);
        return `<td class="status ${st.cls}" data-dep="${e.id}">${esc(st.text)}</td>`;
    }

    /** Tableau des départs programmés d'une gare (heure réelle). */
    function liveBoard(stationKey, compact) {
        const list = liveFor(stationKey);
        if (!list.length) {
            return compact ? '' : `<div class="live-board empty"><div class="live-title">${BELL}<span>Départs programmés</span></div><p class="live-none">Aucun départ programmé pour le moment.</p></div>`;
        }
        const rows = list.map((e) => `<tr class="${e.departed ? 'gone' : ''}">
                <td class="time">${esc(e.timeLabel)}</td>
                <td class="dest">${esc(e.destinationLabel)}<span class="via">${esc(e.via || '')}</span></td>
                <td>${esc(e.train || '—')}</td>
                ${statusCell(e)}</tr>`).join('');
        return `<div class="live-board">
                <div class="live-title">${BELL}<span>Départs programmés</span><i>en direct</i></div>
                <table><thead><tr><th>Heure</th><th>Destination</th><th>Train</th><th style="text-align:right">Statut</th></tr></thead>
                <tbody>${rows}</tbody></table>
            </div>`;
    }

    // --- Wagon, charbon, cargaison ---------------------------------------
    const kg = (w) => `${Math.round((w || 0) / 1000).toLocaleString('fr-FR')} kg`;
    const coalText = (t) => (t.needsCoal ? `Charbon : ${t.coal ?? 0}` : 'Sans charbon');

    /** État de la cargaison d'une mission dans le wagon d'un train. */
    function cargoStatus(mission, train) {
        const summary = (train && train.holdSummary) || {};
        return (mission.cargo || []).map((c) => ({ ...c, have: summary[c.item] || 0, ok: (summary[c.item] || 0) >= c.amount }));
    }

    /** Raison bloquant le départ (charbon insuffisant, cargaison incomplète) ou ''. */
    function departBlocker(mission, train, fuelMin) {
        if (train.needsCoal && (train.coal || 0) < fuelMin) return `Charbon insuffisant dans le wagon (${train.coal || 0}/${fuelMin})`;
        const missing = mission ? cargoStatus(mission, train).filter((c) => !c.ok) : [];
        if (missing.length) return `Cargaison incomplète : ${missing.map((c) => `${c.label} ${c.have}/${c.amount}`).join(', ')}`;
        return '';
    }

    function holdTable(train) {
        const rows = (train.hold || []).map((i) => `<tr><td>${esc(i.label)}</td><td>${esc(i.amount)}</td></tr>`).join('');
        return `<table class="money-table">${rows || '<tr><td colspan="2"><i>Wagon vide.</i></td></tr>'}</table>`;
    }

    const TICKET_STAMP = {
        valid: ['VALABLE', 'green'], used: ['POINÇONNÉ', 'black'], expired: ['PÉRIMÉ', 'ochre'],
        forged: ['FAUX BILLET', ''], foreign: ['NON CESSIBLE', ''],
    };

    function ticketCard(t, o = {}) {
        const stamp = o.stamp !== undefined ? o.stamp : (TICKET_STAMP[t.status] || [null])[0];
        const stampCls = o.stampCls !== undefined ? o.stampCls : (TICKET_STAMP[t.status] || [null, ''])[1];
        return `<div class="ticket ${o.mini ? 'mini' : ''}">
            <div class="main">
                <div class="company-arc">${esc(company().fullName)}</div>
                <div class="good-for">Bon pour un voyage</div>
                <div class="journey">
                    <div class="place"><span class="lbl">De</span>${esc(t.fromLabel)}</div>
                    <svg class="arrow"><use href="#arrow"/></svg>
                    <div class="place"><span class="lbl">À</span>${esc(t.toLabel)}</div>
                </div>
                <div class="ticket-meta">
                    <div><b>Classe</b>${esc(t.classLabel)}</div>
                    <div><b>Ligne</b>${esc(t.routeLabel || '—')}</div>
                    ${t.departure ? `<div><b>Départ</b>${esc(t.departure)}</div>` : `<div><b>Délivré le</b>${esc(t.issued || '—')}</div>`}
                </div>
                ${stamp ? `<span class="stamp float ${o.animate ? 'animate' : ''} ${esc(stampCls)}">${esc(stamp)}</span>` : ''}
            </div>
            <div class="stub">
                <div class="price">${money(t.price)}</div>
                <div class="serial">${esc(t.serial || '— — —')}</div>
                <div class="class-badge">${esc((t.classLabel || '').split(' ')[0])}</div>
                ${t.punched ? '<span class="punch"></span>' : ''}
            </div>
        </div>`;
    }

    // ----------------------------------------------------------------------
    //  Pile de pages
    // ----------------------------------------------------------------------
    const current = () => S.stack[S.stack.length - 1];

    function focusables(page = current()) {
        return page && page.el ? [...page.el.querySelectorAll('[data-act]')] : [];
    }

    function select(index, withSound = true) {
        const page = current();
        const list = focusables(page);
        if (!list.length) return;
        const i = ((index % list.length) + list.length) % list.length;
        list.forEach((el, k) => el.classList.toggle('selected', k === i));
        const changed = page.sel !== i;
        page.sel = i;
        list[i].scrollIntoView({ block: 'nearest' });
        if (withSound && changed) sfx('nav');
    }

    function renderCrumbs() {
        els.crumbs.innerHTML = S.stack.map((p, i) => (i === S.stack.length - 1 ? `<b>${esc(p.crumb)}</b>` : esc(p.crumb))).join('<i>&#8226;</i>');
    }

    function mount(page, dir) {
        const old = els.pages.querySelector('.page.current');
        const el = document.createElement('div');
        el.className = 'page current';
        el.innerHTML = typeof page.html === 'function' ? page.html() : page.html;
        page.el = el;

        el.addEventListener('mousemove', (e) => {
            const target = e.target.closest('[data-act]');
            if (!target || S.busy) return;
            const idx = focusables(page).indexOf(target);
            if (idx >= 0 && idx !== page.sel) select(idx, false);
        });
        el.addEventListener('click', (e) => {
            const target = e.target.closest('[data-act]');
            if (!target) return;
            const idx = focusables(page).indexOf(target);
            if (idx >= 0) { select(idx, false); activate(); }
        });

        if (old) {
            old.classList.remove('current', 'enter-right', 'enter-left', 'enter-fade');
            old.classList.add(dir === 'back' ? 'leave-right' : dir === 'forward' ? 'leave-left' : 'leave-fade');
            setTimeout(() => old.remove(), 260);
        }
        if (dir === 'forward') el.classList.add('enter-right');
        else if (dir === 'back') el.classList.add('enter-left');
        else if (dir === 'fade') el.classList.add('enter-fade');

        els.pages.appendChild(el);
        renderCrumbs();
        select(page.sel || 0, false);
        if (page.onMount) page.onMount(el);
    }

    function push(page) { S.stack.push(page); mount(page, 'forward'); }
    function replace(page) {
        const cur = current();
        if (cur) page.sel = page.sel ?? cur.sel;
        S.stack[S.stack.length - 1] = page;
        mount(page, 'fade');
    }
    function resetTo(page) { S.stack = [page]; mount(page, 'back'); }

    function back() {
        if (S.busy) return;
        if (S.stack.length <= 1) { close(); return; }
        S.stack.pop();
        sfx('back');
        mount(current(), 'back');
    }

    async function activate() {
        if (S.busy) return;
        const page = current();
        const el = focusables(page)[page.sel || 0];
        if (!el) return;
        el.classList.remove('pressed');
        void el.offsetWidth;
        el.classList.add('pressed');
        sfx('select');
        const fn = page.actions && page.actions[el.dataset.act];
        if (fn) await fn(el);
    }

    function shake() {
        const page = current();
        if (!page || !page.el) return;
        page.el.classList.remove('shake');
        void page.el.offsetWidth;
        page.el.classList.add('shake');
    }

    // ----------------------------------------------------------------------
    //  Appels Lua
    // ----------------------------------------------------------------------
    async function call(name, payload = {}, opts = {}) {
        S.busy = true;
        const timer = setTimeout(() => els.telegraph.classList.add('show'), 180);
        const res = (await post('action', { name, payload })) || { ok: false };
        clearTimeout(timer);
        els.telegraph.classList.remove('show');
        S.busy = false;
        if (!res.ok) {
            if (res.error) toast(res.error, 'error');
            shake();
        } else if (res.message && !opts.silent) {
            toast(res.message, 'success');
        }
        return res;
    }

    // ----------------------------------------------------------------------
    //  Colonne de gauche
    // ----------------------------------------------------------------------
    function renderSpine() {
        const c = company();
        let title = 'Registre de la compagnie', sub = '', facts = [], stamp = '';
        const d = S.data || {};

        if (S.view === 'company') {
            title = 'Registre du personnel';
            sub = d.station ? `Bureau de ${stationLabel(d.station)}` : 'En déplacement';
            facts = [
                ['Employé', d.name], ['Emploi', [d.job, d.grade].filter(Boolean).join(' — ')],
                ['Mission', d.run ? d.run.missionLabel : 'Aucune'],
            ];
            stamp = d.onService ? '<span class="stamp">EN SERVICE</span>' : '<span class="stamp off">HORS SERVICE</span>';
        } else if (S.view === 'tickets') {
            title = 'Départs et billets';
            sub = `Gare de ${stationLabel(d.station)}`;
            facts = [['Votre bourse', money(d.money)], ['Validité', `${Math.round((d.validity || 0) / 60 * 10) / 10} h`], ['Classes', String((S.st.classes || []).length)]];
            stamp = '<span class="stamp">GUICHET OUVERT</span>';
        } else if (S.view === 'ticket') {
            title = 'Titre de transport';
            sub = 'À présenter au contrôleur';
        } else if (S.view === 'control') {
            title = 'Contrôle des billets';
            sub = 'Titres présentés par le voyageur';
        } else if (S.view === 'board') {
            title = 'Tableau des départs';
            sub = `Gare de ${stationLabel(d.station)}`;
        } else if (S.view === 'report') {
            title = 'Feuille de route';
            sub = 'Rapport de fin de mission';
        }

        const showWatch = ['company', 'tickets', 'board'].includes(S.view) && S.live && S.live.now;
        els.spine.innerHTML = `
            <div class="card">
                <svg class="engraving" viewBox="0 0 320 150"><use href="#locomotive"/></svg>
                <div class="card-title">${esc(title)}</div>
                ${sub ? `<div class="card-sub">${esc(sub)}</div>` : ''}
                ${facts.length ? `<div class="facts">${facts.map(([k, v]) => `<div class="fact"><span>${esc(k)}</span><span>${esc(v || '—')}</span></div>`).join('')}</div>` : ''}
            </div>
            ${showWatch ? pocketWatch(...serverClock(serverNow()).split(':').map(Number)) : ''}
            <div class="spine-stamp">${stamp}</div>
            <div class="spine-foot">${esc(c.fullName)}<br>${esc(c.founded)}</div>`;
    }

    /** Montre à gousset indiquant l'heure du jeu. */
    function pocketWatch(h, m) {
        let ticks = '';
        for (let i = 0; i < 60; i += 1) {
            const a = (i / 60) * Math.PI * 2;
            const r1 = i % 5 === 0 ? 33 : 36;
            ticks += `<line x1="${(50 + r1 * Math.sin(a)).toFixed(1)}" y1="${(54 - r1 * Math.cos(a)).toFixed(1)}" x2="${(50 + 38 * Math.sin(a)).toFixed(1)}" y2="${(54 - 38 * Math.cos(a)).toFixed(1)}" stroke="#2a1c10" stroke-width="${i % 5 === 0 ? 1.6 : .6}"/>`;
        }
        const hourDeg = ((h % 12) + m / 60) * 30;
        const minDeg = m * 6;
        return `<div class="watch">
            <svg viewBox="0 0 100 108" aria-hidden="true">
                <circle cx="50" cy="8" r="6" fill="none" stroke="#b8914f" stroke-width="2.5"/>
                <rect x="45" y="11" width="10" height="7" rx="2" fill="#b8914f" stroke="#6f5226"/>
                <circle cx="50" cy="54" r="46" fill="#8a6a35"/>
                <circle cx="50" cy="54" r="44" fill="#d6b674" stroke="#6f5226" stroke-width="1.5"/>
                <circle cx="50" cy="54" r="40" fill="#f1e5c9" stroke="#6f5226" stroke-width="1"/>
                ${ticks}
                <text x="50" y="30" text-anchor="middle" font-family="IM Fell English SC, serif" font-size="8" fill="#2a1c10">XII</text>
                <text x="50" y="72" text-anchor="middle" font-family="IM Fell English SC, serif" font-size="5" letter-spacing=".6" fill="#7b2a1b">RAILROAD</text>
                <line x1="50" y1="54" x2="50" y2="34" stroke="#2a1c10" stroke-width="3" stroke-linecap="round" transform="rotate(${hourDeg} 50 54)"/>
                <line x1="50" y1="54" x2="50" y2="22" stroke="#2a1c10" stroke-width="1.6" stroke-linecap="round" transform="rotate(${minDeg} 50 54)"/>
                <circle cx="50" cy="54" r="2.6" fill="#7b2a1b"/>
            </svg>
            <div class="watch-label">Heure de la<br>compagnie<b data-clock>${esc(`${pad2(h)}:${pad2(m)}`)}</b></div>
        </div>`;
    }

    function applyCompany() {
        const c = company();
        els.companyName.textContent = c.name;
        els.companyMotto.textContent = c.motto;
        document.querySelectorAll('.seal-text').forEach((n) => { n.textContent = `${String(c.fullName).toUpperCase()} • `; });
        document.querySelectorAll('.seal-year').forEach((n) => { n.textContent = (String(c.founded).match(/\d{4}/) || [''])[0]; });
        document.querySelectorAll('.seal-mono').forEach((n) => {
            n.textContent = String(c.name).split(/\s+/).map((w) => w[0]).join('').slice(0, 3).toUpperCase();
        });
    }

    // ----------------------------------------------------------------------
    //  Pages : registre (employés)
    // ----------------------------------------------------------------------
    function pageMain() {
        const d = S.data;
        const p = d.perms || {};
        const run = d.run;
        const items = [];
        const actions = {};

        let missionReason = '';
        if (!p.drive) missionReason = 'Réservé aux mécaniciens de la compagnie';
        else if (!d.station) missionReason = "Présentez-vous au bureau d'une gare";
        items.push({
            act: 'mission', label: run ? 'Mission en cours' : 'Prendre une mission',
            meta: run ? run.stateLabel : '', cls: run ? 'primary' : '',
            disabled: !run && !!missionReason, reason: missionReason,
        });
        actions.mission = run ? openRun : openBoard;

        if (p.freeTravel) {
            let freeReason = '';
            if (!d.station) freeReason = "Présentez-vous au guichet d'une gare";
            else if (run) freeReason = 'Un train est déjà sous votre responsabilité';
            else if (!S.st.stations[d.station].hasDepot) freeReason = "Cette gare n'a pas de dépôt";
            items.push({ act: 'free', label: 'Sortir un train (voyage)', meta: 'Sans mission', disabled: !!freeReason, reason: freeReason });
            actions.free = openFree;
        }
        if (p.schedule) {
            let schReason = '';
            if (!d.station) schReason = "Présentez-vous au guichet d'une gare";
            const count = d.station ? liveFor(d.station).filter((e) => !e.departed).length : 0;
            items.push({ act: 'schedule', label: 'Programmer un départ', meta: count ? `${count} programmé(s) ici` : 'Heure réelle', disabled: !!schReason, reason: schReason });
            actions.schedule = openSchedule;
        }

        if (p.purchase) {
            items.push({ act: 'catalogue', label: 'Matériel & acquisitions', meta: 'Direction' });
            actions.catalogue = openCatalogue;
        }

        items.push({ act: 'routes', label: 'Consulter les trajets', meta: `${Object.keys(S.st.routes).length} lignes` });
        actions.routes = () => push(pageRoutes());

        items.push({ act: 'schedules', label: 'Horaires', meta: 'Départs du jour' });
        actions.schedules = () => push(pageScheduleStations());

        items.push({ act: 'info', label: 'Informations du train', meta: run ? run.trainLabel : 'Matériel roulant' });
        actions.info = run ? openRun : () => openFleet(true);

        if (p.maintenance) {
            items.push({ act: 'maintenance', label: 'Maintenance', meta: 'Atelier & dépôt' });
            actions.maintenance = () => openFleet(false);
        }

        items.push({ act: 'quit', label: 'Quitter', meta: '' });
        actions.quit = () => close();

        return {
            crumb: 'Registre',
            html: `<div class="page-title">Service ferroviaire</div>
                   <div class="page-intro">${d.station ? `Bureau de la compagnie — gare de ${esc(stationLabel(d.station))}.` : 'Registre de poche de la compagnie.'}</div>
                   ${entries(items)}`,
            actions,
        };
    }

    // --- Missions --------------------------------------------------------
    async function openBoard() {
        const res = await call('missions:board', { station: S.data.station }, { silent: true });
        if (!res.ok) return;
        S.board = res.data;
        push(S.board.deliveries ? pageDeliveries() : pageTrains());
    }

    function pageDeliveries() {
        const b = S.board, actions = {};
        actions.refresh = async () => {
            const res = await call('missions:board', { station: b.station }, { silent: true });
            if (res.ok) { S.board = res.data; replace(pageDeliveries()); }
        };
        const items = b.missions.map((m) => {
            actions[`m:${m.key}`] = () => push(pageDeliveryTrains(m));
            const reason = !m.fromHere ? `À lancer uniquement à ${stationLabel(b.startStation)}`
                : m.allowed === false ? 'Votre emploi ne permet pas ce contrat'
                : m.cooldown > 0 ? `Disponible dans ${Math.ceil(m.cooldown / 60)} min` : '';
            return { act: `m:${m.key}`, label: m.label, meta: money(m.reward),
                sub: `${m.company} — ${m.originLabel} → ${m.terminusLabel} — ${(m.cargo || []).map((c) => `${c.amount} × ${c.label}`).join(', ')}`,
                disabled: !!reason, reason };
        });
        return { crumb: 'Livraisons', actions,
            html: `<div class="page-title">Contrats de livraison</div>
                <div class="page-intro">Chargement et départ uniquement à ${esc(stationLabel(b.startStation))}. Choisissez la livraison, puis le train. Le délai est partagé par tous les cheminots pour chaque catégorie.</div>${entries(items)}
                ${entries([{ act: 'refresh', label: 'Actualiser les contrats', meta: 'Disponibilités globales' }], false)}` };
    }

    function pageDeliveryTrains(mission) {
        const actions = {};
        const items = S.board.trains.filter((t) => mission.trains.includes(t.key)).map((t) => {
            actions[`t:${t.key}`] = () => push(pageOrder(t, mission, null));
            return { act: `t:${t.key}`, label: t.label, sub: coalText(t),
                metaHtml: bar(t.condition), disabled: !t.available, reason: t.reason };
        });
        return { crumb: 'Train', actions,
            html: `<div class="page-title">${esc(mission.label)}</div><div class="page-intro">${esc(mission.originLabel)} → ${esc(mission.terminusLabel)} — ${money(mission.reward)}</div>
                ${items.length ? entries(items) : '<p class="note">La compagnie doit posséder un train de marchandises compatible.</p>'}` };
    }

    function pageTrains() {
        const b = S.board;
        const cooling = b.cooldown > 0;
        const actions = {};
        const items = b.trains.map((t) => {
            actions[`t:${t.key}`] = () => push(pageMissions(t));
            return {
                act: `t:${t.key}`, label: t.label,
                metaHtml: `${bar(t.condition)} ${t.inUse ? tag('warn', 'En ligne') : trainStateTag(t)}`,
                sub: `${t.category} — ${coalText(t)} — ${t.routes.join(', ')}`,
                disabled: !t.available || cooling, reason: cooling ? `Prochaine affectation dans ${b.cooldown} s` : t.reason,
            };
        });
        return {
            crumb: 'Matériel',
            html: `<div class="page-title">Registre du matériel roulant</div>
                   <div class="page-intro">Choisissez la machine affectée au départ de ${esc(stationLabel(b.station))}.</div>
                   ${entries(items)}`,
            actions,
        };
    }

    function pageMissions(train) {
        const b = S.board;
        const actions = {};
        const here = [], elsewhere = [];
        b.missions.filter((m) => m.trains.includes(train.key)).forEach((m) => {
            const item = {
                act: `m:${m.key}`, label: m.label, meta: money(m.reward),
                sub: `${m.company ? m.company + ' — ' : ''}${m.routeLabel} (${m.originLabel} → ${m.terminusLabel})${(m.cargo || []).length ? ' — cargaison à charger' : ''}${m.canBeRobbed ? ' — convoi exposé' : ''}`,
                disabled: !m.fromHere, reason: `Départ depuis ${m.originLabel}`,
            };
            actions[item.act] = () => push(pageOrder(train, m, null));
            (m.fromHere ? here : elsewhere).push(item);
        });
        const free = train.allowFreeRun
            ? (b.freeRuns || []).filter((r) => train.routeKeys.includes(r.route)).map((r) => {
                actions[`f:${r.route}`] = () => push(pageOrder(train, null, r));
                return { act: `f:${r.route}`, label: r.label, meta: 'Sans prime', sub: `Circulation libre jusqu'à ${r.terminusLabel}` };
            })
            : [];

        let html = `<div class="page-title">Ordres de mission</div>
                    <div class="page-intro">Machine affectée : ${esc(train.label)}.</div>`;
        if (here.length) html += `<div class="section-label">Au départ de cette gare</div>${entries(here)}`;
        if (free.length) html += `<div class="section-label">Circulation libre</div>${entries(free)}`;
        if (elsewhere.length) html += `<div class="section-label">Autres départs</div>${entries(elsewhere, false)}`;
        if (!here.length && !free.length && !elsewhere.length) html += '<p class="note">Aucun ordre de mission compatible avec cette machine.</p>';
        return { crumb: 'Missions', html, actions };
    }

    function pageOrder(train, mission, free) {
        const routeKey = mission ? mission.route : free.route;
        const route = S.st.routes[routeKey];
        const orderNo = String(Math.abs([...`${train.key}${routeKey}`].reduce((a, c) => (a * 31 + c.charCodeAt(0)) | 0, 7)) % 9000 + 1000);
        const lines = mission ? [
            ['Prime de mission', money(mission.reward)],
            ['Par gare intermédiaire desservie', money(mission.rewardPerStop)],
            ['Bonus de ponctualité', mission.timeLimit > 0 ? `${money(mission.onTimeBonus)} (sous ${mission.timeLimit} min)` : '—'],
        ] : [['Prime', 'Aucune — circulation libre']];
        if (mission && (mission.rewardItems || []).length) {
            lines.push(['Remis en fin de mission', mission.rewardItems.map((i) => `${i.label} ×${i.amount}`).join(', ')]);
        }
        const cargo = mission ? cargoStatus(mission, train) : [];
        const blocker = departBlocker(mission, train, S.board.fuelMin || 0);
        const cargoHtml = cargo.length ? `<div class="section-label">Cargaison à charger dans le wagon</div>
            <table class="money-table cargo">${cargo.map((c) => `<tr class="${c.ok ? 'ok' : 'ko'}"><td>${esc(c.label)}</td><td>${c.have} / ${c.amount}</td></tr>`).join('')}</table>` : '';

        const actions = {
            hold: () => call('hold:open', { train: train.key }, { silent: true }),
            sign: async () => {
                const payload = { station: S.board.station, train: train.key };
                if (mission) payload.mission = mission.key; else payload.route = routeKey;
                const res = await call('run:start', payload, { silent: true });
                if (!res.ok) return;
                const doc = current().el.querySelector('.doc');
                if (doc) doc.insertAdjacentHTML('beforeend', '<span class="stamp float animate green">APPROUVÉ</span>');
                toast(res.message, 'success');
                S.busy = true;
                setTimeout(() => { S.busy = false; close(); }, 950);
            },
            back: () => back(),
        };
        return {
            crumb: 'Ordre',
            html: `<div class="doc">
                    <div class="doc-head"><span class="title">Ordre de mission</span><span class="no">N° ${orderNo}</span></div>
                    <div class="fields">
                        ${field('Mécanicien', S.data.name)}
                        ${field('Machine', train.label)}
                        ${mission && mission.company ? field('Commanditaire', mission.company, 'wide') : ''}
                        ${field('Nature', mission ? mission.typeLabel : 'Circulation libre')}
                        ${field('Charbon', train.needsCoal ? `${train.coal || 0} dans le wagon (min. ${S.board.fuelMin})` : 'Sans charbon')}
                        ${field('Ligne', route.label)}
                        ${field('Gare de départ', route.stations[0].label)}
                        ${field('Gare de livraison', route.stations[route.stations.length - 1].label)}
                        ${field('Délai', mission && mission.timeLimit > 0 ? `${mission.timeLimit} minutes` : 'Sans limite')}
                        ${field('Exposition', mission && mission.canBeRobbed ? 'Convoi susceptible d’être attaqué' : 'Faible')}
                        ${mission && mission.description ? field('Instructions', mission.description, 'wide') : ''}
                    </div>
                    ${track(route.stations, { eta: !mission || !mission.delivery })}
                    ${cargoHtml}
                    <table class="money-table">${lines.map(([k, v]) => `<tr><td>${esc(k)}</td><td>${esc(v)}</td></tr>`).join('')}</table>
                </div>
                ${entries([
                    { act: 'sign', label: "Signer l'ordre de mission", cls: 'primary', meta: 'Mise en voie', disabled: !!blocker, reason: blocker },
                    { act: 'hold', label: 'Ouvrir le stockage', meta: 'Inventaire du train' },
                    { act: 'back', label: 'Revenir au registre' },
                ], false)}`,
            actions,
        };
    }

    // --- Voyage libre ----------------------------------------------------
    async function openFree() {
        const res = await call('free:board', { station: S.data.station }, { silent: true });
        if (!res.ok) return;
        S.free = res.data;
        push((S.free.scheduled || []).length ? pageFreeStart() : pageFreeTrains());
    }

    /** Départs programmés depuis cette gare, ou voyage sans horaire. */
    function pageFreeStart() {
        const b = S.free;
        const actions = { none: () => push(pageFreeTrains()) };
        const items = b.scheduled.map((dep) => {
            actions[`dep:${dep.id}`] = () => {
                if (dep.trainKey) {
                    const t = b.trains.find((x) => x.key === dep.trainKey);
                    if (!t || !t.available) { toast(t ? t.reason || 'Train indisponible.' : 'Train indisponible.', 'error'); shake(); return; }
                    push(pageFreeOrder(t, { to: dep.destination, label: dep.destinationLabel, routeLabel: dep.via, km: '' }, dep));
                } else {
                    push(pageFreeTrains(dep));
                }
            };
            return {
                act: `dep:${dep.id}`, label: `${dep.timeLabel} — ${dep.destinationLabel}`,
                meta: dep.train || 'Train à choisir',
                sub: `Programmé par ${dep.by || 'la compagnie'} — par ${dep.via}`,
            };
        });
        items.push({ act: 'none', label: 'Voyage sans horaire', meta: 'Départ immédiat ou différé' });
        return {
            crumb: 'Voyage',
            html: `<div class="page-title">Sortir un train</div>
                   <div class="page-intro">Prenez en charge un départ programmé en gare de ${esc(stationLabel(b.station))}, ou partez sans horaire.</div>
                   ${entries(items)}`,
            actions,
        };
    }

    function pageFreeTrains(dep) {
        const b = S.free;
        const actions = {};
        const items = b.trains.map((t) => {
            actions[`t:${t.key}`] = () => push(dep
                ? pageFreeOrder(t, { to: dep.destination, label: dep.destinationLabel, routeLabel: dep.via, km: '' }, dep)
                : pageFreeDestinations(t));
            return {
                act: `t:${t.key}`, label: t.label,
                metaHtml: `${bar(t.condition)} ${t.inUse ? tag('warn', 'En ligne') : trainStateTag(t)}`,
                sub: `${t.category} — ${coalText(t)}`, disabled: !t.available, reason: t.reason,
            };
        });
        return {
            crumb: 'Voyage',
            html: `<div class="page-title">Sortir un train</div>
                   <div class="page-intro">Voyage libre au départ de ${esc(stationLabel(b.station))} : ni mission, ni prime, ni arrêt imposé.</div>
                   ${entries(items)}`,
            actions,
        };
    }

    function pageFreeDestinations(train) {
        const actions = {};
        const items = S.free.destinations.map((dest) => {
            actions[`d:${dest.to}`] = () => push(pageFreeOrder(train, dest));
            return {
                act: `d:${dest.to}`, label: dest.label, meta: `${String(dest.km).replace('.', ',')} km`,
                sub: `${dest.region} — par ${dest.routeLabel}`,
            };
        });
        return {
            crumb: 'Destination',
            html: `<div class="page-title">Destination</div>
                   <div class="page-intro">Machine : ${esc(train.label)}. Toutes les gares reliées par le réseau.</div>
                   ${items.length ? entries(items) : '<p class="note">Aucune gare reliée depuis ici.</p>'}`,
            actions,
        };
    }

    function pageFreeOrder(train, dest, dep) {
        const actions = { back: () => back() };
        const delays = dep ? [0] : (S.free.delays || [0]);
        const items = delays.map((delay) => {
            actions[`go:${delay}`] = async () => {
                const payload = dep ? { station: S.free.station, train: train.key, departure: dep.id }
                    : { station: S.free.station, train: train.key, destination: dest.to, delay };
                const res = await call('run:startFree', payload, { silent: true });
                if (!res.ok) return;
                const doc = current().el.querySelector('.doc');
                if (doc) doc.insertAdjacentHTML('beforeend', '<span class="stamp float animate green">EN VOITURE</span>');
                toast(res.message, 'success');
                S.busy = true;
                setTimeout(() => { S.busy = false; close(); }, 950);
            };
            if (dep) return { act: 'go:0', label: 'Mettre le train à quai', cls: 'primary', meta: `Départ de ${dep.timeLabel}` };
            return delay === 0
                ? { act: 'go:0', label: 'Partir immédiatement', cls: 'primary', meta: 'Avis : départ imminent' }
                : { act: `go:${delay}`, label: `Annoncer le départ dans ${delay} min`, meta: 'Avis aux voyageurs' };
        });
        items.push({ act: 'back', label: dep ? 'Retour' : 'Choisir une autre destination' });
        return {
            crumb: dest.label,
            html: `<div class="doc">
                    <div class="doc-head"><span class="title">Feuille de route — voyage</span><span class="no">${dep ? `Départ ${esc(dep.timeLabel)}` : `${esc(String(dest.km).replace('.', ','))} km`}</span></div>
                    <div class="fields">
                        ${field('Mécanicien', S.data.name)}
                        ${field('Machine', train.label)}
                        ${field('Gare de départ', stationLabel(S.free.station))}
                        ${field('Gare d’arrivée', dest.label)}
                        ${field('Itinéraire', dest.routeLabel, 'wide')}
                        ${field('Arrêts', 'Aucun arrêt imposé')}
                        ${field('Prime', 'Aucune — voyage libre')}
                    </div>
                    <p class="note">Le départ est annoncé aux voyageurs et affiché au tableau des départs de chaque guichet. Le train peut être rangé au dépôt ou au quai d'une gare (F maintenu en cabine, ou depuis le registre).</p>
                </div>
                ${entries(items, false)}`,
            actions,
        };
    }

    // --- Programmation d'un départ (heure réelle) ------------------------
    async function openSchedule() {
        const res = await call('departure:options', {}, { silent: true });
        if (!res.ok) return;
        S.schedule = res.data;
        push(pageScheduleDest());
    }

    function pageScheduleDest() {
        const station = S.st.stations[S.data.station];
        const actions = {};
        const mine = liveFor(station.key).filter((e) => !e.departed);
        const manage = mine.map((e) => {
            actions[`m:${e.id}`] = () => push(pageDepartureManage(e.id));
            return { act: `m:${e.id}`, label: `${e.timeLabel} — ${e.destinationLabel}`, metaHtml: tag(e.linked ? 'ok' : 'warn', e.linked ? 'Train à quai' : 'Programmé'), sub: `${e.train || 'Train à choisir'} — par ${e.by || 'la compagnie'}` };
        });
        const items = (station.destinations || []).map((dest) => {
            actions[`d:${dest.to}`] = () => push(pageScheduleTrain(dest));
            return { act: `d:${dest.to}`, label: dest.label, meta: `${String(dest.km).replace('.', ',')} km`, sub: `par ${dest.via}` };
        });
        return {
            crumb: 'Programmation',
            html: `<div class="page-title">Programmer un départ</div>
                   <div class="page-intro">Au départ de ${esc(station.label)}, à l'heure réelle. Le départ apparaît au tableau et au guichet : les voyageurs peuvent acheter leur billet.</div>
                   ${manage.length ? `<div class="section-label">Départs programmés ici</div>${entries(manage, false)}` : ''}
                   <div class="section-label">Créer un nouveau départ : choisir la gare d’arrivée</div>
                   ${entries(items)}`,
            actions,
            live: true,
            rebuild: () => pageScheduleDest(),
        };
    }

    function pageScheduleTrain(dest) {
        const actions = { any: () => push(pageScheduleTime(dest, null)) };
        const items = [{ act: 'any', label: 'Train non précisé', meta: 'Choisi à la mise en voie', sub: 'Le mécanicien choisira la machine au moment du départ.' }];
        (S.schedule.trains || []).forEach((t) => {
            actions[`t:${t.key}`] = () => push(pageScheduleTime(dest, t));
            items.push({ act: `t:${t.key}`, label: t.label, meta: t.category });
        });
        return {
            crumb: dest.label,
            html: `<div class="page-title">Train du départ</div>
                   <div class="page-intro">${esc(stationLabel(S.data.station))} → ${esc(dest.label)}.</div>
                   ${entries(items, false)}`,
            actions,
        };
    }

    function pageScheduleTime(dest, train) {
        const actions = {};
        const items = (S.schedule.slots || []).map((slot) => {
            actions[`s:${slot.at}`] = async () => {
                const payload = { station: S.data.station, destination: dest.to, departAt: slot.at };
                if (train) payload.train = train.key;
                const res = await call('departure:create', payload);
                if (res.ok) resetTo(pageMain());
            };
            const inMin = slot.inMinutes;
            return { act: `s:${slot.at}`, label: slot.label, meta: inMin < 60 ? `dans ${inMin} min` : `dans ${Math.floor(inMin / 60)} h ${pad2(inMin % 60)}` };
        });
        return {
            crumb: 'Horaire',
            html: `<div class="page-title">Heure de départ</div>
                   <div class="page-intro">${esc(stationLabel(S.data.station))} → ${esc(dest.label)} — ${esc(train ? train.label : 'train non précisé')}. Heure réelle du serveur.</div>
                   ${entries(items, false)}`,
            actions,
        };
    }

    function pageDepartureManage(id) {
        const e = liveList().find((x) => x.id === id);
        if (!e) return pageScheduleDest();
        const actions = { back: () => back() };
        const items = [];
        if (!e.linked && !e.departed) {
            items.push({ act: 'cancel', label: 'Annuler ce départ', cls: 'danger' });
            actions.cancel = () => push(pageConfirm({
                title: 'Annuler le départ', text: `Le départ de ${e.timeLabel} pour ${e.destinationLabel} sera retiré du tableau. Les voyageurs sont prévenus.`,
                confirm: 'Annuler le départ', onConfirm: async () => { const res = await call('departure:cancel', { id }); if (res.ok) resetTo(pageMain()); },
            }));
        }
        items.push({ act: 'back', label: 'Retour' });
        return {
            crumb: e.timeLabel,
            html: `<div class="doc">
                    <div class="doc-head"><span class="title">Départ de ${esc(e.timeLabel)}</span>${tag(e.linked ? 'ok' : 'warn', e.linked ? 'Train à quai' : 'Programmé')}</div>
                    <div class="fields">
                        ${field('Gare', e.stationLabel)}
                        ${field('Destination', e.destinationLabel)}
                        ${field('Train', e.train || 'Non précisé')}
                        ${field('Programmé par', e.by || '—')}
                        ${field('Itinéraire', e.via || '—', 'wide')}
                    </div>
                </div>
                ${entries(items, false)}`,
            actions,
        };
    }

    // --- Matériel & acquisitions (patron) -------------------------------
    async function openCatalogue() {
        const res = await call('fleet:catalogue', {}, { silent: true });
        if (!res.ok) return;
        S.catalogue = res.data;
        push(pageCatalogue());
    }

    function pageCatalogue() {
        const c = S.catalogue;
        const actions = {};
        const items = c.trains.map((t) => {
            actions[`c:${t.key}`] = () => push(pageCatalogueTrain(t.key));
            return {
                act: `c:${t.key}`, label: t.label,
                metaHtml: t.owned ? tag('ok', 'Possédé') : esc(money(t.price)),
                sub: `${t.category} — ${t.holdSlots} emplacements — ${Math.round(t.maxSpeed * 2.23694)} mph — ${t.needsCoal ? `${t.coalPerKm} charbon/km` : 'sans charbon'}`,
            };
        });
        return {
            crumb: 'Matériel',
            html: `<div class="page-title">Catalogue du matériel roulant</div>
                   <div class="page-intro">Du plus modeste au plus luxueux. Fonds disponibles (${c.account === 'society' ? 'société' : 'personnels'}) : ${esc(money(c.balance))}.</div>
                   ${entries(items)}`,
            actions,
        };
    }

    function pageCatalogueTrain(key) {
        const c = S.catalogue;
        const t = c.trains.find((x) => x.key === key);
        const resale = Math.floor(t.price * (c.sellRatio || 0));
        const refresh = async () => {
            const res = await call('fleet:catalogue', {}, { silent: true });
            if (res.ok) S.catalogue = res.data;
            S.stack.pop();
            S.stack[S.stack.length - 1] = pageCatalogueTrain(key);
            mount(current(), 'fade');
        };
        const actions = { back: () => back() };
        const items = [];
        if (!t.owned) {
            items.push({ act: 'buy', label: `Acquérir pour ${money(t.price)}`, cls: 'primary', disabled: !c.canBuy, reason: 'Réservé à la direction' });
            actions.buy = () => push(pageConfirm({
                title: 'Acquisition', text: `La compagnie acquiert « ${t.label} » pour ${money(t.price)}. Le train rejoint la flotte immédiatement.`,
                confirm: `Payer ${money(t.price)}`, onConfirm: async () => { const res = await call('fleet:buy', { train: key }); if (res.ok) await refresh(); },
            }));
        } else if (!t.starter && resale > 0) {
            items.push({ act: 'sell', label: `Revendre pour ${money(resale)}`, cls: 'danger', disabled: !c.canBuy || t.inUse, reason: t.inUse ? 'Train en circulation' : 'Réservé à la direction' });
            actions.sell = () => push(pageConfirm({
                title: 'Revente', text: `« ${t.label} » quittera la flotte. Le contenu de son wagon reste conservé.`,
                confirm: `Revendre pour ${money(resale)}`, onConfirm: async () => { const res = await call('fleet:sell', { train: key }); if (res.ok) await refresh(); },
            }));
        }
        items.push({ act: 'back', label: 'Retour au catalogue' });
        return {
            crumb: t.label,
            html: `<div class="doc">
                    <div class="doc-head"><span class="title">${esc(t.label)}</span><span class="no">Rang ${t.tier} — ${esc(t.category)}</span></div>
                    <div class="fields">
                        ${field('Prix', money(t.price))}
                        ${field('Statut', t.owned ? (t.starter ? 'Fourni à la compagnie' : 'Possédé') : 'Disponible à l\'achat')}
                        ${field('Vitesse max.', `${Math.round(t.maxSpeed * 2.23694)} mph`)}
                        ${field('Charbon', t.needsCoal ? `${t.coalPerKm} par kilomètre` : 'Aucun (traction à bras)')}
                        ${field('Wagon', `${t.holdSlots} emplacements — ${kg(t.holdWeight)}`)}
                        ${field('Missions', t.allowMissions ? (t.serviceTypes.join(', ') || '—') : 'Voyages uniquement')}
                        ${field('Lignes', t.routes.join(', ') || '—', 'wide')}
                    </div>
                    <p class="note">${esc(t.description)}</p>
                    ${t.owned ? '<span class="stamp float green">EN FLOTTE</span>' : ''}
                </div>
                ${entries(items, false)}`,
            actions,
        };
    }

    // --- Mission en cours ------------------------------------------------
    async function openRun() {
        const res = await call('run:summary', {}, { silent: true });
        if (!res.ok) return;
        if (!res.data) {
            S.data.run = null;
            renderSpine();
            toast('Aucun ordre de mission en cours.', 'info');
            replace(pageMain());
            return;
        }
        push(pageRun(res.data));
    }

    function pageRun(r) {
        const actions = {
            finish: async () => {
                const res = await call('run:finish', {}, { silent: true });
                if (res.ok) S.data.run = null;
            },
            cancel: () => push(pageConfirm({
                title: 'Abandonner la mission',
                text: "L'abandon d'un ordre de mission est consigné et suspend toute nouvelle affectation pendant quelques minutes. Le train sera retiré de la voie.",
                confirm: 'Abandonner la mission',
                onConfirm: async () => {
                    const res = await call('run:cancel');
                    if (!res.ok) return;
                    S.data.run = null;
                    renderSpine();
                    resetTo(pageMain());
                },
            })),
            back: () => back(),
        };
        const items = [];
        if (r.free) {
            items.push({ act: 'finish', label: 'Ranger le train', cls: 'primary', meta: r.state === 'arrived' ? 'Arrivé à destination' : 'Fin du voyage' });
        } else {
            if (r.state === 'arrived') items.push({ act: 'finish', label: 'Terminer le trajet', cls: 'primary', meta: 'Terminus atteint' });
            items.push({ act: 'cancel', label: 'Abandonner la mission', cls: 'danger', disabled: r.state === 'robbery', reason: 'Impossible pendant une attaque' });
        }
        items.push({ act: 'back', label: 'Retour' });
        const stations = r.stations.map((s) => ({ ...s, current: s.current && !s.served }));

        return {
            crumb: 'Feuille de marche',
            html: `<div class="doc">
                    <div class="doc-head"><span class="title">Feuille de marche</span><span class="no">Run ${esc(r.id)}</span></div>
                    <div class="fields">
                        ${field('Mission', r.missionLabel)}
                        ${field('Nature', r.missionType)}
                        ${field('Machine', r.trainLabel)}
                        ${field('Ligne', r.routeLabel)}
                        ${field('État', r.stateLabel)}
                        ${field('Temps écoulé', duration(r.elapsed))}
                        ${field(r.free ? 'Destination' : 'Prochain arrêt', r.state === 'arrived' ? 'Arrivé' : r.nextStation)}
                        ${field('Délai', r.free ? 'Voyage libre' : (r.timeLimit > 0 ? `${r.timeLimit} min` : 'Sans limite'))}
                    </div>
                    ${track(stations)}
                    <div class="gauge-wrap"><span class="field" style="flex:1"><span class="k">État de la machine</span><span class="v">${bar(r.condition)} ${r.condition} %</span></span>${r.robbed ? tag('danger', 'Convoi dévalisé') : ''}</div>
                </div>
                ${entries(items, false)}`,
            actions,
        };
    }

    // --- Lignes & horaires -----------------------------------------------
    function pageRoutes() {
        const actions = {};
        const items = Object.values(S.st.routes).filter((r) => !r.delivery).sort((a, b) => a.label.localeCompare(b.label)).map((r) => {
            actions[`r:${r.key}`] = () => push(pageRoute(r));
            return {
                act: `r:${r.key}`, label: r.label, meta: `≈ ${r.duration} min`,
                sub: `${r.stations[0].label} → ${r.stations[r.stations.length - 1].label} — ${r.stations.length} gares`,
            };
        });
        return {
            crumb: 'Lignes',
            html: `<div class="page-title">Lignes de la compagnie</div>
                   <div class="page-intro">Réseau exploité par la ${esc(company().fullName)}.</div>
                   ${entries(items)}`,
            actions,
        };
    }

    function pageRoute(r) {
        return {
            crumb: r.label,
            html: `<div class="doc">
                    <div class="doc-head"><span class="title">${esc(r.label)}</span><span class="no">≈ ${esc(r.duration)} min</span></div>
                    ${track(r.stations, { eta: true })}
                    <div class="fields">
                        ${field('Départs', (r.departures || []).join(' · ') || '—', 'wide')}
                    </div>
                    <p class="note">Les durées indiquées suivent l'horloge de la compagnie ; les temps d'arrêt en gare sont obligatoires.</p>
                </div>
                ${entries([{ act: 'back', label: 'Retour aux lignes' }], false)}`,
            actions: { back: () => back() },
        };
    }

    function pageScheduleStations() {
        const actions = {};
        const here = S.data.station;
        const list = Object.values(S.st.stations)
            .sort((a, b) => (a.key === here ? -1 : b.key === here ? 1 : a.label.localeCompare(b.label)));
        const items = list.map((s) => {
            actions[`s:${s.key}`] = () => push(pageBoard(s));
            const n = liveFor(s.key).filter((e) => !e.departed).length;
            return { act: `s:${s.key}`, label: s.label, meta: n ? `${n} départ(s)` : 'Aucun départ', sub: s.key === here ? `${s.region} — gare actuelle` : s.region };
        });
        return {
            crumb: 'Horaires',
            live: true,
            rebuild: () => pageScheduleStations(),
            html: `<div class="page-title">Indicateur des chemins de fer</div>
                   <div class="page-intro">Départs programmés par la compagnie, à l'heure réelle.</div>
                   ${entries(items)}`,
            actions,
        };
    }

    function pageBoard(station, isRoot) {
        return {
            crumb: station.label,
            live: true,
            rebuild: () => pageBoard(station, isRoot),
            html: `<div class="departures">
                    <div class="board-title">Départs — ${esc(station.label)}</div>
                    <div class="board-clock">Heure : <span data-clock>${esc(serverClock(serverNow()))}</span></div>
                </div>
                ${liveBoard(station.key, false)}
                ${entries([{ act: 'back', label: isRoot ? 'Fermer le tableau' : 'Retour aux gares' }], false)}`,
            actions: { back: () => back() },
        };
    }

    // --- Matériel & maintenance ------------------------------------------
    async function openFleet(readOnly) {
        const res = await call('fleet:list', {}, { silent: true });
        if (!res.ok) return;
        S.fleet = res.data;
        push(pageFleet(readOnly));
    }

    function refreshFleetTrain(view) {
        if (!view || !S.fleet) return;
        const i = S.fleet.trains.findIndex((t) => t.key === view.key);
        if (i >= 0) S.fleet.trains[i] = view;
    }

    function pageFleet(readOnly) {
        const actions = {};
        const items = S.fleet.trains.map((t) => {
            actions[`t:${t.key}`] = () => push(pageFleetTrain(t.key, readOnly));
            return {
                act: `t:${t.key}`, label: t.label,
                metaHtml: `${bar(t.condition)} ${t.inUse ? tag('warn', 'En ligne') : trainStateTag(t)}`,
                sub: `${t.serviceTypes.join(', ')} — ${t.routes.join(', ')}`,
            };
        });
        let intro = 'État général de la flotte de la compagnie.';
        if (!readOnly && !S.fleet.atDepot) intro = "Les travaux ne peuvent être effectués qu'au dépôt d'une gare équipée.";
        return {
            crumb: readOnly ? 'Matériel' : 'Atelier',
            html: `<div class="page-title">${readOnly ? 'Informations du matériel' : 'Atelier de maintenance'}</div>
                   <div class="page-intro">${esc(intro)}</div>
                   ${entries(items)}`,
            actions,
        };
    }

    function pageFleetTrain(key, readOnly) {
        const f = S.fleet;
        const t = f.trains.find((x) => x.key === key);
        const report = S.reports[key];
        const workReason = !f.atDepot ? 'Rendez-vous au dépôt' : t.inUse ? 'Machine en circulation' : '';
        const actions = { back: () => back() };
        const items = [];

        if (!readOnly && f.canMaintain) {
            items.push({ act: 'inspect', label: 'Inspecter la machine', meta: `${Math.round(f.inspectDuration / 1000)} s`, disabled: !!workReason, reason: workReason });
            actions.inspect = () => doWork({ kind: 'inspect', train: key }, 'Inspection en cours', f.inspectDuration);
            const needInspect = f.requireInspection && !t.inspectionValid;
            items.push({
                act: 'repairs', label: 'Réparer', meta: 'Choisir les travaux',
                disabled: !!workReason || needInspect || t.condition >= 100,
                reason: workReason || (needInspect ? 'Inspection préalable requise' : 'Machine en parfait état'),
            });
            actions.repairs = () => push(pageRepairs(key));
        }
        if (!readOnly && f.canRestore) {
            if (t.state === 'out_of_service' || t.manualOut) {
                items.push({ act: 'restore', label: 'Remettre en service', cls: 'primary', disabled: !!workReason || t.condition < f.restoreMin, reason: workReason || `État minimal : ${f.restoreMin} %` });
                actions.restore = () => fleetDecision('fleet:restore', key, readOnly);
            } else {
                items.push({ act: 'retire', label: 'Retirer du service', cls: 'danger', disabled: !!workReason, reason: workReason });
                actions.retire = () => push(pageConfirm({
                    title: 'Retirer du service', text: `${t.label} ne pourra plus recevoir d'ordre de mission jusqu'à sa remise en service.`,
                    confirm: 'Retirer la machine', onConfirm: async () => { await fleetDecision('fleet:retire', key, readOnly, true); },
                }));
            }
        }
        items.push({ act: 'hold', label: 'Ouvrir le stockage', meta: t.holdOpen ? 'Déjà ouvert' : 'Inventaire du train', disabled: t.holdOpen, reason: 'Le stockage est ouvert par un autre employé' });
        actions.hold = () => call('hold:open', { train: key }, { silent: true });
        items.push({ act: 'back', label: 'Retour' });

        const reportHtml = report ? `<div class="section-label">Rapport d'inspection — ${esc(report.inspector)}</div>
            <div class="report-grid">${report.report.map((c) => `<span class="k">${esc(c.label)}</span>${bar(c.value)}${tag(c.state, `${c.value} %`)}`).join('')}</div>` : '';

        return {
            crumb: t.label,
            html: `<div class="doc">
                    <div class="doc-head"><span class="title">${esc(t.label)}</span>${trainStateTag(t)}</div>
                    <div class="gauge-wrap">
                        ${gauge(t.condition)}
                        <div class="fields" style="flex:1">
                            ${field('État général', `${t.condition} %`)}
                            ${field('Vitesse max.', `${Math.round(t.maxSpeed * 2.23694)} mph`)}
                            ${field('Lignes', t.routes.join(', '), 'wide')}
                            ${field('Services', t.serviceTypes.join(', '), 'wide')}
                            ${field('Inspection', t.inspectionValid ? 'Valable' : 'À effectuer')}
                            ${field('Circulation', t.inUse ? 'En ligne' : 'Au dépôt')}
                            ${field('Charbon', t.needsCoal ? String(t.coal ?? 0) : 'Sans charbon')}
                            ${field('Wagon', `${(t.hold || []).length} / ${t.holdSlots} emplacements — ${kg(t.holdWeight)}`)}
                        </div>
                    </div>
                    <p class="note">${esc(t.description)}</p>
                    <div class="section-label">Contenu du wagon</div>
                    ${holdTable(t)}
                    ${reportHtml}
                </div>
                ${entries(items, false)}`,
            actions,
            onMount: animateGauges,
        };
    }

    function animateGauges(el) {
        el.querySelectorAll('.gauge').forEach((g) => {
            const v = Math.max(0, Math.min(100, Number(g.dataset.value) || 0));
            requestAnimationFrame(() => requestAnimationFrame(() => {
                g.querySelector('.needle').style.transform = `rotate(${-90 + v * 1.8}deg)`;
            }));
        });
    }

    async function fleetDecision(name, key, readOnly, popConfirm) {
        const res = await call(name, { train: key });
        if (!res.ok) return;
        refreshFleetTrain(res.data.train);
        if (popConfirm) S.stack.pop();
        S.stack[S.stack.length - 1] = pageFleetTrain(key, readOnly);
        mount(current(), 'fade');
    }

    function pageRepairs(key) {
        const f = S.fleet;
        const actions = {};
        const items = f.repairs.map((r) => {
            const missing = r.items.filter((i) => i.have < i.amount);
            actions[`r:${r.id}`] = () => doWork({ kind: 'repair', train: key, repair: r.id }, r.label, r.duration);
            return {
                act: `r:${r.id}`, label: r.label, meta: `+${r.restore} %`,
                sub: `${r.description} — ${r.items.map((i) => `${i.label} ×${i.amount} (${i.have})`).join(', ')}`,
                disabled: missing.length > 0, reason: `Matériel manquant : ${missing.map((i) => `${i.label} ×${i.amount - i.have}`).join(', ')}`,
            };
        });
        return {
            crumb: 'Travaux',
            html: `<div class="page-title">Bon de travaux</div>
                   <div class="page-intro">Les fournitures sont prélevées dans votre sacoche à la fin des travaux.</div>
                   ${entries(items)}`,
            actions,
        };
    }

    /** Travaux longs : page de progression, fermeture = abandon. */
    async function doWork(payload, title, ms) {
        const key = payload.train;
        const readOnly = false;
        push({
            crumb: 'Travaux',
            html: `<div class="work">
                    <div class="work-title">${esc(title)}</div>
                    <div class="tube"><i></i></div>
                    <p class="note">Fermer le registre interrompt les travaux.</p>
                </div>`,
            actions: {},
            onMount: (el) => {
                const fill = el.querySelector('.tube i');
                requestAnimationFrame(() => {
                    fill.style.transition = `width ${ms}ms linear`;
                    fill.style.width = 'calc(100% - .36rem)';
                });
            },
        });
        const res = await call('fleet:work', payload, { silent: true });
        if (!S.open || S.closing) return;
        if (res.ok) {
            toast(res.message, 'success');
            refreshFleetTrain(res.data.train);
            if (res.data.report) S.reports[key] = { report: res.data.report, inspector: res.data.inspector };
            refreshFleetItems();
        }
        // Retour à la fiche de la machine.
        while (S.stack.length > 1 && !(current().crumb && S.fleet.trains.some((t) => t.label === current().crumb))) S.stack.pop();
        S.stack[S.stack.length - 1] = pageFleetTrain(key, readOnly);
        mount(current(), 'back');
    }

    async function refreshFleetItems() {
        const res = await post('action', { name: 'fleet:list', payload: {} });
        if (res && res.ok) {
            S.fleet.repairs = res.data.repairs;
            S.fleet.atDepot = res.data.atDepot;
        }
    }

    // --- Contrôle des billets -------------------------------------------
    function pageControlResult(data) {
        const actions = { back: () => back() };
        const tickets = data.tickets || [];
        let body;
        if (!tickets.length) {
            body = `<div class="doc" style="text-align:center;padding:1.6rem">
                        <span class="stamp animate">SANS BILLET</span>
                        <p class="note" style="margin-top:1rem">Le voyageur ne présente aucun titre de transport.</p>
                    </div>`;
        } else {
            body = entries(tickets.map((t, i) => {
                actions[`k:${i}`] = () => push(pageControlTicket(data, i));
                const st = TICKET_STAMP[t.status] || ['?', ''];
                return {
                    act: `k:${i}`, label: `${t.fromLabel} → ${t.toLabel}`,
                    metaHtml: tag(t.warning ? 'warn' : t.status, t.warning ? 'Autre ligne' : st[0]),
                    sub: `N° ${t.serial} — ${t.classLabel} — délivré le ${t.issued}${t.warning ? ` — ${t.warning}` : ''}`,
                };
            }));
        }
        return {
            crumb: data.passenger,
            html: `<div class="page-title">Voyageur : ${esc(data.passenger)}</div>
                   <div class="page-intro">${data.line ? `Convoi de la ${esc(data.line)}.` : 'Contrôle hors convoi.'} ${tickets.length} titre(s) présenté(s).</div>
                   ${body}
                   ${entries([{ act: 'back', label: 'Terminer le contrôle' }], false)}`,
            actions,
        };
    }

    function pageControlTicket(data, index, justPunched) {
        const t = data.tickets[index];
        const canPunch = t.valid && !t.punched;
        const items = [];
        if (canPunch) items.push({ act: 'punch', label: 'Poinçonner le billet', cls: 'primary', meta: 'Pince du contrôleur' });
        items.push({ act: 'back', label: t.punched ? 'Terminer le contrôle' : 'Retour' });
        return {
            crumb: `N° ${t.serial}`,
            html: `${ticketCard(t, justPunched ? { stamp: 'POINÇONNÉ', stampCls: 'black', animate: true } : { animate: true })}
                   ${t.punched ? '<p class="note">Billet poinçonné et retiré de l’inventaire du voyageur.</p>' : ''}
                   ${t.warning ? `<p class="ticket-warning">${esc(t.warning)}</p>` : ''}
                   ${entries(items, false)}`,
            actions: {
                punch: async () => {
                    const res = await call('control:punch', { target: data.target, serial: t.serial });
                    if (!res.ok) return;
                    data.tickets[index] = { ...t, ...res.data.ticket };
                    S.stack[S.stack.length - 1] = pageControlTicket(data, index, true);
                    mount(current(), 'fade');
                },
                back: () => back(),
            },
        };
    }

    // ----------------------------------------------------------------------
    //  Pages : guichet (public)
    // ----------------------------------------------------------------------
    function pageTicketDestinations() {
        const d = S.data;
        const actions = {};
        // Liste du serveur, mise à jour en direct (départs partis ou annulés retirés).
        const live = {};
        liveFor(d.station).forEach((e) => { live[e.id] = e; });
        const deps = liveFor(d.station);
        const items = deps.map((dep) => {
            actions[`dep:${dep.id}`] = async () => {
                // Relire les tarifs et l'état du départ sans fermer le tableau.
                const res = await call('tickets:office', { station: d.station }, { silent: true });
                if (!res.ok) return;
                const currentDeparture = res.data.departures.find((entry) => entry.id === dep.id);
                S.data = { ...S.data, ...res.data };
                renderSpine();
                if (!currentDeparture) {
                    toast('Ce départ ne vend plus de billets.', 'error');
                    replace(pageTicketDestinations());
                    return;
                }
                push(pageTicketStops(currentDeparture));
            };
            return {
                act: `dep:${dep.id}`, label: `${dep.timeLabel} — ${dep.destinationLabel}`,
                metaHtml: `<span class="status ${departState(live[dep.id]).cls}" data-dep="${Number(dep.id)}">${esc(departState(live[dep.id]).text)}</span>`,
                sub: `${dep.train || 'Train de la compagnie'}${dep.via ? ` — par ${dep.via}` : ''}`,
                disabled: dep.departed === true, reason: 'Ce train est déjà parti',
            };
        });
        items.push({ act: 'quit', label: 'Fermer le tableau' });
        actions.quit = () => close();
        return {
            crumb: 'Départs et billets',
            live: true,
            rebuild: () => pageTicketDestinations(),
            html: `<div class="page-title">Départs — gare de ${esc(stationLabel(d.station))}</div>
                   <div class="page-intro">${deps.length ? 'Sélectionnez un départ pour acheter votre billet, puis choisissez votre gare de descente et votre classe.' : 'Aucun départ programmé pour le moment. Les nouveaux départs apparaîtront ici.'}</div>
                   ${entries(items)}`,
            actions,
        };
    }

    function pageTicketStops(dep) {
        const actions = {};
        const items = dep.stops.map((stop) => {
            actions[`s:${stop.to}`] = () => push(pageTicketClass(stop, dep));
            return {
                act: `s:${stop.to}`, label: stop.label, meta: `dès ${money(stop.prices[0].price)}`,
                sub: `${stop.region} — ${String(stop.km).replace('.', ',')} km${stop.to === dep.destination ? ' — terminus' : ''}`,
            };
        });
        return {
            crumb: dep.timeLabel,
            html: `<div class="page-title">Départ de ${esc(dep.timeLabel)}</div>
                   <div class="page-intro">${esc(dep.train || 'Train de la compagnie')} à destination de ${esc(dep.destinationLabel)}. Où descendez-vous ?</div>
                   ${entries(items)}`,
            actions,
        };
    }

    function pageTicketClass(dest, dep) {
        const actions = {};
        const items = dest.prices.map((p) => {
            const cls = (S.st.classes || []).find((c) => c.id === p.id) || {};
            actions[`c:${p.id}`] = () => push(pageTicketConfirm(dest, p, dep));
            return { act: `c:${p.id}`, label: p.label, meta: money(p.price), sub: cls.description || '' };
        });
        return {
            crumb: dest.label,
            html: `<div class="page-title">Classe de voyage</div>
                   <div class="page-intro">${esc(stationLabel(S.data.station))} → ${esc(dest.label)} — départ à ${esc(dep.timeLabel)}.</div>
                   ${entries(items)}`,
            actions,
        };
    }

    function pageTicketConfirm(dest, price, dep) {
        const preview = {
            fromLabel: stationLabel(S.data.station), toLabel: dest.label, classLabel: price.label,
            routeLabel: dep.via, price: price.price, serial: '', issued: 'à la délivrance', departure: dep.timeLabel,
        };
        return {
            crumb: price.label,
            html: `${ticketCard(preview, { stamp: null })}
                   <p class="note" style="text-align:center">Valable pour le départ de ${esc(dep.timeLabel)}, puis ${Math.round((S.data.validity || 0) / 60 * 10) / 10} h. Présentez-le au contrôleur.</p>
                   ${entries([
                       { act: 'pay', label: `Payer ${money(price.price)}`, cls: 'primary', meta: 'Comptant' },
                       { act: 'back', label: 'Choisir une autre classe' },
                   ], false)}`,
            actions: {
                pay: async () => {
                    const res = await call('tickets:buy', { station: S.data.station, departure: dep.id, to: dest.to, class: price.id });
                    if (!res.ok) return;
                    const remaining = parseFloat(S.data.money) - parseFloat(price.price);
                    if (!Number.isNaN(remaining)) S.data.money = remaining.toFixed(2);
                    renderSpine();
                    S.stack[S.stack.length - 1] = pageTicketIssued(res.data.ticket);
                    mount(current(), 'fade');
                },
                back: () => back(),
            },
        };
    }

    function pageTicketIssued(ticket) {
        return {
            crumb: 'Billet délivré',
            html: `${ticketCard(ticket, { stamp: 'PAYÉ', stampCls: 'green', animate: true })}
                   ${entries([
                       { act: 'close', label: 'Ranger le billet', cls: 'primary' },
                       { act: 'again', label: 'Acheter un autre billet' },
                   ], false)}`,
            actions: {
                close: () => close(),
                again: () => resetTo(pageTicketDestinations()),
            },
        };
    }

    function pageTicketView(ticket) {
        const valid = ticket.status === 'valid';
        return {
            crumb: 'Billet',
            html: `${ticketCard(ticket, { stamp: valid ? null : undefined, animate: !valid })}
                   <p class="note" style="text-align:center">${esc(ticket.statusLabel || '')}${ticket.expires ? ` — valable jusqu'au ${esc(ticket.expires)}` : ''}</p>
                   ${entries([{ act: 'close', label: 'Ranger le billet', cls: 'primary' }], false)}`,
            actions: { close: () => close() },
        };
    }

    // ----------------------------------------------------------------------
    //  Pages : rapport & confirmation
    // ----------------------------------------------------------------------
    function pageReport(data) {
        const s = data.summary || {};
        const lines = data.lines || [];
        const total = data.reward || 0;
        const isMission = !!s.mission;
        return {
            crumb: 'Feuille de route',
            html: `<div class="doc">
                    <div class="doc-head"><span class="title">Feuille de route</span><span class="no">Run ${esc(s.id || '')}</span></div>
                    <div class="fields">
                        ${field('Mission', s.missionLabel)}
                        ${field('Machine', s.trainLabel)}
                        ${field('Ligne', s.routeLabel)}
                        ${field('Durée', duration(s.elapsed || 0))}
                    </div>
                    ${isMission ? `<table class="money-table">
                        ${lines.map((l) => `<tr><td>${esc(l.label)}</td><td class="${l.amount < 0 ? 'neg' : ''}">${money(l.amount)}</td></tr>`).join('')}
                        <tr class="total"><td>Total versé</td><td>${money(total)}</td></tr>
                    </table>` : '<p class="note">Circulation libre : aucune prime n\'est versée.</p>'}
                    <span class="stamp float animate ${s.robbed ? 'ochre' : 'green'}">${s.robbed ? 'CONVOI DÉVALISÉ' : isMission ? 'MISSION ACCOMPLIE' : 'TRAJET ACCOMPLI'}</span>
                </div>
                ${entries([{ act: 'close', label: 'Fermer le registre', cls: 'primary' }], false)}`,
            actions: { close: () => close() },
        };
    }

    function pageConfirm(o) {
        return {
            crumb: 'Confirmation',
            html: `<div class="doc">
                    <div class="doc-head"><span class="title">${esc(o.title)}</span></div>
                    <p style="font-size:1.08rem;line-height:1.45">${esc(o.text)}</p>
                </div>
                ${entries([
                    { act: 'yes', label: o.confirm || 'Confirmer', cls: 'danger' },
                    { act: 'no', label: 'Annuler' },
                ], false)}`,
            actions: { yes: o.onConfirm, no: () => back() },
            sel: 1,
        };
    }

    // ----------------------------------------------------------------------
    //  Ouverture / fermeture
    // ----------------------------------------------------------------------
    function rootPage() {
        switch (S.view) {
            case 'company': return pageMain();
            case 'tickets': return pageTicketDestinations();
            case 'ticket': return pageTicketView(S.data.ticket);
            case 'report': return pageReport(S.data);
            case 'control': return S.data.tickets?.length === 1 ? pageControlTicket(S.data, 0) : pageControlResult(S.data);
            case 'board': return pageBoard(S.st.stations[S.data.station], true);
            default: return pageMain();
        }
    }

    function open(msg) {
        S.token += 1;
        S.st = msg.static || S.st;
        if (S.st && S.st.live && S.st.live.list) { S.live = S.st.live; S.liveAt = Date.now(); }
        S.view = msg.view;
        S.data = msg.data || {};
        S.busy = false;
        S.reports = {};
        const wasVisible = S.open && !S.closing;
        S.open = true;
        S.closing = false;

        applyCompany();
        els.app.classList.remove('hidden', 'closing');
        if (!wasVisible) {
            // Relance les animations d'ouverture.
            els.pages.innerHTML = '';
            void els.app.offsetWidth;
        }
        renderSpine();
        S.stack = [rootPage()];
        mount(current(), wasVisible ? 'fade' : 'none');
        startBrowserPad();
    }

    /** Ferme la NUI. Le focus est rendu immédiatement, l'animation suit. */
    function close(fromLua = false) {
        if (!S.open || S.closing) return;
        S.closing = true;
        if (!fromLua) post('close');
        const token = S.token;
        els.app.classList.add('closing');
        els.telegraph.classList.remove('show');
        setTimeout(() => {
            if (S.token !== token) return; // rouvert entre-temps
            els.app.classList.add('hidden');
            els.app.classList.remove('closing');
            els.pages.innerHTML = '';
            S.open = false;
            S.closing = false;
            S.busy = false;
            S.stack = [];
        }, 230);
    }

    // ----------------------------------------------------------------------
    //  Entrées
    // ----------------------------------------------------------------------
    function setInput(mode) {
        document.body.classList.toggle('pad', mode === 'pad');
    }

    function nav(dir) {
        if (!S.open || S.closing) return;
        if (dir === 'back') return back();
        if (S.busy) return;
        if (dir === 'up') select((current().sel || 0) - 1);
        else if (dir === 'down') select((current().sel || 0) + 1);
        else if (dir === 'select') activate();
    }

    window.addEventListener('keydown', (e) => {
        if (!S.open || S.closing) return;
        setInput('kbd');
        switch (e.key) {
            case 'ArrowUp': e.preventDefault(); nav('up'); break;
            case 'ArrowDown': e.preventDefault(); nav('down'); break;
            case 'Enter':
            case ' ':
                e.preventDefault();
                if (!e.repeat) nav('select');
                break;
            case 'Backspace':
            case 'ArrowLeft':
                e.preventDefault();
                nav('back');
                break;
            case 'Escape':
                e.preventDefault();
                close();
                break;
            default: break;
        }
    });

    // Gamepad API du navigateur (secours, désactivée par défaut côté config).
    let padLoop = false;
    function startBrowserPad() {
        if (padLoop || !S.st || !S.st.browserGamepad || !navigator.getGamepads) return;
        padLoop = true;
        const held = {};
        let repeatAt = 0;
        const step = (t) => {
            if (!S.open) { padLoop = false; return; }
            const gp = [...navigator.getGamepads()].find(Boolean);
            if (gp) {
                const state = {
                    up: gp.buttons[12]?.pressed || gp.axes[1] < -0.6,
                    down: gp.buttons[13]?.pressed || gp.axes[1] > 0.6,
                    select: gp.buttons[0]?.pressed,
                    back: gp.buttons[1]?.pressed,
                };
                for (const k of Object.keys(state)) {
                    if (state[k] && !held[k]) { setInput('pad'); nav(k); repeatAt = t + 320; }
                    else if (state[k] && (k === 'up' || k === 'down') && t > repeatAt) { nav(k); repeatAt = t + 110; }
                    held[k] = state[k];
                }
            }
            requestAnimationFrame(step);
        };
        requestAnimationFrame(step);
    }

    // ----------------------------------------------------------------------
    //  Télégrammes, plaque de conduite, braquage
    // ----------------------------------------------------------------------
    function toast(text, kind = 'info', ms = 5500) {
        if (!text) return;
        const el = document.createElement('div');
        el.className = `toast ${kind}`;
        el.innerHTML = `<div class="head"><span>Télégramme</span><span>${esc(company().name)}</span></div><div class="body">${esc(text)}</div>`;
        els.toasts.appendChild(el);
        while (els.toasts.children.length > 3) els.toasts.firstElementChild.remove();
        setTimeout(() => {
            el.classList.add('out');
            setTimeout(() => el.remove(), 320);
        }, ms);
    }

    function renderHud(d) {
        if (!d) { els.hud.classList.add('hidden'); return; }
        const dots = Array.from({ length: d.total }, (_, i) => {
            const idx = i + 1;
            return `<i class="${idx < d.index ? 'done' : idx === d.index ? 'cur' : ''}"></i>`;
        }).join('');
        let state = esc(d.stateLabel);
        let alert = false;
        if (d.state === 'at_station' && d.countdown != null) state = `Départ autorisé dans <span class="h-count">${d.countdown}</span> s`;
        if (d.state === 'robbery') { state = 'Convoi attaqué — train immobilisé'; alert = true; }
        if (d.state === 'arrived' && !d.free) state = 'Terminus — terminez le trajet';
        if (d.free && !alert) state = 'Circulation libre';
        if (d.noFuel) { state = 'Plus de charbon — chargez le wagon'; alert = true; }
        els.hud.innerHTML = `
            <div class="h-company">${esc(d.free ? d.train : `${company().name} — ${d.route}`)}</div>
            ${d.free ? `
            <div class="h-row"><span>${esc(d.notch)}</span><span>${d.speed} mph</span></div>` : `
            <div class="h-next-label">${d.state === 'arrived' ? 'Terminus' : 'Prochain arrêt'}</div>
            <div class="h-next">${esc(d.next)}</div>
            <div class="h-row"><span>${d.distance.toLocaleString('fr-FR')} m</span><span>${d.speed} mph</span></div>
            <div class="h-row"><span>${esc(d.notch)}</span><span>${d.index}/${d.total}</span></div>
            <div class="h-progress">${dots}</div>`}
            ${d.coal != null ? `<div class="h-row h-coal ${d.noFuel ? 'alert' : ''}"><span>Charbon restant</span><span>${d.coal}</span></div>` : ''}
            ${d.junction ? `<div class="h-junction ${d.junction.locked ? 'locked' : ''}"><span>Aiguillage ${d.junction.distance} m</span><span>${esc(d.junction.label)}</span></div>` : ''}
            <div class="h-state ${alert ? 'alert' : ''}">${state}</div>`;
        els.hud.classList.remove('hidden');
    }

    /** Avis aux voyageurs (affiché même interface fermée). */
    function showNotice(n, ms) {
        const el = document.createElement('div');
        el.className = `notice ${n.kind === 'departed' || n.kind === 'boarding' ? 'departed' : ''} ${n.kind === 'cancelled' ? 'cancelled' : ''}`;
        // « Le Heartlands Express » / « Un train de la compagnie » (jamais « Le Un... »)
        const subject = n.train ? `Le <b>${esc(n.train)}</b>` : 'Un train de la compagnie';
        const at = `<b>${esc(n.timeLabel)}</b>`;
        const from = `<b>${esc(n.stationLabel)}</b>`;
        const to = `<b>${esc(n.destinationLabel)}</b>`;
        let body, time = '', cta = '';
        const until = Date.now() + Math.max(0, n.departAt - (n.now || n.departAt)) * 1000;
        if (n.kind === 'boarding') {
            body = `${subject} à destination de ${to} est à quai en gare de ${from}. Départ prévu à ${at}.`;
            time = `<div class="notice-time" data-until="${until}">${esc(departText(until))}</div>`;
            cta = 'En voiture, s\'il vous plaît !';
        } else if (n.kind === 'departed') {
            body = `${subject} à destination de ${to} a quitté la gare de ${from}.`;
        } else if (n.kind === 'cancelled') {
            body = `Le départ de ${at} de la gare de ${from} à destination de ${to} est annulé.`;
        } else {
            body = `${subject} partira de la gare de ${from} à ${at} à destination de ${to}.`;
            time = `<div class="notice-time" data-until="${until}">${esc(departText(until))}</div>`;
            cta = 'Billets en vente au guichet.';
        }
        el.innerHTML = `
            <div class="notice-head">${BELL}<span>Avis aux voyageurs</span><em>${esc(company().name)}</em></div>
            <div class="notice-body">${body}</div>
            ${time}
            <div class="notice-foot">${n.via ? `Par ${esc(n.via)}` : ''}</div>
            ${cta ? `<div class="notice-cta">${cta}</div>` : ''}`;
        els.notices.appendChild(el);
        while (els.notices.children.length > 3) els.notices.firstElementChild.remove();
        setTimeout(() => {
            el.classList.add('out');
            setTimeout(() => el.remove(), 450);
        }, ms || 11000);
    }

    /** Nouvelle liste en direct : re-rend la page si elle l'affiche. */
    function applyLive(live) {
        if (live && Array.isArray(live.list)) { S.live = live; S.liveAt = Date.now(); }
        const page = current();
        if (!S.open || S.closing || S.busy || !page || !page.live || !page.rebuild) return;
        const next = page.rebuild();
        next.sel = page.sel;
        S.stack[S.stack.length - 1] = next;
        mount(next, 'none');
    }

    // Comptes à rebours (tableaux, avis) : une seule minuterie légère.
    setInterval(() => {
        if (!S.open && !els.notices.children.length) return;
        const byId = {};
        liveList().forEach((e) => { byId[e.id] = e; });
        document.querySelectorAll('[data-dep]').forEach((node) => {
            const e = byId[Number(node.dataset.dep)];
            if (!e) return;
            const st = departState(e);
            if (node.textContent !== st.text) { node.textContent = st.text; node.className = `status ${st.cls}`; }
        });
        if (S.live && S.live.now) {
            const clock = serverClock(serverNow());
            document.querySelectorAll('[data-clock]').forEach((node) => { if (node.textContent !== clock) node.textContent = clock; });
        }
        document.querySelectorAll('[data-until]').forEach((node) => {
            const text = departText(Number(node.dataset.until));
            if (node.textContent !== text) node.textContent = text;
        });
    }, 1000);

    function renderRobbery(remaining) {
        if (remaining == null) { els.robbery.classList.add('hidden'); return; }
        els.robbery.innerHTML = `Tenez la position<b>${remaining} s</b>`;
        els.robbery.classList.remove('hidden');
    }

    // ----------------------------------------------------------------------
    //  Messages Lua
    // ----------------------------------------------------------------------
    window.addEventListener('message', (event) => {
        const msg = event.data || {};
        switch (msg.action) {
            case 'open': open(msg); break;
            case 'close': close(true); break;
            case 'nav': setInput('pad'); nav(msg.dir); break;
            case 'toast': toast(msg.text, msg.kind, msg.duration); break;
            case 'hud': renderHud(msg.data); break;
            case 'robbery': renderRobbery(msg.remaining); break;
            case 'live': applyLive(msg.live); break;
            case 'notice': showNotice(msg.notice || {}, msg.duration); break;
            default: break;
        }
    });
})();
