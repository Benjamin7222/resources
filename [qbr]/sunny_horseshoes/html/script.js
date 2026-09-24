(() => {
    const $ = (id) => document.getElementById(id);
    const cfg = { enabled: true, sound: true, volume: 0.45, popupMs: 2600 };

    const esc = (s) => String(s == null ? '' : s).replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
    const plural = (n) => (Math.abs(n) > 1 ? 'S' : '');

    let ctx = null;
    function audio() {
        if (!cfg.sound) return null;
        try {
            if (!ctx) ctx = new (window.AudioContext || window.webkitAudioContext)();
            if (ctx.state === 'suspended') ctx.resume();
        } catch (e) { return null; }
        return ctx;
    }

    function noiseBurst(a, dur, freq, gain) {
        const len = Math.floor(a.sampleRate * dur);
        const buf = a.createBuffer(1, len, a.sampleRate);
        const d = buf.getChannelData(0);
        for (let i = 0; i < len; i++) d[i] = (Math.random() * 2 - 1) * Math.pow(1 - i / len, 3);
        const src = a.createBufferSource();
        src.buffer = buf;
        const f = a.createBiquadFilter();
        f.type = 'lowpass';
        f.frequency.value = freq;
        const g = a.createGain();
        g.gain.value = gain * cfg.volume;
        src.connect(f).connect(g).connect(a.destination);
        src.start();
    }

    function metal(a, base, dur, gain) {
        [1, 2.76, 5.4, 8.93].forEach((m, i) => {
            const o = a.createOscillator();
            const g = a.createGain();
            o.type = 'sine';
            o.frequency.value = base * m;
            const t = a.currentTime;
            g.gain.setValueAtTime((gain / (i + 1)) * cfg.volume, t);
            g.gain.exponentialRampToValueAtTime(0.0001, t + dur / (i * 0.6 + 1));
            o.connect(g).connect(a.destination);
            o.start(t);
            o.stop(t + dur);
        });
    }

    function play(kind) {
        const a = audio();
        if (!a) return;
        if (kind === 'thud') noiseBurst(a, 0.18, 380, 0.9);
        else if (kind === 'clang') { metal(a, 520, 0.7, 0.35); noiseBurst(a, 0.05, 3000, 0.3); }
        else if (kind === 'ring') { metal(a, 660, 1.4, 0.3); setTimeout(() => metal(a, 880, 1.2, 0.18), 120); }
    }

    let turnTimer = null;
    let turnLeft = null;

    function renderTurn(d) {
        const el = $('hud-turn');
        el.classList.toggle('mine', !!d.myTurn);
        let txt = '';
        if (d.myTurn) txt = 'À toi de lancer !';
        else if (d.turnName) txt = `Au tour de ${esc(d.turnName)}`;
        if (turnLeft != null && d.myTurn) txt += ` (${turnLeft} s)`;
        el.innerHTML = txt;
    }

    function hud(d) {
        if (!d.show) {
            $('hud').classList.add('hidden');
            clearInterval(turnTimer);
            return;
        }
        $('hud').classList.remove('hidden');
        const lobby = d.status === 'lobby';
        $('hud-lobby').classList.toggle('hidden', !lobby);
        $('hud-game').classList.toggle('hidden', lobby);

        const players = d.players || [];
        if (lobby) {
            $('lobby-count').textContent = `${players.length} / ${d.maxPlayers}`;
            $('lobby-note').textContent = (d.bet > 0 ? `Mise : ${d.bet} $ par joueur, le gagnant rafle le pot. ` : 'Partie sans mise. ') + (d.maxPlayers === 2
                ? (d.host ? 'Ton adversaire doit parler au PNJ et choisir « Rejoindre ». La partie démarre toute seule.' : 'La partie démarre dès que le 2e joueur rejoint.')
                : (d.host ? 'Lance la partie via le PNJ quand tout le monde est là (2 joueurs minimum).' : 'Le créateur de la partie va la lancer.'));
            return;
        }

        $('hud-round').textContent = `${d.round} / ${d.rounds}`;
        $('hud-throws').textContent = d.throwsLeft;

        let html = '';
        if (players.length === 2) {
            const me = players.find((p) => p.me);
            const other = players.find((p) => !p.me);
            if (me) html += `<div class="score me${me.turn ? ' turn' : ''}"><span class="name">Votre score</span><span class="pts">${me.score}</span></div>`;
            if (other) html += `<div class="score${other.turn ? ' turn' : ''}"><span class="name">${esc(other.name)}</span><span class="pts">${other.score}</span></div>`;
        } else if (players.length === 1) {
            html = `<div class="score me"><span class="name">Votre score</span><span class="pts">${players[0].score}</span></div>`;
        } else {
            players.forEach((p) => {
                html += `<div class="score${p.me ? ' me' : ''}${p.turn ? ' turn' : ''}"><span class="name">${p.me ? 'Vous' : esc(p.name)}</span><span class="pts">${p.score}</span></div>`;
            });
        }
        $('hud-scores').innerHTML = html;

        clearInterval(turnTimer);
        turnLeft = typeof d.turnLeft === 'number' ? d.turnLeft : null;
        renderTurn(d);
        if (turnLeft != null) {
            turnTimer = setInterval(() => {
                turnLeft = Math.max(0, turnLeft - 1);
                renderTurn(d);
            }, 1000);
        }
    }

    function power(d) {
        $('gauge-fill').style.width = `${Math.round((d.power || 0) * 100)}%`;
        const aim = Math.max(-1, Math.min(1, d.aim || 0));
        $('aim-needle').style.left = `calc(${50 + aim * 50}% - 3px)`;
    }

    let popupTimer = null;
    function popup(d) {
        const el = $('popup');
        el.classList.remove('hidden', 'zero', 'ringer');
        void el.offsetWidth;
        el.style.animation = 'none';
        void el.offsetWidth;
        el.style.animation = '';
        if (d.points <= 0) el.classList.add('zero');
        if (d.kind === 'ringer') el.classList.add('ringer');
        $('popup-who').textContent = d.mine ? '' : d.name || '';
        $('popup-points').textContent = `+${d.points} POINT${plural(d.points)}`;
        $('popup-label').textContent = d.label || '';
        clearTimeout(popupTimer);
        popupTimer = setTimeout(() => el.classList.add('hidden'), cfg.popupMs);
    }

    let bannerTimer = null;
    function banner(d) {
        const el = $('banner');
        $('banner-text').textContent = d.text;
        el.classList.add('hidden');
        void el.offsetWidth;
        el.classList.remove('hidden');
        clearTimeout(bannerTimer);
        bannerTimer = setTimeout(() => el.classList.add('hidden'), 2200);
    }

    let finalTimer = null;
    function final(d) {
        const rows = d.rows || [];
        $('final-rows').innerHTML = rows.map((r) => {
            const extra = [];
            if (r.ringers > 0) extra.push(`${r.ringers} fer${r.ringers > 1 ? 's' : ''} accroché${r.ringers > 1 ? 's' : ''}`);
            if (r.gain > 0) extra.push(`pari gagné : ${r.gain} $`);
            return `<div class="final-row${r.me ? ' me' : ''}"><span class="name">${esc(r.name)}${extra.length ? `<small>${extra.join(' · ')}</small>` : ''}</span><span>${r.score} POINT${plural(r.score)}</span></div>`;
        }).join('');
        let winner = '';
        if (d.solo) winner = `Score final : ${rows[0] ? rows[0].score : 0}`;
        else if (d.tie) winner = 'Égalité !';
        else if (d.winner) winner = `Victoire : ${esc(d.winner)}`;
        $('final-winner').innerHTML = winner;
        const notes = [];
        if (d.reason === 'forfeit') notes.push('Victoire par abandon de l\'adversaire.');
        if (!d.solo && d.pot > 0) notes.push(`Pot en jeu : ${d.pot} $`);
        $('final-note').textContent = notes.join(' ');
        $('final').classList.remove('hidden');
        clearTimeout(finalTimer);
        finalTimer = setTimeout(() => $('final').classList.add('hidden'), d.ms || 9000);
        play('ring');
    }

    const RES = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'sunny_horseshoes';
    const post = (name, data) => fetch(`https://${RES}/${name}`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/json; charset=UTF-8' },
        body: JSON.stringify(data || {}),
    }).then((r) => r.json()).catch(() => null);

    const COLS = { score: 'Meilleur score', ringers: 'Fers accrochés', wins: 'Victoires' };
    const valueOf = (r, sort) => (sort === 'ringers' ? r.ringers : sort === 'wins' ? r.wins : r.score);
    let boardSort = 'score';

    function renderBoard(res) {
        boardSort = res.sort || 'score';
        document.querySelectorAll('#board .tab').forEach((t) => t.classList.toggle('active', t.dataset.sort === boardSort));
        $('board-col').textContent = COLS[boardSort];
        const rows = res.rows || [];
        $('board-rows').innerHTML = rows.length
            ? rows.map((r) => `<tr class="${r.me ? 'me' : ''}${r.rank === 1 ? ' top1' : ''}"><td>${r.rank}</td><td>${esc(r.name)}</td><td>${valueOf(r, boardSort)}</td><td>${r.games}</td></tr>`).join('')
            : '<tr><td colspan="4" class="empty">Personne n\'a encore joué. À toi l\'honneur !</td></tr>';
        const me = res.me;
        const shown = rows.some((r) => r.me);
        $('board-me').classList.toggle('hidden', !me || shown);
        if (me && !shown) $('board-me').innerHTML = `<span>${me.rank}. Vous</span><span>${valueOf(me, boardSort)} · ${me.games} partie${me.games > 1 ? 's' : ''}</span>`;
    }

    function closeBoard() {
        if ($('board').classList.contains('hidden')) return;
        $('board').classList.add('hidden');
        post('close');
    }

    document.querySelectorAll('#board .tab').forEach((t) => t.addEventListener('click', () => {
        if (t.dataset.sort === boardSort) return;
        post('boardData', { sort: t.dataset.sort }).then((res) => { if (res && res.ok) renderBoard(res); });
    }));
    $('board-close').addEventListener('click', closeBoard);

    const bet = { open: false, mode: 'create', min: 10, max: 1000, cut: 0 };

    function betValue() {
        const v = Math.floor(Number($('bet-input').value) || 0);
        return v > 0 ? v : 0;
    }

    function betRefresh() {
        const v = bet.mode === 'join' ? bet.amount : betValue();
        const ok = bet.mode === 'join' || v === 0 || (v >= bet.min && v <= bet.max);
        document.querySelectorAll('#bet-quick button').forEach((b) => b.classList.toggle('active', Number(b.dataset.v) === v));
        $('bet-error').classList.toggle('hidden', ok);
        $('bet-error').textContent = ok ? '' : `La mise doit être entre ${bet.min} $ et ${bet.max} $.`;
        $('bet-ok').disabled = !ok;
        const pot = Math.floor(v * 2 * (1 - bet.cut) * 100) / 100;
        $('bet-pot').textContent = v > 0 ? `En duel, le gagnant empoche ${pot} $` : (bet.mode === 'create' ? 'Partie amicale, sans argent en jeu' : '');
        if (bet.mode === 'create') $('bet-ok').textContent = v > 0 ? `Parier ${v} $ et créer` : 'Créer sans mise';
    }

    function openBet(d) {
        bet.open = true;
        bet.mode = d.mode === 'join' ? 'join' : 'create';
        bet.min = d.min || 10;
        bet.max = d.max || 1000;
        bet.cut = d.houseCut || 0;
        bet.amount = Math.floor(d.bet || 0);
        const join = bet.mode === 'join';
        $('bet-create').classList.toggle('hidden', join);
        $('bet-join').classList.toggle('hidden', !join);
        $('bet-title').textContent = join ? 'Rejoindre le défi' : 'Défi au lancer de fer';
        $('bet-subtitle').textContent = 'Le gagnant rafle le pot';
        if (join) {
            $('bet-join-host').textContent = d.host ? `${d.host} mise` : 'Mise par joueur';
            $('bet-join-amount').textContent = `${bet.amount} $`;
            $('bet-ok').textContent = `Suivre la mise (${bet.amount} $)`;
        } else {
            const quick = [0, bet.min, 50, 100, 250, 500, bet.max].filter((v, i, a) => (v === 0 || (v >= bet.min && v <= bet.max)) && a.indexOf(v) === i);
            $('bet-quick').innerHTML = quick.map((v) => `<button data-v="${v}">${v === 0 ? 'Sans mise' : `${v} $`}</button>`).join('');
            document.querySelectorAll('#bet-quick button').forEach((b) => b.addEventListener('click', () => {
                $('bet-input').value = Number(b.dataset.v) || '';
                betRefresh();
                $('bet-input').focus();
            }));
            $('bet-input').min = bet.min;
            $('bet-input').max = bet.max;
            $('bet-input').placeholder = '0';
            $('bet-input').value = '';
            $('bet-range').textContent = `De ${bet.min} $ à ${bet.max} $ — laisse vide pour jouer sans mise.`;
        }
        betRefresh();
        $('bet').classList.remove('hidden');
        if (!join) setTimeout(() => $('bet-input').focus(), 50);
    }

    function closeBet(send) {
        if (!bet.open) return;
        bet.open = false;
        $('bet').classList.add('hidden');
        if (send) post('betCancel');
    }

    function confirmBet() {
        if (!bet.open || $('bet-ok').disabled) return;
        const v = bet.mode === 'join' ? bet.amount : betValue();
        bet.open = false;
        $('bet').classList.add('hidden');
        post('betConfirm', { bet: v });
    }

    $('bet-input').addEventListener('input', betRefresh);
    $('bet-ok').addEventListener('click', confirmBet);
    $('bet-cancel').addEventListener('click', () => closeBet(true));
    $('bet-close').addEventListener('click', () => closeBet(true));

    window.addEventListener('keydown', (e) => {
        if (bet.open) {
            if (e.key === 'Escape') closeBet(true);
            else if (e.key === 'Enter') confirmBet();
            return;
        }
        if (e.key === 'Escape' || e.key === 'Backspace') closeBoard();
    });

    window.addEventListener('message', (e) => {
        const d = e.data || {};
        switch (d.action) {
            case 'config':
                Object.assign(cfg, d);
                break;
            case 'hud': hud(d); break;
            case 'aim': $('aim').classList.toggle('hidden', !d.show); if (d.show) power({ power: 0, aim: 0 }); break;
            case 'power': power(d); break;
            case 'popup': popup(d); break;
            case 'banner': banner(d); break;
            case 'final': final(d); break;
            case 'sound': play(d.kind); break;
            case 'bet':
                if (d.show) openBet(d); else closeBet(false);
                break;
            case 'board':
                if (d.show && d.data) { renderBoard(d.data); $('board').classList.remove('hidden'); }
                else $('board').classList.add('hidden');
                break;
            default: break;
        }
    });
})();
