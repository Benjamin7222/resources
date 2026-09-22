'use strict';

const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'sunny_rodeo';
const $ = (id) => document.getElementById(id);

const KEYS = {
    ArrowUp: 'up', ArrowDown: 'down', ArrowLeft: 'left', ArrowRight: 'right',
    z: 'up', w: 'up', s: 'down', q: 'left', a: 'left', d: 'right',   // ZQSD (AZERTY) et WASD
};
const ARROW_SVG = '<svg viewBox="0 0 24 24" aria-hidden="true"><path d="M12 3 21 14h-6v7H9v-7H3z"/></svg>';

let mode = null;                       // 'board' | 'ride' | 'result' | null
let boardQuery = { sort: 'combo', period: 'all' };
let ch = null;                         // séquence en cours { id, seq, idx }
let feedbackTimer = null;
let hitTimer = null;
let introTimer = null;
let resultTimer = null;
let lastBeat = 0;
let lastCombo = 0;

function post(name, data) {
    return fetch(`https://${RES}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {}),
    }).then((r) => r.json()).catch(() => null);
}

function show(id, on) { $(id).classList.toggle('hidden', !on); }

function hideAll() {
    mode = null;
    ch = null;
    clearTimeout(resultTimer);
    clearTimeout(introTimer);
    clearTimeout(feedbackTimer);
    clearTimeout(hitTimer);
    ['board', 'ride', 'result'].forEach((id) => show(id, false));
}

function el(tag, className, text) {
    const node = document.createElement(tag);
    if (className) node.className = className;
    if (text !== undefined) node.textContent = text;
    return node;
}

// Relance une animation CSS sur un élément.
function replay(node, className) {
    node.classList.remove(className);
    void node.offsetWidth;
    node.classList.add(className);
}

// SONS ---------------------------------------------------------------------------------------
// Bruitages synthétisés (aucun fichier). Silencieux si le navigateur du jeu refuse l'audio.
const Sound = (() => {
    let ctx = null;
    let on = true;
    let vol = 0.35;

    function ensure() {
        if (!on) return null;
        try {
            if (!ctx) ctx = new (window.AudioContext || window.webkitAudioContext)();
            if (ctx.state === 'suspended') ctx.resume();
        } catch (e) { ctx = null; }
        return ctx;
    }

    function envelope(gain, t, peak, dur) {
        gain.gain.setValueAtTime(0.0001, t);
        gain.gain.exponentialRampToValueAtTime(Math.max(peak, 0.0002), t + 0.008);
        gain.gain.exponentialRampToValueAtTime(0.0001, t + dur);
    }

    function tone(freq, dur, o) {
        const c = ensure();
        if (!c) return;
        o = o || {};
        const t = c.currentTime + (o.delay || 0);
        const osc = c.createOscillator();
        const g = c.createGain();
        osc.type = o.type || 'sine';
        osc.frequency.setValueAtTime(freq, t);
        if (o.slide) osc.frequency.exponentialRampToValueAtTime(o.slide, t + dur);
        envelope(g, t, (o.gain !== undefined ? o.gain : 0.5) * vol, dur);
        osc.connect(g);
        g.connect(c.destination);
        osc.start(t);
        osc.stop(t + dur + 0.05);
    }

    function noise(dur, o) {
        const c = ensure();
        if (!c) return;
        o = o || {};
        const t = c.currentTime + (o.delay || 0);
        const len = Math.max(1, Math.floor(c.sampleRate * dur));
        const buf = c.createBuffer(1, len, c.sampleRate);
        const data = buf.getChannelData(0);
        for (let i = 0; i < len; i += 1) data[i] = Math.random() * 2 - 1;
        const src = c.createBufferSource();
        src.buffer = buf;
        const filter = c.createBiquadFilter();
        filter.type = 'bandpass';
        filter.frequency.value = o.freq || 800;
        filter.Q.value = o.q || 1;
        const g = c.createGain();
        envelope(g, t, (o.gain !== undefined ? o.gain : 0.5) * vol, dur);
        src.connect(filter);
        filter.connect(g);
        g.connect(c.destination);
        src.start(t);
    }

    return {
        configure(enabled, volume) {
            on = enabled !== false;
            if (typeof volume === 'number') vol = Math.max(0, Math.min(1, volume));
            ensure();
        },
        // une flèche juste : un « toc » de bois
        knock() { noise(0.07, { freq: 950, q: 1.3, gain: 0.7 }); tone(190, 0.09, { type: 'triangle', gain: 0.45, slide: 110 }); },
        good() { tone(392, 0.12, { type: 'triangle' }); tone(523, 0.2, { type: 'triangle', delay: 0.09 }); },
        perfect() {
            tone(523, 0.1, { type: 'triangle' });
            tone(659, 0.1, { type: 'triangle', delay: 0.08 });
            tone(784, 0.26, { type: 'triangle', delay: 0.16 });
        },
        bad() { tone(150, 0.4, { type: 'sawtooth', slide: 55, gain: 0.4 }); noise(0.28, { freq: 300, q: 0.7, gain: 0.6 }); },
        heart() { tone(60, 0.14, { gain: 0.9, slide: 40 }); tone(54, 0.16, { delay: 0.16, gain: 0.7, slide: 38 }); },
        tick() { tone(330, 0.1, { type: 'square', gain: 0.22 }); },
        go() {
            tone(523, 0.12, { type: 'square', gain: 0.28 });
            tone(784, 0.4, { type: 'triangle', delay: 0.1, gain: 0.5 });
            noise(0.25, { freq: 2200, q: 0.8, gain: 0.3 });
        },
        stamp() { tone(95, 0.22, { gain: 0.85, slide: 48 }); noise(0.12, { freq: 520, q: 0.9, gain: 0.55 }); },
    };
})();

// FORMATS -------------------------------------------------------------------
// Virgule décimale à la française.
function f1(seconds) { return seconds.toFixed(1).replace('.', ','); }

function fmtTime(ms) {
    const s = ms / 1000;
    if (s < 60) return `${f1(s)} s`;
    const m = Math.floor(s / 60);
    return `${m} min ${String(Math.floor(s % 60)).padStart(2, '0')} s`;
}

// Chrono du HUD : 12,3  ou  1:05,3 au-delà d'une minute.
function fmtClock(ms) {
    const s = ms / 1000;
    if (s < 60) return f1(s);
    const m = Math.floor(s / 60);
    return `${m}:${f1(s % 60).padStart(4, '0')}`;
}

function fmtValue(sort, value) {
    if (sort === 'time') return fmtTime(value);
    if (sort === 'combo') return String(value); // l'en-tête de colonne dit déjà « Épreuves »
    return `${value.toLocaleString('fr-FR')} XP`;
}

const VALUE_HEAD = { time: 'Temps', combo: 'Épreuves', level: 'XP' };

// CLASSEMENT --------------------------------------------------------------------
function renderBoard(res) {
    boardQuery = { sort: res.sort, period: res.period };
    $('arena').textContent = res.arena || '';
    $('valueHead').textContent = (VALUE_HEAD[res.sort] || 'Score') + (res.period === 'week' ? ' (7 j)' : '');

    document.querySelectorAll('#sortTabs button').forEach((b) => b.classList.toggle('on', b.dataset.sort === res.sort));
    document.querySelectorAll('#periodTabs button').forEach((b) => b.classList.toggle('on', b.dataset.period === res.period));

    const list = $('rows');
    list.textContent = '';
    (res.rows || []).forEach((row) => {
        const li = el('li', `row${row.me ? ' me' : ''}${row.rank <= 3 ? ` p${row.rank}` : ''}`);
        li.appendChild(el('span', 'rank', String(row.rank)));
        li.appendChild(el('span', 'name', row.name));
        const lvl = el('span', 'lvl');
        lvl.appendChild(el('b', '', `Niv. ${row.level}`));
        lvl.appendChild(document.createTextNode(` ${row.title}`));
        li.appendChild(lvl);
        li.appendChild(el('span', 'val', fmtValue(res.sort, row.value)));
        list.appendChild(li);
    });
    show('empty', !(res.rows && res.rows.length));

    renderProfile(res);
}

function renderProfile(res) {
    const body = $('meBody');
    body.textContent = '';
    const p = res.profile;
    if (!p) {
        body.appendChild(el('p', 'none', 'Tu n\'as pas encore fait de tour. Monte en selle pour entrer au classement !'));
        return;
    }
    body.appendChild(el('div', 'lvl-title', p.level.title));
    body.appendChild(el('div', 'lvl-num', `Niveau ${p.level.level} — ${p.level.xp.toLocaleString('fr-FR')} XP`));

    const bar = el('div', 'bar gold');
    const fill = el('i');
    bar.appendChild(fill);
    body.appendChild(bar);
    const span = p.level.to ? p.level.to - p.level.from : 0;
    fill.style.width = `${span ? Math.min(100, ((p.level.xp - p.level.from) / span) * 100) : 100}%`;
    fill.style.transition = 'none';

    const dl = el('dl');
    const add = (k, v) => { dl.appendChild(el('dt', '', k)); dl.appendChild(el('dd', '', v)); };
    if (res.me) add('Position', `n°${res.me.rank}`);
    else add('Position', 'hors classement');
    add('Meilleur score', `${p.bestCombo} ${p.bestCombo > 1 ? 'épreuves' : 'épreuve'}`);
    add('Tours', String(p.rides));
    add('Temps total', fmtTime(p.totalMs));
    if (p.level.to) add('Prochain niveau', `${p.level.to.toLocaleString('fr-FR')} XP`);
    body.appendChild(dl);
}

function loadBoard(patch) {
    boardQuery = Object.assign({}, boardQuery, patch);
    post('boardData', boardQuery).then((res) => { if (res && res.ok) renderBoard(res); });
}

document.querySelectorAll('#sortTabs button').forEach((b) => b.addEventListener('click', () => loadBoard({ sort: b.dataset.sort })));
document.querySelectorAll('#periodTabs button').forEach((b) => b.addEventListener('click', () => loadBoard({ period: b.dataset.period })));
$('closeBoard').addEventListener('click', () => post('close'));

// TOUR ----------------------------------------------------------------------------------
function setGrip(value) {
    const pct = Math.max(0, Math.min(100, value));
    $('gripBar').style.width = `${pct}%`;
    const strap = $('strap');
    strap.classList.toggle('low', pct < 25);
    strap.classList.toggle('mid', pct >= 25 && pct < 50);
    $('vignette').classList.toggle('danger', pct < 28);
    // battements de cœur quand la chute approche
    if (pct < 25) {
        const now = Date.now();
        if (now - lastBeat > 1000) { lastBeat = now; Sound.heart(); }
    }
}

function setStreak(n) {
    const box = $('combo');
    $('comboNum').textContent = String(n);
    box.classList.toggle('on', n > 0);
    if (n > lastCombo && n > 0) replay(box, 'pop');
    lastCombo = n;
}

function flash(kind) {
    const f = $('flash');
    f.className = 'flash';
    void f.offsetWidth;
    f.className = `flash ${kind}`;
}

function startRide(d) {
    hideAll();
    mode = 'ride';
    lastBeat = 0;
    lastCombo = 0;
    Sound.configure(d && d.sound, d && d.volume);
    show('ride', true);
    show('challenge', false);
    show('countdown', false);
    $('timer').textContent = fmtClock(0);
    $('clock').classList.remove('hit');
    $('penalty').className = 'penalty';
    $('feedback').className = 'feedback';
    $('flash').className = 'flash';
    setStreak(0);
    setGrip(100);

    // carton de titre
    $('introName').textContent = (d && d.arena) || 'Rodéo';
    show('intro', true);
    replay($('intro'), 'run');
    introTimer = setTimeout(() => show('intro', false), 3500);

    // le rappel des touches s'efface tout seul
    replay($('hint'), 'fade');
}

function showCountdown(value) {
    const box = $('countdown');
    if (value <= 0) {
        box.textContent = 'Yeehaa !';
        box.classList.add('go');
        box.classList.remove('hidden', 'tick');
        void box.offsetWidth;
        box.classList.add('tick');
        Sound.go();
        setTimeout(() => show('countdown', false), 800);
        return;
    }
    box.classList.remove('go');
    box.textContent = String(value);
    box.classList.remove('hidden', 'tick');
    void box.offsetWidth;
    box.classList.add('tick');
    Sound.tick();
}

const FEEDBACK = { ok: 'Bien !', fast: 'Parfait !', wrong: 'Raté !', timeout: 'Trop lent !' };

function showFeedback(kind, penaltyMs) {
    const box = $('feedback');
    box.className = 'feedback';
    void box.offsetWidth;
    $('fbText').textContent = FEEDBACK[kind] || '';
    $('fbSub').textContent = penaltyMs > 0 ? `−${f1(penaltyMs / 1000)} s` : '';
    box.className = `feedback ${kind} show`;
    clearTimeout(feedbackTimer);
    feedbackTimer = setTimeout(() => { box.className = 'feedback'; }, 1000);
}

// Une erreur retire du temps : le chrono rougit et « −2,0 s » en sort.
function showPenalty(ms) {
    if (!(ms > 0)) return;
    const p = $('penalty');
    p.textContent = `−${f1(ms / 1000)} s`;
    replay(p, 'show');
    const clock = $('clock');
    clock.classList.add('hit');
    clearTimeout(hitTimer);
    hitTimer = setTimeout(() => clock.classList.remove('hit'), 900);
}

function endChallenge() {
    ch = null;
    show('challenge', false);
}

function onState(s) {
    if (mode !== 'ride') return;
    $('timer').textContent = fmtClock(s.left);
    $('clock').classList.toggle('low', s.left < 10000); // les 10 dernières secondes : chrono rouge
    setGrip(s.grip);
    setStreak(s.score);
    if (s.fb) {
        showFeedback(s.fb, s.pen);
        showPenalty(s.pen);
        if (s.fb === 'fast') { Sound.perfect(); flash('good'); }
        else if (s.fb === 'ok') Sound.good();
        else if (s.fb === 'timeout') { Sound.bad(); flash('bad'); }
        // 'wrong' : le bruit et l'éclair ont déjà eu lieu à l'appui de la mauvaise touche
        endChallenge();
    }
}

function onChallenge(d) {
    if (mode !== 'ride') return;
    ch = { id: d.id, seq: d.seq, idx: 0 };
    const box = $('arrows');
    box.textContent = '';
    box.classList.remove('fail');
    d.seq.forEach((dir, i) => {
        const a = el('div', `arrow ${dir}${i === 0 ? ' next' : ''}`);
        a.innerHTML = ARROW_SVG;
        box.appendChild(a);
    });
    show('challenge', true);

    const bar = $('tBar');
    bar.style.transition = 'none';
    bar.style.width = '100%';
    void bar.offsetWidth;
    bar.style.transition = `width ${d.window}ms linear`;
    bar.style.width = '0%';
}

function onArrow(dir) {
    if (!ch) return;
    const cells = $('arrows').children;
    if (dir === ch.seq[ch.idx]) {
        cells[ch.idx].classList.remove('next');
        cells[ch.idx].classList.add('done');
        Sound.knock();
        ch.idx += 1;
        if (ch.idx >= ch.seq.length) {
            const id = ch.id;
            ch = null;
            post('answer', { id, ok: true });
        } else {
            cells[ch.idx].classList.add('next');
        }
    } else {
        const id = ch.id;
        ch = null;
        $('arrows').classList.add('fail');
        Sound.bad();
        flash('bad');
        post('answer', { id, ok: false });
    }
}

// RESULTAT ------------------------------------------------------------------------------
const REASONS = {
    fall:  ['La bête a gagné', 'Désarçonné !'],
    quit:  ['Tu as choisi de descendre', 'Lâcher prise'],
    max:   ['Temps écoulé', 'Manche terminée !'],
    dead:  ['Ça a mal fini', 'Mise à terre'],
    error: ['Le tour a été interrompu', 'Tour interrompu'],
};

function showResult(d) {
    hideAll();
    mode = 'result';
    const [kicker, title] = REASONS[d.reason] || REASONS.error;
    $('resKicker').textContent = kicker;
    $('resTitle').textContent = title;
    $('resTime').textContent = String(d.combos || 0);

    const s = d.server || {};
    const stats = $('resStats');
    stats.textContent = '';
    const banner = $('resBanner');
    banner.classList.add('hidden');
    show('resLevel', false);
    show('resError', false);

    if (!s.ok) {
        $('resError').textContent = s.error || 'Le résultat n\'a pas pu être enregistré.';
        show('resError', true);
    } else {
        const add = (value, label, className) => {
            const li = el('li', className || '', label);
            li.insertBefore(el('b', '', value), li.firstChild);
            stats.appendChild(li);
        };
        add(fmtTime(d.ms), 'Temps tenu');
        if (d.penalty > 0) {
            const n = d.mistakes || 0;
            add(`−${f1(d.penalty / 1000)} s`, `Pénalités (${n} erreur${n > 1 ? 's' : ''})`, 'neg');
        }
        if (s.counted) {
            add(`+${s.xp} XP`, 'Expérience gagnée');
            add(`n°${s.rank}`, 'Position au classement');
        } else {
            add('—', 'Manche trop courte : non comptée');
        }

        const notes = [];
        if ((s.record || s.first) && s.rank === 1) notes.push('Nouveau record du rodéo !');
        else if (s.record) notes.push('Record personnel battu !');
        else if (s.first) notes.push('Premier tour au classement !');
        if (s.levelUp) notes.push('Niveau supérieur !');
        if (notes.length) {
            banner.textContent = notes.join('  ·  ');
            banner.classList.remove('hidden');
        }

        if (s.level) {
            const lv = s.level;
            $('resLvlTitle').textContent = `Niveau ${lv.level} — ${lv.title}`;
            $('resXp').textContent = lv.to ? `${lv.xp} / ${lv.to} XP` : `${lv.xp} XP`;
            const bar = $('resLvlBar');
            bar.style.width = '0%';
            show('resLevel', true);
            const span = lv.to ? lv.to - lv.from : 0;
            const pct = span ? Math.min(100, ((lv.xp - lv.from) / span) * 100) : 100;
            setTimeout(() => { bar.style.width = `${pct}%`; }, 200);
        }
    }

    show('result', true);
    Sound.stamp();
    resultTimer = setTimeout(() => { if (mode === 'result') post('close'); }, 19000);
}

$('resClose').addEventListener('click', () => post('close'));

// CLAVIER ----------------------------------------------------------------------------------
document.addEventListener('keydown', (e) => {
    if (mode === 'ride') {
        if (e.key === 'Backspace' || e.key === 'Escape') {
            e.preventDefault();
            post('quit');
            return;
        }
        const dir = KEYS[e.key] || KEYS[String(e.key).toLowerCase()];
        if (!dir) return;
        e.preventDefault();
        if (!e.repeat) onArrow(dir);
    } else if (mode === 'result') {
        if (e.key === 'Enter' || e.key === 'Escape' || e.key === 'Backspace' || e.key === ' ') {
            e.preventDefault();
            post('close');
        }
    } else if (mode === 'board') {
        if (e.key === 'Escape' || e.key === 'Backspace') {
            e.preventDefault();
            post('close');
        }
    }
});

// MESSAGES DU JEU -----------------------------------------------------------------------
window.addEventListener('message', (event) => {
    const { action, data } = event.data || {};
    switch (action) {
        case 'board':
            hideAll();
            mode = 'board';
            show('board', true);
            renderBoard(data);
            break;
        case 'rideStart': startRide(data); break;
        case 'countdown': showCountdown(data); break;
        case 'state': onState(data); break;
        case 'challenge': onChallenge(data); break;
        case 'rideEnd':
            endChallenge();
            show('ride', false);
            break;
        case 'result': showResult(data); break;
        case 'hideAll': hideAll(); break;
    }
});
