import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const localAdsPath = path.join(__dirname, 'ads.json');

// Response contract this app expects, whether the ads come from your own
// backend/ads.json or an external ad API:
//   { "ads": [ { "id": string, "type": "image" | "video", "mediaUrl": string,
//                "linkUrl": string, "altText": string } ] }
// If a real ad network's API returns a different shape, transform its
// response into this shape inside fetchFromExternalApi() below - that's the
// one place a network-specific adapter belongs.

let cache = { ads: null, fetchedAt: 0 };
const CACHE_TTL_MS = 5 * 60 * 1000; // 5 minutes - avoid hammering the ad API on every page load

function loadLocalAds() {
  try {
    const raw = fs.readFileSync(localAdsPath, 'utf-8');
    return JSON.parse(raw).ads ?? [];
  } catch (err) {
    console.error('[ads] failed to read local ads.json:', err.message);
    return [];
  }
}

async function fetchFromExternalApi(apiUrl, apiKey) {
  const res = await fetch(apiUrl, {
    headers: apiKey ? { Authorization: `Bearer ${apiKey}` } : {},
  });
  if (!res.ok) {
    throw new Error(`ad API returned ${res.status}`);
  }
  const data = await res.json();
  // If your ad network's response doesn't already match the {ads: [...]}
  // contract above, map it here, e.g.:
  //   return data.creatives.map(c => ({ id: c.creativeId, type: c.format, ... }));
  return data.ads ?? [];
}

/**
 * Returns the current list of ads to show, preferring a configured external
 * ad API (ADS_API_URL) and falling back to the local ads.json if it's not
 * set, or if the external call fails. Cached for CACHE_TTL_MS so repeated
 * ad slot requests don't all hit the network.
 */
export async function getAds({ adsApiUrl, adsApiKey } = {}) {
  const isFresh = Date.now() - cache.fetchedAt < CACHE_TTL_MS;
  if (isFresh && cache.ads) return cache.ads;

  let ads;
  if (adsApiUrl) {
    try {
      ads = await fetchFromExternalApi(adsApiUrl, adsApiKey);
    } catch (err) {
      console.error('[ads] external ad API failed, falling back to local ads.json:', err.message);
      ads = loadLocalAds();
    }
  } else {
    ads = loadLocalAds();
  }

  cache = { ads, fetchedAt: Date.now() };
  return ads;
}
