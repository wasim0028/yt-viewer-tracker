import test from 'node:test';
import assert from 'node:assert/strict';
import { getAds } from '../ads.js';

// Each test file runs in its own process, so ads.js's in-memory cache starts
// empty here. The tests below therefore run in order and share that cache.

const realFetch = globalThis.fetch;
test.after(() => {
  globalThis.fetch = realFetch;
});

test('falls back to the local ads.json when the external ad API fails', async () => {
  globalThis.fetch = async () => ({ ok: false, status: 503, json: async () => ({}) });
  const ads = await getAds({ adsApiUrl: 'http://ads.invalid/api', adsApiKey: 'k' });
  assert.ok(Array.isArray(ads));
  for (const ad of ads) {
    // Contract documented in ads.js
    assert.ok(ad.id && ad.mediaUrl, 'each ad needs an id and a mediaUrl');
    assert.ok(['image', 'video'].includes(ad.type), `unexpected ad type: ${ad.type}`);
  }
});

test('serves the second call from the cache without calling the network', async () => {
  let called = false;
  globalThis.fetch = async () => {
    called = true;
    throw new Error('should not be called');
  };
  const ads = await getAds({ adsApiUrl: 'http://ads.invalid/api' });
  assert.ok(Array.isArray(ads));
  assert.equal(called, false);
});
