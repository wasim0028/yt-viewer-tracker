import { useEffect, useRef, useState } from 'react';

function formatTime(iso) {
  const d = new Date(iso);
  return d.toLocaleTimeString([], { hour12: false });
}

export default function DataTable({ channels, series }) {
  const rows = [...series].reverse(); // newest first, like the original tool
  const lastSeenTimestamp = useRef(null);
  const [flashTimestamp, setFlashTimestamp] = useState(null);

  const newestTimestamp = rows.length ? rows[0].timestamp : null;

  useEffect(() => {
    if (!newestTimestamp) return;
    if (
      lastSeenTimestamp.current &&
      newestTimestamp !== lastSeenTimestamp.current
    ) {
      setFlashTimestamp(newestTimestamp);
      const t = setTimeout(() => setFlashTimestamp(null), 1600);
      lastSeenTimestamp.current = newestTimestamp;
      return () => clearTimeout(t);
    }
    lastSeenTimestamp.current = newestTimestamp;
  }, [newestTimestamp]);

  if (rows.length === 0) {
    return <div className="state-note">No readings yet for this window.</div>;
  }

  return (
    <div className="table-scroll">
      <table className="reading-table">
        <thead>
          <tr>
            <th>Time</th>
            {channels.map((c) => (
              <th
                key={c.name}
                className="channel-head"
                style={{ '--head-color': c.color, color: c.color }}
              >
                {c.name}
              </th>
            ))}
          </tr>
        </thead>
        <tbody>
          {rows.map((row) => (
            <tr
              key={row.timestamp}
              className={row.timestamp === flashTimestamp ? 'row-new' : ''}
            >
              <td>{formatTime(row.timestamp)}</td>
              {channels.map((c) => (
                <td key={c.name}>
                  {row[c.name] != null ? row[c.name].toLocaleString() : '—'}
                </td>
              ))}
            </tr>
          ))}
        </tbody>
      </table>
    </div>
  );
}
