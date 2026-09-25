'use strict';
const config = window.SunnyLoadingConfig || {};
const $ = (id) => document.getElementById(id);
const video = $('background');
const music = $('music');
const audioSource = music;
video.muted = true;
let toastTimer;
function notify(message) {
    $('toast').textContent = message;
    $('toast').hidden = false;
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => { $('toast').hidden = true; }, 4500);
}
$('server-name').textContent = config.serverName || 'SUNNY';
document.title = `${config.serverName || 'SUNNY'} — Chargement`;

const rulesDialog = $('rules-dialog');
for (const rule of config.rules || []) {
    const section = document.createElement('section');
    const title = document.createElement('h3');
    const description = document.createElement('p');
    title.textContent = rule.title;
    description.textContent = rule.text;
    section.append(title, description);
    $('rules-content').append(section);
}
document.querySelectorAll('[data-link]').forEach((button) => {
    button.addEventListener('click', () => {
        const key = button.dataset.link;
        const url = (config.links || {})[key];
        if (key === 'rules' && !url) { rulesDialog.showModal(); return; }
        if (!url) { notify('Ce lien sera bientôt disponible.'); return; }
        try {
            const parsed = new URL(url);
            if (parsed.protocol !== 'https:' && parsed.protocol !== 'http:') throw new Error('URL');
            if (typeof window.invokeNative === 'function') window.invokeNative('openUrl', parsed.href);
            else window.open(parsed.href, '_blank', 'noopener,noreferrer');
        } catch (_) { notify('Ce lien est indisponible pour le moment.'); }
    });
});
$('close-rules').addEventListener('click', () => rulesDialog.close());
rulesDialog.addEventListener('click', (event) => { if (event.target === rulesDialog) {
    const bounds = rulesDialog.getBoundingClientRect();
    if (event.clientX < bounds.left || event.clientX > bounds.right || event.clientY < bounds.top || event.clientY > bounds.bottom) rulesDialog.close();
} });

let volume = Number(config.volume);
volume = Number.isFinite(volume) && volume > 0 ? Math.min(100, volume) : 30;
try {
    const saved = localStorage.getItem('sunny_loading_volume');
    if (saved !== null && Number.isFinite(Number(saved)) && Number(saved) > 0) volume = Math.min(100, Number(saved));
} catch (_) {  }
let previousVolume = volume || 30;
let userPaused = false;
let audioPlayPending = false;
let audioRequest = 0;
const audioFiles = new Map();
function audioUrl(path) {
    const base = location.href.replace(/^nui:\/\/([^/]+)\//, 'https://cfx-nui-$1/');
    return new URL(path, base).href;
}
async function loadAudioFile(path) {
    const url = audioUrl(path);
    if (!audioFiles.has(url)) {
        const request = (async () => {
            const controller = new AbortController();
            const timeout = setTimeout(() => controller.abort(), 20000);
            try {
                const response = await fetch(url, { signal: controller.signal });
                if (!response.ok) throw new Error(`HTTP ${response.status}`);
                const bytes = await response.arrayBuffer();
                if (!bytes.byteLength) throw new Error('Fichier audio vide');
                const type = /\.ogg(?:$|\?)/i.test(path) ? 'audio/ogg' : /\.mp3(?:$|\?)/i.test(path) ? 'audio/mpeg' : response.headers.get('content-type') || 'application/octet-stream';
                return URL.createObjectURL(new Blob([bytes], { type }));
            } finally { clearTimeout(timeout); }
        })();
        audioFiles.set(url, request);
        request.catch(() => audioFiles.delete(url));
    }
    return audioFiles.get(url);
}
function setVolume(value) {
    volume = value;
    audioSource.volume = value / 100;
    audioSource.muted = value === 0;
    video.muted = true;
    $('volume').value = value;
    $('volume-value').textContent = `${value} %`;
    $('mute').textContent = value ? '♪' : '×';
    $('mute').setAttribute('aria-pressed', String(value === 0));
    $('mute').setAttribute('aria-label', value ? 'Couper le son' : 'Rétablir le son');
    if (!music.paused) audioState(value ? 'En lecture' : 'Son coupé', true);
    try { localStorage.setItem('sunny_loading_volume', String(value)); } catch (_) {  }
}
function audioState(label, playing = false) {
    $('audio-status').textContent = label;
    $('play-audio').hidden = false;
    $('play-audio').textContent = playing ? 'Pause' : 'Écouter';
    $('play-audio').setAttribute('aria-label', playing ? 'Mettre en pause' : 'Lancer la musique');
}
function startAudio() {
    if (!audioSource.getAttribute('src') || userPaused || audioPlayPending) return;
    const requestedSource = audioSource.getAttribute('src');
    const request = audioRequest;
    audioSource.muted = volume === 0;
    audioPlayPending = true;
    audioState('Chargement…');
    audioSource.play().then(() => {
        if (request === audioRequest && !music.paused) audioState(volume ? 'En lecture' : 'Son coupé', true);
    }).catch((error) => {
        if (audioSource.getAttribute('src') !== requestedSource || error.name === 'AbortError') return;
        audioState(error.name === 'NotAllowedError' ? 'Cliquez sur Écouter' : 'Lecture impossible — réessayer');
        console.warn('[sunny_loading] Lecture audio :', requestedSource, error.name);
    }).finally(() => { if (request === audioRequest) audioPlayPending = false; });
}
$('volume').addEventListener('input', (event) => { setVolume(Number(event.target.value)); if (!userPaused) startAudio(); });
$('mute').addEventListener('click', () => {
    if (volume) { previousVolume = volume; setVolume(0); } else setVolume(previousVolume);
    if (!userPaused) startAudio();
});
$('play-audio').addEventListener('click', () => {
    if (!tracks.length) return;
    if (!music.paused && !music.error) {
        userPaused = true;
        music.autoplay = false;
        music.pause();
        audioState('En pause');
        return;
    }
    userPaused = false;
    music.autoplay = true;
    if (!volume) setVolume(previousVolume || 30);
    if (music.error || !music.getAttribute('src')) { failedTracks.clear(); selectTrack(trackIndex); }
    else startAudio();
});
setVolume(volume);
const tracks = (Array.isArray(config.tracks) ? config.tracks : []).filter((track) => track && typeof track.src === 'string' && track.src.trim());
let trackIndex = 0;
const failedTracks = new Set();
tracks.forEach((track, index) => {
    const option = document.createElement('option');
    option.value = String(index);
    option.textContent = track.title || `Musique ${index + 1}`;
    $('track-select').append(option);
});
async function selectTrack(index) {
    if (!tracks.length) return;
    const request = ++audioRequest;
    music.pause();
    music.removeAttribute('src');
    music.load();
    audioPlayPending = false;
    trackIndex = (index + tracks.length) % tracks.length;
    $('track-select').value = String(trackIndex);
    audioState('Chargement…');
    try {
        const source = await loadAudioFile(tracks[trackIndex].src);
        if (request !== audioRequest) return;
        music.src = source;
        music.load();
        if (!userPaused) startAudio();
        else audioState('En pause');
    } catch (error) {
        if (request !== audioRequest) return;
        console.error('[sunny_loading] Chargement audio :', tracks[trackIndex].src, error.message);
        audioState('Fichier audio inaccessible');
    }
}
function advanceTrack(direction) {
    if (!tracks.length || failedTracks.size === tracks.length) return;
    let next = trackIndex;
    do { next = (next + direction + tracks.length) % tracks.length; } while (failedTracks.has(next));
    selectTrack(next);
}
$('track-select').addEventListener('change', (event) => selectTrack(Number(event.target.value)));
$('previous-track').addEventListener('click', () => advanceTrack(-1));
$('next-track').addEventListener('click', () => advanceTrack(1));
music.addEventListener('ended', () => advanceTrack(1));
music.addEventListener('canplay', () => { if (!userPaused && music.paused) startAudio(); });
window.addEventListener('focus', () => { if (!userPaused && music.paused && !music.error) startAudio(); });
music.addEventListener('playing', () => {
    audioState(volume ? 'En lecture' : 'Son coupé', true);
});
music.addEventListener('waiting', () => audioState('Chargement…'));
music.addEventListener('error', () => {
    console.error('[sunny_loading] Fichier audio indisponible :', music.currentSrc, music.error && music.error.code);
    failedTracks.add(trackIndex);
    if (!tracks.length) return;
    if (failedTracks.size < tracks.length) advanceTrack(1);
    else {
        const code = music.error && music.error.code;
        audioState(code === 4 ? 'Fichier introuvable ou incompatible' : 'Erreur audio — réessayer');
    }
});
if (tracks.length) selectTrack(0);
else {
    const option = document.createElement('option');
    option.textContent = 'Aucune musique configurée';
    $('track-select').append(option);
    audioState('Aucune musique');
    $('play-audio').disabled = true;
    for (const id of ['track-select', 'previous-track', 'next-track']) $(id).disabled = true;
}

const playlist = (Array.isArray(config.videos) ? config.videos : []).filter((path) => typeof path === 'string' && path.trim());
if (config.shuffleVideos) {
    for (let i = playlist.length - 1; i > 0; i--) {
        const j = Math.floor(Math.random() * (i + 1));
        [playlist[i], playlist[j]] = [playlist[j], playlist[i]];
    }
}
let videoIndex = -1;
let videoTimer;
const failedVideos = new Set();
const duration = Math.max(5, Number(config.videoDuration) || 30) * 1000;
function nextVideo() {
    clearTimeout(videoTimer);
    if (!playlist.length || failedVideos.size === playlist.length) {
        video.style.opacity = '0';
        video.pause();
        video.removeAttribute('src');
        video.load();
        return;
    }
    do { videoIndex = (videoIndex + 1) % playlist.length; } while (failedVideos.has(videoIndex));
    video.style.opacity = '0';
    video.src = playlist[videoIndex];
    video.load();
    videoTimer = setTimeout(() => { failedVideos.add(videoIndex); nextVideo(); }, 60000);
    video.play().catch((error) => {
        if (error.name !== 'AbortError') console.warn('[sunny_loading] Lecture vidéo :', video.currentSrc, error.name);
    });
}
video.addEventListener('playing', () => {
    video.style.opacity = '1';
    clearTimeout(videoTimer);
    videoTimer = setTimeout(nextVideo, duration);
});
video.addEventListener('ended', nextVideo);
video.addEventListener('error', () => {
    console.error('[sunny_loading] Fichier vidéo indisponible :', video.currentSrc, video.error && video.error.code);
    if (videoIndex >= 0 && video.getAttribute('src')) { failedVideos.add(videoIndex); nextVideo(); }
});
nextVideo();

let progress = 0;
window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data || data.eventName !== 'loadProgress' || typeof data.loadFraction !== 'number' || !Number.isFinite(data.loadFraction)) return;
    progress = Math.max(progress, Math.min(100, Math.max(0, data.loadFraction * 100)));
    const rounded = Math.round(progress);
    document.documentElement.style.setProperty('--progress', `${progress}%`);
    $('percentage').textContent = `${rounded} %`;
    $('progress').setAttribute('aria-valuenow', String(rounded));
    $('loading-status').textContent = progress >= 100 ? 'Derniers préparatifs…' : 'Chargement du territoire…';
});
