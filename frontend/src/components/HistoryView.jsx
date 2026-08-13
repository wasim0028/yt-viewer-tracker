import { useState } from 'react';
import { getChannels, getHistory } from '../api.js';
import ChartPanel from './ChartPanel.jsx';
import DataTable from './DataTable.jsx';

function toLocalInputValue(date) {
  const pad = (n) => String(n).padStart(2, '0');
  return `${date.getFullYear()}-${pad(date.getMonth() + 1)}-${pad(
    date.getDate()
  )}T${pad(date.getHours())}:${pad(date.getMinutes())}`;
}

function defaultStart() {
  const d = new Date();
  d.setDate(d.getDate() - 1);
  return toLocalInputValue(d);
}

function defaultEnd() {
  return toLocalInputValue(new Date());
}

export default function HistoryView() {
  const [start, setStart] = useState(defaultStart());
  const [end, setEnd] = useState(defaultEnd());
  const [bucket, setBucket] = useState('0');
  const [channels, setChannels] = useState([]);
  const [series, setSeries] = useState([]);
  const [status, setStatus] = useState('idle'); // idle | loading | loaded | error
  const [error, setError] = useState(null);

  async function handleLoad() {
    setStatus('loading');
    try {
      const chans = await getChannels();
      const data = await getHistory(
        new Date(start).toISOString(),
        new Date(end).toISOString(),
        Number(bucket)
      );
      setChannels(chans);
      setSeries(data.series);
      setStatus('loaded');
    } catch (err) {
      setError(err.message);
      setStatus('error');
    }
  }

  return (
    <div className="panel">
      <div className="panel-header">
        <div className="panel-title">History</div>
        <div className="panel-subtitle">Query any past date range</div>
      </div>

      <div className="history-controls">
        <div className="history-field">
          <label>Start</label>
          <input
            type="datetime-local"
            value={start}
            onChange={(e) => setStart(e.target.value)}
          />
        </div>
        <div className="history-field">
          <label>End</label>
          <input
            type="datetime-local"
            value={end}
            onChange={(e) => setEnd(e.target.value)}
          />
        </div>
        <div className="history-field">
          <label>Resolution</label>
          <select value={bucket} onChange={(e) => setBucket(e.target.value)}>
            <option value="0">Raw ticks</option>
            <option value="60">Hourly average</option>
            <option value="1440">Daily average</option>
          </select>
        </div>
        <button className="history-load-btn" onClick={handleLoad}>
          Load
        </button>
      </div>

      {status === 'idle' && (
        <div className="state-note">Pick a range and press Load.</div>
      )}
      {status === 'loading' && <div className="state-note">Loading…</div>}
      {status === 'error' && (
        <div className="state-note error">{error}</div>
      )}
      {status === 'loaded' && (
        <>
          <ChartPanel channels={channels} series={series} />
          <div style={{ height: 18 }} />
          <DataTable channels={channels} series={series} />
        </>
      )}
    </div>
  );
}
