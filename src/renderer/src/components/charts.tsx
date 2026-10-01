import ReactECharts from 'echarts-for-react';
import type { AssignmentRow, CourseSummary } from '../../../core/types';
import { scoreColorResolved, useThemeColors } from '../useTheme';

/**
 * ECharts paints to a canvas, so CSS functions like color-mix() are not
 * available - colours have to be plain rgba strings.
 */
function withAlpha(color: string, alpha: number): string {
  const raw = color.trim();
  if (!raw.startsWith('#')) return raw;
  const hex = raw.slice(1);
  const full = hex.length === 3 ? hex.split('').map((ch) => ch + ch).join('') : hex;
  const n = Number.parseInt(full, 16);
  if (!Number.isFinite(n)) return raw;
  return `rgba(${(n >> 16) & 255}, ${(n >> 8) & 255}, ${n & 255}, ${alpha})`;
}

/** Horizontal bars of the current score of every course. */
export function CourseScoreChart({
  courses,
  onSelect,
  height,
}: {
  courses: CourseSummary[];
  onSelect?: (id: number) => void;
  height?: number;
}) {
  const c = useThemeColors();

  // Lowest scores at the top, which is the order a student cares about.
  const data = courses
    .filter((x) => x.currentScore !== null)
    .sort((a, b) => (a.currentScore as number) - (b.currentScore as number));

  if (data.length === 0) {
    return <div className="empty">暂无已评分课程</div>;
  }

  const names = data.map((x) => (x.displayName.length > 22 ? x.displayName.slice(0, 21) + '…' : x.displayName));

  const option = {
    backgroundColor: 'transparent',
    textStyle: { color: c.text, fontFamily: 'inherit' },
    tooltip: {
      backgroundColor: c.surface,
      borderColor: c.border,
      borderWidth: 1,
      textStyle: { color: c.text, fontSize: 12 },
      extraCssText: 'box-shadow: 0 8px 24px rgba(20,28,46,.14); border-radius: 10px;',
    },
    grid: { left: 4, right: 48, top: 6, bottom: 4, containLabel: true },
    xAxis: {
      type: 'value',
      max: 100,
      axisLabel: { color: c.muted, fontSize: 11 },
      splitLine: { lineStyle: { color: c.border } },
      axisLine: { show: false },
    },
    yAxis: {
      type: 'category',
      data: names,
      axisLabel: { color: c.dim, fontSize: 11.5, width: 150, overflow: 'truncate' },
      axisLine: { show: false },
      axisTick: { show: false },
    },
    series: [
      {
        type: 'bar',
        data: data.map((x) => ({
          value: Number((x.currentScore as number).toFixed(2)),
          itemStyle: { color: scoreColorResolved(x.currentScore, c), borderRadius: [0, 6, 6, 0] },
        })),
        barMaxWidth: 16,
        label: {
          show: true,
          position: 'right',
          formatter: (p: { value: number }) => p.value.toFixed(1),
          color: c.muted,
          fontSize: 11,
          fontWeight: 600,
        },
      },
    ],
  };

  return (
    <ReactECharts
      option={option}
      style={{ height: height ?? Math.max(180, data.length * 31 + 36) }}
      opts={{ renderer: 'canvas' }}
      onEvents={
        onSelect
          ? {
              click: (p: { componentType: string; dataIndex: number }) => {
                if (p.componentType === 'series') onSelect(data[p.dataIndex].id);
              },
            }
          : undefined
      }
    />
  );
}

/** Per-assignment-group attainment, which is what feeds a weighted course score. */
export function GroupChart({
  groups,
}: {
  groups: { name: string; weight: number; percent: number | null; earned: number; possible: number }[];
}) {
  const c = useThemeColors();
  const usable = groups.filter((g) => g.percent !== null);
  if (usable.length === 0) return <div className="empty">暂无已评分的作业分组</div>;

  const option = {
    backgroundColor: 'transparent',
    textStyle: { color: c.text, fontFamily: 'inherit' },
    tooltip: {
      backgroundColor: c.surface,
      borderColor: c.border,
      borderWidth: 1,
      textStyle: { color: c.text, fontSize: 12 },
      extraCssText: 'box-shadow: 0 8px 24px rgba(20,28,46,.14); border-radius: 10px;',
    },
    grid: { left: 4, right: 12, top: 28, bottom: 4, containLabel: true },
    xAxis: {
      type: 'category',
      data: usable.map((g) => (g.name.length > 12 ? g.name.slice(0, 11) + '…' : g.name)),
      axisLabel: { color: c.dim, fontSize: 11, interval: 0, rotate: usable.length > 5 ? 22 : 0 },
      axisLine: { show: false },
      axisTick: { show: false },
    },
    yAxis: {
      type: 'value',
      max: 100,
      axisLabel: { color: c.muted, fontSize: 11, formatter: '{value}%' },
      splitLine: { lineStyle: { color: c.border } },
      axisLine: { show: false },
    },
    series: [
      {
        type: 'bar',
        data: usable.map((g) => ({
          value: Number((g.percent as number).toFixed(2)),
          itemStyle: { color: scoreColorResolved(g.percent, c), borderRadius: [6, 6, 0, 0] },
        })),
        barMaxWidth: 46,
        label: {
          show: true,
          position: 'top',
          formatter: (p: { value: number }) => p.value.toFixed(1),
          color: c.muted,
          fontSize: 11,
          fontWeight: 600,
        },
      },
    ],
  };

  return <ReactECharts option={option} style={{ height: 224 }} opts={{ renderer: 'canvas' }} />;
}

/**
 * Running course percentage in due-date order.
 * Only graded work moves the line, which makes flat stretches meaningful:
 * they are periods where nothing has been marked yet.
 */
export function ScoreTrendChart({ rows }: { rows: AssignmentRow[] }) {
  const c = useThemeColors();

  const graded = rows
    .filter((r) => r.score !== null && r.pointsPossible !== null && r.pointsPossible > 0 && !r.excused)
    .sort((a, b) => {
      const ta = a.dueAt ? Date.parse(a.dueAt) : a.gradedAt ? Date.parse(a.gradedAt) : 0;
      const tb = b.dueAt ? Date.parse(b.dueAt) : b.gradedAt ? Date.parse(b.gradedAt) : 0;
      return ta - tb;
    });

  if (graded.length < 2) {
    return <div className="empty">已评分的作业不足，暂无法绘制趋势</div>;
  }

  let earned = 0;
  let possible = 0;
  const points: [string, number][] = [];
  for (const r of graded) {
    earned += r.score as number;
    possible += r.pointsPossible as number;
    points.push([r.dueAt ?? r.gradedAt ?? new Date().toISOString(), Number(((earned / possible) * 100).toFixed(2))]);
  }

  const option = {
    backgroundColor: 'transparent',
    textStyle: { color: c.text, fontFamily: 'inherit' },
    tooltip: {
      trigger: 'axis',
      backgroundColor: c.surface,
      borderColor: c.border,
      borderWidth: 1,
      textStyle: { color: c.text, fontSize: 12 },
      extraCssText: 'box-shadow: 0 8px 24px rgba(20,28,46,.14); border-radius: 10px;',
    },
    grid: { left: 4, right: 16, top: 20, bottom: 4, containLabel: true },
    xAxis: {
      type: 'category',
      boundaryGap: false,
      data: points.map((p) => {
        const d = new Date(p[0]);
        return `${d.getMonth() + 1}/${d.getDate()}`;
      }),
      axisLabel: { color: c.muted, fontSize: 11 },
      axisLine: { lineStyle: { color: c.border } },
      axisTick: { show: false },
    },
    yAxis: {
      type: 'value',
      min: (v: { min: number }) => Math.max(0, Math.floor(v.min - 6)),
      max: 100,
      axisLabel: { color: c.muted, fontSize: 11, formatter: '{value}%' },
      splitLine: { lineStyle: { color: c.border } },
    },
    series: [
      {
        type: 'line',
        smooth: true,
        symbolSize: 7,
        data: points.map((p) => p[1]),
        lineStyle: { width: 2.6, color: c.accent },
        itemStyle: { color: c.accent, borderColor: c.surface, borderWidth: 2 },
        areaStyle: {
          color: {
            type: 'linear',
            x: 0,
            y: 0,
            x2: 0,
            y2: 1,
            colorStops: [
              { offset: 0, color: withAlpha(c.accent, 0.26) },
              { offset: 1, color: withAlpha(c.accent, 0.01) },
            ],
          },
        },
      },
    ],
  };

  return <ReactECharts option={option} style={{ height: 224 }} opts={{ renderer: 'canvas' }} />;
}
