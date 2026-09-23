const game = document.getElementById('game');
const result = document.getElementById('result');
const leaderboard = document.getElementById('leaderboard');
const preparation = document.getElementById('preparation');
const welcome = document.getElementById('welcome');
async function menuAction(action) {
    try {
        await fetch('https://' + GetParentResourceName() + '/' + action, {
            method: 'POST', headers: {'Content-Type': 'application/json'}, body: '{}'
        });
    } catch (error) { console.warn('Sunny-tiro: action indisponible', error); }
}
document.querySelectorAll('[data-action]').forEach(button => {
    button.addEventListener('click', () => menuAction(button.dataset.action));
});
const targetArrows = document.getElementById('targetArrows');
const arrowNodes = new Map();
function updateArrows(targets) {
    const visible = new Set();
    for (const target of (Array.isArray(targets) ? targets : [])) {
        if (!Number.isFinite(target.x) || !Number.isFinite(target.y)) continue;
        visible.add(target.id);
        let node = arrowNodes.get(target.id);
        if (!node) {
            node = document.createElement('div');
            node.className = 'target-arrow';
            node.appendChild(document.createElement('span'));
            targetArrows.appendChild(node);
            arrowNodes.set(target.id, node);
        }
        node.style.left = (target.x * 100) + '%';
        node.style.top = (target.y * 100) + '%';
    }
    for (const [id, node] of arrowNodes) {
        if (!visible.has(id)) { node.remove(); arrowNodes.delete(id); }
    }
}
let duration = 30;
let closing = false;
let activeSound;
function playCue(name, volume) {
    if (name !== 'countdown' && name !== 'start') return;
    const level = Number(volume);
    if (!Number.isFinite(level) || level <= 0) return;
    if (activeSound) activeSound.pause();
    activeSound = new Audio('sounds/' + name + '.wav');
    activeSound.volume = Math.min(1, level);
    activeSound.play().catch(error => console.warn('Sunny-tiro: son indisponible', error));
}
const el = id => document.getElementById(id);
const number = value => Math.max(0, Number(value) || 0);
const formatShots = value => value == null ? '—' : String(number(value));
const formatTime = value => value == null || !Number.isFinite(Number(value)) ? '—' : (Number(value) / 1000).toLocaleString('fr-FR', {maximumFractionDigits: 2}) + ' s';
function hideAll() {
    updateArrows([]);
    [game, result, leaderboard, preparation, welcome].forEach(panel => panel.classList.add('hidden'));
}
function dots(score, max) {
    el('dots').replaceChildren();
    for (let i = 0; i < Math.min(100, max); i++) {
        const dot = document.createElement('div');
        dot.className = i < score ? 'dot' : 'dot empty';
        el('dots').appendChild(dot);
    }
}
function timer(time) {
    const left = number(time);
    el('timer').textContent = left;
    game.classList.toggle('urgent', left <= 5);
    el('timeBar').style.width = Math.min(100, left / duration * 100) + '%';
}
function startGame(data) {
    hideAll();
    duration = Math.max(1, number(data.duration));
    el('title').textContent = data.title || 'TIRO MEXICANO';
    el('subtitle').textContent = data.subtitle || 'CAMPEONATO DE TIRO';
    el('score').textContent = number(data.score);
    el('maxScore').textContent = number(data.maxScore);
    dots(number(data.score), number(data.maxScore));
    timer(duration);
    el('shotsLeft').textContent = number(data.maxShots);
    el('finalWarning').classList.add('hidden');
    game.classList.remove('hidden');
}
function showResult(data) {
    hideAll();
    el('resultScore').textContent = number(data.score);
    el('resultTime').textContent = formatTime(data.elapsedMs);
    el('resultShots').textContent = formatShots(data.shots);
    el('resultMax').textContent = number(data.maxScore);
    el('record').classList.toggle('hidden', !data.newRecord);
    const ratio = number(data.score) / Math.max(1, number(data.maxScore));
    el('resultVerdict').textContent = ratio >= 1 ? 'Une légende du stand.' : ratio >= 0.6 ? 'Une belle main, tireur.' : 'La poussière retombe. Votre histoire continue.';
    result.classList.remove('hidden');
}
function showLeaderboard(data) {
    hideAll();
    const box = el('rows');
    box.replaceChildren();
    const rows = Array.isArray(data.rows) ? data.rows : [];
    if (!rows.length) {
        const empty = document.createElement('p');
        empty.textContent = 'Aucun score pour le moment.';
        box.appendChild(empty);
    }
    rows.forEach((entry, index) => {
        const row = document.createElement('div');
        row.className = 'row';
        const values = [index + 1, entry.player_name || 'Inconnu', number(entry.best_score) + '/' + number(data.maxScore), formatTime(entry.best_time_ms), formatShots(entry.best_shots)];
        ['rank', 'name', 'points', 'elapsed', 'shot-count'].forEach((className, i) => {
            const cell = document.createElement('span');
            cell.className = className;
            cell.textContent = values[i];
            if (className === 'shot-count' && entry.best_shots == null) {
                cell.title = 'Ancien record : tirs non enregistrés. Établissez un nouveau record pour les afficher.';
            }
            row.appendChild(cell);
        });
        box.appendChild(row);
    });
    el('personal').textContent = number(data.personalBest) + ' / ' + number(data.maxScore);
    el('personalTime').textContent = formatTime(data.personalTime);
    el('personalShots').textContent = formatShots(data.personalShots);
    leaderboard.classList.remove('hidden');
}
async function closeUI() {
    if (closing || [result, leaderboard, welcome].every(panel => panel.classList.contains('hidden'))) return;
    closing = true;
    try {
        await fetch('https://' + GetParentResourceName() + '/close', {
            method: 'POST', headers: {'Content-Type': 'application/json'}, body: '{}'
        });
        hideAll();
    } catch (error) {
        console.error('Sunny-tiro: fermeture impossible', error);
    } finally {
        closing = false;
    }
}
window.addEventListener('keydown', event => {
    if (event.key === 'Escape') closeUI();
});
window.addEventListener('message', event => {
    const data = event.data || {};
    if (data.action === 'preparation' || data.action === 'startGame') playCue(data.sound, data.volume);
    switch (data.action) {
        case 'welcome':
            hideAll();
            el('welcomeTitle').textContent = data.title || 'TIRO MEXICANO';
            el('entryFee').textContent = number(data.fee);
            el('entryTargets').textContent = number(data.maxScore);
            el('entryTime').textContent = number(data.duration);
            el('difficultyRules').textContent = `${number(data.maxShots)} tirs maximum · Dernière cible : ${number(data.finalDuration)} s · Flèches : ${number(data.arrowDuration) > 0 ? number(data.arrowDuration) + ' s' : 'permanentes'}`;
            welcome.classList.remove('hidden');
            break;
        case 'targetArrows': updateArrows(data.targets); break;
        case 'preparation':
            hideAll();
            el('preparationValue').textContent = data.value;
            el('preparationLabel').textContent = data.label;
            preparation.classList.remove('hidden');
            break;
        case 'startGame': startGame(data); break;
        case 'timer': timer(data.time); break;
        case 'shots': el('shotsLeft').textContent = number(data.remaining); break;
        case 'finalTarget':
            el('finalWarning').classList.remove('hidden');
            break;
        case 'score':
            el('score').textContent = number(data.score);
            dots(number(data.score), number(data.maxScore));
            break;
        case 'result': showResult(data); break;
        case 'leaderboard': showLeaderboard(data); break;
        case 'hideGame': game.classList.add('hidden'); break;
        case 'close':
            if (activeSound) activeSound.pause();
            hideAll();
            break;
    }
});
