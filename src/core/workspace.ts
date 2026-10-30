import type { AssignmentRow, Snapshot } from "./types.ts";
import type { LectureRef } from "./lectures.ts";

export type Repeat = "none" | "daily" | "weekly" | "monthly";
export interface TaskDraft {
  title: string;
  notes: string;
  courseId: number | null;
  dueAt: string | null;
  repeat: Repeat;
  weekdays: number[];
  endDate: string | null;
  checklist: { id: string; title: string }[];
  reminders: number[];
  /** A durable navigation target; lecture text and credentials stay elsewhere. */
  lectureSource?: LectureRef & { title: string };
}
export interface Exception {
  completed?: boolean;
  deleted?: boolean;
  checked?: string[];
  draft?: TaskDraft;
}
export interface Series extends TaskDraft {
  id: string;
  createdAt: string;
  exceptions: Record<string, Exception>;
}
export interface ChangeRecord {
  id: string;
  batch: string;
  at: string;
  courseId: number;
  kind: ResourceKind;
  title: string;
  before: string | null;
  after: string;
  read: boolean;
  objectId: string;
}
export type ResourceKind = "assignment" | "grade" | "announcement" | "file" | "lecture";
export interface ResourceResult {
  courseId: number;
  kind: ResourceKind;
  status: "success" | "failed" | "reused";
  error?: string;
  /** Lecture source + binding generation. A new binding starts a silent baseline. */
  baselineKey?: string;
  items?: { id: string; title: string; value: string }[];
}
export interface WorkspaceData {
  version: 1;
  account: number;
  series: Series[];
  deadlines: Record<string, string>;
  ignored: string[];
  changes: ChangeRecord[];
  baselines: Record<string, Record<string, { title: string; value: string }>>;
  delivered: Record<string, number>;
}
export type WorkspaceCommand =
  | {
      type: "save";
      draft: TaskDraft;
      seriesId?: string;
      key?: string;
      scope?: "one" | "future";
    }
  | {
      type: "complete";
      items: { seriesId: string; key: string }[];
      completed: boolean;
    }
  | { type: "check"; seriesId: string; key: string; checked: string[] }
  | {
      type: "delete";
      items: { seriesId: string; key: string }[];
      scope: "one" | "future";
    }
  | { type: "deadline"; id: string; value: string | null }
  | { type: "ignore"; ids: string[]; ignored: boolean }
  | { type: "read"; ids: string[] };
export interface TaskView {
  id: string;
  title: string;
  courseId: number | null;
  courseName: string;
  dueAt: string | null;
  completed: boolean;
  ignored: boolean;
  source: "school" | "personal";
  row?: AssignmentRow;
  seriesId?: string;
  key?: string;
  draft?: TaskDraft;
  checked?: string[];
}
export const emptyWorkspace = (account: number): WorkspaceData => ({
  version: 1,
  account,
  series: [],
  deadlines: {},
  ignored: [],
  changes: [],
  baselines: {},
  delivered: {},
});
// Calendar arithmetic is explicitly Asia/Shanghai, matching the iOS domain.
export const dayKey = (date: string | number | Date): string =>
  new Date(new Date(date).getTime() + 8 * 3600000).toISOString().slice(0, 10);
const midnight = (key: string) => Date.parse(`${key}T00:00:00+08:00`);
const previousDay = (key: string) => dayKey(midnight(key) - 86400000);
export function occurrences(
  s: Series,
  until: number,
): { key: string; draft: TaskDraft; state: Exception }[] {
  if (s.repeat === "none" || !s.dueAt) {
    const state = s.exceptions.single ?? {};
    return state.deleted
      ? []
      : [{ key: "single", draft: state.draft ?? s, state }];
  }
  const start = dayKey(s.dueAt),
    end = s.endDate ? Math.min(until, midnight(s.endDate) + 86399999) : until;
  const clock = new Date(Date.parse(s.dueAt) + 8 * 3600000)
    .toISOString()
    .slice(11, 19);
  const anchor = Number(start.slice(8));
  const out: { key: string; draft: TaskDraft; state: Exception }[] = [];
  for (let at = midnight(start); at <= end; at += 86400000) {
    const key = dayKey(at),
      d = new Date(at + 8 * 3600000);
    const monthEnd = new Date(
      Date.UTC(d.getUTCFullYear(), d.getUTCMonth() + 1, 0),
    ).getUTCDate();
    if (
      s.repeat === "weekly" &&
      !(
        s.weekdays.length
          ? s.weekdays
          : [new Date(midnight(start) + 8 * 3600000).getUTCDay() + 1]
      ).includes(d.getUTCDay() + 1)
    )
      continue;
    if (s.repeat === "monthly" && d.getUTCDate() !== Math.min(anchor, monthEnd))
      continue;
    const state = s.exceptions[key] ?? {};
    const scheduled = `${key}T${clock}+08:00`;
    const draft = state.draft ?? { ...s, dueAt: scheduled };
    if (
      !state.deleted &&
      Date.parse(scheduled) <= end &&
      (!draft.dueAt || Date.parse(draft.dueAt) <= until)
    )
      out.push({ key, draft, state });
  }
  // A later occurrence can be moved into the visible range without changing its identity.
  const keys = new Set(out.map((o) => o.key));
  for (const [key, state] of Object.entries(s.exceptions)) {
    if (
      !keys.has(key) &&
      !state.deleted &&
      state.draft &&
      key >= start &&
      (!s.endDate || key <= s.endDate) &&
      state.draft.dueAt &&
      Date.parse(state.draft.dueAt) <= until
    ) {
      out.push({ key, draft: state.draft, state });
    }
  }
  return out;
}
export function validateDraft(d: TaskDraft): TaskDraft {
  if (
    !d ||
    typeof d.title !== "string" ||
    !d.title.trim() ||
    d.title.length > 500
  )
    throw new Error("请输入 1–500 字的任务标题");
  if (!["none", "daily", "weekly", "monthly"].includes(d.repeat))
    throw new Error("重复规则无效");
  if (d.dueAt && !Number.isFinite(Date.parse(d.dueAt)))
    throw new Error("截止时间无效");
  if (d.repeat !== "none" && !d.dueAt) throw new Error("重复任务需要日期");
  if (d.repeat === "weekly" && !d.weekdays.length)
    throw new Error("每周重复请至少选择一个星期");
  if (
    d.endDate &&
    (!/^\d{4}-\d{2}-\d{2}$/.test(d.endDate) ||
      !d.dueAt ||
      d.endDate < dayKey(d.dueAt))
  )
    throw new Error("结束日期不能早于首次日期");
  if (
    d.reminders.length > 5 ||
    d.reminders.some((v) => !Number.isInteger(v) || v < 0 || v > 525600)
  )
    throw new Error("最多 5 个提醒，提前分钟数须为 0–525600");
  if (d.weekdays.some((v) => !Number.isInteger(v) || v < 1 || v > 7))
    throw new Error("星期无效");
  if (
    d.checklist.length > 100 ||
    new Set(d.checklist.map((c) => c.id)).size !== d.checklist.length
  )
    throw new Error("子任务无效");
  const lecture = d.lectureSource;
  if (lecture !== undefined && (
    !lecture || typeof lecture !== "object" ||
    [lecture.sourceId, lecture.icourseCourseId, lecture.lectureId].some(
      (value) => typeof value !== "string" || !value.trim() || value.length >= 300,
    ) || typeof lecture.title !== "string" || !lecture.title.trim() || lecture.title.length > 500
  )) throw new Error("课堂笔记来源无效，请重新从笔记创建任务");
  return {
    title: d.title.trim(),
    notes: d.notes,
    courseId: d.courseId,
    dueAt: d.dueAt,
    repeat: d.repeat,
    weekdays: [...d.weekdays],
    endDate: d.endDate,
    checklist: d.checklist.map((c) => ({ id: c.id, title: c.title })),
    reminders: d.dueAt ? [...new Set(d.reminders)] : [],
    ...(lecture ? { lectureSource: {
      sourceId: lecture.sourceId,
      icourseCourseId: lecture.icourseCourseId,
      lectureId: lecture.lectureId,
      title: lecture.title.trim(),
    } } : {}),
  };
}
export function mutateWorkspace(
  old: WorkspaceData,
  command: WorkspaceCommand,
  uuid: () => string,
  now = new Date().toISOString(),
): WorkspaceData {
  const data: WorkspaceData = JSON.parse(JSON.stringify(old));
  const series = (id: string) => {
    const s = data.series.find((s) => s.id === id);
    if (!s) throw new Error("任务已不存在，请刷新");
    return s;
  };
  const state = (id: string, key: string) => {
    const s = series(id);
    const until = key === "single" ? Date.now() : midnight(key) + 86399999;
    if (
      !Number.isFinite(until) ||
      !occurrences({ ...s, exceptions: {} }, until).some((o) => o.key === key)
    )
      throw new Error("任务期次无效");
    return (s.exceptions[key] ??= {});
  };
  switch (command.type) {
    case "save": {
      const draft = validateDraft(command.draft);
      if (!command.seriesId)
        data.series.push({
          ...draft,
          id: uuid(),
          createdAt: now,
          exceptions: {},
        });
      else {
        const s = series(command.seriesId),
          key = command.key ?? "single";
        state(s.id, key);
        if (s.repeat === "none") {
          const previous = s.exceptions.single;
          Object.assign(s, draft);
          if (draft.repeat !== "none")
            s.exceptions = previous ? { [dayKey(draft.dueAt!)]: previous } : {};
        } else if (command.scope === "one")
          state(s.id, key).draft = { ...draft, repeat: "none" };
        else {
          s.endDate = previousDay(key);
          // Future exceptions intentionally belong to the old series and no longer materialize.
          data.series.push({
            ...draft,
            id: uuid(),
            createdAt: now,
            exceptions: {},
          });
        }
      }
      break;
    }
    case "complete":
      for (const i of command.items)
        state(i.seriesId, i.key).completed = command.completed;
      break;
    case "check": {
      const s = series(command.seriesId);
      const valid = state(s.id, command.key).draft ?? s;
      if (
        command.checked.some((id) => !valid.checklist.some((c) => c.id === id))
      )
        throw new Error("子任务无效");
      state(s.id, command.key).checked = command.checked;
      break;
    }
    case "delete":
      for (const i of command.items) {
        const s = series(i.seriesId);
        state(s.id, i.key);
        if (command.scope === "future" && s.repeat !== "none")
          s.endDate = previousDay(i.key);
        else state(s.id, i.key).deleted = true;
      }
      break;
    case "deadline":
      if (command.value) {
        if (!Number.isFinite(Date.parse(command.value)))
          throw new Error("截止时间无效");
        data.deadlines[command.id] = command.value;
      } else delete data.deadlines[command.id];
      break;
    case "ignore":
      data.ignored = command.ignored
        ? [...new Set([...data.ignored, ...command.ids])]
        : data.ignored.filter((id) => !command.ids.includes(id));
      break;
    case "read": {
      const ids = new Set(command.ids);
      data.changes.forEach((c) => {
        if (ids.has(c.id)) c.read = true;
      });
      break;
    }
  }
  return data;
}
export function unifyTasks(
  snapshot: Snapshot,
  data: WorkspaceData,
  until = Date.now() + 90 * 86400000,
): TaskView[] {
  const ignored = new Set(data.ignored),
    names = new Map(snapshot.courses.map((c) => [c.id, c.displayName]));
  const school: TaskView[] = snapshot.assignments.map((row) => {
    const key = `${row.courseId}:${row.id}`;
    return {
      id: `school:${key}`,
      title: row.name,
      courseId: row.courseId,
      courseName: row.courseName,
      dueAt: data.deadlines[key] ?? row.dueAt,
      completed: !!(row.submittedAt || row.gradedAt || row.excused),
      ignored: ignored.has(key),
      source: "school",
      row,
    };
  });
  for (const s of data.series)
    for (const o of occurrences(s, until))
      school.push({
        id: `personal:${s.id}:${o.key}`,
        title: o.draft.title,
        courseId: o.draft.courseId,
        courseName: names.get(o.draft.courseId ?? -1) ?? "个人任务",
        dueAt: o.draft.dueAt,
        completed: o.state.completed ?? false,
        ignored: false,
        source: "personal",
        seriesId: s.id,
        key: o.key,
        draft: o.draft,
        checked: o.state.checked ?? [],
      });
  return school.sort(
    (a, b) =>
      (a.dueAt ? Date.parse(a.dueAt) : Infinity) -
        (b.dueAt ? Date.parse(b.dueAt) : Infinity) ||
      a.title.localeCompare(b.title),
  );
}
export function recordChanges(
  old: WorkspaceData,
  results: ResourceResult[],
  batch: string,
  now: string,
  uuid: () => string,
): WorkspaceData {
  const data: WorkspaceData = JSON.parse(JSON.stringify(old));
  for (const r of results) {
    if (r.status !== "success" || !r.items) continue;
    // Keep Canvas keys unchanged for pre-integration caches. Lecture namespaces
    // include a binding generation, so reassigning a source never replays history.
    const key = `${r.courseId}:${r.kind}${r.kind === "lecture" && r.baselineKey ? `:${r.baselineKey}` : ""}`,
      previous = data.baselines[key];
    const next = { ...previous };
    for (const item of r.items) {
      if (r.kind === "lecture" && !/^[a-f0-9]{64}$/i.test(item.value))
        throw new Error("课堂变化只接受摘要指纹，不能保存笔记正文");
      const before = previous?.[item.id];
      let emptyNewGrade = false;
      if (r.kind === "grade" && !before) {
        try {
          const grade = JSON.parse(item.value);
          emptyNewGrade = grade.score == null && grade.grade == null;
        } catch {
          /* opaque fixtures remain comparable */
        }
      }
      if (previous && before?.value !== item.value && !emptyNewGrade)
        data.changes.unshift({
          id: uuid(),
          batch,
          at: now,
          courseId: r.courseId,
          kind: r.kind,
          title: item.title,
          before: before?.value ?? null,
          after: item.value,
          read: false,
          objectId: item.id,
        });
      next[item.id] = { title: item.title, value: item.value };
    }
    data.baselines[key] = next;
  }
  data.changes = data.changes
    .filter((c) => Date.parse(c.at) >= Date.parse(now) - 180 * 86400000)
    .slice(0, 2000);
  return data;
}

/** Collect missed reminder instants without modifying caller-owned state. */
export function dueReminders(tasks: TaskView[], delivered: Record<string, number>, now: number, resume: boolean) {
  const marks = { ...delivered };
  const due = new Map<string, { id: string; title: string }>();
  for (const task of tasks) {
    if (task.completed || task.ignored || !task.dueAt) continue;
    for (const minutes of task.draft?.reminders ?? [60]) {
      const at = Date.parse(task.dueAt) - minutes * 60000;
      const key = `${task.id}:${task.dueAt}:${minutes}`;
      if (at <= now && at > now - (resume ? 86400000 : 90000) && !marks[key]) {
        due.set(task.id, { id: task.id, title: task.title }); marks[key] = now;
      }
    }
  }
  return { due: [...due.values()], delivered: Object.fromEntries(Object.entries(marks).filter(([, at]) => at > now - 180 * 86400000)) };
}
