import test from 'node:test';
import assert from 'node:assert/strict';
import { fetchConcurrentViewersBatch, resolveAllLiveVideoIds } from '../youtube.js';

// Replace the global fetch so no test ever touches the real YouTube API
// (which would cost quota and make the test depend on the network).
const realFetch = globalThis.fetch;
test.afterEach(() => {
  globalThis.fetch = realFetch;
});

function mockFetch(handler) {
  const calls = [];
  globalThis.fetch = async (url) => {
    calls.push(String(url));
    return handler(String(url), calls.length);
  };
  return calls;
}

const ok = (body) => ({ ok: true, status: 200, json: async () => body, text: async () => JSON.stringify(body) });
const fail = (status, text = 'boom') => ({ ok: false, status, json: async () => ({}), text: async () => text });

test('fetchConcurrentViewersBatch: empty input makes no request', async () => {
  const calls = mockFetch(() => ok({}));
  const result = await fetchConcurrentViewersBatch([], 'key');
  assert.equal(result.size, 0);
  assert.equal(calls.length, 0);
});

test('fetchConcurrentViewersBatch: parses viewers and omits videos that are not live', async () => {
  mockFetch(() =>
    ok({
      items: [
        { id: 'live1', liveStreamingDetails: { concurrentViewers: '1234' } },
        { id: 'ended1', liveStreamingDetails: {} }, // no concurrentViewers => not live
      ],
    })
  );
  const result = await fetchConcurrentViewersBatch(['live1', 'ended1'], 'key');
  assert.equal(result.get('live1'), 1234);
  assert.ok(!result.has('ended1'));
});

test('fetchConcurrentViewersBatch: splits more than 50 ids into batches', async () => {
  const ids = Array.from({ length: 120 }, (_, i) => `v${i}`);
  const calls = mockFetch(() => ok({ items: [] }));
  await fetchConcurrentViewersBatch(ids, 'key');
  assert.equal(calls.length, 3); // 50 + 50 + 20
});

test('fetchConcurrentViewersBatch: throws a readable error on API failure', async () => {
  mockFetch(() => fail(403, 'quotaExceeded'));
  await assert.rejects(() => fetchConcurrentViewersBatch(['a'], 'key'), /YouTube videos API error \(403\)/);
});

test('resolveAllLiveVideoIds: returns only video ids and skips items without one', async () => {
  mockFetch(() => ok({ items: [{ id: { videoId: 'a' } }, { id: {} }, { id: { videoId: 'b' } }] }));
  assert.deepEqual(await resolveAllLiveVideoIds('UC123', 'key'), ['a', 'b']);
});

test('resolveAllLiveVideoIds: URL-encodes the channel id', async () => {
  const calls = mockFetch(() => ok({ items: [] }));
  await resolveAllLiveVideoIds('UC 1&2', 'key');
  assert.match(calls[0], /channelId=UC%201%262/);
});

test('resolveAllLiveVideoIds: throws on API failure', async () => {
  mockFetch(() => fail(500));
  await assert.rejects(() => resolveAllLiveVideoIds('UC1', 'key'), /YouTube search API error \(500\)/);
});
