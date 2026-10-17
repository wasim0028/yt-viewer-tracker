import test from 'node:test';
import assert from 'node:assert/strict';
import { pivot } from '../db.js';

// pivot() turns one-row-per-channel readings into one-row-per-timestamp
// objects, which is the shape the chart and table consume.

test('groups rows that share a timestamp into one object', () => {
  const out = pivot([
    { channel_name: 'A', timestamp: '2026-01-01T00:00:00.000Z', viewers: 10, stream_count: null },
    { channel_name: 'B', timestamp: '2026-01-01T00:00:00.000Z', viewers: 20, stream_count: null },
  ]);
  assert.deepEqual(out, [{ timestamp: '2026-01-01T00:00:00.000Z', A: 10, B: 20 }]);
});

test('adds a <channel>__streams key only when stream_count is present', () => {
  const out = pivot([
    { channel_name: 'A', timestamp: '2026-01-01T00:00:00.000Z', viewers: 10, stream_count: 3 },
    { channel_name: 'B', timestamp: '2026-01-01T00:00:00.000Z', viewers: 20, stream_count: null },
  ]);
  assert.equal(out[0].A__streams, 3);
  assert.ok(!('B__streams' in out[0]));
});

test('sorts output by timestamp ascending', () => {
  const out = pivot([
    { channel_name: 'A', timestamp: '2026-01-01T02:00:00.000Z', viewers: 3, stream_count: null },
    { channel_name: 'A', timestamp: '2026-01-01T01:00:00.000Z', viewers: 1, stream_count: null },
  ]);
  assert.deepEqual(out.map((r) => r.A), [1, 3]);
});

test('converts Date timestamps (as returned by pg) to ISO strings', () => {
  const out = pivot([
    { channel_name: 'A', timestamp: new Date('2026-01-01T00:00:00Z'), viewers: 5, stream_count: null },
  ]);
  assert.equal(out[0].timestamp, '2026-01-01T00:00:00.000Z');
});

test('returns an empty array for no rows', () => {
  assert.deepEqual(pivot([]), []);
});
