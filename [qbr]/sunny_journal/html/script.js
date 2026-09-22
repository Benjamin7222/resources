'use strict';

const RESOURCE = typeof GetParentResourceName === 'function' ? GetParentResourceName() : 'sunny_journal';
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
        return { ok: false, error: 'Erreur de communication avec le serveur.' };
    }
}

const isImageUrl = (value) => /^https?:\/\//i.test(value);

// Les liens Discord copiés depuis l'aperçu portent souvent "&width=256&height=384" :
// Discord renvoie alors une miniature. On les retire pour obtenir l'image en taille réelle.
function fullSizeUrl(value) {
    if (!/^https?:\/\/(media|cdn)\.discordapp\.(net|com)\//i.test(value)) return value;
    const [head, query] = value.split('?');
    if (!query) return value;
    const kept = query.split('&').filter((part) => !/^(width|height)=/i.test(part));
    return kept.length ? `${head}?${kept.join('&')}` : head;
}

const st = {
    mode: null,
    perms: {},
    defaults: { title: '', author: '', nextEdition: 1 },
    limits: { maxPages: 40, maxCopies: 50 },
    editions: [],
    current: null,
    dirty: false,
    busy: false,
};

let toastTimer = null;
function toast(message, isError) {
    const box = $('toast');
    box.textContent = message;
    box.className = 'toast' + (isError ? ' error' : '');
    clearTimeout(toastTimer);
    toastTimer = setTimeout(() => box.classList.add('hidden'), 3800);
}

let confirmResolve = null;
function confirmBox(text, yesLabel) {
    return new Promise((resolve) => {
        $('confirm-text').textContent = text;
        $('confirm-yes').textContent = yesLabel || 'Confirmer';
        $('confirm').classList.remove('hidden');
        confirmResolve = resolve;
    });
}
function closeConfirm(value) {
    $('confirm').classList.add('hidden');
    if (confirmResolve) {
        const resolve = confirmResolve;
        confirmResolve = null;
        resolve(value);
    }
}
$('confirm-yes').addEventListener('click', () => closeConfirm(true));
$('confirm-no').addEventListener('click', () => closeConfirm(false));

function hideAll() {
    $('editor').classList.add('hidden');
    $('reader').classList.add('hidden');
    $('confirm').classList.add('hidden');
    confirmResolve = null;
    st.mode = null;
}

function closeUI() {
    cancelPageTurn();
    hideAll();
    st.current = null;
    st.dirty = false;
    post('close');
}

window.addEventListener('message', (event) => {
    const data = event.data;
    if (!data) return;
    if (data.action === 'openEditor') openEditor();
    else if (data.action === 'openReader') openReader(data.journal, {});
});

async function openEditor() {
    st.mode = 'editor';
    st.current = null;
    st.dirty = false;
    $('editor').classList.remove('hidden');
    renderForm();
    await refreshList(true);
}

async function refreshList(closeOnError) {
    const res = await post('list');
    if (!res.ok) {
        toast(res.error || 'Accès refusé.', true);
        if (closeOnError) closeUI();
        return;
    }
    st.perms = res.perms;
    st.defaults = res.defaults;
    st.limits = res.limits;
    st.editions = res.editions;
    const label = res.paper ? res.paper.label : '';
    $('editor-paper').textContent = label ? `· ${label}` : '';
    $('f-paper').value = label;
    renderList();
    renderForm();
}

function formatDate(seconds) {
    if (!seconds) return '';
    return new Date(seconds * 1000).toLocaleDateString('fr-FR');
}

function renderList() {
    const list = $('edition-list');
    list.replaceChildren();
    if (st.editions.length === 0) {
        list.appendChild(el('li', 'list-empty', 'Aucune édition pour le moment.'));
        return;
    }
    for (const edition of st.editions) {
        const published = edition.status === 'published';
        const li = el('li');
        if (published) li.classList.add('is-published');
        if (st.current && st.current.journal_id === edition.journal_id) li.classList.add('active');

        li.appendChild(el('div', 'ed-title', edition.title));
        const meta = el('div', 'ed-meta');
        meta.appendChild(el('span', '', `Éd. n°${edition.edition} · ${edition.page_count || 0} p. · ${formatDate(edition.created_at)}`));
        meta.appendChild(el('span', 'tag' + (published ? ' tag-published' : ''), published ? 'Publié' : 'Brouillon'));
        li.appendChild(meta);
        li.appendChild(el('div', 'ed-meta', `par ${edition.author_name}`));

        li.addEventListener('click', () => selectEdition(edition.journal_id));
        list.appendChild(li);
    }
}

async function discardChangesAllowed() {
    if (!st.dirty) return true;
    return confirmBox('Tu as des modifications non enregistrées. Les abandonner ?', 'Abandonner');
}

async function selectEdition(journalId) {
    if (st.busy) return;
    if (st.current && st.current.journal_id === journalId) return;
    if (!(await discardChangesAllowed())) return;
    const res = await post('get', { journal_id: journalId });
    if (!res.ok) {
        toast(res.error, true);
        return;
    }
    st.current = res.edition;
    st.dirty = false;
    renderList();
    renderForm();
}

async function newEdition() {
    if (st.busy) return;
    if (!(await discardChangesAllowed())) return;
    st.current = {
        journal_id: null,
        title: st.defaults.title,
        edition: st.defaults.nextEdition,
        author: st.defaults.author,
        status: 'draft',
        printed: 0,
        pages: [''],
    };
    st.dirty = false;
    renderList();
    renderForm();
}

function setBusy(busy) {
    st.busy = busy;
    document.querySelectorAll('.actions button, #btn-print, #new-edition').forEach((button) => {
        button.disabled = busy;
    });
}

function renderForm() {
    const current = st.current;
    $('empty-state').classList.toggle('hidden', !!current);
    $('edition-form').classList.toggle('hidden', !current);
    $('new-edition').classList.toggle('hidden', !st.perms.create);
    if (!current) return;

    const published = current.status === 'published';
    $('f-title').value = current.title;
    $('f-edition').value = current.edition;
    $('f-author').value = current.author;
    for (const id of ['f-title', 'f-edition', 'f-author']) $(id).disabled = published;

    const banner = $('status-banner');
    banner.classList.toggle('hidden', !published);
    banner.textContent = 'Édition publiée : son contenu est figé et ne peut plus être modifié. Pour changer quelque chose, crée une nouvelle édition.';

    $('btn-save').classList.toggle('hidden', published || !st.perms.create);
    $('btn-publish').classList.toggle('hidden', published || !st.perms.publish);
    $('btn-delete').classList.toggle('hidden', !current.journal_id || !st.perms.delete);
    $('btn-delete').textContent = published ? 'Supprimer l\'édition' : 'Supprimer le brouillon';
    $('add-page').classList.toggle('hidden', published);

    const printBox = $('print-box');
    printBox.classList.toggle('hidden', !(published && st.perms.print));
    $('printed-info').textContent = current.printed ? `Déjà imprimé : ${current.printed} exemplaire(s).` : '';
    $('f-copies').max = st.limits.maxCopies;

    renderPages();
}

function renderPages() {
    const current = st.current;
    const published = current.status === 'published';
    const list = $('pages-list');
    list.replaceChildren();
    $('pages-count').textContent = `(${current.pages.length} / ${st.limits.maxPages})`;

    current.pages.forEach((url, index) => {
        const li = el('li');
        li.appendChild(el('span', 'page-num', String(index + 1)));

        const thumb = el('img', 'page-thumb');
        thumb.alt = '';
        if (isImageUrl(url)) thumb.src = url;
        thumb.addEventListener('error', () => thumb.removeAttribute('src'));
        li.appendChild(thumb);

        const input = el('input');
        input.type = 'text';
        input.placeholder = 'https://…/page.jpg';
        input.value = url;
        input.disabled = published;
        input.addEventListener('input', () => {
            current.pages[index] = input.value;
            st.dirty = true;
        });
        input.addEventListener('change', () => {
            if (isImageUrl(input.value.trim())) thumb.src = input.value.trim();
            else thumb.removeAttribute('src');
        });
        li.appendChild(input);

        if (!published) {
            const up = el('button', 'row-btn', '▲');
            up.type = 'button';
            up.title = 'Monter';
            up.disabled = index === 0;
            up.addEventListener('click', () => movePage(index, -1));
            const down = el('button', 'row-btn', '▼');
            down.type = 'button';
            down.title = 'Descendre';
            down.disabled = index === current.pages.length - 1;
            down.addEventListener('click', () => movePage(index, 1));
            const remove = el('button', 'row-btn', '✕');
            remove.type = 'button';
            remove.title = 'Retirer la page';
            remove.addEventListener('click', () => removePage(index));
            li.append(up, down, remove);
        }
        list.appendChild(li);
    });
}

function movePage(index, delta) {
    const pages = st.current.pages;
    const target = index + delta;
    if (target < 0 || target >= pages.length) return;
    [pages[index], pages[target]] = [pages[target], pages[index]];
    st.dirty = true;
    renderPages();
}

function removePage(index) {
    st.current.pages.splice(index, 1);
    st.dirty = true;
    renderPages();
}

function addPage() {
    if (st.current.pages.length >= st.limits.maxPages) {
        toast(`Une édition ne peut pas dépasser ${st.limits.maxPages} pages.`, true);
        return;
    }
    st.current.pages.push('');
    st.dirty = true;
    renderPages();
    const inputs = document.querySelectorAll('#pages-list input');
    if (inputs.length) inputs[inputs.length - 1].focus();
}

function cleanPages() {
    return st.current.pages.map((url) => fullSizeUrl(url.trim())).filter((url) => url.length > 0);
}

async function saveDraft(silent) {
    const current = st.current;
    if (!current || st.busy) return false;
    const payload = {
        title: current.title,
        edition: Number(current.edition),
        author: current.author,
        pages: cleanPages(),
    };
    if (current.journal_id) payload.journal_id = current.journal_id;

    setBusy(true);
    const res = await post('save', payload);
    setBusy(false);
    if (!res.ok) {
        toast(res.error, true);
        return false;
    }
    current.journal_id = res.journal_id;
    current.pages = payload.pages;
    st.dirty = false;
    await refreshList(false);
    if (!silent) toast('Brouillon enregistré.');
    return true;
}

async function publishEdition() {
    const current = st.current;
    if (!current || st.busy) return;
    if (cleanPages().length < 1) {
        toast('Ajoute au moins une page avant de publier.', true);
        return;
    }
    const ok = await confirmBox(
        `Publier « ${current.title} », édition n°${current.edition} ? Une fois publiée, elle ne pourra plus jamais être modifiée.`,
        'Publier'
    );
    if (!ok) return;
    if (!(await saveDraft(true))) return;

    setBusy(true);
    const res = await post('publish', { journal_id: current.journal_id });
    setBusy(false);
    if (!res.ok) {
        toast(res.error, true);
        return;
    }
    toast('Édition publiée. Tu peux maintenant l\'imprimer.');
    await reloadCurrent();
}

async function reloadCurrent() {
    const id = st.current && st.current.journal_id;
    if (!id) return;
    const res = await post('get', { journal_id: id });
    if (res.ok) {
        st.current = res.edition;
        st.dirty = false;
    }
    await refreshList(false);
}

async function deleteDraft() {
    const current = st.current;
    if (!current || !current.journal_id || st.busy) return;
    const published = current.status === 'published';
    const ok = await confirmBox(
        published
            ? `Supprimer définitivement « ${current.title} », édition n°${current.edition} ? Les exemplaires déjà imprimés seront trop froissés pour être lus. Cette action est irréversible.`
            : `Supprimer définitivement le brouillon « ${current.title} » ?`,
        'Supprimer'
    );
    if (!ok) return;
    setBusy(true);
    const res = await post('delete', { journal_id: current.journal_id });
    setBusy(false);
    if (!res.ok) {
        toast(res.error, true);
        return;
    }
    st.current = null;
    st.dirty = false;
    toast(published ? 'Édition supprimée.' : 'Brouillon supprimé.');
    await refreshList(false);
}

async function printCopies() {
    const current = st.current;
    if (!current || st.busy) return;
    const copies = Number($('f-copies').value);
    if (!Number.isInteger(copies) || copies < 1 || copies > st.limits.maxCopies) {
        toast(`Le nombre d'exemplaires doit être entre 1 et ${st.limits.maxCopies}.`, true);
        return;
    }
    setBusy(true);
    const res = await post('print', { journal_id: current.journal_id, copies });
    setBusy(false);
    if (!res.ok) {
        toast(res.error, true);
        return;
    }
    if (res.given < res.requested) toast(`${res.given} exemplaire(s) sur ${res.requested} imprimé(s) : ton inventaire est plein.`, true);
    else toast(`${res.given} exemplaire(s) ajouté(s) à ton inventaire.`);
    await reloadCurrent();
}

function previewEdition() {
    const pages = cleanPages().filter(isImageUrl);
    if (!pages.length) {
        toast('Ajoute au moins une page avec un lien valide.', true);
        return;
    }
    openReader({ pages }, { fromEditor: true });
}

async function requestCloseEditor() {
    if (!(await discardChangesAllowed())) return;
    closeUI();
}

$('f-title').addEventListener('input', (e) => { st.current.title = e.target.value; st.dirty = true; });
$('f-edition').addEventListener('input', (e) => { st.current.edition = e.target.value; st.dirty = true; });
$('f-author').addEventListener('input', (e) => { st.current.author = e.target.value; st.dirty = true; });
$('new-edition').addEventListener('click', newEdition);
$('add-page').addEventListener('click', addPage);
$('btn-save').addEventListener('click', () => saveDraft(false));
$('btn-publish').addEventListener('click', publishEdition);
$('btn-delete').addEventListener('click', deleteDraft);
$('btn-print').addEventListener('click', printCopies);
$('btn-preview').addEventListener('click', previewEdition);
$('editor-close').addEventListener('click', requestCloseEditor);

const rd = { pages: [], spread: 0, fromEditor: false, animating: false, turnId: 0 };

function cancelPageTurn() {
    rd.turnId++;
    rd.animating = false;
    $('r-book').getAnimations({ subtree: true }).forEach((animation) => animation.cancel());
}

const spreadCount = () => (rd.pages.length === 0 ? 0 : 1 + Math.ceil((rd.pages.length - 1) / 2));

function spreadUrls(spread) {
    if (spread === 0) return rd.pages.slice(0, 1);
    const first = 2 * spread - 1;
    return rd.pages.slice(first, first + 2);
}

function openReader(journal, options) {
    cancelPageTurn();
    rd.pages = ((journal && journal.pages) || []).filter(isImageUrl).map(fullSizeUrl);
    rd.spread = 0;
    rd.fromEditor = !!options.fromEditor;
    rd.animating = false;
    $('reader').classList.remove('hidden');
    st.mode = 'reader';
    renderSpread();
}

function renderSpread() {
    const book = $('r-book');
    book.replaceChildren();
    for (const url of spreadUrls(rd.spread)) {
        const page = el('div', 'book-page');
        const img = el('img');
        img.alt = '';
        img.draggable = false;
        img.addEventListener('error', () => img.replaceWith(el('div', 'page-error', 'Image introuvable')));
        img.src = url;
        page.appendChild(img);
        book.appendChild(page);
    }
}

function preloadImages(urls) {
    return Promise.all(urls.map((url) => new Promise((resolve) => {
        const probe = new Image();
        probe.onload = probe.onerror = () => resolve();
        probe.src = url;
        setTimeout(resolve, 2500);
    })));
}

function settle(animation, limit) {
    return Promise.race([
        animation.finished.catch(() => {}),
        new Promise((resolve) => setTimeout(resolve, limit)),
    ]);
}

async function turnPage(target) {
    if (rd.animating || target < 0 || target >= spreadCount() || target === rd.spread) return;
    rd.animating = true;
    const turnId = ++rd.turnId;
    const direction = target > rd.spread ? 1 : -1;
    const book = $('r-book');
    try {
        // Garder la page lisible pendant le chargement de la suivante.
        await preloadImages(spreadUrls(target));
        if (turnId !== rd.turnId) return;
        if (window.matchMedia('(prefers-reduced-motion: reduce)').matches) {
            rd.spread = target;
            renderSpread();
            return;
        }
        const outgoing = direction > 0 ? book.lastElementChild : book.firstElementChild;
        outgoing.style.transformOrigin = direction > 0 ? 'left center' : 'right center';
        outgoing.classList.add('turning');
        const outAnim = outgoing.animate([
            { transform: 'rotateY(0deg)', filter: 'brightness(1)' },
            { transform: `rotateY(${-direction * 45}deg)`, filter: 'brightness(.88)', offset: .6 },
            { transform: `rotateY(${-direction * 90}deg)`, filter: 'brightness(.65)' },
        ], { duration: 280, easing: 'ease-in', fill: 'forwards' });
        await settle(outAnim, 500);
        if (turnId !== rd.turnId) return;
        rd.spread = target;
        renderSpread();
        outAnim.cancel();
        const incoming = direction > 0 ? book.firstElementChild : book.lastElementChild;
        incoming.style.transformOrigin = direction > 0 ? 'right center' : 'left center';
        incoming.classList.add('turning');
        const inAnim = incoming.animate([
            { transform: `rotateY(${direction * 90}deg)`, filter: 'brightness(.65)' },
            { transform: `rotateY(${direction * 35}deg)`, filter: 'brightness(.92)', offset: .4 },
            { transform: 'rotateY(0deg)', filter: 'brightness(1)' },
        ], { duration: 360, easing: 'ease-out', fill: 'forwards' });
        await settle(inAnim, 600);
        inAnim.cancel();
        incoming.classList.remove('turning');
    } catch (e) {
        if (turnId !== rd.turnId) return;
        book.getAnimations({ subtree: true }).forEach((animation) => animation.cancel());
        rd.spread = target;
        renderSpread();
    } finally {
        if (turnId === rd.turnId) rd.animating = false;
    }
}

function closeReader() {
    cancelPageTurn();
    $('r-book').replaceChildren();
    if (rd.fromEditor) {
        $('reader').classList.add('hidden');
        st.mode = 'editor';
    } else {
        closeUI();
    }
}

document.addEventListener('keydown', (event) => {
    if (!$('confirm').classList.contains('hidden')) {
        if (event.key === 'Escape') closeConfirm(false);
        else if (event.key === 'Enter') closeConfirm(true);
        return;
    }
    if (st.mode === 'reader') {
        if (event.key === 'Backspace' || event.key === 'Escape') {
            event.preventDefault();
            closeReader();
        } else if (event.key === 'ArrowRight') turnPage(rd.spread + 1);
        else if (event.key === 'ArrowLeft') turnPage(rd.spread - 1);
    } else if (st.mode === 'editor') {
        if (event.key === 'Escape') requestCloseEditor();
    }
});
