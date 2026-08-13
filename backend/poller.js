import { resolveAllLiveVideoIds, fetchConcurrentViewersBatch } from './youtube.js';
import { insertTick } from './db.js';

// Per-channel cache of which video IDs to check each tick.
//   pinned:        video IDs from config.json's "videoIds" - never expire,
//                  always included, and never removed by pruning.
//   discovered:    video IDs found via search.list, refreshed either on the
//                  slow LIVE_LOOKUP_REFRESH_MS timer, OR reactively (see
//                  below) - pruned automatically once they stop being live.
//   discoveredAt:  when "discovered" was last refreshed. Also used as the
//                  cooldown clock for reactive rediscovery.
//   lastLiveCount: how many streams were live for this channel on the
//                  previous tick, used to detect a drop.
const channelCache = new Map();

function getCache(channelName) {
  if (!channelCache.has(channelName)) {
    channelCache.set(channelName, {
      pinned: new Set(),
      discovered: new Set(),
      discoveredAt: 0,
      lastLiveCount: null,
    });
  }
  return channelCache.get(channelName);
}

function initCaches(channels) {
  for (const channel of channels) {
    const cache = getCache(channel.name);
    for (const id of channel.videoIds ?? []) cache.pinned.add(id);
  }
}

function wantsDiscovery(channel) {
  return Boolean(channel.channelId) && channel.autoDiscover !== false;
}

async function refreshDiscoveryIfStale(channel, apiKey, refreshMs) {
  const cache = getCache(channel.name);
  if (!wantsDiscovery(channel)) return;

  const isStale = Date.now() - cache.discoveredAt > refreshMs;
  if (!isStale) return;

  try {
    const ids = await resolveAllLiveVideoIds(channel.channelId, apiKey);
    cache.discovered = new Set(ids);
    cache.discoveredAt = Date.now();
    console.log(
      `[poller] ${channel.name}: discovery found ${ids.length} live stream(s)`
    );
  } catch (err) {
    console.error(`[poller] ${channel.name} discovery failed:`, err.message);
    // Leave the previous discovered set in place rather than clearing it -
    // a transient failure shouldn't blank out a channel until next refresh.
  }
}

/**
 * If a channel's live-stream count just dropped (a stream likely ended),
 * that's also a reasonable signal a *new* one may have started that
 * discovery hasn't seen yet. Rather than wait up to LIVE_LOOKUP_REFRESH_MS
 * for the next scheduled discovery, mark this channel's cache as stale so
 * refreshDiscoveryIfStale() picks it up on the very next tick instead.
 *
 * Bounded by reactiveCooldownMs so a channel that's constantly flapping
 * can't force full-price (100 unit) discovery calls every single tick -
 * worst case, this fires at most once per cooldown window per channel.
 */
function maybeScheduleReactiveRediscovery(channel, cache, liveCount, reactiveCooldownMs) {
  if (!wantsDiscovery(channel)) return;
  if (cache.lastLiveCount === null) return; // first tick, nothing to compare yet
  if (liveCount >= cache.lastLiveCount) return; // no drop, nothing to do

  const sinceLastDiscovery = Date.now() - cache.discoveredAt;
  if (sinceLastDiscovery < reactiveCooldownMs) return; // cooldown still active

  console.log(
    `[poller] ${channel.name}: live count dropped (${cache.lastLiveCount} -> ${liveCount}), ` +
      `scheduling rediscovery next tick`
  );
  cache.discoveredAt = 0; // forces refreshDiscoveryIfStale() to fire next tick
}

export async function pollOnce(channels, apiKey, liveLookupRefreshMs, reactiveCooldownMs) {
  const tickTimestamp = new Date().toISOString();

  // 1. Refresh any channel whose discovered-live-videos cache is stale,
  //    either because the normal timer elapsed or because a reactive
  //    rediscovery was scheduled at the end of the previous tick.
  await Promise.all(
    channels.map((c) => refreshDiscoveryIfStale(c, apiKey, liveLookupRefreshMs))
  );

  // 2. Build one global list of every video ID across every channel, and
  //    fetch them all in as few batched calls as possible (1 unit per 50
  //    videos, total - not per channel).
  const idToChannel = new Map(); // videoId -> channelName (first owner wins)
  for (const channel of channels) {
    const cache = getCache(channel.name);
    for (const id of new Set([...cache.pinned, ...cache.discovered])) {
      if (!idToChannel.has(id)) idToChannel.set(id, channel.name);
    }
  }
  const allVideoIds = [...idToChannel.keys()];

  let viewersById;
  try {
    viewersById = await fetchConcurrentViewersBatch(allVideoIds, apiKey);
  } catch (err) {
    console.error('[poller] batched viewers fetch failed:', err.message);
    return;
  }

  // 3. Sum viewers per channel, count how many of its streams are live,
  //    prune discovered (non-pinned) IDs that came back not-live, and
  //    check whether a drop should trigger reactive rediscovery.
  const viewersByChannel = {};
  const streamCountByChannel = {};

  for (const channel of channels) {
    const cache = getCache(channel.name);
    let total = 0;
    let liveCount = 0;

    for (const id of cache.discovered) {
      if (viewersById.has(id)) {
        total += viewersById.get(id);
        liveCount += 1;
      } else {
        cache.discovered.delete(id); // stream ended - drop it until rediscovered
      }
    }
    for (const id of cache.pinned) {
      if (viewersById.has(id)) {
        total += viewersById.get(id);
        liveCount += 1;
      }
      // Pinned IDs are kept even when not currently live, so they're
      // picked up again automatically next time that stream goes live.
    }

    maybeScheduleReactiveRediscovery(channel, cache, liveCount, reactiveCooldownMs);
    cache.lastLiveCount = liveCount;

    if (liveCount > 0) {
      viewersByChannel[channel.name] = total;
      streamCountByChannel[channel.name] = liveCount;
    } else {
      console.warn(`[poller] ${channel.name}: no live streams found this tick`);
    }
  }

  if (Object.keys(viewersByChannel).length > 0) {
    try {
      await insertTick(tickTimestamp, viewersByChannel, streamCountByChannel);
      console.log(
        `[poller] ${tickTimestamp} -> ${JSON.stringify(viewersByChannel)} ` +
          `(streams: ${JSON.stringify(streamCountByChannel)})`
      );
    } catch (err) {
      console.error('[poller] failed to write tick to the database:', err.message);
    }
  }
}

export function startPolling({
  channels,
  apiKey,
  pollIntervalMs,
  liveLookupRefreshMs,
  reactiveCooldownMs,
}) {
  initCaches(channels);
  // Run immediately on startup, then on the configured interval.
  pollOnce(channels, apiKey, liveLookupRefreshMs, reactiveCooldownMs);
  return setInterval(
    () => pollOnce(channels, apiKey, liveLookupRefreshMs, reactiveCooldownMs),
    pollIntervalMs
  );
}
