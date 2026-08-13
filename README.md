# Viewer Watch

A live dashboard that tracks concurrent viewers on two or more YouTube live
streams over time, so you can compare channels head-to-head — the same idea
as the internal "RBANGLA vs ABPANANDA" tool in the screenshot.

- **Backend** (`/backend`): Node.js + Express. Polls the YouTube Data API on
  a timer, stores every reading in PostgreSQL, and serves it over a small
  REST API.
- **Frontend** (`/frontend`): React + Vite. A **Live Chart** tab (auto-refreshing
  chart + reading log) and a **History** tab (pick any past date range).

---

## 1. Get a YouTube Data API key

This app needs a YouTube Data API v3 key to read viewer counts. It's free for
this volume of usage.

1. Go to the [Google Cloud Console](https://console.cloud.google.com/).
2. Create a new project (or pick an existing one) from the project dropdown
   at the top.
3. Go to **APIs & Services → Library**, search for **YouTube Data API v3**,
   and click **Enable**.
4. Go to **APIs & Services → Credentials → Create Credentials → API key**.
5. Copy the key it gives you. Optionally click **Restrict key** and limit it
   to "YouTube Data API v3" so it can't be used for anything else.

Two things worth knowing:

- **Quota**: Google gives every project 10,000 free "units" per day.
  Checking viewer counts (`videos.list`) costs **1 unit per call, and one
  call can check up to 50 videos at once** — this app batches every
  channel's videos into as few calls as possible, so reading is cheap no
  matter how many streams you're tracking (up to ~50 total). Finding
  *which* videos are currently live for a channel (`search.list`) is the
  expensive part at **100 units per channel, per lookup** — see "Quota
  cost of discovery" below for how to keep that under control.
- **`concurrentViewers` only exists while a video is actively live.** It
  won't work on a regular uploaded video, and it disappears once a stream
  ends.

## 2. Find your channel and video IDs

- **Channel ID**: open the channel's YouTube page → "About" tab → "Share
  channel" → "Copy channel ID". It looks like `UCxxxxxxxxxxxxxxxxxxxxxx`.
- **Video ID** (recommended if the channel has one persistent live stream):
  open the live stream and copy the `v=` value from the URL, e.g. for
  `https://www.youtube.com/watch?v=ABC123xyz` the video ID is `ABC123xyz`.

## 3. Configure the channels to track

A channel can have **more than one video live at the same time** (e.g. a
main feed plus several regional/bulletin feeds). Each poll tick sums the
concurrent viewers across *all* of a channel's live streams, so the number
you see is that channel's total live audience, not just one broadcast.

Edit `backend/config.json`:

```json
{
  "channels": [
    {
      "name": "RBANGLA",
      "color": "#E5384B",
      "channelId": "UC...",
      "videoIds": ["knownVideoId1", "knownVideoId2"],
      "autoDiscover": true
    },
    {
      "name": "ABPANANDA",
      "color": "#2F6FED",
      "channelId": "UC...",
      "videoIds": [],
      "autoDiscover": true
    }
  ]
}
```

Two ways a video ID gets tracked for a channel, and you can use either or
both together:

- **`videoIds`** — a fixed list you already know (e.g. persistent regional
  feeds). These are always checked, cost nothing extra in quota (checking
  videos is batched and billed as one call regardless of how many you pass,
  up to 50), and are never dropped even if that stream is temporarily
  offline — so they start being counted again automatically next time it
  goes live.
- **`autoDiscover: true`** (with `channelId` set) — periodically (every
  `LIVE_LOOKUP_REFRESH_MS`) searches for *every* video currently live on
  that channel and adds any new ones to the set being tracked. A stream
  found this way that stops returning viewer data is automatically dropped
  from the tracked set, until discovery finds it again.

This hybrid is the recommended setup if you know most of a channel's
streams but want new ones to be picked up without you manually maintaining
the list — set `videoIds` to whatever you're confident about, leave
`autoDiscover: true`, and let discovery fill in the gaps.

Other notes:
- Add as many channels as you like — the chart, stat chips, and table all
  adapt automatically.
- `color` is any CSS color and controls that channel's line, chip border,
  and table header color.
- The stat chips show "across N live streams" whenever a channel's total is
  made up of more than one simultaneous broadcast.

### Quota cost of discovery

Reading viewer counts is cheap no matter how many streams you track (see
next section), but *discovery* (`search.list`, finding which videos are
currently live) costs 100 units per channel, per refresh.

Discovery runs two ways, together:

1. **On a timer** - every `LIVE_LOOKUP_REFRESH_MS`, regardless of anything
   else. This is the baseline freshness guarantee.
2. **Reactively** - if a channel's live stream count drops between two
   ticks (a sign a stream ended, and maybe a new one started to replace it),
   discovery runs again on the very next tick instead of waiting for the
   timer. This is what actually keeps fast-rotating channels (frequent
   short segments, debate clips, etc.) accurate - without it, a channel can
   silently drift downward in stream count for up to the full timer
   interval before catching back up. `REACTIVE_REDISCOVER_COOLDOWN_MS`
   bounds how often this can fire per channel, so a channel that's
   constantly flapping can't force full-price discovery every single tick.

Tune both based on how many auto-discovering channels you have and how
"bursty" they are:

```
worst-case daily discovery units =
  channels_with_autoDiscover × 100 × (24 / min(refresh_hours, reactive_cooldown_hours))
```

| Channels (autoDiscover) | Refresh every | Reactive cooldown | Worst-case daily cost |
|---|---|---|---|
| 2 | 1 hour | 1 hour | 4,800 |
| 2 | 1 hour | 30 min | 9,600 |
| 6 | 3 hours | 3 hours | 4,800 |
| 6 | 3 hours | 1 hour | 14,400 (over the 10,000 free limit) |

In practice, actual cost is usually well below the worst case shown above -
the reactive trigger only fires when a real drop happens, not every tick -
but the table shows what to expect if a channel is genuinely volatile all
day. Pin as many known-stable streams as `videoIds` as you can; that
reduces how much you depend on discovery at all.

## 4. Set up PostgreSQL

The app stores every reading in PostgreSQL and creates its own table
automatically on first run - you just need a running Postgres server and an
empty database for it to connect to. No migration tool, no manual schema
setup.

**Option A - already have a Postgres server** (local install, a company
server, or a managed provider like Render/Supabase/RDS/Neon/Heroku):

Create a database for this app (name it whatever you like):

```bash
createdb yt_viewer_tracker
```

Then grab its connection string - it looks like:

```
postgres://user:password@host:5432/yt_viewer_tracker
```

**Option B - don't have Postgres yet, want the fastest local setup:**

```bash
docker run --name yt-viewer-postgres \
  -e POSTGRES_PASSWORD=devpassword \
  -e POSTGRES_DB=yt_viewer_tracker \
  -p 5432:5432 \
  -d postgres:16
```

That gives you `postgres://postgres:devpassword@localhost:5432/yt_viewer_tracker`.

Either way, put the connection string in `backend/.env` as `DATABASE_URL`
(see the next section). If your provider requires SSL (common on managed
hosts), also set `PGSSL=true`.

## 5. Run it locally

**Backend:**

```bash
cd backend
npm install
cp .env.example .env
# edit .env and paste your YOUTUBE_API_KEY
npm start
```

This starts the API on `http://localhost:4000`, connects to the PostgreSQL
database in `DATABASE_URL` and creates the `readings` table automatically
if it doesn't exist yet, then immediately does its first poll (then every
`POLL_INTERVAL_MS`, 3 minutes by default). If it can't reach PostgreSQL, it
logs a clear error and exits rather than silently failing later.

**Frontend** (in a second terminal):

```bash
cd frontend
npm install
npm run dev
```

Open the URL Vite prints (usually `http://localhost:5173`). It proxies
`/api/*` to the backend automatically in dev mode.

## 6. Deploy it

Build the frontend and let the backend serve it as static files, so you only
have one process to run in production:

```bash
cd frontend && npm run build
cd ../backend && npm start
```

The backend automatically serves `frontend/dist` if it exists, on the same
port as the API (`PORT` in `.env`, default 4000). Put it behind whatever
reverse proxy / process manager (nginx, pm2, systemd, Docker, etc.) you
normally use, and make sure the process stays running so polling doesn't
stop.

Point `DATABASE_URL` at your production Postgres instance (a managed
provider is usually easiest so you're not also responsible for backups).
The app never drops or alters existing data on startup - it only creates
the table if it's missing - so it's safe to point at a database that's
already running other things, as long as nothing else uses a table named
`readings`.

## Ad slots (side rails)

On wide screens (≥1500px viewport), two ad slots render in the blank space
on either side of the main content column - each shows one ad (image or
video) with a close button overlaid on its top-right corner. They're absent
below that width, so they never crowd real content on laptops, tablets, or
phones.

**Where the ad comes from:**

- If `ADS_API_URL` is set in `.env`, the backend fetches ads from that URL
  (sending `ADS_API_KEY` as a Bearer token, if set) and serves them through
  its own `/api/ads` endpoint - the frontend never calls the external API
  directly. Responses are cached for 5 minutes so repeated page loads don't
  hammer your ad API.
- If it's not set (or the external call fails for any reason), it falls
  back to the sample ad in `backend/ads.json` automatically - the feature
  always works, even with nothing configured.

**Response contract** your ad API (or `ads.json`) needs to match:

```json
{
  "ads": [
    {
      "id": "unique-id",
      "type": "image",
      "mediaUrl": "https://.../creative.jpg",
      "linkUrl": "https://advertiser.example.com",
      "altText": "Description for accessibility"
    }
  ]
}
```

`type` can be `"image"` or `"video"` - video ads autoplay muted and loop,
with a small "Learn more" link underneath instead of wrapping the whole
player in a clickable link (so it doesn't interfere with video controls).

If your ad network's API returns a different shape, adapt it in
`backend/ads.js` - there's a single clearly-marked function
(`fetchFromExternalApi`) where you map its response into the shape above.

**Note on Google AdSense specifically:** if that's what you actually meant
by "ad API," it works differently from what's built here - AdSense doesn't
give you a JSON endpoint to fetch and render yourself; instead you embed
Google's script tag and an `<ins class="adsbygoogle">` element, and Google's
script fills it in client-side. That's a simpler, different integration -
let me know if that's the direction you want instead and I'll swap this out.

**Dismissing an ad** is remembered for that browser tab's session (via
`sessionStorage`) - closing one won't show it again until the tab is closed
or a different ad rotates in, but it won't stay hidden forever across visits.



```
backend/
  youtube.js   -> resolveAllLiveVideoIds (search.list, finds every live video on
                  a channel) and fetchConcurrentViewersBatch (videos.list, up to
                  50 videos per call)
  poller.js    -> on a timer: refreshes stale channels' discovered video sets,
                  batches every tracked video into as few calls as possible,
                  sums viewers per channel, and prunes streams that ended
  db.js        -> PostgreSQL storage + queries via a connection pool (raw
                  range, hourly/daily bucketed averages, pivoting) - each
                  row is a channel's summed total plus how many streams
                  made up that sum. initDb() creates the table on first run.
  server.js    -> Express API: /api/channels, /api/live, /api/history, /api/ads
  ads.js       -> fetches ad creatives from ADS_API_URL if set, falls back to
                  ads.json, caches for 5 minutes
  config.json  -> which channels to track, and their pinned/auto-discovered videos
  ads.json     -> sample/fallback ad creative(s) used when no external ad
                  API is configured

frontend/
  src/api.js                    -> fetch wrappers for the backend API
  src/components/LiveView.jsx   -> auto-refreshing chart + table for "right now"
  src/components/HistoryView.jsx-> date-range picker + chart + table for any past window
  src/components/ChartPanel.jsx -> shared recharts line chart
  src/components/DataTable.jsx  -> shared reading log table
  src/components/StatChips.jsx  -> current value + tick-over-tick delta per channel
  src/components/AdSlot.jsx     -> side-rail ad unit (image or video), fetches
                                    /api/ads, hidden below 1500px viewport width
```

### API reference

- `GET /api/channels` → `[{ name, color }, ...]`
- `GET /api/live?hours=24` → readings from the last N hours, pivoted by
  timestamp: `{ channels, series: [{ timestamp, ChannelA, ChannelB }, ...] }`
- `GET /api/history?start=ISO&end=ISO&bucketMinutes=60` → same shape, for
  an arbitrary range. `bucketMinutes` is optional; omit it (or pass `0`) for
  raw ticks, or pass e.g. `60` / `1440` to average into hourly/daily buckets
  for large ranges.

## A note on this sandbox vs. your machine

I built and tested this entire stack in my sandbox, including installing a
real local PostgreSQL server and running the poller and API against it end
to end (schema creation, inserts, the hourly-bucket averaging query, and
all three API routes) - not just a syntax check. The one thing I still
couldn't test here is the live call to `googleapis.com` itself, since this
sandbox's network doesn't allow reaching it - that'll work fine once you
run it on your own machine or server with your API key and your own
Postgres connection string.
