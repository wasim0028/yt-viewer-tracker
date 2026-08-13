const BASE = '/api';

async function getJson(url) {
  const res = await fetch(url);
  if (!res.ok) {
    throw new Error(`Request failed (${res.status}): ${await res.text()}`);
  }
  return res.json();
}

export function getChannels() {
  return getJson(`${BASE}/channels`);
}

export function getLive(hours = 24) {
  return getJson(`${BASE}/live?hours=${hours}`);
}

export function getHistory(startIso, endIso, bucketMinutes = 0) {
  const params = new URLSearchParams({
    start: startIso,
    end: endIso,
    bucketMinutes: String(bucketMinutes),
  });
  return getJson(`${BASE}/history?${params.toString()}`);
}
