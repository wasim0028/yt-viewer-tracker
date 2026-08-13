import 'dotenv/config';
import express from 'express';
import cors from 'cors';
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

import { initDb, getSince, getRange, getRangeBucketed, pivot } from './db.js';
import { startPolling } from './poller.js';
import { getAds } from './ads.js';

const __dirname = path.dirname(fileURLToPath(import.meta.url));

const {
  YOUTUBE_API_KEY,
  PORT = 4000,
  POLL_INTERVAL_MS = 180000,
  LIVE_LOOKUP_REFRESH_MS = 1800000,
  REACTIVE_REDISCOVER_COOLDOWN_MS = 1800000,
  ADS_API_URL,
  ADS_API_KEY,
} = process.env;

const config = JSON.parse(
  fs.readFileSync(path.join(__dirname, 'config.json'), 'utf-8')
);
const channels = config.channels;

if (!YOUTUBE_API_KEY) {
  console.warn(
    '[server] WARNING: YOUTUBE_API_KEY is not set. Copy .env.example to .env and add your key, or the poller will fail every tick.'
  );
}

const app = express();
app.use(cors());
app.use(express.json());
app.use('/ads-media', express.static(path.join(__dirname, 'public', 'ads')));

app.get('/api/channels', (req, res) => {
  res.json(channels.map(({ name, color }) => ({ name, color })));
});

// Recent readings, e.g. /api/live?hours=24
app.get('/api/live', async (req, res) => {
  try {
    const hours = Number(req.query.hours) || 24;
    const since = new Date(Date.now() - hours * 60 * 60 * 1000).toISOString();
    const rows = await getSince(since);
    res.json({
      channels: channels.map(({ name, color }) => ({ name, color })),
      series: pivot(rows),
    });
  } catch (err) {
    console.error('[server] /api/live failed:', err.message);
    res.status(500).json({ error: 'Failed to load readings from the database.' });
  }
});

// Historical range, e.g. /api/history?start=...&end=...&bucketMinutes=60
// bucketMinutes is optional; omit it (or pass 0) for raw, unaveraged ticks.
app.get('/api/history', async (req, res) => {
  const { start, end, bucketMinutes } = req.query;
  if (!start || !end) {
    return res
      .status(400)
      .json({ error: 'Both start and end query params (ISO timestamps) are required.' });
  }

  try {
    const bucket = Number(bucketMinutes) || 0;
    const rows = bucket > 0
      ? await getRangeBucketed(start, end, bucket)
      : await getRange(start, end);

    res.json({
      channels: channels.map(({ name, color }) => ({ name, color })),
      series: pivot(rows),
    });
  } catch (err) {
    console.error('[server] /api/history failed:', err.message);
    res.status(500).json({ error: 'Failed to load readings from the database.' });
  }
});

// Ad creatives for the side rail slots, e.g. /api/ads
app.get('/api/ads', async (req, res) => {
  try {
    const ads = await getAds({ adsApiUrl: ADS_API_URL, adsApiKey: ADS_API_KEY });
    res.json({ ads });
  } catch (err) {
    console.error('[server] /api/ads failed:', err.message);
    res.status(500).json({ ads: [] });
  }
});

// Serve the built frontend in production, if present.
const frontendDist = path.join(__dirname, '..', 'frontend', 'dist');
if (fs.existsSync(frontendDist)) {
  app.use(express.static(frontendDist));
  app.get('*', (req, res) => {
    res.sendFile(path.join(frontendDist, 'index.html'));
  });
}

try {
  await initDb();
} catch (err) {
  console.error('[server] Could not connect to PostgreSQL:', err.message);
  console.error(
    '[server] Check DATABASE_URL (or PGHOST/PGUSER/PGPASSWORD/PGDATABASE/PGPORT) in your .env file, and that the database server is running.'
  );
  process.exit(1);
}

app.listen(PORT, () => {
  console.log(`[server] listening on http://localhost:${PORT}`);
  startPolling({
    channels,
    apiKey: YOUTUBE_API_KEY,
    pollIntervalMs: Number(POLL_INTERVAL_MS),
    liveLookupRefreshMs: Number(LIVE_LOOKUP_REFRESH_MS),
    reactiveCooldownMs: Number(REACTIVE_REDISCOVER_COOLDOWN_MS),
  });
});
