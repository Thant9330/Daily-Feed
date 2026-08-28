const express = require('express');
const path = require('path');
const fs = require('fs');

const app = express();
const PORT = process.env.PORT || 3000;
const DATA_DIR = path.join(__dirname, '..', 'data');
const PUBLIC_DIR = path.join(__dirname, 'public');

const DATE_RE = /^\d{4}-\d{2}-\d{2}$/;

// ── Pages ────────────────────────────────────────────────────────────────────
// The reading view (rendered feed.md) is the default page. Registered before
// express.static so it wins over public/index.html at "/".
app.get('/', (req, res) => {
  res.sendFile(path.join(PUBLIC_DIR, 'read.html'));
});

// The card dashboard — filters, search, bookmarks, read tracking.
app.get('/dashboard', (req, res) => {
  res.sendFile(path.join(PUBLIC_DIR, 'index.html'));
});

// ── API ──────────────────────────────────────────────────────────────────────
// GET /api/feed — today's feed
app.get('/api/feed', (req, res) => {
  const feedPath = path.join(DATA_DIR, 'feed.json');
  if (!fs.existsSync(feedPath)) {
    return res.status(404).json({ error: 'feed.json not found — run /refresh first' });
  }
  res.setHeader('Content-Type', 'application/json');
  res.sendFile(feedPath);
});

// GET /api/feed/:date — archived feed for a specific date (YYYY-MM-DD)
app.get('/api/feed/:date', (req, res) => {
  const { date } = req.params;
  if (!DATE_RE.test(date)) {
    return res.status(400).json({ error: 'Invalid date format — use YYYY-MM-DD' });
  }
  const archivePath = path.join(DATA_DIR, date, 'feed.json');
  if (!fs.existsSync(archivePath)) {
    return res.status(404).json({ error: `No archive for ${date}` });
  }
  res.setHeader('Content-Type', 'application/json');
  res.sendFile(archivePath);
});

// GET /api/feed.md — today's feed as markdown (what the reading view renders)
app.get('/api/feed.md', (req, res) => {
  const mdPath = path.join(DATA_DIR, 'feed.md');
  if (!fs.existsSync(mdPath)) {
    return res.status(404).json({ error: 'feed.md not found — run /refresh first' });
  }
  res.setHeader('Content-Type', 'text/plain; charset=utf-8');
  res.sendFile(mdPath);
});

// GET /api/feed.md/:date — archived markdown for a specific date
app.get('/api/feed.md/:date', (req, res) => {
  const { date } = req.params;
  if (!DATE_RE.test(date)) {
    return res.status(400).json({ error: 'Invalid date format — use YYYY-MM-DD' });
  }
  const archivePath = path.join(DATA_DIR, date, 'feed.md');
  if (!fs.existsSync(archivePath)) {
    return res.status(404).json({ error: `No archive for ${date}` });
  }
  res.setHeader('Content-Type', 'text/plain; charset=utf-8');
  res.sendFile(archivePath);
});

// GET /api/dates — list available archive dates
app.get('/api/dates', (req, res) => {
  if (!fs.existsSync(DATA_DIR)) {
    return res.json({ dates: [] });
  }
  const dates = fs.readdirSync(DATA_DIR)
    .filter(name => DATE_RE.test(name))
    .filter(name => fs.existsSync(path.join(DATA_DIR, name, 'feed.json')))
    .sort()
    .reverse();
  res.json({ dates });
});

// ── Static files ─────────────────────────────────────────────────────────────
app.use(express.static(PUBLIC_DIR));

// GET /YYYY-MM-DD — the reading view for an archived day. Registered AFTER
// express.static so real files (style.css, app.js) still resolve first, and
// the date is checked inside the handler: Express 5 dropped inline path
// regexes like "/:date(\\d{4}-\\d{2}-\\d{2})".
app.get('/:date', (req, res, next) => {
  if (!DATE_RE.test(req.params.date)) return next();
  res.sendFile(path.join(PUBLIC_DIR, 'read.html'));
});

app.listen(PORT, () => {
  console.log(`Daily Feed server running at http://localhost:${PORT}`);
  console.log(`Data directory: ${DATA_DIR}`);
});
