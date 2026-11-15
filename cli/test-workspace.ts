import assert from "node:assert/strict";
import { mkdtempSync, readFileSync, writeFileSync, mkdirSync } from "node:fs";
import { tmpdir } from "node:os";
import { join } from "node:path";
import {
  dueReminders,
  emptyWorkspace,
  mutateWorkspace,
  occurrences,
  recordChanges,
  unifyTasks,
  validateDraft,
  type TaskDraft,
  type ResourceResult,
  type Series,
} from "../src/core/workspace.ts";
import { WorkspaceStore } from "../src/main/workspace-store.ts";
import { buildDemoSnapshot } from "../src/core/demo.ts";
import { buildSnapshot } from "../src/core/aggregate.ts";
import type { CanvasClient } from "../src/core/canvas.ts";
let counter = 0;
const uuid = () => `id-${++counter}`;
const base: TaskDraft = {
  title: "月末复盘",
  notes: "",
  courseId: null,
  dueAt: "2024-01-31T12:00:00+08:00",
  repeat: "monthly",
  weekdays: [],
  endDate: null,
  checklist: [{ id: "read", title: "阅读" }],
  reminders: [0, 60],
};
let data = mutateWorkspace(
  emptyWorkspace(7),
  { type: "save", draft: base },
  uuid,
);
const id = data.series[0].id;
assert.deepEqual(
  occurrences(data.series[0], Date.parse("2024-04-30T12:00:00+08:00")).map(
    (o) => o.key,
  ),
  ["2024-01-31", "2024-02-29", "2024-03-31", "2024-04-30"],
);
assert.equal(
  occurrences(data.series[0], Date.parse("2024-02-29T11:00:00+08:00")).length,
  1,
);
data = mutateWorkspace(
  data,
  {
    type: "complete",
    items: [{ seriesId: id, key: "2024-02-29" }],
    completed: true,
  },
  uuid,
);
data = mutateWorkspace(
  data,
  { type: "check", seriesId: id, key: "2024-02-29", checked: ["read"] },
  uuid,
);
assert.equal(data.series[0].exceptions["2024-03-31"], undefined);
data = mutateWorkspace(
  data,
  {
    type: "save",
    seriesId: id,
    key: "2024-03-31",
    scope: "one",
    draft: { ...base, dueAt: "2024-02-28T12:00:00+08:00" },
  },
  uuid,
);
assert(
  occurrences(data.series[0], Date.parse("2024-02-29T13:00:00+08:00")).some(
    (o) => o.key === "2024-03-31",
  ),
);
assert(!("exceptions" in data.series[0].exceptions["2024-03-31"].draft!));
data = mutateWorkspace(
  data,
  {
    type: "delete",
    items: [{ seriesId: id, key: "2024-03-31" }],
    scope: "future",
  },
  uuid,
);
assert.deepEqual(
  occurrences(data.series[0], Date.parse("2024-05-01")).map((o) => o.key),
  ["2024-01-31", "2024-02-29"],
);
const weekly: Series = {
  ...base,
  id: "weekly",
  createdAt: "",
  dueAt: "2026-10-19T12:00:00+08:00",
  repeat: "weekly",
  weekdays: [2, 6],
  exceptions: {},
};
assert.deepEqual(
  occurrences(weekly, Date.parse("2026-10-30T12:00:00+08:00")).map(
    (o) => o.key,
  ),
  ["2026-10-19", "2026-10-23", "2026-10-26", "2026-10-30"],
);
assert.throws(() =>
  mutateWorkspace(
    data,
    { type: "save", draft: { ...base, reminders: [0, 1, 2, 3, 4, 5] } },
    uuid,
  ),
);
let split = mutateWorkspace(
  emptyWorkspace(7),
  { type: "save", draft: { ...weekly } },
  uuid,
);
split = mutateWorkspace(
  split,
  {
    type: "save",
    seriesId: split.series[0].id,
    key: "2026-10-23",
    scope: "future",
    draft: { ...weekly, title: "新版", dueAt: "2026-10-23T14:00:00+08:00" },
  },
  uuid,
);
assert.equal(split.series.length, 2);
assert.equal(split.series[0].endDate, "2026-10-22");
const snap = buildDemoSnapshot(),
  school = snap.assignments[0],
  key = `${school.courseId}:${school.id}`;
let manual = mutateWorkspace(
  emptyWorkspace(snap.profile.id),
  { type: "deadline", id: key, value: "2028-01-01T00:00:00Z" },
  uuid,
);
assert.equal(
  unifyTasks(snap, manual).find((t) => t.row?.id === school.id)!.dueAt,
  "2028-01-01T00:00:00Z",
);
school.dueAt = "2027-05-01T00:00:00Z";
manual = mutateWorkspace(
  manual,
  { type: "deadline", id: key, value: null },
  uuid,
);
assert.equal(
  unifyTasks(snap, manual).find((t) => t.row?.id === school.id)!.dueAt,
  school.dueAt,
);
const now = "2026-10-18T12:00:00Z";
const result = (value: string): ResourceResult[] => [
  {
    courseId: 1,
    kind: "grade",
    status: "success",
    items: [{ id: "1", title: "作业", value }],
  },
];
let changes = recordChanges(
  emptyWorkspace(7),
  result("null"),
  "first",
  now,
  uuid,
);
assert.equal(changes.changes.length, 0);
changes = recordChanges(changes, result("0"), "zero", now, uuid);
assert.equal(changes.changes.length, 1);
changes = recordChanges(
  changes,
  [{ courseId: 1, kind: "grade", status: "failed" }],
  "failed",
  now,
  uuid,
);
changes = recordChanges(changes, result("0"), "again", now, uuid);
assert.equal(changes.changes.length, 1);
changes = recordChanges(changes, result("null"), "withdraw", now, uuid);
assert.equal(changes.changes.length, 2);
changes = recordChanges(
  changes,
  [{ courseId: 1, kind: "grade", status: "success", items: [] }],
  "empty",
  now,
  uuid,
);
assert.equal(changes.changes.length, 2);
assert.equal(changes.baselines["1:grade"]["1"].value, "null");
changes.changes = Array.from({ length: 2100 }, () => ({
  ...changes.changes[0],
  id: uuid(),
}));
assert.equal(recordChanges(changes, [], "", now, uuid).changes.length, 2000);
assert.equal(
  recordChanges(changes, [], "", "2027-10-18T12:00:00Z", uuid).changes.length,
  0,
);
const directory = mkdtempSync(join(tmpdir(), "elearning-workspace-test-")),
  store = new WorkspaceStore(directory);
store.write(data);
assert.equal(store.read(7).series.length, 1);
assert.equal(store.read(8).series.length, 0);
const path = join(directory, "workspace-7.json");
const before = readFileSync(path, "utf8");
mkdirSync(`${path}.bak`);
assert.throws(() => store.write({ ...data, ignored: ["1:1"] }));
assert.equal(readFileSync(path, "utf8"), before);
writeFileSync(join(directory, "workspace-8.json"), "{broken");
assert.throws(() => store.read(8));
const big = emptyWorkspace(7);
big.series = Array.from({ length: 5000 }, (_, i) => ({
  ...base,
  id: String(i),
  repeat: "none",
  createdAt: now,
  exceptions: {},
}));
const started = performance.now();
assert.equal(unifyTasks({ ...snap, assignments: [] }, big).length, 5000);
console.log(`5000 tasks: ${Math.round(performance.now() - started)} ms`);
// The network failure regression must preserve the previous rows and summary.
const previous = buildDemoSnapshot(),
  c = previous.courses[0];
const client = {
  getProfile: async () => previous.profile,
  getCourses: async () => [
    {
      id: c.id,
      name: c.name,
      course_code: c.courseCode,
      workflow_state: "available",
      term: { id: c.termId, name: c.termName },
    },
  ],
  getCourseNicknames: async () => [],
  getAssignmentGroups: async () => [],
  getAssignments: async () => {
    throw Error("offline");
  },
  getTodo: async () => [],
} as unknown as CanvasClient;
const failed = await buildSnapshot(client, { previous, full: true });
assert.deepEqual(
  failed.assignments.map((a) => a.id).sort(),
  previous.assignments
    .filter((a) => a.courseId === c.id)
    .map((a) => a.id)
    .sort(),
);
assert.equal(
  failed.resources?.find((r) => r.kind === "assignment")?.status,
  "failed",
);
assert.equal(failed.courses[0].currentScore, c.currentScore);
console.log(
  "Workspace domain, recurrence parity, persistence, account isolation and failed-sync regressions passed.",
);

const fixtures = JSON.parse(readFileSync(new URL('../fixtures/task-recurrence.json', import.meta.url), 'utf8')) as { name: string; repeat: Series['repeat']; dueAt: string; until: string; weekdays: number[]; expected: string[] }[];
for (const f of fixtures) assert.deepEqual(occurrences({ ...base, ...f, id: f.name, createdAt: now, exceptions: {} }, Date.parse(f.until)).map(o => o.key), f.expected, f.name);
console.log('Shared Swift/TypeScript recurrence fixtures passed.');

const reminderTime = Date.parse('2026-10-18T12:00:00Z');
const reminderTask = { id: 'personal:reminder:single', title: '提醒测试', courseId: null, courseName: '', dueAt: new Date(reminderTime - 60000).toISOString(), completed: false, ignored: false, source: 'personal' as const, draft: { ...base, reminders: [0, 60] } };
const catchup = dueReminders([reminderTask], {}, reminderTime, true);
assert.equal(catchup.due.length, 1); assert.equal(Object.keys(catchup.delivered).length, 2);
assert.equal(dueReminders([reminderTask], catchup.delivered, reminderTime + 1000, true).due.length, 0);
assert.equal(dueReminders([{ ...reminderTask, completed: true }], {}, reminderTime, true).due.length, 0);
assert.equal(dueReminders([{ ...reminderTask, dueAt: new Date(reminderTime - 25 * 3600000).toISOString() }], {}, reminderTime, true).due.length, 0);
assert.equal(dueReminders([reminderTask], {}, reminderTime, false).due.length, 1);
console.log('Resume reminders: 24-hour bound, deduplication, completion and delivery persistence passed.');

const cachedCourseRows = previous.assignments.filter(a => a.courseId === c.id);
const groupFailureClient = { ...client,
  getAssignmentGroups: async () => { throw Error('groups offline'); },
  getAssignments: async () => cachedCourseRows.map(a => ({ id: a.id, course_id: a.courseId, name: a.name, due_at: a.dueAt, points_possible: a.pointsPossible, assignment_group_id: a.groupId, published: true, submission: { score: a.score, grade: a.grade, workflow_state: a.workflowState, submitted_at: a.submittedAt, graded_at: a.gradedAt } }))
} as unknown as CanvasClient;
const groupFailure = await buildSnapshot(groupFailureClient, { previous, full: true });
for (const a of groupFailure.assignments) {
  const cached = cachedCourseRows.find(r => r.id === a.id)!;
  assert.equal(a.groupName, cached.groupName); assert.equal(a.groupWeight, cached.groupWeight);
}
console.log('Assignment group failure preserves cached grade weights.');

// Sources remain optional for every existing task, and persist only a small target.
assert(!('lectureSource' in validateDraft(base)));
const lectureSource = { sourceId: 'source-a', icourseCourseId: '35472', lectureId: 'lecture-1', title: '第三讲：极限' };
const sourceDraft: TaskDraft = { ...base, lectureSource };
let sourced = mutateWorkspace(emptyWorkspace(7), { type: 'save', draft: sourceDraft }, uuid);
assert.deepEqual(sourced.series[0].lectureSource, lectureSource);
assert.deepEqual(occurrences(sourced.series[0], Date.parse('2024-02-29T13:00:00+08:00'))[1].draft.lectureSource, lectureSource);
sourced = mutateWorkspace(sourced, { type: 'save', seriesId: sourced.series[0].id, key: '2024-02-29', scope: 'one', draft: { ...sourceDraft, title: '仅本次修改' } }, uuid);
assert.deepEqual(sourced.series[0].exceptions['2024-02-29'].draft?.lectureSource, lectureSource);
const sourceStore = new WorkspaceStore(mkdtempSync(join(tmpdir(), 'elearning-lecture-task-test-')));
sourceStore.write(sourced);
assert.deepEqual(sourceStore.read(7).series[0].lectureSource, lectureSource);
assert.equal(sourceStore.read(8).series.length, 0);
for (const invalid of [null, {}, { ...lectureSource, sourceId: '' }, { ...lectureSource, lectureId: 42 }, { ...lectureSource, icourseCourseId: 'x'.repeat(300) }, { ...lectureSource, title: ' ' }]) {
  assert.throws(() => validateDraft({ ...base, lectureSource: invalid } as unknown as TaskDraft), /课堂笔记来源无效/);
}
assert.deepEqual(validateDraft({ ...base, lectureSource: { ...lectureSource, password: 'must-not-persist' } } as TaskDraft).lectureSource, lectureSource);
assert.deepEqual(validateDraft(JSON.parse(JSON.stringify(base))), validateDraft(base));

// The same local course may bind several remote courses. Rebinding uses a new
// generation, so neither another source's baseline nor its events are replaced.
const fingerprintA = 'a'.repeat(64), fingerprintB = 'b'.repeat(64);
const lectureResult = (namespace: string, fingerprint = fingerprintA): ResourceResult[] => [{
  courseId: 1, kind: 'lecture', status: 'success', baselineKey: namespace,
  items: [{ id: JSON.stringify(['source-a', '35472', 'lecture-1']), title: lectureSource.title, value: fingerprint }],
}];
let lectureChanges = recordChanges(emptyWorkspace(7), lectureResult('source-a:35472:g1'), 'first', now, uuid);
assert.equal(lectureChanges.changes.length, 0);
lectureChanges = recordChanges(lectureChanges, lectureResult('source-a:35472:g1', fingerprintB), 'updated', now, uuid);
assert.equal(lectureChanges.changes.length, 1);
assert.equal(lectureChanges.changes[0].after, fingerprintB);
assert.equal(lectureChanges.changes[0].before, fingerprintA);
const savedLectureChange = { ...lectureChanges.changes[0] };
lectureChanges = recordChanges(lectureChanges, lectureResult('source-b:35472:g1', fingerprintB), 'other-source', now, uuid);
lectureChanges = recordChanges(lectureChanges, lectureResult('source-a:35472:g2', fingerprintB), 'rebound', now, uuid);
assert.equal(lectureChanges.changes.length, 1);
assert.deepEqual(lectureChanges.changes[0], savedLectureChange);
assert.equal(Object.keys(lectureChanges.baselines).length, 3);
lectureChanges = recordChanges(lectureChanges, [{ courseId: 1, kind: 'lecture', baselineKey: 'source-a:35472:g2', status: 'failed' }], 'offline', now, uuid);
lectureChanges = recordChanges(lectureChanges, lectureResult('source-a:35472:g2', fingerprintB), 'recovered', now, uuid);
assert.equal(lectureChanges.changes.length, 1);
assert.throws(() => recordChanges(lectureChanges, lectureResult('source-a:35472:g2', 'full private lecture text'), 'invalid', now, uuid), /只接受摘要指纹/);
assert.equal(lectureChanges.baselines['1:lecture:source-a:35472:g2'][JSON.stringify(['source-a', '35472', 'lecture-1'])].value, fingerprintB);
console.log('Lecture task sources, legacy tasks, account persistence, isolated binding baselines and fingerprint-only changes passed.');
