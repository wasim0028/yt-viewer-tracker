import { useTheme } from '../ThemeContext.jsx';

export default function Navbar({ tab, onTabChange }) {
  const { theme, toggleTheme } = useTheme();

  return (
    <header className="navbar">
      <div className="navbar-brand">
        <span className="navbar-mark" aria-hidden="true" />
        <span className="navbar-word">Viewer Watch</span>
      </div>

      <nav className="navbar-tabs" aria-label="View">
        <button
          className={tab === 'live' ? 'active' : ''}
          onClick={() => onTabChange('live')}
        >
          Live chart
        </button>
        <button
          className={tab === 'history' ? 'active' : ''}
          onClick={() => onTabChange('history')}
        >
          History
        </button>
      </nav>

      <div className="navbar-actions">
        {tab === 'live' && (
          <span className="live-indicator">
            <span className="live-dot" />
            Live
          </span>
        )}
        <button
          className="theme-toggle"
          onClick={toggleTheme}
          aria-label={
            theme === 'light' ? 'Switch to dark mode' : 'Switch to light mode'
          }
          title={theme === 'light' ? 'Switch to dark mode' : 'Switch to light mode'}
        >
          <span className={`theme-toggle-track ${theme}`}>
            <span className="theme-toggle-thumb">
              {theme === 'light' ? (
                <svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" strokeWidth="2">
                  <circle cx="12" cy="12" r="4" />
                  <path d="M12 2v2M12 20v2M4.9 4.9l1.4 1.4M17.7 17.7l1.4 1.4M2 12h2M20 12h2M4.9 19.1l1.4-1.4M17.7 6.3l1.4-1.4" />
                </svg>
              ) : (
                <svg viewBox="0 0 24 24" width="12" height="12" fill="none" stroke="currentColor" strokeWidth="2">
                  <path d="M21 12.8A9 9 0 1 1 11.2 3a7 7 0 0 0 9.8 9.8Z" />
                </svg>
              )}
            </span>
          </span>
        </button>
      </div>
    </header>
  );
}
