import pg from 'pg';

const { Pool } = pg;

// Prefer a full connection string (DATABASE_URL) if given - that's what
// every managed Postgres provider (Heroku, Render, Supabase, RDS, Neon...)
// hands you. If it's not set, pg automatically falls back to reading
// PGHOST / PGUSER / PGPASSWORD / PGDATABASE / PGPORT from the environment
// on its own, so this still works with plain env vars instead.
const pool = new Pool(
  process.env.DATABASE_URL
    ? {
        connectionString: process.env.DATABASE_URL,
        ssl:
          process.env.PGSSL === 'true'
            ? { rejectUnauthorized: false }
            : undefined,
      }
    : undefined
);

pool.on('error', (err) => {
  // Fires on idle-client errors (e.g. the DB restarting) - log, don't crash.
  console.error('[db] unexpected PostgreSQL pool error:', err.message);
});

let initialized = false;

/**
 * Creates the readings table and indexes if they don't already exist.
 * Await this once at startup before serving requests or polling.
 */
export async function initDb() {
  if (initialized) return;
  await pool.query(`
    CREATE TABLE IF NOT EXISTS readings (
      id BIGSERIAL PRIMARY KEY,
      channel_name TEXT NOT NULL,
      timestamp TIMESTAMPTZ NOT NULL,
      viewers INTEGER NOT NULL,
      stream_count INTEGER
    );
  `);
  await pool.query(
    `CREATE INDEX IF NOT EXISTS idx_readings_timestamp ON readings(timestamp);`
  );
  await pool.query(
    `CREATE INDEX IF NOT EXISTS idx_readings_channel ON readings(channel_name);`
  );
  initialized = true;
  console.log('[db] connected to PostgreSQL, schema ready');
}

/**
 * Insert one reading for one channel at a given tick timestamp.
 */
export async function insertReading(
  channelName,
  timestampIso,
  viewers,
  streamCount = null
) {
  await pool.query(
    'INSERT INTO readings (channel_name, timestamp, viewers, stream_count) VALUES ($1, $2, $3, $4)',
    [channelName, timestampIso, viewers, streamCount]
  );
}

/**
 * Insert readings for every channel captured in a single poll tick, so they
 * share one timestamp and line up cleanly in the pivoted table/chart.
 * All rows for a tick are inserted in one transaction.
 */
export async function insertTick(
  timestampIso,
  viewersByChannel,
  streamCountByChannel = {}
) {
  const entries = Object.entries(viewersByChannel).filter(
    ([, v]) => v !== null && v !== undefined
  );
  if (entries.length === 0) return;

  const client = await pool.connect();
  try {
    await client.query('BEGIN');
    for (const [channelName, viewers] of entries) {
      await client.query(
        'INSERT INTO readings (channel_name, timestamp, viewers, stream_count) VALUES ($1, $2, $3, $4)',
        [channelName, timestampIso, viewers, streamCountByChannel[channelName] ?? null]
      );
    }
    await client.query('COMMIT');
  } catch (err) {
    await client.query('ROLLBACK');
    throw err;
  } finally {
    client.release();
  }
}

/**
 * Raw rows at or after `sinceIso`, oldest first.
 */
export async function getSince(sinceIso) {
  const { rows } = await pool.query(
    'SELECT channel_name, timestamp, viewers, stream_count FROM readings WHERE timestamp >= $1 ORDER BY timestamp ASC',
    [sinceIso]
  );
  return rows;
}

/**
 * Raw rows between two ISO timestamps (inclusive), oldest first.
 */
export async function getRange(startIso, endIso) {
  const { rows } = await pool.query(
    'SELECT channel_name, timestamp, viewers, stream_count FROM readings WHERE timestamp >= $1 AND timestamp <= $2 ORDER BY timestamp ASC',
    [startIso, endIso]
  );
  return rows;
}

/**
 * Same as getRange, but averages viewers (and stream_count) into fixed-size
 * time buckets (in minutes) so long date ranges don't return tens of
 * thousands of points. Uses floor-division on the epoch so any bucket size
 * works, not just Postgres's built-in date_trunc units.
 */
export async function getRangeBucketed(startIso, endIso, bucketMinutes) {
  const bucketSeconds = bucketMinutes * 60;
  const { rows } = await pool.query(
    `SELECT channel_name,
            to_timestamp(floor(extract(epoch FROM timestamp) / $3::double precision) * $3::double precision) AS bucket,
            AVG(viewers) AS viewers,
            AVG(stream_count) AS stream_count
     FROM readings
     WHERE timestamp >= $1 AND timestamp <= $2
     GROUP BY channel_name, bucket
     ORDER BY bucket ASC`,
    [startIso, endIso, bucketSeconds]
  );
  return rows.map((r) => ({
    channel_name: r.channel_name,
    timestamp: r.bucket,
    // AVG() on integer columns returns Postgres NUMERIC, which node-postgres
    // hands back as a string (to avoid float precision loss) - convert before rounding.
    viewers: Math.round(Number(r.viewers)),
    stream_count: r.stream_count != null ? Math.round(Number(r.stream_count)) : null,
  }));
}

/**
 * Pivot raw {channel_name, timestamp, viewers, stream_count} rows into
 * [{ timestamp, [channelA]: n, [channelA__streams]: n, ... }, ...] ordered
 * by timestamp ascending, which is what both the chart and table want.
 * `timestamp` comes back from Postgres as a JS Date - normalized to an ISO
 * string here so the API response shape matches what the frontend expects.
 */
export function pivot(rows) {
  const byTimestamp = new Map();
  for (const row of rows) {
    const tsKey =
      row.timestamp instanceof Date ? row.timestamp.toISOString() : row.timestamp;
    if (!byTimestamp.has(tsKey)) {
      byTimestamp.set(tsKey, { timestamp: tsKey });
    }
    const entry = byTimestamp.get(tsKey);
    entry[row.channel_name] = row.viewers;
    if (row.stream_count != null) {
      entry[`${row.channel_name}__streams`] = row.stream_count;
    }
  }
  return Array.from(byTimestamp.values()).sort((a, b) =>
    a.timestamp < b.timestamp ? -1 : a.timestamp > b.timestamp ? 1 : 0
  );
}

export default pool;
