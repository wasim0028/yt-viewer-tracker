import { useEffect, useState } from 'react';
import {
  LineChart,
  Line,
  XAxis,
  YAxis,
  CartesianGrid,
  Tooltip,
  Legend,
  ResponsiveContainer,
} from 'recharts';
import { useTheme } from '../ThemeContext.jsx';

// recharts renders via inline SVG/JS props, so it can't read CSS variables
// directly - these mirror the light/dark tokens in App.css for just the
// handful of values the chart needs.
const CHART_THEME = {
  light: {
    grid: '#dfe2e8',
    axis: '#6b7280',
    tooltipBg: '#ffffff',
    tooltipBorder: 'rgba(20, 23, 31, 0.1)',
    tooltipLabel: '#5b616e',
  },
  dark: {
    grid: '#2a3040',
    axis: '#8a90a3',
    tooltipBg: '#191d27',
    tooltipBorder: '#262b38',
    tooltipLabel: '#8a90a3',
  },
};

function formatTick(iso) {
  const d = new Date(iso);
  return d.toLocaleTimeString([], {
    hour: '2-digit',
    minute: '2-digit',
    hour12: false,
  });
}

function useIsNarrow() {
  const [isNarrow, setIsNarrow] = useState(
    typeof window !== 'undefined' && window.innerWidth < 640
  );
  useEffect(() => {
    const onResize = () => setIsNarrow(window.innerWidth < 640);
    window.addEventListener('resize', onResize);
    return () => window.removeEventListener('resize', onResize);
  }, []);
  return isNarrow;
}

export default function ChartPanel({ channels, series }) {
  const { theme } = useTheme();
  const c = CHART_THEME[theme];
  const isNarrow = useIsNarrow();

  if (series.length === 0) {
    return (
      <div className="state-note">
        No data yet — once the poller records a few ticks, the chart appears
        here.
      </div>
    );
  }

  const axisTickStyle = {
    fontFamily: 'IBM Plex Mono',
    fontSize: isNarrow ? 10 : 11,
    fill: c.axis,
  };

  return (
    // Axis titles are plain HTML/CSS here, NOT recharts' built-in XAxis/YAxis
    // `label` prop - that prop isn't legend-aware, so it can render on top of
    // the Legend when vertical space is tight. Positioning them outside the
    // SVG entirely guarantees they never collide with it.
    <div className="chart-frame">
      <span className="chart-axis-title chart-axis-title-y" style={{ color: c.tooltipLabel }}>
        POPULARITY
      </span>

      <ResponsiveContainer width="100%" height={isNarrow ? 260 : 340}>
        <LineChart
          data={series}
          margin={{
            top: 8,
            right: isNarrow ? 10 : 16,
            left: isNarrow ? -8 : 4,
            bottom: 4,
          }}
        >
          {/* Solid full grid (horizontal + vertical, recharts' default for
              both when unset) to match the classic boxed-chart look. */}
          <CartesianGrid stroke={c.grid} />

          <XAxis
            dataKey="timestamp"
            tickFormatter={formatTick}
            stroke={c.axis}
            tick={axisTickStyle}
            tickLine={{ stroke: c.axis }}
            axisLine={{ stroke: c.axis }}
            minTickGap={isNarrow ? 56 : 40}
          />
          <YAxis
            stroke={c.axis}
            tick={axisTickStyle}
            tickLine={{ stroke: c.axis }}
            axisLine={{ stroke: c.axis }}
            width={isNarrow ? 40 : 56}
          />

          {/* Mirrored top/right axes, ticks and labels hidden, purely to draw
              the bounding-box border around the plot area. */}
          <XAxis
            xAxisId="top-border"
            dataKey="timestamp"
            orientation="top"
            tick={false}
            tickLine={false}
            axisLine={{ stroke: c.axis }}
          />
          <YAxis
            yAxisId="right-border"
            orientation="right"
            tick={false}
            tickLine={false}
            axisLine={{ stroke: c.axis }}
          />

          <Tooltip
            labelFormatter={(v) => new Date(v).toLocaleString()}
            contentStyle={{
              background: c.tooltipBg,
              border: `1px solid ${c.tooltipBorder}`,
              borderRadius: 10,
              fontFamily: 'IBM Plex Mono',
              fontSize: 12,
              boxShadow: '0 8px 24px -8px rgba(16,24,40,0.2)',
            }}
            labelStyle={{ color: c.tooltipLabel }}
          />
          <Legend
            iconType="circle"
            wrapperStyle={{ fontFamily: 'Space Grotesk', fontSize: 12, color: c.tooltipLabel, paddingTop: 8 }}
          />
          {channels.map((ch) => (
            <Line
              key={ch.name}
              type="monotone"
              dataKey={ch.name}
              stroke={ch.color}
              dot={{ r: isNarrow ? 1.5 : 2, fill: ch.color, strokeWidth: 0 }}
              activeDot={{ r: 4 }}
              strokeWidth={2}
              isAnimationActive={false}
              connectNulls
            />
          ))}
        </LineChart>
      </ResponsiveContainer>

      {!isNarrow && (
        <span className="chart-axis-title chart-axis-title-x" style={{ color: c.tooltipLabel }}>
          TIME
        </span>
      )}
    </div>
  );
}
