import { useCallback, useEffect, useState } from 'react';
import { getChannels, getLive } from '../api.js';
import StatChips from './StatChips.jsx';
import ChartPanel from './ChartPanel.jsx';
import DataTable from './DataTable.jsx';

const WINDOWS = [
  { label: '1H', hours: 1 },
  { label: '6H', hours: 6 },
  { label: '24H', hours: 24 },
  { label: '3D', hours: 72 },
];

const REFRESH_MS = 30000;

export default function LiveView() {
  const [channels, setChannels] = useState([]);
  const [series, setSeries] = useState([]);
  const [hours, setHours] = useState(24);
  const [error, setError] = useState(null);
  const [loading, setLoading] = useState(true);

  const load = useCallback(async () => {
    try {
      const [chans, live] = await Promise.all([getChannels(), getLive(hours)]);
      setChannels(chans);
      setSeries(live.series);
      setError(null);
    } catch (err) {
      setError(err.message);
    } finally {
      setLoading(false);
    }
  }, [hours]);

  useEffect(() => {
    load();
    const id = setInterval(load, REFRESH_MS);
    return () => clearInterval(id);
  }, [load]);

  return (
    <>
      <StatChips channels={channels} series={series} />

      <div className="panel">
        <div className="panel-header">
          <div>
            <div className="panel-title">Viewer comparison</div>
            <div className="panel-subtitle">
              Concurrent viewers · refreshed every 30s
            </div>
          </div>
          <div className="tab-toggle">
            {WINDOWS.map((w) => (
              <button
                key={w.hours}
                className={hours === w.hours ? 'active' : ''}
                onClick={() => setHours(w.hours)}
              >
                {w.label}
              </button>
            ))}
          </div>
        </div>
        {loading ? (
          <div className="state-note">Loading…</div>
        ) : error ? (
          <div className="state-note error">{error}</div>
        ) : (
          <ChartPanel channels={channels} series={series} />
        )}
      </div>

      <div className="panel">
        <div className="panel-header">
          <div className="panel-title">Reading log</div>
          <div className="panel-subtitle">{series.length} ticks in window</div>
        </div>
        {!loading && !error && (
          <DataTable channels={channels} series={series} />
        )}
      </div>
    </>
  );
}
