import { useClock } from "./useClock";
import { htmlToPlainText } from "../../core/summary";
import { useEffect, useMemo, useRef, useState } from "react";
import type { Snapshot } from "../../core/types";
import {
  dayKey,
  unifyTasks,
  type TaskView,
  type WorkspaceCommand,
  type WorkspaceData,
  type TaskDraft,
} from "../../core/workspace";
import { parseLectureKey, type LectureRef } from "../../core/lectures";
import { asyncView } from "./AsyncView";
const CourseOverview = asyncView(() => import("./CourseContent").then(m=>({default:m.CourseOverview})));
const LectureReader = asyncView(() => import("./CourseContent").then(m=>({default:m.LectureReader})));
const LectureSettings = asyncView(() => import("./CourseContent").then(m=>({default:m.LectureSettings})));
const Settings = asyncView(() => import("./Settings").then(m=>({default:m.Settings})));
const GradeDetails = asyncView(() => import("./CourseGrades").then(m=>({default:m.GradeDetails})));
const CourseScoreChart = asyncView(() => import("./components/charts").then(m=>({default:m.CourseScoreChart})));
import type { Prefs } from "../../preload/index.d";
import LoginView from "./components/LoginView";
import AssignmentDetail from "./components/AssignmentDetail";
import CourseFiles from "./components/CourseFiles";

import { formatDate } from "./util";
import {
  TaskEditor,
  DeleteDialog,
  Calendar,
  Deadline,
} from "./WorkspaceParts";
import "./workspace.css";
import "./interaction.css";
import { Surface } from "./Interaction";
type Page = "today" | "tasks" | "changes" | "courses" | "settings";
const pages: [Page, string, string][] = [
  ["today", "今日", "☀"],
  ["tasks", "任务", "☑"],
  ["changes", "变化中心", "◷"],
  ["courses", "课程", "▤"],
];
const kinds = {
  assignment: "作业",
  grade: "成绩",
  announcement: "公告",
  file: "文件",
  lecture: "课堂笔记",
};
const courseTabs = [["overview", "概览"], ["lectures", "课堂笔记"], ["assignments", "作业"], ["grades", "成绩"], ["files", "文件"]];
export default function App() {
  const now = useClock();
  const [snapshot, setSnapshot] = useState<Snapshot | null>(null),
    [data, setData] = useState<WorkspaceData | null>(null),
    [prefs, setPrefs] = useState<Prefs | null>(null),
    [login, setLogin] = useState(false);
  const [page, setPage] = useState<Page>("today"),
    [term, setTerm] = useState("all"),
    [query, setQuery] = useState(""),
    [source, setSource] = useState("all"),
    [status, setStatus] = useState("pending"),
    [course, setCourse] = useState("all");
  const [selected, setSelected] = useState(""),
    [checked, setChecked] = useState<Set<string>>(new Set()),
    [tab, setTab] = useState("overview"),
    [calendar, setCalendar] = useState(false),
    [month, setMonth] = useState(dayKey(now).slice(0, 7));
  const [unread, setUnread] = useState(false),
    [kind, setKind] = useState("all"),
    [batch, setBatch] = useState(""),
    [error, setError] = useState(""),
    [busy, setBusy] = useState(false),
    [saving, setSaving] = useState(false),
    [progress, setProgress] = useState("");
  const [editor, setEditor] = useState<{ task?: TaskView; initialDraft?: TaskDraft } | null>(null),
    [deleting, setDeleting] = useState<TaskView[] | null>(null),
    [width, setDetailWidth] = useState(420),
    [limit, setLimit] = useState(100);
  const [notice, setNotice] = useState<{ text: string; undo?: WorkspaceCommand; taskId?: string } | null>(null);
  const [reader, setReader] = useState<{ courseId: number; ref?: LectureRef; previousTab: string } | null>(null);
  const readerFocus = useRef<HTMLElement | null>(null);
  const [operation, setOperation] = useState("");
  const [retry, setRetry] = useState<WorkspaceCommand | null>(null);
  const [finishing, setFinishing] = useState<Set<string>>(new Set());
  const [exiting, setExiting] = useState(false);
  const timers = useRef<ReturnType<typeof setTimeout>[]>([]);
  const syncLock = useRef(false);
  const prefsLock = useRef(false);
  const [prefsSaving, setPrefsSaving] = useState(false);
  const lastSaved = useRef<WorkspaceData | null>(null);
  const viewEpoch = useRef(0);
  const contentAnimation = useRef<Animation | null>(null);
  useEffect(() => {
    if (!selected || innerWidth >= 960) return;
    const frame = requestAnimationFrame(() => document.querySelector<HTMLElement>(".ws-detail-toolbar button")?.focus({ preventScroll: true }));
    return () => cancelAnimationFrame(frame);
  }, [selected]);
  useEffect(() => () => { timers.current.forEach(clearTimeout); contentAnimation.current?.cancel(); }, []);
  useEffect(() => {
    viewEpoch.current++;
    timers.current.forEach(clearTimeout);
    timers.current = [];
    setFinishing(new Set()); setExiting(false);
  }, [page, snapshot?.profile.id, status, source, query, course, term]);
  useEffect(() => { setNotice(null); setRetry(null); setOperation(""); setReader(null); }, [snapshot?.profile.id]);
  useEffect(() => {
    contentAnimation.current?.cancel();
    if (!matchMedia("(prefers-reduced-motion: reduce)").matches && list.current)
      contentAnimation.current = list.current.animate([{ opacity: .3 }, { opacity: 1 }], { duration: 180, easing: "ease-out" });
    return () => contentAnimation.current?.cancel();
  }, [page, calendar]);
  const search = useRef<HTMLInputElement>(null),
    focus = useRef<HTMLElement | null>(null),
    account = useRef<number | null>(null),
    lock = useRef(false),
    list = useRef<HTMLDivElement>(null),
    positions = useRef<Record<string, number>>({}),
    queries = useRef<Record<string, string>>({});
  const [dark, setSystemDark] = useState(
    matchMedia("(prefers-color-scheme: dark)").matches,
  );
  const theme = prefs?.followSystem
    ? dark
      ? "dark"
      : "light"
    : (prefs?.theme ?? "light");
  useEffect(() => {
    const m = matchMedia("(prefers-color-scheme: dark)");
    const f = () => setSystemDark(m.matches);
    m.addEventListener("change", f);
    return () => m.removeEventListener("change", f);
  }, []);
  useEffect(() => {
    document.documentElement.dataset.theme = theme;
  }, [theme]);
  async function load(s: Snapshot) {
    account.current = s.profile.id;
    const r = await window.elearning.workspace.get(s.profile.id);
    if (account.current !== s.profile.id) return;
    if (r.ok) setData(r.data);
    else {
      setData(null);
      setError(r.error.message);
    }
  }
  async function refresh(full = true) {
    if (syncLock.current) return;
    const initialAccount = account.current;
    syncLock.current = true;
    setBusy(true);
    setError("");
    try {
      const r = await window.elearning.data.snapshot({ force: true, full });
      if (!r.ok) throw Error(r.error.message);
      if (account.current !== initialAccount) return;
      setSnapshot(r.data);
      await load(r.data);
      setNotice({ text: r.data.warnings.length ? "同步完成，部分内容未更新，请查看详情。" : "同步完成" });
    } catch (e) {
      if (account.current !== initialAccount) return;
      setError(`${String(e)}。可继续使用本地任务，或重试同步。`);
    } finally {
      syncLock.current = false;
      setBusy(false);
      setProgress("");
    }
  }
  useEffect(() => {
    void (async () => {
      try {
        setPrefs(await window.elearning.prefs.get());
        const s = await window.elearning.data.cached();
        if (s) {
          setSnapshot(s);
          await load(s);
          setTerm(String(s.terms.find((t) => t.isCurrent)?.id ?? "all"));
        }
        const a = await window.elearning.auth.status();
        if (a.ok && a.data.loggedIn) await refresh(false);
        else if (!s) setLogin(true);
      } catch (e) {
        setError(String(e));
        setLogin(true);
      }
    })();
    const a = window.elearning.data.onProgress((p) =>
      setProgress(`${p.done}/${p.total} ${p.label}`),
    );
    const b = window.elearning.workspace.onUpdated(() => {
      void window.elearning.data.cached().then((s) => {
        if (s) {
          setSnapshot(s);
          void load(s);
        }
      });
    });
    const c = window.elearning.workspace.onNavigate((t) => {
      if (t.error) setError(t.error);
      if (t.page) {
        setPage(t.page as Page);
        setSelected(t.task ?? "");
        setBatch(t.batch ?? "");
        setStatus("all");
        setTerm("all");
        setCourse("all");
        setSource("all");
        setQuery("");
        setUnread(false);
        setKind("all");
        if (t.task?.match(/\d{4}-\d{2}-\d{2}$/))
          setMonth(t.task.slice(-10, -3));
        if (t.lecture) {
          const ref = parseLectureKey(t.lecture);
          if (ref) void openLectureTarget(ref);
        }
      }
    });
    return () => {
      a();
      b();
      c();
    };
  }, []);
  async function mutate(command: WorkspaceCommand) {
    if (!snapshot || !data || lock.current) return false;
    lock.current = true;
    setSaving(true);
    setError("");
    setRetry(null);
    setOperation("正在保存…");
    const id = snapshot.profile.id;
    const originView = viewEpoch.current;
    try {
      const r = await window.elearning.workspace.mutate(id, command);
      if (!r.ok) throw Error(r.error.message);
      if (account.current !== id) return false;
      setData(r.data);
      lastSaved.current = r.data;
      if (viewEpoch.current === originView) setOperation(command.type === "read" ? `已将 ${command.ids.length} 项变化标为已读` : command.type === "ignore" ? `已更新 ${command.ids.length} 项作业状态` : "已保存");
      if (command.type === "read" || command.type === "ignore") setChecked(new Set());
      return true;
    } catch (e) {
      if (account.current !== id) return false;
      if (viewEpoch.current !== originView) return false;
      setError(`保存失败：${e instanceof Error ? e.message : String(e)}，请重试。`);
      setRetry(command);
      setOperation("保存失败，原有数据已保留");
      return false;
    } finally {
      lock.current = false;
      setSaving(false);
    }
  }
  async function complete(items: TaskView[], completed: boolean) {
    if (lock.current) return;
    timers.current.forEach(clearTimeout); timers.current = [];
    const id = account.current;
    const epoch = viewEpoch.current;
    const pending = new Set(items.map(t => t.id));
    // Keep affected rows until persistence and their short exit have finished.
    setFinishing(pending); setExiting(false);
    if (!await mutate({ type: "complete", items: refs(items), completed })) {
      setFinishing(new Set()); return;
    }
    if (account.current !== id || viewEpoch.current !== epoch) return;
    setNotice({ text: completed ? `已完成 ${items.length} 项任务` : `已恢复 ${items.length} 项任务`,
      undo: { type: "complete", items: refs(items.filter(t => t.completed !== completed)), completed: !completed } });
    setChecked(old => new Set([...old].filter(key => !pending.has(key))));
    const hidden = completed && (page === "today" || status === "pending" || status === "overdue");
    if (!hidden) { setFinishing(new Set()); return; }
    const delay = matchMedia("(prefers-reduced-motion: reduce)").matches ? 0 : 350;
    timers.current.push(setTimeout(() => {
      setExiting(true);
      timers.current.push(setTimeout(() => {
        const active = document.activeElement;
        const affected = [...(list.current?.querySelectorAll<HTMLElement>("[data-task-id]") ?? [])]
          .filter(el => pending.has(el.dataset.taskId!));
        if (affected.some(el => el.contains(active))) {
          const rows = [...(list.current?.querySelectorAll<HTMLElement>("[data-task-id]") ?? [])];
          const first = rows.findIndex(el => pending.has(el.dataset.taskId!));
          const next = rows.slice(first + 1).find(el => !pending.has(el.dataset.taskId!))
            ?? rows.slice(0, first).reverse().find(el => !pending.has(el.dataset.taskId!));
          (next?.querySelector<HTMLElement>(".ws-row-main") ?? search.current)?.focus({ preventScroll: true });
        }
        setFinishing(new Set()); setExiting(false);
      }, delay ? 200 : 0));
    }, delay));
  }
  async function savePrefs(p: Partial<Prefs>) {
    if (prefsLock.current) return;
    prefsLock.current = true; setPrefsSaving(true); setOperation("正在保存设置…");
    try {
      setPrefs(await window.elearning.prefs.set(p));
      setOperation("设置已保存");
    } catch (e) {
      setError(`设置保存失败：${String(e)}`);
      setOperation("设置保存失败，请再次操作重试");
    } finally { prefsLock.current = false; setPrefsSaving(false); }
  }
  function close() {
    if (reader) { closeReader(); return; }
    setSelected("");
    requestAnimationFrame(() => {
      if (list.current) list.current.scrollTop = positions.current[page] ?? 0;
      (focus.current?.isConnected ? focus.current : search.current)?.focus({ preventScroll: true });
    });
  }
  function open(id: string) {
    focus.current = document.activeElement as HTMLElement;
    if (
      list.current &&
      getComputedStyle(list.current.parentElement!).display !== "none"
    )
      positions.current[page] = list.current.scrollTop;
    setSelected(id);
    if (id.startsWith("course:") && selected !== id) setTab("overview");
  }
  function startReading(courseId: number, ref?: LectureRef) {
    readerFocus.current = document.activeElement as HTMLElement;
    setReader({ courseId, ref, previousTab: tab === "lectures" ? "overview" : tab });
    setSelected(`course:${courseId}`);
    setPage("courses");
  }
  function closeReader() {
    if (!reader) return;
    setTab(reader.previousTab);
    setReader(null);
    requestAnimationFrame(() => {
      const trigger = readerFocus.current;
      const usable = trigger?.isConnected && trigger.getClientRects().length && trigger.matches('button,a[href],input,select,textarea,[tabindex]');
      (usable ? trigger : document.querySelector<HTMLElement>('.ws-course-tabs [aria-selected="true"]'))?.focus({ preventScroll: true });
    });
  }
  async function openLectureTarget(ref: LectureRef) {
    const id = account.current;
    if (!id) return;
    const result = await window.elearning.lectures.state(id);
    if (id !== account.current) return;
    if (!result.ok) { setError(result.error.message); return; }
    const binding = result.data.bindings.find(b => b.icourseCourseId === ref.icourseCourseId);
    if (result.data.sourceId !== ref.sourceId || !binding) {
      setError("此笔记来源已断开或课程关联已调整，请在课堂笔记设置中检查。"); return;
    }
    const cached = await window.elearning.data.cached();
    if (id !== account.current) return;
    if (!cached?.courses.some(c => c.id === binding.canvasCourseId)) {
      setError("当前课程列表中已没有这门课，请同步历史课程后再打开。"); return;
    }
    startReading(binding.canvasCourseId, ref);
  }
  function go(p: Page) {
    setReader(null);
    setNotice(null); setOperation(""); setRetry(null); setError("");
    positions.current[page] = list.current?.scrollTop ?? 0;
    queries.current[page] = query;
    setPage(p);
    setQuery(queries.current[p] ?? "");
    setSelected("");
    setChecked(new Set());
    setBatch("");
    requestAnimationFrame(() => {
      if (list.current) list.current.scrollTop = positions.current[p] ?? 0;
    });
  }
  useEffect(() => {
    const f = (e: KeyboardEvent) => {
      if (document.querySelector("dialog[open]")) return;
      if (e.key === "Escape" && !e.defaultPrevented) {
        if (selected) close();
        else setChecked(new Set());
      }
      if (
        (e.target as HTMLElement).closest(
          'input,textarea,select,[contenteditable="true"]',
        ) ||
        !e.ctrlKey ||
        e.altKey ||
        e.metaKey
      )
        return;
      const k = e.key.toLowerCase();
      if (["n", "f", "r"].includes(k)) e.preventDefault();
      if (k === "n") setEditor({});
      if (k === "f") (reader ? document.querySelector<HTMLInputElement>('[aria-label="搜索课次"]') : search.current)?.focus();
      if (k === "r" && !busy) void refresh();
    };
    window.addEventListener("keydown", f);
    return () => window.removeEventListener("keydown", f);
  }, [selected, busy, reader]);
  const horizon = useMemo(
    () =>
      Math.max(
        now + 90 * 86400000,
        Date.parse(`${month}-01T00:00:00+08:00`) + 32 * 86400000,
      ),
    [month, now],
  );
  const tasks = useMemo(
    () => (snapshot && data ? unifyTasks(snapshot, data, horizon) : []),
    [snapshot, data, horizon],
  );
  const courses = useMemo(
    () =>
      snapshot?.courses.filter(
        (c) => term === "all" || String(c.termId) === term,
      ) ?? [],
    [snapshot, term],
  );
  const courseIds = useMemo(() => new Set(courses.map((c) => c.id)), [courses]);
  const filtered = useMemo(
    () =>
      tasks.filter(
        (t) =>
          (t.courseId === null || courseIds.has(t.courseId)) &&
          (source === "all" || source === t.source) &&
          (course === "all" || String(t.courseId) === course) &&
          `${t.title} ${t.courseName} ${t.draft?.notes ?? ""}`
            .toLowerCase()
            .includes(query.toLowerCase()) &&
          (finishing.has(t.id) || status === "all" ||
            (status === "pending"
              ? !t.completed && !t.ignored
              : status === "completed"
                ? t.completed
                : status === "ignored"
                  ? t.ignored
                  : !t.completed &&
                    !t.ignored &&
                    !!t.dueAt &&
                    Date.parse(t.dueAt) < now)),
      ),
    [tasks, courseIds, source, course, query, status, finishing, now],
  );
  const changes = useMemo(
    () =>
      data?.changes.filter(
        (c) =>
          courseIds.has(c.courseId) &&
          (!unread || !c.read) &&
          (kind === "all" || kind === c.kind) &&
          (course === "all" || String(c.courseId) === course) &&
          (!batch || c.batch === batch) &&
          c.title.toLowerCase().includes(query.toLowerCase()),
      ) ?? [],
    [data, courseIds, unread, kind, course, batch, query],
  );
  const taskIndex = useMemo(
    () => new Map(tasks.map((t) => [t.id, t])),
    [tasks],
  );
  const task = taskIndex.get(selected),
    change = data?.changes.find((c) => c.id === selected),
    chosenCourse = snapshot?.courses.find((c) => `course:${c.id}` === selected),
    chosenTasks = [...checked]
      .map((id) => taskIndex.get(id))
      .filter((t): t is TaskView => !!t);
  const refs = (items: TaskView[]) =>
    items.map((t) => ({ seriesId: t.seriesId!, key: t.key! }));
  function toggle(id: string) {
    setChecked((old) => {
      const next = new Set(old);
      next.has(id) ? next.delete(id) : next.add(id);
      return next;
    });
  }
  useEffect(() => {
    setLimit(100);
    setChecked(new Set());
  }, [page, query, source, course, status, term, unread, kind, batch]);
  function row(t: TaskView, selectable = true) {
    return (
      <div data-task-id={t.id} className={`ws-row ${selected === t.id ? "chosen" : ""} ${t.completed ? "is-completed" : ""} ${finishing.has(t.id) && exiting ? "is-exiting" : ""}`} key={t.id}>
        {selectable && (
          <input
            type="checkbox"
            aria-label={`选择 ${t.title}`}
            checked={checked.has(t.id)}
            onChange={() => toggle(t.id)}
          />
        )}
        {t.source === "personal" && <input type="checkbox" aria-label={`完成 ${t.title}`} checked={t.completed}
          disabled={saving || finishing.has(t.id)} onChange={() => void complete([t], !t.completed)} />}
        <button className="ws-row-main" onClick={() => open(t.id)}>
          <strong>{t.title}</strong>
          <span>
            {t.courseName} · {t.source === "personal" ? "个人任务" : "学校作业"}
          </span>
        </button>
        <div
          className={`ws-row-date ${!t.completed && !t.ignored && t.dueAt && Date.parse(t.dueAt) < now ? "overdue" : ""}`}
        >
          <span>{t.dueAt ? formatDate(t.dueAt) : "无截止时间"}</span>
          <small>
            {t.ignored ? "— 无需提交" : t.completed ? "✓ 已完成" : "○ 待处理"}
          </small>
        </div>
      </div>
    );
  }
  const groups = useMemo(() => {
    const today = dayKey(now),
      week = dayKey(now + 7 * 86400000),
      active = tasks.filter(
        (t) =>
          (!t.completed || finishing.has(t.id)) &&
          !t.ignored &&
          (t.courseId === null || courseIds.has(t.courseId)) &&
          t.title.includes(query),
      );
    return [
      ["今天截止", active.filter((t) => t.dueAt && dayKey(t.dueAt) === today)],
      [
        "未来七天",
        active.filter(
          (t) => t.dueAt && dayKey(t.dueAt) > today && dayKey(t.dueAt) <= week,
        ),
      ],
      ["逾期任务", active.filter((t) => t.dueAt && dayKey(t.dueAt) < today)],
    ] as [string, TaskView[]][];
  }, [tasks, courseIds, query, finishing, now]);
  if (login)
    return (
      <LoginView
        theme={theme}
        notice={error}
        onToggleTheme={() =>
          void savePrefs({
            theme: theme === "dark" ? "light" : "dark",
            followSystem: false,
          })
        }
        onSuccess={() => {
          setLogin(false);
          setSnapshot(null);
          setData(null);
          void refresh();
        }}
      />
    );
  if (!snapshot || !prefs)
    return (
      <div className="ws-loading">
        正在加载学习工作区…
        {error && (
          <p role="alert">
            {error}
            <button onClick={() => setLogin(true)}>重新登录</button>
          </p>
        )}
      </div>
    );
  return (
    <div
      className="workspace"
      style={{ "--detail-width": `${width}px` } as React.CSSProperties}
    >
      <nav className="ws-nav" aria-label="主导航">
        <div className="ws-brand">
          <b>复旦</b>
          <span>eLearning</span>
        </div>
        <div className="ws-nav-links">
          {page !== "settings" && <span className="ws-nav-marker" aria-hidden style={{ transform: `translateY(${pages.findIndex(p => p[0] === page) * 47}px)` }} />}
          {pages.map(([id, label, icon]) => (
            <button
              key={id}
              title={label}
              aria-current={page === id ? "page" : undefined}
              className={page === id ? "active" : ""}
              onClick={() => go(id)}
            >
              <i aria-hidden>{icon}</i>
              <span>{label}</span>
              {id === "changes" && !!data?.changes.some((c) => !c.read) && (
                <small>{data.changes.filter((c) => !c.read).length}</small>
              )}
            </button>
          ))}
        </div>
        <div className="ws-nav-bottom">
          <label className="ws-term">
            <span>学期</span>
            <select
              aria-label="学期"
              value={term}
              onChange={(e) => setTerm(e.target.value)}
            >
              <option value="all">全部学期</option>
              {snapshot.terms.map((t) => (
                <option key={String(t.id)} value={String(t.id)}>
                  {t.name}
                </option>
              ))}
            </select>
          </label>
          <button title="设置" onClick={() => go("settings")}>
            <i aria-hidden>⚙</i>
            <span>设置</span>
          </button>
          <div className="ws-sync">
            <span>{busy ? "正在同步…" : "最近同步"}</span>
            <time>{formatDate(snapshot.fetchedAt)}</time>
          </div>
          <div className="ws-account" title={snapshot.profile.name}>
            <b>{snapshot.profile.name.slice(0, 1)}</b>
            <span>{snapshot.profile.name}</span>
          </div>
        </div>
      </nav>
      <main className="ws-main">
        <header className="ws-toolbar">
          <h1>{pages.find((p) => p[0] === page)?.[1] ?? "设置"}</h1>
          {page !== "settings" && !reader && (
            <input
              ref={search}
              type="search"
              aria-label="搜索当前页面"
              placeholder="搜索当前页面  Ctrl+F"
              value={query}
              onChange={(e) => setQuery(e.target.value)}
            />
          )}
          <button
            disabled={busy}
            aria-busy={busy}
            title="全量同步，包括历史课程（Ctrl+R）"
            onClick={() => void refresh()}
          >
            {busy ? "同步中…" : "同步"}
          </button>
          <button
            className="primary"
            disabled={!data}
            onClick={() => setEditor({})}
          >
            ＋ 新建任务
          </button>
        </header>
        {error && !editor && !deleting && (
          <div className="ws-alert" role="alert">
            {error}
            {!error.startsWith("设置保存失败") && !editor && !deleting && <button disabled={saving || busy} onClick={() => retry ? void mutate(retry) : void refresh()}>{retry ? "重试保存" : "重试同步"}</button>}
            <button aria-label="关闭提示" onClick={() => setError("")}>
              ×
            </button>
          </div>
        )}
        {progress && (
          <div className="ws-status" role="status">
            {progress}
          </div>
        )}
        <div className="ws-live" role="status" aria-live="polite">{operation}</div>
        {operation && <div className="ws-status ws-operation" data-busy={saving || prefsSaving}>{saving ? "正在保存…" : operation}</div>}
        {!!snapshot.warnings.length && (
          <details className="ws-warning">
            <summary>部分内容未更新（{snapshot.warnings.length}）</summary>
            {snapshot.warnings.map((w, i) => (
              <p key={i}>{w}</p>
            ))}
          </details>
        )}
        {page === "settings" ? (
          <div className="ws-settings-scroll">
          <LectureSettings account={snapshot.profile.id} courses={snapshot.courses} />
          <Settings
            prefs={prefs}
            saving={prefsSaving}
            save={savePrefs}
            onLogout={async () => {
              const r = await window.elearning.auth.logout();
              if (r.ok) {
                account.current = null;
                setEditor(null); setDeleting(null); setSelected(""); setError(""); setOperation(""); setRetry(null); setNotice(null);
                setSnapshot(null);
                setData(null);
                setLogin(true);
              } else setError(r.error.message);
            }}
          />
          </div>
        ) : (
          <div className={`ws-panes ${selected ? "has-detail" : ""}`} style={reader && page === "courses" ? { display: "none" } : undefined}>
            <section className="ws-list-pane" aria-label="列表">
              {page === "tasks" && (
                <div className="ws-filters">
                  <select
                    aria-label="任务来源"
                    value={source}
                    onChange={(e) => setSource(e.target.value)}
                  >
                    <option value="all">全部来源</option>
                    <option value="school">学校作业</option>
                    <option value="personal">个人任务</option>
                  </select>
                  <select
                    aria-label="任务状态"
                    value={status}
                    onChange={(e) => setStatus(e.target.value)}
                  >
                    {[
                      ["pending", "待处理"],
                      ["all", "全部状态"],
                      ["completed", "已完成"],
                      ["overdue", "逾期"],
                      ["ignored", "无需提交"],
                    ].map(([v, l]) => (
                      <option key={v} value={v}>
                        {l}
                      </option>
                    ))}
                  </select>
                  <button
                    aria-pressed={calendar}
                    onClick={() => setCalendar(!calendar)}
                  >
                    {calendar ? "列表" : "月历"}
                  </button>
                </div>
              )}
              {page === "changes" && (
                <div className="ws-filters">
                  <label>
                    <input
                      type="checkbox"
                      checked={unread}
                      onChange={(e) => setUnread(e.target.checked)}
                    />
                    仅未读
                  </label>
                  <select
                    aria-label="变化类型"
                    value={kind}
                    onChange={(e) => setKind(e.target.value)}
                  >
                    <option value="all">全部类型</option>
                    {Object.entries(kinds).map(([v, l]) => (
                      <option key={v} value={v}>
                        {l}
                      </option>
                    ))}
                  </select>
                  <button
                    disabled={saving || !changes.some((c) => !c.read)}
                    onClick={() =>
                      void mutate({
                        type: "read",
                        ids: changes.map((c) => c.id),
                      })
                    }
                  >
                    本筛选全部已读
                  </button>
                  {batch && (
                    <button onClick={() => setBatch("")}>取消批次筛选</button>
                  )}
                </div>
              )}
              {(page === "tasks" || page === "changes") && (
                <div className="ws-filters">
                  <select
                    aria-label="课程筛选"
                    value={course}
                    onChange={(e) => setCourse(e.target.value)}
                  >
                    <option value="all">全部课程</option>
                    {courses.map((c) => (
                      <option key={c.id} value={c.id}>
                        {c.displayName}
                      </option>
                    ))}
                  </select>
                  <span>
                    {page === "tasks" ? filtered.length : changes.length} 项
                  </span>
                </div>
              )}
              {checked.size > 0 && (
                <div className="ws-bulk">
                  <span>已选 {checked.size} 项</span>
                  {page === "changes" ? (
                    <button
                      disabled={saving}
                      onClick={() =>
                        void mutate({ type: "read", ids: [...checked] })
                      }
                    >
                      标为已读
                    </button>
                  ) : (
                    <>
                      {chosenTasks.length > 0 &&
                        chosenTasks.every((t) => t.source === "personal") && (
                          <>
                            <button
                              disabled={saving}
                              onClick={() =>
                                void complete(chosenTasks, true)
                              }
                            >
                              完成
                            </button>
                            <button onClick={() => setDeleting(chosenTasks)}>
                              删除
                            </button>
                          </>
                        )}
                      {chosenTasks.length > 0 &&
                        chosenTasks.every((t) => t.source === "school") && (
                          <button
                            disabled={saving}
                            onClick={() =>
                              void mutate({
                                type: "ignore",
                                ids: chosenTasks.map(
                                  (t) => `${t.row!.courseId}:${t.row!.id}`,
                                ),
                                ignored: true,
                              })
                            }
                          >
                            无需提交
                          </button>
                        )}
                    </>
                  )}
                  <button onClick={() => setChecked(new Set())}>
                    取消选择
                  </button>
                </div>
              )}
              <div className="ws-list-scroll" ref={list}>
                {page === "today" && (
                  <>
                    <div className="ws-intro">
                      <span>
                        {new Date(now).toLocaleDateString("zh-CN", {
                          month: "long",
                          day: "numeric",
                          weekday: "long",
                        })}
                      </span>
                      <h2>从今天要做的事开始</h2>
                      <p>
                        今天 {groups[0][1].length} 项 · 未来七天{" "}
                        {groups[1][1].length} 项
                      </p>
                    </div>
                    {groups.map(([title, items], i) =>
                      i === 2 ? (
                        <details key={title}>
                          <summary className="ws-group overdue">
                            {title}（{items.length}）
                          </summary>
                          {items.slice(0, limit).map((t) => row(t, false))}
                          {items.length > limit && (
                            <button onClick={() => setLimit(limit + 100)}>
                              加载更多
                            </button>
                          )}
                        </details>
                      ) : (
                        <section key={title}>
                          <h2 className="ws-group">{title}</h2>
                          {items.slice(0, limit).map((t) => row(t, false))}
                          {!items.length && (
                            <p className="ws-empty">没有到期任务。</p>
                          )}
                          {items.length > limit && (
                            <button onClick={() => setLimit(limit + 100)}>
                              加载更多
                            </button>
                          )}
                        </section>
                      ),
                    )}
                    <h2 className="ws-group">最近变化</h2>
                    {data?.changes.slice(0, 5).map((c) => (
                      <button
                        className="ws-change-short"
                        key={c.id}
                        onClick={() => {
                          setPage("changes");
                          open(c.id);
                        }}
                      >
                        {!c.read && "● "}
                        {c.title}
                        <small>
                          {kinds[c.kind]} · {formatDate(c.at)}
                        </small>
                      </button>
                    ))}
                    {!data?.changes.length && (
                      <p className="ws-empty">
                        首次同步建立基线，后续更新将显示在这里。
                      </p>
                    )}
                  </>
                )}
                {page === "tasks" &&
                  (calendar ? (
                    <Calendar
                      tasks={filtered}
                      month={month}
                      setMonth={setMonth}
                      onOpen={open}
                    />
                  ) : (
                    <>
                      {filtered.slice(0, limit).map((t) => row(t))}
                      {!filtered.length && (
                        <p className="ws-empty">
                          没有符合筛选的任务，可切换状态或新建个人任务。
                        </p>
                      )}
                      {filtered.length > limit && (
                        <button
                          className="ws-more"
                          onClick={() => setLimit(limit + 100)}
                        >
                          加载后 100 项（共 {filtered.length} 项）
                        </button>
                      )}
                    </>
                  ))}
                {page === "changes" && (
                  <>
                    {changes.slice(0, limit).map((c) => (
                      <div
                        className={`ws-row ${selected === c.id ? "chosen" : ""}`}
                        key={c.id}
                      >
                        <input
                          type="checkbox"
                          aria-label={`选择变化 ${c.title}`}
                          checked={checked.has(c.id)}
                          onChange={() => toggle(c.id)}
                        />
                        <button
                          className="ws-row-main"
                          onClick={() => open(c.id)}
                        >
                          <strong>
                            {!c.read && "● "}
                            {c.title}
                          </strong>
                          <span>
                            {kinds[c.kind]} ·{" "}
                            {c.before === null ? "新增" : "修改"} ·{" "}
                            {formatDate(c.at)}
                          </span>
                        </button>
                      </div>
                    ))}
                    {!changes.length && (
                      <p className="ws-empty">
                        没有符合条件的变化。首次同步只建立基线。
                      </p>
                    )}
                    {changes.length > limit && (
                      <button onClick={() => setLimit(limit + 100)}>
                        加载更多变化
                      </button>
                    )}
                  </>
                )}
                {page === "courses" && (
                  <>
                    <button
                      className="ws-overview"
                      onClick={() => open("grades")}
                    >
                      跨课程成绩概览
                    </button>
                    {courses
                      .filter((c) =>
                        c.displayName
                          .toLowerCase()
                          .includes(query.toLowerCase()),
                      )
                      .map((c) => (
                        <div
                          className={`ws-row ${selected === `course:${c.id}` ? "chosen" : ""}`}
                          key={c.id}
                        >
                          <button
                            className="ws-row-main"
                            onClick={() => open(`course:${c.id}`)}
                          >
                            <strong>{c.displayName}</strong>
                            <span>
                              {c.courseCode} · {c.termName}
                            </span>
                          </button>
                          <div className="ws-row-date">
                            <b>
                              {c.currentScore === null
                                ? "—"
                                : `${c.currentScore.toFixed(1)}%`}
                            </b>
                            <small>{c.assignmentCount} 项作业</small>
                          </div>
                        </div>
                      ))}
                  </>
                )}
              </div>
            </section>
            {selected && (
              <>
                <div
                  className="ws-resizer"
                  role="separator"
                  aria-label="调整详情宽度"
                  aria-orientation="vertical"
                  tabIndex={0}
                  aria-valuenow={width}
                  aria-valuemin={320}
                  aria-valuemax={620}
                  onKeyDown={(e) => {
                    if (["ArrowLeft", "ArrowRight"].includes(e.key)) {
                      e.preventDefault();
                      setDetailWidth((w) =>
                        Math.max(
                          320,
                          Math.min(620, w + (e.key === "ArrowLeft" ? 20 : -20)),
                        ),
                      );
                    }
                  }}
                  onPointerDown={(e) =>
                    { e.currentTarget.setPointerCapture(e.pointerId); e.currentTarget.dataset.dragging = "true"; }
                  }
                  onPointerMove={(e) => {
                    if (e.currentTarget.hasPointerCapture(e.pointerId))
                      setDetailWidth(
                        Math.max(
                          320,
                          Math.min(620, window.innerWidth - e.clientX),
                        ),
                      );
                  }}
                  onLostPointerCapture={e => { delete e.currentTarget.dataset.dragging; }}
                  title="拖动调整宽度，或聚焦后使用左右方向键"
                  onPointerUp={(e) =>
                    e.currentTarget.releasePointerCapture(e.pointerId)
                  }
                />
                <aside className="ws-detail" aria-label="详情">
                  <div className="ws-detail-toolbar">
                    <button onClick={close}>← 返回列表</button>
                    <span>详情</span>
                  </div>
                  <Surface identity={selected}>
                  {task && (
                    <>
                      <div className="ws-detail-content">
                        <h2>{task.title}</h2>
                        <p className="ws-muted">{task.courseName}</p>
                        {task.source === "school" ? (
                          <Deadline
                            task={task}
                            data={data!}
                            saving={saving}
                            mutate={mutate}
                          />
                        ) : (
                          <>
                            <p>
                              {formatDate(task.dueAt)} ·{" "}
                              {task.completed ? "已完成" : "待处理"}
                            </p>
                            <p className="ws-notes">
                              {task.draft?.notes || "暂无备注"}
                            </p>
                            {task.draft?.lectureSource && <button onClick={() => void openLectureTarget(task.draft!.lectureSource!)}>返回课堂笔记：{task.draft.lectureSource.title}</button>}
                            {task.draft?.checklist.map((c) => (
                              <label className="ws-check" key={c.id}>
                                <input
                                  type="checkbox"
                                  disabled={saving}
                                  checked={
                                    task.checked?.includes(c.id) ?? false
                                  }
                                  onChange={(e) =>
                                    void mutate({
                                      type: "check",
                                      seriesId: task.seriesId!,
                                      key: task.key!,
                                      checked: e.target.checked
                                        ? [...task.checked!, c.id]
                                        : task.checked!.filter(
                                            (id) => id !== c.id,
                                          ),
                                    })
                                  }
                                />
                                {c.title}
                              </label>
                            ))}
                            <p className="ws-muted">
                              提醒：
                              {task.draft?.reminders
                                .map((m) =>
                                  m === 0 ? "到期时" : `提前 ${m} 分钟`,
                                )
                                .join("、") || "未设置"}
                            </p>
                            <div className="ws-actions">
                              <button
                                disabled={saving}
                                onClick={() =>
                                  void complete([task], !task.completed)
                                }
                              >
                                {task.completed ? "恢复待处理" : "标为完成"}
                              </button>
                              <button onClick={() => setEditor({ task })}>
                                编辑
                              </button>
                              <button onClick={() => setDeleting([task])}>
                                删除
                              </button>
                            </div>
                          </>
                        )}
                      </div>
                      {task.row && (
                        <AssignmentDetail
                          inline
                          saving={saving}
                          row={{ ...task.row, dueAt: task.dueAt }}
                          ignored={task.ignored}
                          onToggleIgnored={() =>
                            void mutate({
                              type: "ignore",
                              ids: [`${task.row!.courseId}:${task.row!.id}`],
                              ignored: !task.ignored,
                            })
                          }
                          onClose={close}
                        />
                      )}
                    </>
                  )}
                  {change && (
                    <div className="ws-detail-content">
                      <h2>{change.title}</h2>
                      <p>
                        {kinds[change.kind]} · {formatDate(change.at)}
                      </p>
                      <button
                        disabled={change.read || saving}
                        onClick={() =>
                          void mutate({ type: "read", ids: [change.id] })
                        }
                      >
                        {change.read ? "已读" : "标为已读"}
                      </button>
                      {change.kind === "lecture" ? <>
                        <p>{change.before ? "这节课的摘要已更新，可打开笔记阅读最新内容。" : "新增一节课堂笔记，可打开查看摘要和转写。"}</p>
                        <button className="primary" onClick={() => {
                          const ref = parseLectureKey(change.objectId);
                          if (ref) void openLectureTarget(ref);
                          else setError("课次地址无法识别，请从课程页打开课堂笔记。");
                        }}>打开课堂笔记</button>
                      </> : <><h3>变更前</h3>
                      <pre>{pretty(change.before)}</pre>
                      <h3>变更后</h3>
                      <pre>{pretty(change.after)}</pre></>}
                    </div>
                  )}
                  {selected === "grades" && (
                    <div className="ws-detail-content">
                      <h2>成绩概览</h2>
                      <CourseScoreChart
                        courses={courses}
                        onSelect={(id) => open(`course:${id}`)}
                        height={Math.max(280, courses.length * 36)}
                      />
                    </div>
                  )}
                  {chosenCourse && (
                    <div className="ws-detail-content">
                      <h2>{chosenCourse.displayName}</h2>
                      <div className="ws-tabs ws-course-tabs" role="tablist" aria-label="课程内容">
                        {courseTabs.map(([id, l]) => (
                          <button
                            key={id}
                            role="tab"
                            aria-selected={tab === id}
                            tabIndex={tab === id ? 0 : -1}
                            onKeyDown={e => {
                              if (!["ArrowLeft", "ArrowRight", "Home", "End"].includes(e.key)) return;
                              e.preventDefault();
                              const ids = courseTabs.map(t => t[0]);
                              const index = e.key === "Home" ? 0 : e.key === "End" ? ids.length - 1 : (ids.indexOf(tab) + (e.key === "ArrowRight" ? 1 : ids.length - 1)) % ids.length;
                              setTab(ids[index]);
                              e.currentTarget.parentElement?.querySelectorAll("button")[index]?.focus();
                            }}
                            onClick={() => { setTab(id); if (id === "lectures") startReading(chosenCourse.id); }}
                          >
                            {l}
                          </button>
                        ))}
                      </div>
                      <Surface identity={tab}>
                      {tab === "overview" ? <CourseOverview account={snapshot.profile.id} course={chosenCourse} tasks={tasks} onOpenTask={id => { setPage("tasks"); open(id); }} onRead={ref => startReading(chosenCourse.id, ref)} onSettings={() => go("settings")} /> : tab === "lectures" ? <button className="primary" onClick={() => startReading(chosenCourse.id)}>阅读课堂笔记</button> : tab === "files" ? (
                        <CourseFiles
                          key={chosenCourse.id}
                          courseId={chosenCourse.id}
                        />
                      ) : tab === "grades" ? (
                        <GradeDetails
                          snapshot={snapshot}
                          courseId={chosenCourse.id}
                        />
                      ) : (
                        <>
                          {tasks
                            .filter((t) => t.courseId === chosenCourse.id)
                            .slice(0, limit)
                            .map((t) => row(t, false))}
                          <button onClick={() => setLimit(limit + 100)}>
                            加载更多
                          </button>
                        </>
                      )}
                      </Surface>
                    </div>
                  )}
                  </Surface>
                </aside>
              </>
            )}
          </div>
        )}
        {reader && page === "courses" && snapshot.courses.find(c => c.id === reader.courseId) && <LectureReader
          key={`${snapshot.profile.id}:${reader.courseId}`}
          account={snapshot.profile.id} course={snapshot.courses.find(c => c.id === reader.courseId)!}
          initialLecture={reader.ref} onBack={closeReader} onSettings={() => go("settings")}
          onCreateTask={initialDraft => { setError(""); setEditor({ initialDraft }); }}
        />}
      </main>
      {notice && <div className="ws-toast"><span role="status">{notice.text}</span>
        {notice.taskId && <button onClick={() => { setReader(null); setPage("tasks"); setSelected(notice.taskId!); setNotice(null); }}>查看任务</button>}
        {notice.undo && <button disabled={saving} onClick={async () => {
          if (await mutate(notice.undo!)) { timers.current.forEach(clearTimeout); setFinishing(new Set()); setExiting(false); setNotice({ text: "已撤销" }); }
        }}>撤销</button>}
        <button aria-label="关闭操作提示" title="关闭提示" onClick={() => setNotice(null)}>×</button>
      </div>}
      {editor && (
        <TaskEditor
          task={editor.task}
          initialDraft={editor.initialDraft}
          courses={snapshot.courses}
          saving={saving}
          error={error}
          close={() => setEditor(null)}
          save={async (draft, scope) => {
            const previous = new Set(data?.series.map(s => s.id));
            if (
              await mutate({
                type: "save",
                draft,
                seriesId: editor.task?.seriesId,
                key: editor.task?.key,
                scope,
              })
            ) {
              const saved = lastSaved.current?.series.find(s => editor.task ? s.id === editor.task.seriesId : !previous.has(s.id));
              if (saved && snapshot && lastSaved.current) {
                const views = unifyTasks(snapshot, lastSaved.current, horizon);
                const view = views.find(t => t.seriesId === saved.id && (!editor.task || t.key === editor.task.key)) ?? views.find(t => t.seriesId === saved.id);
                if (view) {
                  if (editor.initialDraft?.lectureSource) setNotice({ text: "任务已保存", taskId: view.id });
                  else { setReader(null); setPage("tasks"); setSelected(view.id); }
                }
              }
              if (!editor.initialDraft?.lectureSource) setNotice({ text: "任务已保存" });
              return true;
            }
            return false;
          }}
        />
      )}
      {deleting && (
        <DeleteDialog
          tasks={deleting}
          saving={saving}
          error={error}
          close={() => setDeleting(null)}
          confirm={async (scope) => {
            if (
              await mutate({ type: "delete", items: refs(deleting), scope })
            ) {
              setChecked(new Set());
              close();
              setNotice({ text: "任务已删除" });
              return true;
            }
            return false;
          }}
        />
      )}
    </div>
  );
}
function pretty(value: string | null) {
  if (value === null) return "此前不存在";
  const labels: Record<string, string> = {
    title: "标题",
    dueAt: "截止时间",
    description: "说明",
    points: "满分",
    score: "得分",
    grade: "等级",
    gradedAt: "评分时间",
    message: "公告正文",
    posted_at: "发布时间",
    name: "文件名",
    size: "文件大小（字节）",
    updated_at: "更新时间",
    locked: "已锁定",
  };
  try {
    return Object.entries(JSON.parse(value))
      .map(
        ([key, v]) =>
          `${labels[key] ?? key}：${v === null ? "未设置" : typeof v === "boolean" ? (v ? "是" : "否") : /At$|_at$/.test(key) && typeof v === "string" ? formatDate(v) : htmlToPlainText(String(v))}`,
      )
      .join("\n\n");
  } catch {
    return htmlToPlainText(value);
  }
}
