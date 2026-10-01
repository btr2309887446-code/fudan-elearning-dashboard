import { scoreColor, scoreLabel } from '../util';

interface Props {
  score: number | null;
  size?: number;
  stroke?: number;
  showLabel?: boolean;
}

/** Circular score indicator drawn with plain SVG (no chart library needed). */
export default function ScoreRing({ score, size = 62, stroke = 6, showLabel = true }: Props) {
  const has = score !== null && !Number.isNaN(score);
  const pct = has ? Math.max(0, Math.min(100, score as number)) : 0;
  const r = (size - stroke) / 2;
  const circ = 2 * Math.PI * r;
  const color = scoreColor(score);

  return (
    <div className="ring" style={{ width: size, height: size }}>
      <svg width={size} height={size} style={{ transform: 'rotate(-90deg)' }}>
        <circle cx={size / 2} cy={size / 2} r={r} fill="none" stroke="var(--ring-track)" strokeWidth={stroke} />
        <circle
          cx={size / 2}
          cy={size / 2}
          r={r}
          fill="none"
          stroke={color}
          strokeWidth={stroke}
          strokeLinecap="round"
          strokeDasharray={circ}
          strokeDashoffset={circ * (1 - pct / 100)}
          style={{ transition: 'stroke-dashoffset 0.7s cubic-bezier(0.32,0.72,0,1)' }}
        />
      </svg>
      <div className="ring-text">
        <div className="ring-score" style={{ color, fontSize: size * 0.27 }}>
          {has ? (score as number).toFixed(has && (score as number) % 1 === 0 ? 0 : 1) : '—'}
        </div>
        {showLabel && size >= 56 && (
          <div className="ring-grade" style={{ fontSize: size * 0.15 }}>
            {scoreLabel(score)}
          </div>
        )}
      </div>
    </div>
  );
}
