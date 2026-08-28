/* ─────────────────────────────────────────────
   Daily Feed — reading view
   Renders data/feed.md. Vanilla JS, no frameworks.

   This is NOT a general markdown parser. It reads the exact grammar
   summarise/build-feed.sh emits:

     # Daily Feed — DATE
     > optional note (a provisional, not-yet-summarised feed)
     ## GitHub (16 items)
     ### item title
     <bare url>
     <summary paragraph>
     Tags: a, b | Relevance: 4/5

   Anything it doesn't recognise falls through as a plain paragraph, so an
   edit to the generator degrades the page rather than breaking it.
   ───────────────────────────────────────────── */

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

// Section label in feed.md → the source colour token in style.css
const SOURCE_KEYS = {
  'GitHub': 'github',
  'Hacker News': 'hn',
  'Reddit': 'reddit',
};

const el = {
  feed:        document.getElementById('feed'),
  feedDate:    document.getElementById('feedDate'),
  datePicker:  document.getElementById('datePicker'),
  jumpNav:     document.getElementById('jumpNav'),
  jumpNavInner: document.getElementById('jumpNavInner'),
  loading:     document.getElementById('loadingState'),
  error:       document.getElementById('errorState'),
  errorMsg:    document.getElementById('errorMessage'),
  itemCount:   document.getElementById('footerItemCount'),
  rawLink:     document.getElementById('rawLink'),
};

/* ── Which day are we showing? ──────────────────────────────────────────── */

function dateFromPath() {
  const seg = location.pathname.replace(/^\/+|\/+$/g, '');
  return DATE_RE.test(seg) ? seg : '';
}

/* ── Parse ──────────────────────────────────────────────────────────────── */

// → { date, sections: [{ label, key, count, items: [...] }] }
function parseFeed(md) {
  const out = { date: '', note: '', sections: [] };
  let section = null;
  let item = null;

  for (const raw of md.split('\n')) {
    const line = raw.trim();
    if (!line) continue;

    if (line.startsWith('# ')) {
      const m = line.match(/—\s*(\d{4}-\d{2}-\d{2})/);
      if (m) out.date = m[1];
      continue;
    }

    // A note only appears before the first section — build-feed.sh writes it
    // directly under the heading when FEED_NOTE is set.
    if (line.startsWith('> ') && !section) {
      out.note = line.slice(2).trim();
      continue;
    }

    if (line.startsWith('## ')) {
      const heading = line.slice(3).trim();
      const m = heading.match(/^(.*?)\s*\((\d+)\s+items?\)$/);
      const label = m ? m[1] : heading;
      section = {
        label,
        key: SOURCE_KEYS[label] || 'other',
        count: m ? Number(m[2]) : 0,
        items: [],
      };
      out.sections.push(section);
      item = null;
      continue;
    }

    if (line.startsWith('### ')) {
      item = { title: line.slice(4).trim(), url: '', summary: '', tags: [], relevance: null };
      if (section) section.items.push(item);
      continue;
    }

    if (!item) continue;

    if (/^https?:\/\//.test(line)) {
      if (!item.url) item.url = line;
      continue;
    }

    const meta = line.match(/^Tags:\s*(.*?)\s*\|\s*Relevance:\s*(\d+)\/5$/);
    if (meta) {
      item.tags = meta[1].split(',').map(t => t.trim()).filter(Boolean);
      item.relevance = Number(meta[2]);
      continue;
    }

    item.summary = item.summary ? `${item.summary} ${line}` : line;
  }

  return out;
}

/* ── Render ─────────────────────────────────────────────────────────────── */

// Everything below builds nodes with createElement + textContent. Titles and
// summaries are model-written text; never interpolate them into innerHTML.
function node(tag, className, text) {
  const n = document.createElement(tag);
  if (className) n.className = className;
  if (text !== undefined) n.textContent = text;
  return n;
}

function relevanceClass(n) {
  if (n >= 5) return 'rel-high';
  if (n >= 4) return 'rel-good';
  if (n >= 3) return 'rel-mid';
  return 'rel-low';
}

function renderItem(item) {
  const wrap = node('section', 'read-item');

  const h3 = node('h3', 'read-item-title');
  if (item.url) {
    const a = node('a', null, item.title);
    a.href = item.url;
    a.target = '_blank';
    a.rel = 'noopener';
    h3.appendChild(a);
  } else {
    h3.textContent = item.title;
  }
  wrap.appendChild(h3);

  if (item.url) {
    const link = node('a', 'read-item-url', item.url);
    link.href = item.url;
    link.target = '_blank';
    link.rel = 'noopener';
    wrap.appendChild(link);
  }

  if (item.summary) wrap.appendChild(node('p', 'read-item-summary', item.summary));

  if (item.tags.length || item.relevance !== null) {
    const meta = node('div', 'read-item-meta');
    for (const tag of item.tags) meta.appendChild(node('span', 'read-tag', tag));
    if (item.relevance !== null) {
      meta.appendChild(node('span', `read-relevance ${relevanceClass(item.relevance)}`,
        `${item.relevance}/5`));
    }
    wrap.appendChild(meta);
  }

  return wrap;
}

function renderSection(section, index) {
  const wrap = node('section', `read-section src-${section.key}`);
  wrap.id = `section-${index}`;

  const head = node('div', 'read-section-head');
  head.appendChild(node('span', 'read-section-dot'));
  head.appendChild(node('h2', 'read-section-title', section.label));
  head.appendChild(node('span', 'read-section-count',
    `${section.items.length} item${section.items.length === 1 ? '' : 's'}`));
  wrap.appendChild(head);

  for (const item of section.items) wrap.appendChild(renderItem(item));
  return wrap;
}

function renderJumpNav(sections) {
  el.jumpNavInner.replaceChildren();
  if (!sections.length) {
    el.jumpNav.hidden = true;
    return;
  }
  sections.forEach((section, i) => {
    const a = node('a', `jump-link src-${section.key}`);
    a.href = `#section-${i}`;
    a.appendChild(node('span', 'read-section-dot'));
    a.appendChild(node('span', null, `${section.label} (${section.items.length})`));
    el.jumpNavInner.appendChild(a);
  });
  el.jumpNav.hidden = false;
}

function render(feed) {
  el.feed.replaceChildren();
  // A provisional feed carries build-feed.sh's default relevance of 3 for every
  // item. Nobody judged those, so don't display them as if someone had.
  el.feed.classList.toggle('is-provisional', Boolean(feed.note));
  if (feed.note) el.feed.appendChild(node('p', 'read-note', feed.note));
  feed.sections.forEach((section, i) => el.feed.appendChild(renderSection(section, i)));
  renderJumpNav(feed.sections);

  const total = feed.sections.reduce((n, s) => n + s.items.length, 0);
  el.itemCount.textContent = `${total} item${total === 1 ? '' : 's'}`;
  el.feedDate.textContent = feed.date || '—';
  document.title = feed.date ? `Daily Feed — ${feed.date}` : 'Daily Feed';
}

/* ── States ─────────────────────────────────────────────────────────────── */

function showError(message) {
  el.loading.classList.add('hidden');
  el.error.classList.remove('hidden');
  el.errorMsg.textContent = message;
  el.feed.replaceChildren();
  el.jumpNav.hidden = true;
}

/* ── Load ───────────────────────────────────────────────────────────────── */

async function loadFeed() {
  const date = dateFromPath();
  const url = date ? `/api/feed.md/${date}` : '/api/feed.md';
  el.rawLink.href = url;

  try {
    const res = await fetch(url);
    if (!res.ok) {
      const body = await res.json().catch(() => ({}));
      showError(body.error || `Could not load the feed (${res.status}).`);
      return;
    }
    const feed = parseFeed(await res.text());
    el.loading.classList.add('hidden');
    el.error.classList.add('hidden');
    render(feed);
  } catch (err) {
    showError(`Could not reach the server: ${err.message}`);
  }
}

async function loadDates() {
  try {
    const res = await fetch('/api/dates');
    if (!res.ok) return;
    const { dates } = await res.json();
    const current = dateFromPath();

    for (const date of dates) {
      const opt = document.createElement('option');
      opt.value = date;
      opt.textContent = date;
      el.datePicker.appendChild(opt);
    }
    el.datePicker.value = current;
  } catch {
    /* the date picker is a convenience — a failure here must not blank the page */
  }
}

el.datePicker.addEventListener('change', () => {
  const date = el.datePicker.value;
  location.pathname = date ? `/${date}` : '/';
});

loadFeed();
loadDates();
