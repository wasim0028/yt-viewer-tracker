// Both AdSlot instances (left/right) want the same ad list - share one
// in-flight/completed fetch instead of each firing its own request.
let adsPromise = null;

export function fetchAdsOnce() {
  if (!adsPromise) {
    adsPromise = fetch('/api/ads')
      .then((res) => res.json())
      .then((data) => data.ads ?? [])
      .catch((err) => {
        console.error('[ads] failed to load:', err.message);
        adsPromise = null; // allow a retry on the next call rather than caching a failure forever
        return [];
      });
  }
  return adsPromise;
}
