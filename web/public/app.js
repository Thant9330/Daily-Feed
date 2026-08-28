/* ─────────────────────────────────────────────────────────
   Daily Feed — app.js
   Vanilla JS, no frameworks. Reads from /api/feed.
   ───────────────────────────────────────────────────────── */

// ── Storage keys ──────────────────────────────────────────
const KEYS = {
  READ:      'df_read',
  BOOKMARKS: 'df_bookmarks',
  FILTERS:   'df_filters',
  YESTERDAY: 'df_yesterday_ids',
};

// ── State ─────────────────────────────────────────────────
const state = {
  allItems:      [],
  read:          new Set(),
  bookmarks:     new Set(),
  activeSources: new Set(['github', 'hackernews', 'reddit']),
  showBookmarks: false,
  search:        '',
  yesterdayIds:  new Set(),
};

// ── Persistence helpers ───────────────────────────────────

function loadSet(key) {
  try { return new Set(JSON.parse(localStorage.getItem(key) || '[]')); }
  catch { return new Set(); }
}

function saveSet(key, set) {
  localStorage.setItem(key, JSON.stringify([...set]));
}

function loadFilters() {
  try {
    const saved = JSON.parse(localStorage.getItem(KEYS.FILTERS));
    if (Array.isArray(saved)) return new Set(saved);
  } catch {}
  return new Set(['github', 'hackernews', 'reddit']);
}

// ── DOM helpers ───────────────────────────────────────────

const $  = id => document.getElementById(id);
const $q = sel => document.querySelector(sel);
const $qa = sel => document.querySelectorAll(sel);

function show(el) { el.classList.remove('hidden'); }
function hide(el) { el.classList.add('hidden'); }

// ── Fetch feed ────────────────────────────────────────────

async function loadFeed(date) {
  const url = date ? `/api/feed/${date}` : '/api/feed';

  show($('loadingState'));
  hide($('errorState'));
  hide($('emptyState'));
  $('cardsGrid').innerHTML = '';

  try {
    const res = await fetch(url);
    if (!res.ok) throw new Error(res.status === 404 ? 'not_found' : `HTTP ${res.status}`);
    const data = await res.json();

    state.allItems = Array.isArray(data.items) ? data.items : [];

    // Update date display
    $('feedDate').textContent = data.date || '';

    // Cache yesterday's ids for "New" badge logic
    await cacheYesterdayIds(data.date);

    hide($('loadingState'));
    renderAll();
  } catch (err) {
    hide($('loadingState'));
    const msg = err.message === 'not_found'
      ? 'No feed yet — run <code>/refresh</code> to generate today\'s feed.'
      : `Failed to load feed: ${err.message}`;
    $('errorMessage').innerHTML = msg;
    show($('errorState'));
  }
}

// Fetch and cache yesterday's item IDs for "New" badge
async function cacheYesterdayIds(todayDate) {
  const cached = localStorage.getItem(KEYS.YESTERDAY);
  if (cached) {
    try {
      const obj = JSON.parse(cached);
      if (obj.date && obj.date !== todayDate) {
        state.yesterdayIds = new Set(obj.ids || []);
        return;
      }
    } catch {}
  }

  // Try to fetch yesterday's feed
  if (!todayDate) return;
  const d = new Date(todayDate);
  d.setDate(d.getDate() - 1);
  const yDate = d.toISOString().slice(0, 10);
  try {
    const res = await fetch(`/api/feed/${yDate}`);
    if (res.ok) {
      const data = await res.json();
      const ids = (data.items || []).map(i => i.id);
      state.yesterdayIds = new Set(ids);
      localStorage.setItem(KEYS.YESTERDAY, JSON.stringify({ date: todayDate, ids }));
    }
  } catch {}
}

// ── Render ─────────────────────────────────────────────────

function getVisible() {
  const q = state.search.toLowerCase().trim();
  return state.allItems.filter(item => {
    if (!state.activeSources.has(item.source)) return false;
    if (state.showBookmarks && !state.bookmarks.has(item.id)) return false;
    if (q) {
      const haystack = `${item.title} ${item.summary}`.toLowerCase();
      if (!haystack.includes(q)) return false;
    }
    return true;
  });
}

function renderAll() {
  const visible = getVisible();
  const grid = $('cardsGrid');
  grid.innerHTML = '';

  if (visible.length === 0 && state.allItems.length > 0) {
    show($('emptyState'));
  } else {
    hide($('emptyState'));
  }

  visible.forEach((item, i) => {
    grid.appendChild(buildCard(item, i));
  });

  updateStats();
  updateFooter();
}

function buildCard(item, index) {
  const isRead       = state.read.has(item.id);
  const isBookmarked = state.bookmarks.has(item.id);
  const isNew        = !state.yesterdayIds.has(item.id) && state.yesterdayIds.size > 0;

  const card = document.createElement('article');
  card.className = [
    'card',
    `source-${item.source}`,
    isRead ? 'is-read' : '',
  ].filter(Boolean).join(' ');
  card.dataset.id = item.id;
  card.style.setProperty('--i', index);

  // Source label
  const srcLabel = { github: 'GitHub', hackernews: 'HN', reddit: 'Reddit' }[item.source] || item.source;

  // Tags HTML
  const tagsHtml = (item.tags || []).slice(0, 3)
    .map(t => `<span class="tag-chip">${escHtml(t)}</span>`)
    .join('');

  // Relevance dot
  const rel = Math.min(5, Math.max(1, item.relevance || 3));
  const relLabel = ['', 'Low', 'Low', 'Medium', 'High', 'Top'][rel] || '';

  card.innerHTML = `
    <div class="card-body">
      <div class="card-meta">
        <span class="source-chip chip-${item.source}">${srcLabel}</span>
        ${isNew ? '<span class="new-badge">New</span>' : ''}
      </div>
      <h3 class="card-title">
        <a href="${escHtml(item.url || '#')}" target="_blank" rel="noopener noreferrer"
           data-id="${escHtml(item.id)}">
          ${escHtml(item.title || 'Untitled')}
        </a>
      </h3>
      ${item.summary ? `<p class="card-summary">${escHtml(item.summary)}</p>` : ''}
    </div>
    <footer class="card-footer">
      ${tagsHtml}
      <div class="footer-right">
        <span class="relevance-dot rel-${rel}" title="Relevance: ${relLabel} (${rel}/5)"></span>
        <button class="bookmark-btn ${isBookmarked ? 'bookmarked' : ''}"
                data-id="${escHtml(item.id)}"
                title="${isBookmarked ? 'Remove bookmark' : 'Bookmark'}">
          ${isBookmarked ? '★' : '☆'}
        </button>
      </div>
    </footer>
  `;

  return card;
}

function escHtml(str) {
  return String(str)
    .replace(/&/g, '&amp;')
    .replace(/</g, '&lt;')
    .replace(/>/g, '&gt;')
    .replace(/"/g, '&quot;')
    .replace(/'/g, '&#39;');
}

// ── Stats ─────────────────────────────────────────────────

function updateStats() {
  const visible = getVisible();
  const unread = visible.filter(i => !state.read.has(i.id)).length;
  const bookmarked = state.bookmarks.size;

  $('statTotal').textContent    = `${visible.length} item${visible.length !== 1 ? 's' : ''}`;
  $('statUnread').textContent   = `${unread} unread`;
  $('statBookmarked').textContent = `${bookmarked} bookmarked`;
}

function updateFooter() {
  const visible = getVisible();
  $('footerItemCount').textContent = `${visible.length} item${visible.length !== 1 ? 's' : ''}`;
}

// ── Event delegation: card interactions ───────────────────

document.addEventListener('click', e => {
  // Title click → mark read
  const titleLink = e.target.closest('.card-title a');
  if (titleLink) {
    const id = titleLink.dataset.id;
    if (id) markRead(id);
    return; // let the link navigate normally
  }

  // Bookmark toggle
  const bkBtn = e.target.closest('.bookmark-btn');
  if (bkBtn) {
    e.preventDefault();
    toggleBookmark(bkBtn.dataset.id, bkBtn);
    return;
  }
});

function markRead(id) {
  state.read.add(id);
  saveSet(KEYS.READ, state.read);

  // Update card in DOM without full re-render
  const card = document.querySelector(`.card[data-id="${CSS.escape(id)}"]`);
  if (card) {
    card.classList.add('is-read');
    const link = card.querySelector('.card-title a');
    if (link) link.closest('.card-title').querySelector('a').style.textDecoration = '';
  }
  updateStats();
}

function toggleBookmark(id, btn) {
  if (state.bookmarks.has(id)) {
    state.bookmarks.delete(id);
    btn.classList.remove('bookmarked');
    btn.textContent = '☆';
    btn.title = 'Bookmark';
  } else {
    state.bookmarks.add(id);
    btn.classList.add('bookmarked');
    btn.textContent = '★';
    btn.title = 'Remove bookmark';
    btn.style.transform = 'scale(1.3)';
    setTimeout(() => { btn.style.transform = ''; }, 200);
  }
  saveSet(KEYS.BOOKMARKS, state.bookmarks);
  if (state.showBookmarks) renderAll(); // re-filter if bookmarks-only mode
  updateStats();
  updateFooter();
}

// ── Source filter buttons ─────────────────────────────────

$('filters').addEventListener('click', e => {
  const btn = e.target.closest('.filter-btn');
  if (!btn) return;

  if (btn.id === 'bookmarksToggle') {
    state.showBookmarks = !state.showBookmarks;
    btn.classList.toggle('active', state.showBookmarks);
    renderAll();
    return;
  }

  const src = btn.dataset.source;
  if (!src) return;

  if (state.activeSources.has(src)) {
    // Don't allow deactivating all sources
    if (state.activeSources.size === 1) return;
    state.activeSources.delete(src);
    btn.classList.remove('active');
  } else {
    state.activeSources.add(src);
    btn.classList.add('active');
  }

  saveSet(KEYS.FILTERS, state.activeSources);
  renderAll();
});

// ── Search ────────────────────────────────────────────────

let searchTimer;
$('searchInput').addEventListener('input', e => {
  state.search = e.target.value;
  $('searchClear').classList.toggle('visible', state.search.length > 0);
  clearTimeout(searchTimer);
  searchTimer = setTimeout(renderAll, 120);
});

$('searchClear').addEventListener('click', () => {
  $('searchInput').value = '';
  state.search = '';
  $('searchClear').classList.remove('visible');
  renderAll();
  $('searchInput').focus();
});

// ── Date picker ───────────────────────────────────────────

async function populateDatePicker() {
  try {
    const res = await fetch('/api/dates');
    if (!res.ok) return;
    const { dates } = await res.json();
    const sel = $('datePicker');
    dates.forEach(d => {
      const opt = document.createElement('option');
      opt.value = d;
      opt.textContent = d;
      sel.appendChild(opt);
    });
  } catch {}
}

$('datePicker').addEventListener('change', e => {
  loadFeed(e.target.value || null);
});

// ── Footer actions ────────────────────────────────────────

$('markAllRead').addEventListener('click', () => {
  const visible = getVisible();
  visible.forEach(item => state.read.add(item.id));
  saveSet(KEYS.READ, state.read);
  renderAll();
});

$('clearRead').addEventListener('click', () => {
  state.read.clear();
  saveSet(KEYS.READ, state.read);
  renderAll();
});

// ── Init ──────────────────────────────────────────────────

function init() {
  // Load persisted state
  state.read       = loadSet(KEYS.READ);
  state.bookmarks  = loadSet(KEYS.BOOKMARKS);
  state.activeSources = loadFilters();

  // Sync filter buttons to loaded state
  $qa('.filter-btn[data-source]').forEach(btn => {
    btn.classList.toggle('active', state.activeSources.has(btn.dataset.source));
  });

  populateDatePicker();
  loadFeed(null);
}

init();
