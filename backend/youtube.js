const API_BASE = 'https://www.googleapis.com/youtube/v3';

// videos.list accepts up to 50 ids in one call, for a flat 1 unit total -
// batching is what keeps this cheap even at dozens of simultaneous streams.
const VIDEOS_BATCH_SIZE = 50;

function chunk(arr, size) {
  const out = [];
  for (let i = 0; i < arr.length; i += size) out.push(arr.slice(i, i + size));
  return out;
}

/**
 * Find every video currently live on a channel (not just one).
 * Costs 100 quota units per call, regardless of how many results come back,
 * so this should only run on a slow discovery interval, not every tick.
 * Returns up to 50 video IDs (one search.list page). A channel running more
 * than 50 simultaneous live streams would need pagination (another 100
 * units per extra page) - uncommon, so left out by default.
 */
export async function resolveAllLiveVideoIds(channelId, apiKey) {
  const url =
    `${API_BASE}/search?part=snippet&channelId=${encodeURIComponent(channelId)}` +
    `&eventType=live&type=video&maxResults=50&key=${apiKey}`;

  const res = await fetch(url);
  if (!res.ok) {
    const body = await res.text();
    throw new Error(`YouTube search API error (${res.status}): ${body}`);
  }
  const data = await res.json();
  return (data.items ?? [])
    .map((item) => item.id?.videoId)
    .filter(Boolean);
}

/**
 * Get current concurrent viewers for up to 50 videos in ONE call (1 unit
 * total, not 1 unit per video). Automatically chunks larger lists into
 * multiple 50-video batches. Returns a Map of videoId -> viewers, only
 * including videos that are actually live right now (ended/never-live
 * videos are simply absent from the result, not returned as 0).
 */
export async function fetchConcurrentViewersBatch(videoIds, apiKey) {
  const results = new Map();
  if (videoIds.length === 0) return results;

  for (const batch of chunk(videoIds, VIDEOS_BATCH_SIZE)) {
    const url =
      `${API_BASE}/videos?part=liveStreamingDetails&id=${encodeURIComponent(batch.join(','))}` +
      `&key=${apiKey}`;

    const res = await fetch(url);
    if (!res.ok) {
      const body = await res.text();
      throw new Error(`YouTube videos API error (${res.status}): ${body}`);
    }
    const data = await res.json();
    for (const item of data.items ?? []) {
      const viewers = item.liveStreamingDetails?.concurrentViewers;
      if (viewers !== undefined) {
        results.set(item.id, parseInt(viewers, 10));
      }
    }
  }
  return results;
}
