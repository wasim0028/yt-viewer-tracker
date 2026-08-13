export default function StatChips({ channels, series }) {
  if (series.length === 0) return null;
  const latest = series[series.length - 1];
  const previous = series.length > 1 ? series[series.length - 2] : null;

  return (
    <div className="stat-row">
      {channels.map((c) => {
        const value = latest[c.name];
        const prevValue = previous ? previous[c.name] : null;
        const delta =
          value != null && prevValue != null ? value - prevValue : null;
        const streamCount = latest[`${c.name}__streams`];

        return (
          <div key={c.name} className="stat-chip">
            <div className="stat-chip-name">
              <span
                className="stat-chip-dot"
                style={{ '--dot-color': c.color }}
              />
              {c.name}
            </div>
            <div className="stat-chip-value-row">
              <span className="stat-chip-value">
                {value != null ? value.toLocaleString() : '—'}
              </span>
              {delta != null && delta !== 0 && (
                <span
                  className={`stat-chip-delta ${delta > 0 ? 'up' : 'down'}`}
                >
                  {delta > 0 ? '▲' : '▼'} {Math.abs(delta).toLocaleString()}
                </span>
              )}
            </div>
            {streamCount > 1 && (
              <div className="stat-chip-streams">
                across {streamCount} live streams
              </div>
            )}
          </div>
        );
      })}
    </div>
  );
}
