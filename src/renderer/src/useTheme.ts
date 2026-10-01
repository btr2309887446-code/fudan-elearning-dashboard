import { useEffect, useState } from 'react';

export interface ThemeColors {
  text: string;
  dim: string;
  muted: string;
  border: string;
  surface: string;
  surface2: string;
  accent: string;
  good: string;
  warn: string;
  bad: string;
}

function read(): ThemeColors {
  if (typeof window === 'undefined') {
    return {
      text: '#1c1c1e',
      dim: '#5b6070',
      muted: '#9298a8',
      border: '#e5e7ee',
      surface: '#ffffff',
      surface2: '#f7f8fa',
      accent: '#007aff',
      good: '#34c759',
      warn: '#ff9f0a',
      bad: '#ff3b30',
    };
  }
  const cs = getComputedStyle(document.documentElement);
  const v = (name: string, fallback: string) => cs.getPropertyValue(name).trim() || fallback;
  return {
    text: v('--text', '#1c1c1e'),
    dim: v('--text-dim', '#5b6070'),
    muted: v('--muted', '#9298a8'),
    border: v('--border', '#e5e7ee'),
    surface: v('--surface', '#ffffff'),
    surface2: v('--surface-2', '#f7f8fa'),
    accent: v('--accent', '#007aff'),
    good: v('--good', '#34c759'),
    warn: v('--warn', '#ff9f0a'),
    bad: v('--bad', '#ff3b30'),
  };
}

/**
 * Resolve the active theme's colours for libraries that cannot use CSS
 * variables - ECharts paints to a canvas. Re-reads whenever `data-theme`
 * changes, so charts follow the light/dark switch.
 */
export function useThemeColors(): ThemeColors {
  const [colors, setColors] = useState<ThemeColors>(read);

  useEffect(() => {
    const update = () => setColors(read());
    update();
    const observer = new MutationObserver(update);
    observer.observe(document.documentElement, {
      attributes: true,
      attributeFilter: ['data-theme'],
    });
    return () => observer.disconnect();
  }, []);

  return colors;
}

/**
 * Score band colour using resolved values.
 *
 * `util.scoreColor` returns CSS variables, which is right for DOM elements but
 * useless inside ECharts - a canvas cannot resolve `var(--good)` and silently
 * falls back to grey. Charts must use this instead.
 */
export function scoreColorResolved(score: number | null, c: ThemeColors): string {
  if (score === null || Number.isNaN(score)) return c.muted;
  if (score >= 90) return c.good;
  if (score >= 80) return c.accent;
  if (score >= 70) return '#ffb020';
  if (score >= 60) return '#ff9500';
  return c.bad;
}
