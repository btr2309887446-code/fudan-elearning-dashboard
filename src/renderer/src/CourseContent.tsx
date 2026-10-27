import { useCallback, useEffect, useId, useMemo, useRef, useState, type KeyboardEvent, type ReactNode } from "react";
import ReactMarkdown from "react-markdown";
import remarkGfm from "remark-gfm";
import remarkMath from "remark-math";
import rehypeKatex from "rehype-katex";
import "katex/dist/katex.min.css";
import type { CourseSummary } from "../../core/types";
import type { TaskDraft, TaskView } from "../../core/workspace";
import { DEFAULT_LECTURE_REPOSITORY, lectureKey, type CourseIntroduction, type LectureBody, type LectureConnection, type LectureCourse, type LectureItem, type LectureRef } from "../../core/lectures";
import "./course-content.css";

const dateLabel = (date?: string) => {
  if (!date) return "日期未提供";
  const value = new Date(date);
  return Number.isFinite(value.getTime()) ? value.toLocaleDateString("zh-CN", { timeZone: "Asia/Shanghai", month: "long", day: "numeric", year: "numeric" }) : date;
};
const messageOf = (error: unknown) => error instanceof Error ? error.message : String(error);

function useConnection(account: number) {
  const [state, setState] = useState<LectureConnection | null>(null);
  const [error, setError] = useState("");
  const [revision, setRevision] = useState(0);
  const revisionRef = useRef(0);
  const reload = useCallback(() => setRevision(value => value + 1), []);
  useEffect(() => {
    setState(null); setError("");
    return window.elearning.lectures.onUpdated(reload);
  }, [account, reload]);
  useEffect(() => {
    let alive = true;
    const id = ++revisionRef.current;
    void window.elearning.lectures.state(account).then(result => {
      if (!alive || id !== revisionRef.current) return;
      if (result.ok) { setState(result.data); setError(""); } else setError(result.error.message);
    }).catch(error => { if (alive) setError(messageOf(error)); });
    return () => { alive = false; };
  }, [account, revision]);
  return { state, setState, error, reload, revision };
}

function ContentMessage({ children, retry, tone = "normal" }: { children: ReactNode; retry?: () => void; tone?: "normal" | "error" }) {
  return <div className={`cc-message ${tone === "error" ? "cc-error" : ""}`} role={tone === "error" ? "alert" : "status"}>
    <span>{children}</span>{retry && <button onClick={retry}>重试</button>}
  </div>;
}

function ConnectionHint({ state, onSettings }: { state: LectureConnection | null; onSettings: () => void }) {
  if (!state) return <p className="cc-muted" role="status">正在读取课堂笔记…</p>;
  if (!state.configured) return <div className="cc-empty"><strong>让课堂笔记回到课程里</strong><p>连接 iCourse 订阅仓库后，可以在这里阅读每次课的摘要、转写与 PPT 文字。</p><button onClick={onSettings}>连接课堂笔记</button></div>;
  if (state.locked) return <ContentMessage>课堂笔记尚未解锁。解锁后可离线阅读已缓存内容。<button onClick={onSettings}>解锁连接</button></ContentMessage>;
  return null;
}

export function CourseOverview({ account, course, tasks, onOpenTask, onRead, onSettings }: {
  account: number; course: CourseSummary; tasks: TaskView[]; onOpenTask: (id: string) => void;
  onRead: (ref?: LectureRef) => void; onSettings: () => void;
}) {
  const { state, error: connectionError, revision, reload } = useConnection(account);
  const [intro, setIntro] = useState<CourseIntroduction | null>(null);
  const [introError, setIntroError] = useState("");
  const [introBusy, setIntroBusy] = useState(false);
  const [introRevision, setIntroRevision] = useState(0);
  const [items, setItems] = useState<LectureItem[]>([]);
  const [count, setCount] = useState(0);
  const [listError, setListError] = useState("");
  useEffect(() => { setIntro(null); setItems([]); setCount(0); }, [account, course.id]);
  useEffect(() => {
    let alive = true; setIntroBusy(true); setIntroError("");
    void window.elearning.course.introduction(account, course.id, introRevision > 0).then(result => {
      if (!alive) return;
      if (result.ok) setIntro(result.data); else setIntroError(result.error.message);
    }).catch(error => { if (alive) setIntroError(messageOf(error)); }).finally(() => { if (alive) setIntroBusy(false); });
    return () => { alive = false; };
  }, [account, course.id, introRevision]);
  useEffect(() => {
    let alive = true; setListError("");
    if (!state?.configured || state.locked) { setItems([]); setCount(0); return; }
    void window.elearning.lectures.list(account, course.id, "", 0).then(result => {
      if (!alive) return;
      if (result.ok) { setItems(result.data.items.slice(0, 3)); setCount(result.data.total); }
      else setListError(result.error.message);
    }).catch(error => { if (alive) setListError(messageOf(error)); });
    return () => { alive = false; };
  }, [account, course.id, state?.sourceId, state?.configured, state?.locked, revision]);
  const pending = useMemo(() => tasks.filter(task => task.courseId === course.id && !task.completed && !task.ignored)
    .sort((a, b) => (a.dueAt ? Date.parse(a.dueAt) : Infinity) - (b.dueAt ? Date.parse(b.dueAt) : Infinity)).slice(0, 5), [tasks, course.id]);
  const linkedCourses = state?.courses.filter(item => state.bindings.some(binding => binding.icourseCourseId === item.id && binding.canvasCourseId === course.id)) ?? [];
  const teachers = intro?.teachers.length ? intro.teachers.join("、") : [...new Set(linkedCourses.map(item => item.teacher).filter(Boolean))].join("、");
  return <div className="cc-overview" data-testid="course-overview">
    <section className="cc-intro">
      <h3>课程简介</h3>
      <div className="cc-course-meta"><span>{course.termName}</span>{teachers && <span>教师：{teachers}{!intro?.teachers.length && <small>（iCourse）</small>}</span>}</div>
      {introBusy && !intro && <p className="cc-muted" role="status">正在读取课程简介…</p>}
      {intro?.description ? <p className="cc-description">{intro.description}</p> : !introBusy && <p className="cc-muted">学校暂未提供课程简介，可继续查看作业和课堂笔记。</p>}
      {intro?.cached && <small className="cc-muted">显示上次保存的课程简介</small>}
      {(introError || intro?.warning) && <ContentMessage tone="error" retry={() => setIntroRevision(value => value + 1)}>{introError || intro?.warning}</ContentMessage>}
    </section>
    <section><div className="cc-section-heading"><h3>近期待办</h3><span className="cc-muted">本课程</span></div>
      {pending.length ? <ul className="cc-simple-list">{pending.map(task => <li key={task.id}><button onClick={() => onOpenTask(task.id)}><span>{task.title}</span><small>{task.dueAt ? dateLabel(task.dueAt) : "未设日期"}</small></button></li>)}</ul> : <p className="cc-muted">这门课暂时没有待办。</p>}
    </section>
    <section><div className="cc-section-heading"><h3>最近课堂笔记</h3>{count > 0 && <button className="cc-text-button" onClick={() => onRead()}>查看全部 {count} 次课</button>}</div>
      <ConnectionHint state={state} onSettings={onSettings} />
      {connectionError && <ContentMessage tone="error" retry={reload}>{connectionError}</ContentMessage>}
      {listError && state?.configured && <ContentMessage tone="error" retry={reload}>{listError}</ContentMessage>}
      {!!items.length && <ul className="cc-simple-list">{items.map(item => <li key={lectureKey(item)}><button onClick={() => onRead(item)}><span>{item.title}<LectureBadge item={item} /></span><small>{dateLabel(item.date)}</small></button></li>)}</ul>}
      {!items.length && state?.configured && !listError && <div className="cc-empty"><p>{linkedCourses.length ? "还没有可阅读的课次。订阅仓库生成内容后，将在下次同步时出现。" : "还没有关联这门课的 iCourse 课堂。"}</p><button onClick={onSettings}>{linkedCourses.length ? "查看连接" : "关联课程"}</button></div>}
    </section>
  </div>;
}

function LectureBadge({ item }: { item: LectureItem }) {
  return <small className={`cc-badge ${item.updated || !item.read ? "cc-badge-new" : ""}`}>{item.updated ? "摘要更新" : item.read ? "已读" : "未读"}</small>;
}

type ReadingTab = "summary" | "transcript" | "ppt";
type ReadingMemory = { query: string; offset: number; ref?: LectureRef; tab: ReadingTab; scroll: Record<string, number>; listScroll: number };
const readingMemory = new Map<string, ReadingMemory>();
function memoryFor(key: string): ReadingMemory {
  if (!readingMemory.has(key)) {
    if (readingMemory.size >= 20) readingMemory.delete(readingMemory.keys().next().value!);
    readingMemory.set(key, { query: "", offset: 0, tab: "summary", scroll: {}, listScroll: 0 });
  }
  return readingMemory.get(key)!;
}

function headingEntries(content: string) {
  let fenced = false;
  return content.split("\n").flatMap((line, index) => {
    if (/^\s*(```|~~~)/.test(line)) { fenced = !fenced; return []; }
    const match = !fenced && /^(#{1,6})\s+(.+?)\s*#*\s*$/.exec(line);
    return match ? [{ id: `cc-heading-${index + 1}`, title: match[2].replace(/[*_`]/g, ""), level: match[1].length }] : [];
  });
}

/** Rendering is local: raw HTML and remote images never enter the reader. */
function LectureMarkdown({ text, onError }: { text: string; onError: (value: string) => void }) {
  const content = useMemo(() => text.replace(/\\\[([\s\S]*?)\\\]/g, (_, math) => `$$${math}$$`).replace(/\\\((.*?)\\\)/g, (_, math) => `$${math}$`), [text]);
  return <ReactMarkdown skipHtml remarkPlugins={[remarkGfm, remarkMath]} rehypePlugins={[[rehypeKatex, { trust: false, throwOnError: false, strict: false }]]}
    components={{
      h1: ({ node, children }) => <h2 id={`cc-heading-${node?.position?.start.line}`}>{children}</h2>,
      h2: ({ node, children }) => <h2 id={`cc-heading-${node?.position?.start.line}`}>{children}</h2>,
      h3: ({ node, children }) => <h3 id={`cc-heading-${node?.position?.start.line}`}>{children}</h3>,
      h4: ({ node, children }) => <h4 id={`cc-heading-${node?.position?.start.line}`}>{children}</h4>,
      h5: ({ node, children }) => <h5 id={`cc-heading-${node?.position?.start.line}`}>{children}</h5>,
      h6: ({ node, children }) => <h6 id={`cc-heading-${node?.position?.start.line}`}>{children}</h6>,
      a: ({ href, children }) => href && /^https:\/\//i.test(href) ? <a href={href} onClick={event => { event.preventDefault(); void window.elearning.open(href).catch(error => onError(messageOf(error))); }}>{children}</a> : <span>{children}</span>,
      img: ({ alt }) => <span className="cc-muted">〔{alt || "图片"}〕</span>,
      table: ({ children }) => <div className="cc-table-scroll" tabIndex={0} role="region" aria-label="表格，可横向滚动"><table>{children}</table></div>,
    }}>{content}</ReactMarkdown>;
}

function classroomItems(summary: string): string[] {
  // Surface only existing action-like text. No generated dates or inferred task state.
  const result: string[] = [];
  let relevantSection = false;
  let fenced = false;
  for (const line of summary.split("\n")) {
    if (/^\s*(```|~~~)/.test(line)) { fenced = !fenced; continue; }
    if (fenced) continue;
    if (/^#{1,6}\s/.test(line)) { relevantSection = /作业|考试|签到|考勤|小组|待办|重要事项|课后|通知|提醒/.test(line); continue; }
    const list = /^\s*(?:[-*+]\s+(?:\[[ xX]\]\s*)?|\d+[.、)]\s*)(.+)/.exec(line);
    if (list && (relevantSection || /(?:作业|考试|签到|考勤|小组任务|需提交|请提交|截止)/.test(list[1]))) {
      const value = list[1].replace(/\*\*|__|`/g, "").trim();
      if (value && !result.includes(value)) result.push(value);
    }
  }
  return result.slice(0, 20);
}

export function LectureReader({ account, course, initialLecture, onBack, onCreateTask, onSettings }: {
  account: number; course: CourseSummary; initialLecture?: LectureRef; onBack: () => void;
  onCreateTask: (draft: TaskDraft) => void; onSettings: () => void;
}) {
  const { state, error: connectionError, reload, revision } = useConnection(account);
  const baseKey = `${account}:${course.id}`;
  const initialMemory = memoryFor(baseKey);
  const [query, setQuery] = useState(initialMemory.query);
  const [search, setSearch] = useState(initialMemory.query);
  const [offset, setOffset] = useState(initialMemory.offset);
  const [items, setItems] = useState<LectureItem[]>([]);
  const [total, setTotal] = useState(0);
  const [selected, setSelected] = useState<LectureRef | undefined>(initialLecture ?? initialMemory.ref);
  const [body, setBody] = useState<LectureBody | null>(null);
  const [tab, setTab] = useState<ReadingTab>(initialMemory.tab);
  const [listBusy, setListBusy] = useState(true);
  const [bodyBusy, setBodyBusy] = useState(false);
  const [listError, setListError] = useState("");
  const [bodyError, setBodyError] = useState("");
  const [actionError, setActionError] = useState("");
  const [selection, setSelection] = useState("");
  const [detailRevision, setDetailRevision] = useState(0);
  const [syncBusy, setSyncBusy] = useState(false);
  const syncLock = useRef(false);
  const scrollRef = useRef<HTMLDivElement>(null);
  const listRef = useRef<HTMLDivElement>(null);
  const articleRef = useRef<HTMLElement>(null);
  const epoch = useRef(0);
  const selectedKey = selected ? lectureKey(selected) : "";
  const bodyIdentity = body ? lectureKey(body) : "";
  const scrollKey = `${selectedKey}:${tab}`;
  const memory = useRef(initialMemory);
  const previousSource = useRef<string | undefined>(undefined);
  const tabId = useId();
  const readAttempt = useRef("");
  useEffect(() => {
    epoch.current += 1;
    const next = memoryFor(baseKey); memory.current = next;
    setQuery(next.query); setSearch(next.query); setOffset(next.offset); setSelected(initialLecture ?? next.ref); setTab(next.tab);
    setItems([]); setBody(null); setSelection(""); setActionError(""); previousSource.current = undefined;
    return () => { epoch.current += 1; };
  }, [baseKey]);
  useEffect(() => {
    if (!initialLecture) return;
    setSelected(initialLecture);
  }, [initialLecture && lectureKey(initialLecture)]);
  useEffect(() => {
    if (!state) return;
    if (!state.configured || state.locked) { setItems([]); setBody(null); setListBusy(false); setTotal(0); return; }
    if ((previousSource.current !== undefined && previousSource.current !== state.sourceId) || (selected && selected.sourceId !== state.sourceId)) {
      epoch.current += 1; setSelected(undefined); setBody(null); setQuery(""); setSearch(""); setOffset(0); setItems([]);
      memory.current = { query: "", offset: 0, tab: "summary", scroll: {}, listScroll: 0 }; readingMemory.set(baseKey, memory.current);
    }
    previousSource.current = state.sourceId;
  }, [state?.sourceId, state?.configured, state?.locked, baseKey]);
  useEffect(() => {
    const timer = setTimeout(() => { setSearch(query); setOffset(0); }, 180);
    return () => clearTimeout(timer);
  }, [query]);
  useEffect(() => { memory.current.query = query; memory.current.offset = offset; memory.current.ref = selected; memory.current.tab = tab; }, [query, offset, selectedKey, tab]);
  useEffect(() => {
    if (!state) return;
    if (!state.configured || state.locked) { setItems([]); setListError(""); setListBusy(false); setTotal(0); return; }
    let alive = true; setListBusy(true); setListError("");
    void window.elearning.lectures.list(account, course.id, search, offset).then(result => {
      if (!alive) return;
      if (result.ok) {
        setItems(result.data.items); setTotal(result.data.total);
        setSelected(current => current ?? result.data.items[0]);
      } else setListError(result.error.message);
    }).catch(error => { if (alive) setListError(messageOf(error)); }).finally(() => { if (alive) setListBusy(false); });
    return () => { alive = false; };
  }, [account, course.id, state?.sourceId, state?.configured, state?.locked, search, offset, revision]);
  const selectedVersion = items.find(item => lectureKey(item) === selectedKey)?.summaryHash;
  useEffect(() => {
    if (!selected || !state?.configured || state.locked || selected.sourceId !== state.sourceId) { setBody(null); return; }
    let alive = true; setBodyBusy(true); setBodyError(""); setActionError(""); setSelection("");
    void window.elearning.lectures.detail(account, selected).then(result => {
      if (!alive) return;
      if (result.ok) setBody(result.data); else { setBody(null); setBodyError(result.error.message); }
    }).catch(error => { if (alive) { setBody(null); setBodyError(messageOf(error)); } }).finally(() => { if (alive) setBodyBusy(false); });
    return () => { alive = false; };
  }, [account, selectedKey, selectedVersion, state?.sourceId, state?.configured, state?.locked, detailRevision]);
  // Reading state is acknowledged only after persistence succeeds; failures can be retried in place.
  useEffect(() => {
    if (!body || bodyIdentity !== selectedKey || (body.read && !body.updated)) return;
    const key = `${bodyIdentity}:${body.summaryHash}:${detailRevision}`;
    if (readAttempt.current === key) return;
    readAttempt.current = key;
    let alive = true;
    void window.elearning.lectures.read(account, body).then(result => {
      if (!alive) return;
      if (result.ok) {
        setBody(current => current && lectureKey(current) === bodyIdentity ? { ...current, read: true, updated: false } : current);
        setItems(current => current.map(item => lectureKey(item) === bodyIdentity ? { ...item, read: true, updated: false } : item));
      } else setActionError(`已读状态未保存：${result.error.message}`);
    }).catch(error => { if (alive) setActionError(`已读状态未保存：${messageOf(error)}`); });
    return () => { alive = false; };
  }, [account, bodyIdentity, body?.summaryHash, detailRevision, selectedKey]);
  useEffect(() => {
    if (!body || bodyIdentity !== selectedKey || bodyBusy) return;
    const frame = requestAnimationFrame(() => { if (scrollRef.current) scrollRef.current.scrollTop = memory.current.scroll[scrollKey] ?? 0; });
    return () => cancelAnimationFrame(frame);
  }, [bodyIdentity, selectedKey, tab, bodyBusy]);
  useEffect(() => {
    if (listRef.current) listRef.current.scrollTop = memory.current.listScroll;
  }, [items.length]);
  useEffect(() => {
    function captureSelection() {
      const selectedText = window.getSelection();
      if (selectedText?.anchorNode && selectedText.focusNode && articleRef.current?.contains(selectedText.anchorNode) && articleRef.current.contains(selectedText.focusNode)) {
        setSelection(selectedText.toString().trim().slice(0, 12000));
      } else if (!document.querySelector("dialog[open]")) setSelection("");
    }
    document.addEventListener("selectionchange", captureSelection);
    return () => document.removeEventListener("selectionchange", captureSelection);
  }, []);
  function choose(item: LectureItem) {
    if (scrollRef.current) memory.current.scroll[scrollKey] = scrollRef.current.scrollTop;
    setSelected(item); setTab("summary");
  }
  function setReadingTab(next: ReadingTab) {
    if (scrollRef.current) memory.current.scroll[scrollKey] = scrollRef.current.scrollTop;
    setTab(next); setSelection("");
  }
  function createTask(text: string) {
    if (!body || bodyIdentity !== selectedKey) return;
    onCreateTask({ title: text.replace(/\s+/g, " ").slice(0, 120), notes: text, courseId: course.id, dueAt: null, repeat: "none", weekdays: [], endDate: null, checklist: [], reminders: [],
      lectureSource: { sourceId: body.sourceId, icourseCourseId: body.icourseCourseId, lectureId: body.lectureId, title: body.title } });
  }
  async function synchronize() {
    if (syncLock.current) return;
    syncLock.current = true;
    const current = epoch.current; setSyncBusy(true); setActionError("");
    try { const result = await window.elearning.lectures.sync(account); if (current === epoch.current) { if (!result.ok) setActionError(result.error.message); else { reload(); setDetailRevision(value => value + 1); } } }
    catch (error) { if (current === epoch.current) setActionError(messageOf(error)); }
    finally { syncLock.current = false; if (current === epoch.current) setSyncBusy(false); }
  }
  const actions = useMemo(() => classroomItems(body?.summary ?? ""), [body?.summary]);
  const headings = useMemo(() => headingEntries(body?.summary ?? ""), [body?.summary]);
  const tabs: { id: ReadingTab; label: string }[] = [{ id: "summary", label: "课堂摘要" }, { id: "transcript", label: "原始转写" }, { id: "ppt", label: "PPT 文字" }];
  function tabKeyboard(event: KeyboardEvent<HTMLDivElement>) {
    const index = tabs.findIndex(item => item.id === tab);
    const next = event.key === "ArrowRight" ? (index + 1) % 3 : event.key === "ArrowLeft" ? (index + 2) % 3 : event.key === "Home" ? 0 : event.key === "End" ? 2 : -1;
    if (next < 0) return;
    event.preventDefault(); setReadingTab(tabs[next].id); document.getElementById(`${tabId}-${tabs[next].id}`)?.focus();
  }
  const visibleBody = body && bodyIdentity === selectedKey ? body : null;
  return <section className={`cc-reader ${visibleBody ? "cc-has-body" : ""}`} data-testid="lecture-reader" aria-label={`${course.displayName} 课堂笔记`}>
    <header className="cc-reader-header"><button onClick={onBack} aria-label="返回课程">‹ 返回课程</button><div><h2>{course.displayName}</h2><span className="cc-muted">课堂笔记</span></div><button className="cc-reader-sync" onClick={() => void synchronize()} disabled={syncBusy || state?.syncing || !state?.configured || state?.locked} aria-busy={syncBusy || state?.syncing}>{syncBusy || state?.syncing ? "同步中…" : "同步笔记"}</button></header>
    <div className="cc-reader-layout">
      <aside className="cc-lecture-list" aria-label="课次列表"><label className="cc-search"><span className="cc-sr-only">搜索课次</span><input type="search" value={query} onChange={event => setQuery(event.target.value)} placeholder="搜索课次、教师" aria-label="搜索课次" /></label>
        <div className="cc-list-status" role="status">{listBusy ? "正在读取课次…" : `${total} 次课`}</div>
        <div className="cc-lecture-rows" ref={listRef} onScroll={event => { memory.current.listScroll = event.currentTarget.scrollTop; }}>
          {listError && <ContentMessage tone="error" retry={reload}>{listError}</ContentMessage>}
          {!items.length && !listBusy && !listError && <p className="cc-muted cc-list-empty">{search ? "没有匹配的课次，试试其他关键词。" : "暂无课次"}</p>}
          {items.map(item => <button key={lectureKey(item)} className="cc-lecture-row" aria-pressed={lectureKey(item) === selectedKey} onClick={() => choose(item)}><time>{dateLabel(item.date)}</time><strong>{item.title}</strong><span><LectureBadge item={item} />{!item.hasSummary && <small className="cc-muted">摘要待生成</small>}</span></button>)}
        </div>
        {total > 50 && <nav className="cc-pagination" aria-label="课次分页"><button disabled={offset === 0 || listBusy} onClick={() => { setOffset(Math.max(0, offset - 50)); memory.current.listScroll = 0; }}>上一页</button><span>{Math.floor(offset / 50) + 1} / {Math.ceil(total / 50)}</span><button disabled={offset + 50 >= total || listBusy} onClick={() => { setOffset(offset + 50); memory.current.listScroll = 0; }}>下一页</button></nav>}
      </aside>
      <div className="cc-reading-pane">
        <div className="cc-reading-toolbar"><div className="cc-reading-tabs" role="tablist" aria-label="笔记内容" onKeyDown={tabKeyboard}>{tabs.map(item => <button key={item.id} id={`${tabId}-${item.id}`} role="tab" tabIndex={tab === item.id ? 0 : -1} aria-selected={tab === item.id} aria-controls={`${tabId}-panel`} onClick={() => setReadingTab(item.id)}>{item.label}</button>)}</div><button disabled={!selection || !visibleBody} onMouseDown={event => event.preventDefault()} onClick={() => createTask(selection)} title="选中正文中的文字后可创建任务">选中文字建任务</button></div>
        <div className="cc-reading-scroll" ref={scrollRef} onScroll={event => { if (visibleBody) memory.current.scroll[scrollKey] = event.currentTarget.scrollTop; }}>
          <div className="cc-reading-content">
            <ConnectionHint state={state} onSettings={onSettings} />
            {connectionError && <ContentMessage tone="error" retry={reload}>{connectionError}</ContentMessage>}
            {state?.error && <ContentMessage tone="error" retry={() => void synchronize()}>{state.error}</ContentMessage>}
            {actionError && <ContentMessage tone="error" retry={() => setDetailRevision(value => value + 1)}>{actionError}</ContentMessage>}
            {bodyBusy && !visibleBody && <p className="cc-muted" role="status">正在打开课堂笔记…</p>}
            {bodyError && <ContentMessage tone="error" retry={() => setDetailRevision(value => value + 1)}>{bodyError}</ContentMessage>}
            {!selected && !bodyBusy && state?.configured && <div className="cc-empty"><h3>在左侧选择一次课</h3><p>关联课程后，这里会展示已生成的课堂笔记。</p><button onClick={onSettings}>管理课程关联</button></div>}
            {visibleBody && <><header className="cc-article-heading"><time>{dateLabel(visibleBody.date)}</time><h1>{visibleBody.title}</h1><p>{visibleBody.courseTitle}{visibleBody.teacher && `　${visibleBody.teacher}`}</p><small>{tab === "summary" ? "AI 生成的课堂摘要，请结合教师原意核对事项。" : tab === "transcript" ? "课堂音频自动转写，可能存在识别误差。" : "PPT 自动识别文字，按课件页码排列。"}</small></header>
              {tab === "summary" && headings.length > 2 && <details className="cc-toc"><summary>本次课目录</summary><nav aria-label="本次课目录">{headings.map(heading => <button key={heading.id} style={{ paddingLeft: 12 + Math.min(heading.level - 1, 3) * 12 }} onClick={() => { const target = scrollRef.current?.querySelector<HTMLElement>(`#${heading.id}`); if (target) { target.setAttribute("tabindex", "-1"); target.scrollIntoView({ block: "start", behavior: "auto" }); target.focus({ preventScroll: true }); } }}>{heading.title}</button>)}</nav></details>}
              <article className="cc-article" ref={articleRef} role="tabpanel" id={`${tabId}-panel`} aria-labelledby={`${tabId}-${tab}`} tabIndex={0}>
                {tab === "summary" && (visibleBody.summary ? <LectureMarkdown text={visibleBody.summary} onError={setActionError} /> : <p className="cc-muted">摘要尚未生成，可以先查看原始转写或 PPT 文字。</p>)}
                {tab === "transcript" && (visibleBody.transcript ? <div className="cc-transcript">{visibleBody.transcript}</div> : <p className="cc-muted">本次课暂无转写文字。</p>)}
                {tab === "ppt" && (visibleBody.pages.length ? visibleBody.pages.map(page => <section className="cc-ppt-page" key={`${page.page}:${page.seconds}`}><h3>第 {page.page} 页{page.seconds > 0 && <small>　{Math.floor(page.seconds / 60)}:{String(Math.floor(page.seconds % 60)).padStart(2, "0")}</small>}</h3><div className="cc-transcript">{page.text || "这一页未识别到文字。"}</div></section>) : <p className="cc-muted">本次课暂无 PPT 识别文字。</p>)}
              </article>
              {tab === "summary" && actions.length > 0 && <section className="cc-classroom-items" aria-label="课堂事项"><h2>课堂事项</h2><p className="cc-muted">摘自本次摘要。加入任务前，请确认具体要求和日期。</p><ul>{actions.map((text, index) => <li key={index}><p>{text}</p><button onClick={() => createTask(text)}>加入个人任务</button></li>)}</ul></section>}
              {visibleBody.error && <ContentMessage tone="error">上游处理提示：{visibleBody.error}</ContentMessage>}
              <footer className="cc-source-note">来源：iCourse 订阅仓库{visibleBody.processedAt && `　更新于 ${dateLabel(visibleBody.processedAt)}`}</footer>
            </>}
          </div>
        </div>
      </div>
    </div>
  </section>;
}

function recommendedCourse(source: LectureCourse, courses: CourseSummary[]): CourseSummary | undefined {
  const clean = (name: string) => name.toLowerCase().replace(/[\s（）()【】\[\]·\-_]/g, "");
  const name = clean(source.title);
  if (!name) return undefined;
  const candidates = courses.filter(course => [course.name, course.displayName].some(value => clean(value) === name));
  if (candidates.length === 1) return candidates[0];
  const termMatches = candidates.filter(course => source.terms.some(term => clean(course.termName).includes(clean(term)) || clean(term).includes(clean(course.termName))));
  return termMatches.length === 1 ? termMatches[0] : undefined;
}

function parseCourseReference(value: string): string | null {
  if (/^\d+$/.test(value.trim())) return value.trim();
  try {
    const url = new URL(value.trim());
    if (url.protocol !== "https:" && url.protocol !== "http:") return null;
    const id = url.searchParams.get("courseId") ?? url.searchParams.get("course_id") ?? url.searchParams.get("id") ?? /\/(\d+)\/?$/.exec(url.pathname)?.[1];
    return id && /^\d+$/.test(id) ? id : null;
  } catch { return null; }
}

export function LectureSettings({ account, courses }: { account: number; courses: CourseSummary[] }) {
  const { state, setState, error: stateError, reload } = useConnection(account);
  const [repository, setRepository] = useState(DEFAULT_LECTURE_REPOSITORY);
  const [branch, setBranch] = useState("data");
  const [studentId, setStudentId] = useState("");
  const [password, setPassword] = useState("");
  const [token, setToken] = useState("");
  const [remember, setRemember] = useState(false);
  const [busy, setBusy] = useState("");
  const [error, setError] = useState("");
  const [success, setSuccess] = useState("");
  const [bindingChoices, setBindingChoices] = useState<Record<string, string>>({});
  const [courseLink, setCourseLink] = useState("");
  const [linkCourseId, setLinkCourseId] = useState("");
  const [confirmDisconnect, setConfirmDisconnect] = useState(false);
  const initialized = useRef(false);
  const epoch = useRef(0);
  const busyRef = useRef(false);
  useEffect(() => {
    epoch.current += 1; initialized.current = false; busyRef.current = false;
    setStudentId(""); setPassword(""); setToken(""); setRemember(false); setError(""); setSuccess(""); setBusy(""); setBindingChoices({}); setConfirmDisconnect(false);
    return () => { epoch.current += 1; };
  }, [account]);
  useEffect(() => {
    if (state && !initialized.current) { setRepository(state.repository || DEFAULT_LECTURE_REPOSITORY); setBranch(state.branch || "data"); initialized.current = true; }
  }, [state]);
  async function act(name: string, operation: () => Promise<Awaited<ReturnType<typeof window.elearning.lectures.state>>>, done: string) {
    if (busyRef.current) return;
    const current = epoch.current; busyRef.current = true; setBusy(name); setError(""); setSuccess("");
    try {
      const result = await operation();
      if (current !== epoch.current) return;
      if (result.ok) { setState(result.data); if (!result.data.error) setSuccess(done); if (name === "connect") { setPassword(""); setToken(""); } if (name === "disconnect") setConfirmDisconnect(false); }
      else setError(result.error.message);
    } catch (error) { if (current === epoch.current) setError(messageOf(error)); }
    finally { if (current === epoch.current) { busyRef.current = false; setBusy(""); } }
  }
  function bind(sourceId: string, canvasId: string) {
    void act(`bind:${sourceId}`, () => window.elearning.lectures.bind(account, sourceId, canvasId ? Number(canvasId) : null), canvasId ? "课程关联已保存，历史笔记已建立基线。" : "课程关联已解除。");
  }
  const unbound = state?.courses.filter(course => !state.bindings.some(binding => binding.icourseCourseId === course.id)).length ?? 0;
  return <section className="cc-settings" data-testid="lecture-settings">
    <h2>课堂笔记</h2><p className="cc-muted">把 iCourse 订阅仓库生成的摘要、转写和 PPT 文字带到对应课程中。邮件仍照常发送。</p>
    {state && <div className="cc-connection-status"><strong>{state.configured ? state.locked ? "连接待解锁" : "已连接" : "尚未连接"}</strong><span>{state.syncing ? "同步中…" : state.lastSynced ? `上次同步 ${dateLabel(state.lastSynced)}` : "连接后开始同步"}</span>{state.remembered && <small>本机已记住解锁信息</small>}</div>}
    {stateError && <ContentMessage tone="error" retry={reload}>{stateError}</ContentMessage>}
    {state?.error && <ContentMessage tone="error">{state.error}</ContentMessage>}
    <form onSubmit={event => { event.preventDefault(); void act("connect", () => window.elearning.lectures.connect(account, { repository: repository.trim(), branch: branch.trim(), studentId: studentId.trim(), password, token: token.trim() || undefined, remember }), "课堂笔记已连接，可以继续关联课程。"); }}>
      <fieldset disabled={!!busy}><legend className="cc-sr-only">连接与解锁</legend>
        <label>GitHub 仓库<input required value={repository} onChange={event => setRepository(event.target.value)} placeholder="用户名/仓库名" autoComplete="off" /><small>可以输入仓库网址或“用户名/仓库名”。</small></label>
        <label>数据分支<input required value={branch} onChange={event => setBranch(event.target.value)} autoComplete="off" /></label>
        <div className="cc-form-pair"><label>生成笔记时的学号<input required value={studentId} onChange={event => setStudentId(event.target.value)} inputMode="numeric" autoComplete="off" /></label><label>生成笔记时的 UIS 密码<input required type="password" value={password} onChange={event => setPassword(event.target.value)} autoComplete="off" /></label></div>
        <small className="cc-muted">密码只用于在本机解锁笔记。如果修改过 UIS 密码，请使用生成这份笔记时的密码。</small>
        <details className="cc-private-config"><summary>私有仓库访问</summary><label>GitHub 访问令牌<input type="password" value={token} onChange={event => setToken(event.target.value)} autoComplete="off" /><small>仅私有仓库需要，授予此仓库的内容读取权限即可。</small></label></details>
        <label className="cc-check"><input type="checkbox" checked={remember} onChange={event => setRemember(event.target.checked)} />在本机记住解锁信息</label>
        <small className="cc-muted">默认仅本次解锁；记住后由 Windows 安全存储保护。</small>
        <div className="cc-settings-actions"><button type="submit" className="primary" aria-busy={busy === "connect"}>{busy === "connect" ? "正在连接…" : state?.configured ? "解锁并保存连接" : "连接课堂笔记"}</button>{state?.configured && <button type="button" disabled={state.locked || state.syncing} onClick={() => void act("sync", () => window.elearning.lectures.sync(account), "课堂笔记同步已完成。")}>{busy === "sync" || state.syncing ? "同步中…" : "立即同步"}</button>}{state?.configured && <button type="button" onClick={() => setConfirmDisconnect(true)}>断开连接</button>}</div>
      </fieldset>
    </form>
    {confirmDisconnect && <div className="cc-confirm" role="group" aria-label="确认断开课堂笔记连接"><p>断开后将停止读取这个仓库。已有个人任务不会被删除。</p><button disabled={!!busy} onClick={() => void act("disconnect", () => window.elearning.lectures.disconnect(account), "课堂笔记连接已断开。")}>确认断开</button><button disabled={!!busy} onClick={() => setConfirmDisconnect(false)}>取消</button></div>}
    <div className="cc-settings-feedback" aria-live="polite">{error && <ContentMessage tone="error">{error}</ContentMessage>}{success && <ContentMessage>{success}</ContentMessage>}</div>
    {state?.configured && <section className="cc-bindings"><div className="cc-section-heading"><h3>课程关联</h3><span className="cc-muted">{unbound} 门待关联</span></div><p className="cc-muted">确认对应的 eLearning 课程后，笔记才会出现在课程页。同名或跨学期课程请核对学期。</p>
      {!state.courses.length && <p className="cc-empty">同步成功后，这里会列出订阅仓库中的课程。</p>}
      {state.courses.map(source => {
        const bound = state.bindings.find(binding => binding.icourseCourseId === source.id);
        const recommendation = !bound ? recommendedCourse(source, courses) : undefined;
        const choice = bindingChoices[source.id] ?? (bound ? String(bound.canvasCourseId) : recommendation ? String(recommendation.id) : "");
        return <div key={source.id} className="cc-binding-row"><div><strong>{source.title}</strong><p>{source.teacher || "教师未提供"}{source.terms.length ? `　${source.terms.join("、")}` : ""}</p><small className="cc-muted">iCourse {source.id}{bound ? "　已关联" : recommendation ? "　下方为推荐，请确认" : "　待关联"}</small></div><div className="cc-binding-controls"><select aria-label={`为 ${source.title} 选择 eLearning 课程`} value={choice} disabled={!!busy} onChange={event => setBindingChoices(current => ({ ...current, [source.id]: event.target.value }))}><option value="">暂不关联</option>{bound && !courses.some(course => course.id === bound.canvasCourseId) && <option value={bound.canvasCourseId}>历史课程 {bound.canvasCourseId}</option>}{courses.map(course => <option key={course.id} value={course.id}>{course.displayName}（{course.termName}）</option>)}</select><button disabled={!!busy || (bound ? choice === String(bound.canvasCourseId) : !choice)} onClick={() => bind(source.id, choice)}>{busy === `bind:${source.id}` ? "保存中…" : bound ? choice ? "保存关联" : "解除关联" : "确认关联"}</button></div></div>;
      })}
      <details className="cc-link-binding"><summary>粘贴 iCourse 课程链接关联</summary><label>iCourse 课程链接或编号<input value={courseLink} onChange={event => setCourseLink(event.target.value)} placeholder="粘贴课程链接，或输入课程编号" /></label><label>对应的 eLearning 课程<select value={linkCourseId} onChange={event => setLinkCourseId(event.target.value)}><option value="">选择课程</option>{courses.map(course => <option key={course.id} value={course.id}>{course.displayName}（{course.termName}）</option>)}</select></label><button disabled={!!busy || !courseLink.trim() || !linkCourseId} onClick={() => { const id = parseCourseReference(courseLink); if (!id) { setError("未识别到课程编号，请检查 iCourse 链接或直接输入数字编号。"); return; } if (!state.courses.some(course => course.id === id)) { setError("这个课程尚未出现在订阅数据中，请先确认已订阅并完成同步。"); return; } bind(id, linkCourseId); }}>确认关联</button></details>
    </section>}
  </section>;
}
