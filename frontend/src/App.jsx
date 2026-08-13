import { useState } from 'react';
import Navbar from './components/Navbar.jsx';
import LiveView from './components/LiveView.jsx';
import HistoryView from './components/HistoryView.jsx';
import AdSlot from './components/AdSlot.jsx';

export default function App() {
  const [tab, setTab] = useState('live');

  return (
    <div className="app-shell">
      <Navbar tab={tab} onTabChange={setTab} />
      <AdSlot side="left" />
      <AdSlot side="right" />
      <main className="app-content">
        {tab === 'live' ? <LiveView /> : <HistoryView />}
      </main>
    </div>
  );
}
