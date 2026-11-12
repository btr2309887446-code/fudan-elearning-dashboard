import type { LectureRef } from './lectures.ts';
import type { Series, WorkspaceData } from './workspace.ts';

export type Mastery = 'unassessed' | 'weak' | 'familiar' | 'confident';
export const masteryLabels: Record<Mastery, string> = { unassessed: '未评估', weak: '需加强', familiar: '基本掌握', confident: '熟练' };
export interface ReviewSource extends LectureRef { title: string; summaryHash: string; quote: string }
export interface ReviewItem {
  id: string; title: string; notes: string; minutes: number; extraMinutes: number;
  mastery: Mastery; questions: { question: string; answer: string }[]; sources: ReviewSource[];
}
export interface ReviewPlan { id: string; courseId: number; title: string; examDate: string | null; items: ReviewItem[] }
export interface ReviewSlot { id: string; planId: string; date: string; locked: boolean; allocations: { itemId: string; minutes: number }[]; taskId: string }
export interface ReviewData {
  version: 1; revision: number; plans: ReviewPlan[]; slots: ReviewSlot[];
  budget: number[]; finishTime: string;
}
export interface SchedulePreview {
  revision: number; start: string; slots: Omit<ReviewSlot, 'taskId'>[];
  shortages: { planId: string; minutes: number; reason: string }[];
  changes: { added: number; moved: number; removed: number }; warnings: string[];
}
export type ReviewAction =
  | { kind: 'plan'; plan: ReviewPlan; revision: number }
  | { kind: 'remove'; planId: string; revision: number }
  | { kind: 'budget'; budget: number[]; finishTime: string; revision: number }
  | { kind: 'lock'; slotId: string; locked: boolean; revision: number }
  | { kind: 'schedule'; revision: number; start: string; expected?: string };

export const emptyReview = (): ReviewData => ({ version: 1, revision: 0, plans: [], slots: [], budget: [60, 60, 60, 60, 60, 60, 60], finishTime: '21:00' });
export const beijingDay = (now: number) => new Date(now + 8 * 3600000).toISOString().slice(0, 10);
const midnight = (day: string) => Date.parse(`${day}T00:00:00+08:00`);
export const validDay = (day: string) => /^\d{4}-\d{2}-\d{2}$/.test(day) && Number.isFinite(midnight(day)) && beijingDay(midnight(day)) === day;
const clean = (v: unknown, max: number, required = false): string => {
  if (typeof v !== 'string' || v.length > max || (required && !v.trim())) throw Error('复习内容格式或长度无效');
  return v.trim();
};
const integer = (v: unknown, min: number, max: number): number => {
  if (!Number.isInteger(v) || (v as number) < min || (v as number) > max) throw Error('复习时间或编号无效');
  return v as number;
};
export function validatePlan(input: ReviewPlan): ReviewPlan {
  if (!input || !Array.isArray(input.items) || input.items.length > 1000) throw Error('每个计划最多 1,000 个复习项');
  if (input.examDate !== null && !validDay(input.examDate)) throw Error('考试日期无效');
  const ids = new Set<string>();
  return { id: clean(input.id, 100, true), courseId: integer(input.courseId, 0, Number.MAX_SAFE_INTEGER), title: clean(input.title, 200, true), examDate: input.examDate,
    items: input.items.map(item => {
      const id = clean(item.id, 100, true);
      if (ids.has(id)) throw Error('复习项编号重复'); ids.add(id);
      if (!Object.prototype.hasOwnProperty.call(masteryLabels, item.mastery) || !Array.isArray(item.questions) || item.questions.length > 10 || !Array.isArray(item.sources) || item.sources.length > 20) throw Error('复习项格式无效');
      return { id, title: clean(item.title, 500, true), notes: clean(item.notes, 12000), minutes: integer(item.minutes, 1, 1440), extraMinutes: integer(item.extraMinutes ?? 0, 0, 100000), mastery: item.mastery,
        questions: item.questions.map(q => ({ question: clean(q.question, 4000, true), answer: clean(q.answer, 12000) })),
        sources: item.sources.map(s => ({ sourceId: clean(s.sourceId, 299, true), icourseCourseId: clean(s.icourseCourseId, 299, true), lectureId: clean(s.lectureId, 299, true), title: clean(s.title, 500, true), summaryHash: clean(s.summaryHash, 100), quote: clean(s.quote, 2000) })) };
    }) };
}
export function slotCompleted(data: WorkspaceData, slot: ReviewSlot): boolean {
  const task = data.series.find(s => s.id === slot.taskId);
  return !!task?.exceptions.single?.completed;
}
export function slotActive(data: WorkspaceData, slot: ReviewSlot): boolean {
  const task = data.series.find(s => s.id === slot.taskId);
  return !!task && !task.exceptions.single?.deleted;
}
export function reviewedMinutes(data: WorkspaceData, planId: string, itemId: string): number {
  return (data.review?.slots ?? []).filter(s => s.planId === planId && slotCompleted(data, s))
    .reduce((sum, s) => sum + s.allocations.filter(a => a.itemId === itemId).reduce((n, a) => n + a.minutes, 0), 0);
}
export function previewSchedule(data: WorkspaceData, start: string, now: number): SchedulePreview {
  const review = data.review ?? emptyReview();
  if (!validDay(start) || start < beijingDay(now)) throw Error('排期开始日期不能早于今天');
  const keep = review.slots.filter(s => slotCompleted(data, s) || (s.locked && slotActive(data, s)));
  const capacity = new Map<string, number>();
  const warnings: string[] = [];
  const minutesOn = (date: string) => {
    if (!capacity.has(date)) {
      const used = keep.filter(s => s.date === date).reduce((n, s) => n + s.allocations.reduce((n, a) => n + a.minutes, 0), 0);
      const budget = review.budget[new Date(midnight(date) + 8 * 3600000).getUTCDay()];
      if (used > budget) warnings.push(`${date} 已完成或锁定安排超出预算 ${used - budget} 分钟`);
      capacity.set(date, Math.max(0, budget - used));
    }
    return capacity.get(date)!;
  };
  const slots = new Map<string, Omit<ReviewSlot, 'taskId'>>();
  const shortages: SchedulePreview['shortages'] = [];
  const rank: Record<Mastery, number> = { weak: 0, unassessed: 1, familiar: 2, confident: 3 };
  for (const plan of [...review.plans].sort((a, b) => (a.examDate ?? '9999').localeCompare(b.examDate ?? '9999') || a.id.localeCompare(b.id))) {
    let missing = 0;
    const items = plan.items.map((item, order) => ({ item, order })).sort((a, b) => rank[a.item.mastery] - rank[b.item.mastery] || a.order - b.order);
    for (const { item } of items) {
      let left = Math.max(0, item.minutes + item.extraMinutes - keep.filter(s => s.planId === plan.id).reduce((sum, s) => sum + s.allocations.filter(a => a.itemId === item.id).reduce((n, a) => n + a.minutes, 0), 0));
      if (plan.examDate && midnight(plan.examDate) - midnight(start) > 730 * 86400000) throw Error('排期范围最多两年，请调整开始日期');
      for (let time = midnight(start); left > 0 && plan.examDate && time < midnight(plan.examDate); time += 86400000) {
        const date = beijingDay(time), available = minutesOn(date);
        // Today's completion time may already have passed; never schedule immediately overdue work.
        if (Date.parse(`${date}T${review.finishTime}:00+08:00`) <= now || !available) continue;
        const amount = Math.min(left, available), id = `${plan.id}:${date}`;
        // Locked/completed days retain their existing task without appending new work to it.
        if (keep.some(s => review.plans.find(p => p.id === s.planId)?.courseId === plan.courseId && s.date === date)) continue;
        const slot = slots.get(id) ?? { id, planId: plan.id, date, locked: false, allocations: [] };
        slot.allocations.push({ itemId: item.id, minutes: amount }); slots.set(id, slot);
        left -= amount; capacity.set(date, available - amount);
      }
      missing += left;
    }
    if (missing) shortages.push({ planId: plan.id, minutes: missing, reason: !plan.examDate ? '未设置考试日期' : plan.examDate <= start ? '考试前已无可用日期' : '可用时间不足' });
  }
  const next = [...slots.values()].sort((a, b) => a.date.localeCompare(b.date) || a.planId.localeCompare(b.planId));
  const previous = review.slots.filter(s => !keep.includes(s) && slotActive(data, s));
  const same = (a: { allocations: ReviewSlot['allocations'] }, b: { allocations: ReviewSlot['allocations'] }) => JSON.stringify(a.allocations) === JSON.stringify(b.allocations);
  return { revision: review.revision, start, slots: next, shortages, warnings,
    changes: { added: next.filter(s => !previous.some(p => p.id === s.id)).length, moved: next.filter(s => previous.some(p => p.id === s.id && !same(s, p))).length, removed: previous.filter(p => !next.some(s => s.id === p.id)).length } };
}
export function applyReview(data: WorkspaceData, action: ReviewAction, uuid: () => string, now: string): void {
  const review = data.review ??= emptyReview();
  if (!action || action.revision !== review.revision) throw Error('复习计划已变化，请重新查看后保存');
  const plan = (id: string) => { const p = review.plans.find(p => p.id === id); if (!p) throw Error('复习计划不存在'); return p; };
  const taskFor = (slots: ReviewSlot[], previous?: Series): Series => {
    const p = plan(slots[0].planId), duration = slots.reduce((n, s) => n + s.allocations.reduce((n, a) => n + a.minutes, 0), 0);
    return { id: slots[0].taskId, title: `复习 · ${slots.map(s => plan(s.planId).title).join(' / ').slice(0, 400)}（${duration} 分钟）`, courseId: p.courseId,
      notes: slots.flatMap(s => s.allocations.map(a => `${plan(s.planId).title} · ${plan(s.planId).items.find(i => i.id === a.itemId)?.title ?? '已移除知识点'} · ${a.minutes} 分钟`)).join('\n'),
      dueAt: `${slots[0].date}T${review.finishTime}:00+08:00`, repeat: 'none', weekdays: [], endDate: null, checklist: [], reminders: [], createdAt: previous?.createdAt ?? now,
      exceptions: previous?.exceptions ?? {}, reviewSource: { planId: p.id, slotId: slots[0].id } };
  };
  if (action.kind === 'plan') {
    const incoming = validatePlan(action.plan), index = review.plans.findIndex(p => p.id === incoming.id);
    if (index >= 0 && review.plans[index].courseId !== incoming.courseId) throw Error('不能更换已有计划的课程');
    if (index < 0) { if (review.plans.length >= 200) throw Error('最多保存 200 个复习计划'); review.plans.push(incoming); }
    else {
      const removed = new Set(review.plans[index].items.filter(i => !incoming.items.some(n => n.id === i.id)).map(i => i.id));
      if (review.slots.some(s => s.planId === incoming.id && slotActive(data, s) && !slotCompleted(data, s) && s.allocations.some(a => removed.has(a.itemId)))) throw Error('请先取消该知识点的未完成安排，再删除知识点');
      review.plans[index] = incoming;
    }
  } else if (action.kind === 'remove') {
    plan(action.planId);
    const taskIds = new Set(review.slots.filter(s => s.planId === action.planId).map(s => s.taskId));
    review.slots = review.slots.filter(s => s.planId !== action.planId); review.plans = review.plans.filter(p => p.id !== action.planId);
    data.series = data.series.flatMap(s => {
      if (!taskIds.has(s.id)) return [s];
      const remaining = review.slots.filter(slot => slot.taskId === s.id);
      return remaining.length ? [taskFor(remaining, s)] : [];
    });
  } else if (action.kind === 'budget') {
    if (!Array.isArray(action.budget) || action.budget.length !== 7 || !/^([01]\d|2[0-3]):[0-5]\d$/.test(action.finishTime)) throw Error('每日预算或完成时间无效');
    review.budget = action.budget.map(n => integer(n, 0, 720)); review.finishTime = action.finishTime;
  } else if (action.kind === 'lock') {
    const slot = review.slots.find(s => s.id === action.slotId);
    if (!slot || typeof action.locked !== 'boolean') throw Error('复习安排不存在');
    for (const s of review.slots.filter(s => s.taskId === slot.taskId)) s.locked = action.locked;
  } else if (action.kind === 'schedule') {
    const preview = previewSchedule(data, action.start, Date.parse(now));
    if (action.expected !== undefined && action.expected !== JSON.stringify(preview.slots)) throw Error('可用复习时间已变化，请重新预览排期');
    const keep = review.slots.filter(s => slotCompleted(data, s) || (s.locked && slotActive(data, s)));
    const keepTasks = new Set(keep.map(s => s.taskId));
    const oldTasks = new Map(data.series.map(s => [s.id, s]));
    data.series = data.series.filter(s => !s.reviewSource || keepTasks.has(s.id));
    const grouped = new Map<string, ReviewSlot[]>();
    for (const slot of preview.slots) {
      const p = plan(slot.planId), group = `${p.courseId}:${slot.date}`;
      const previous = review.slots.find(s => s.date === slot.date && plan(s.planId).courseId === p.courseId);
      const siblings = grouped.get(group) ?? [], taskId = siblings[0]?.taskId ?? previous?.taskId ?? uuid();
      siblings.push({ ...slot, taskId }); grouped.set(group, siblings);
    }
    const next = [...grouped.values()].flat();
    for (const slots of grouped.values()) {
      const old = oldTasks.get(slots[0].taskId);
      data.series.push(taskFor(slots, old ? { ...old, exceptions: {} } : undefined));
    }
    review.slots = [...keep, ...next];
  } else throw Error('未知复习操作');
  review.revision++;
}
