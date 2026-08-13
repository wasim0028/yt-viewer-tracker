import { useEffect, useState } from 'react';
import { fetchAdsOnce } from '../adsCache.js';

const DISMISSED_KEY = 'viewer-watch-dismissed-ads';
const ROTATE_MS = 15000;
// Ad slots only make sense once the viewport is wide enough to have real
// blank gutter beyond the app's centered ~1180px content column - this
// threshold comfortably excludes phones and tablets (including landscape),
// so ads are web/desktop-only by construction, not just by convention.
const MIN_WIDTH_FOR_ADS = 1700;

function getDismissedIds() {
  try {
    return new Set(JSON.parse(sessionStorage.getItem(DISMISSED_KEY) ?? '[]'));
  } catch {
    return new Set();
  }
}

function dismissAd(id) {
  const ids = getDismissedIds();
  ids.add(id);
  sessionStorage.setItem(DISMISSED_KEY, JSON.stringify([...ids]));
}

function useIsWideEnoughForAds() {
  const [isWide, setIsWide] = useState(
    typeof window !== 'undefined' && window.innerWidth >= MIN_WIDTH_FOR_ADS
  );
  useEffect(() => {
    const onResize = () => setIsWide(window.innerWidth >= MIN_WIDTH_FOR_ADS);
    window.addEventListener('resize', onResize);
    return () => window.removeEventListener('resize', onResize);
  }, []);
  return isWide;
}

export default function AdSlot({ side }) {
  const isWide = useIsWideEnoughForAds();
  const [pool, setPool] = useState([]);
  // Start the two slots on different ads (when there's more than one) so
  // they don't show the same creative at the same time.
  const [index, setIndex] = useState(side === 'right' ? 1 : 0);
  const [, forceRefilter] = useState(0);

  useEffect(() => {
    if (!isWide) return;
    let cancelled = false;
    fetchAdsOnce().then((ads) => {
      if (!cancelled) setPool(ads);
    });
    return () => {
      cancelled = true;
    };
  }, [isWide]);

  const visiblePool = pool.filter((ad) => !getDismissedIds().has(ad.id));

  // Auto-rotate through every ad in the pool, not just the first one or two -
  // with 11 real client creatives, this is what actually shows all of them
  // over time instead of only ever displaying the first couple.
  useEffect(() => {
    if (visiblePool.length <= 1) return;
    const id = setInterval(() => {
      setIndex((i) => (i + 1) % visiblePool.length);
    }, ROTATE_MS);
    return () => clearInterval(id);
  }, [visiblePool.length]);

  if (!isWide || visiblePool.length === 0) return null;
  const ad = visiblePool[index % visiblePool.length];
  if (!ad) return null;

  const handleClose = () => {
    dismissAd(ad.id);
    forceRefilter((t) => t + 1); // re-run the sessionStorage filter above
  };

  const media =
    ad.type === 'video' ? (
      <video className="ad-slot-media" src={ad.mediaUrl} muted autoPlay loop playsInline />
    ) : (
      <img className="ad-slot-media" src={ad.mediaUrl} alt={ad.altText ?? 'Advertisement'} />
    );

  return (
    <aside className={`ad-slot ad-slot-${side}`} aria-label="Advertisement">
      <span className="ad-slot-label">Advertisement</span>
      <button
        className="ad-slot-close"
        onClick={handleClose}
        aria-label="Close advertisement"
        title="Close"
      >
        ×
      </button>

      {ad.linkUrl ? (
        <a href={ad.linkUrl} target="_blank" rel="noopener noreferrer sponsored">
          {media}
        </a>
      ) : (
        media
      )}

      {ad.type === 'video' && ad.linkUrl && (
        <a
          className="ad-slot-link"
          href={ad.linkUrl}
          target="_blank"
          rel="noopener noreferrer sponsored"
        >
          Learn more →
        </a>
      )}
    </aside>
  );
}
