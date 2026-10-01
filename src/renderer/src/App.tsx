import { useEffect, useMemo, useRef, useState } from 'react';
import type { AssignmentRow, CanvasProfile, Snapshot } from '../../core/types';
import AssignmentDetail from './components/AssignmentDetail';
import CourseDetail from './components/CourseDetail';
import Dashboard from './components/Dashboard';
import Icon from './components/Icon';
import LoginView from './components/LoginView';
import SettingsModal from './components/SettingsModal';
import Sidebar from './components/Sidebar';
import Timeline from './components/Timeline';
import type { TermFilter, Theme } from './types';

type Screen = 'booting' | 'login' | 'app';
type Tab = 'overview' | 'timeline';

export default function App() {
  const [screen, setScreen] = useState<Screen>('booting');
  const [tab, setTab] = useState<Tab>('overview');
  const [snapshot, setSnapshot] = useState<Snapshot | null>(null);
  const [profile, setProfile] = useState<CanvasProfile | null>(null);
  const [selectedCourse, setSelectedCourse] = useState<number | null>(null);
  const [busy, setBusy] = useState(false);
  const [progress, setProgress] = useState<{ done: number; total: number; label: string } | null>(null);
  const [error, setError] = useState<string | null>(null);
  const [notice, setNotice] = useState<string | null>(null);
  const [hideUnsubmitted, setHideUnsubmitted] = useState(false);
  /** 首页各板块的显示开关（key -> 是否显示）。 */
  const [dashboardSections, setDashboardSections] = useState<Record<string, boolean>>({});
  /** 当前打开的作业详情；null 表示浮层关闭。 */
  const [openAssignment, setOpenAssignment] = useState<AssignmentRow | null>(null);
  const [settingsOpen, setSettingsOpen] = useState(false);
  // Read the theme synchronously from localStorage so a dark-mode user never
  // sees a flash of the light theme while the preference IPC round-trips.
  const [theme, setTheme] = useState<Theme>(() => {
    try {
      const saved = localStorage.getItem('elearning.theme');
      if (saved === 'dark' || saved === 'light') return saved;
    } catch {
      /* localStorage unavailable */
    }
    return 'light';
  });
  const [termFilter, setTermFilter] = useState<TermFilter>('all');
  const termTouched = useRef(false);
  const themeTouched = useRef(false);
  const booted = useRef(false);

  // --- theme ---------------------------------------------------------------
  useEffect(() => {
    document.documentElement.dataset.theme = theme;
    try {
      localStorage.setItem('elearning.theme', theme);
    } catch {
      /* ignore */
    }
  }, [theme]);

  // Default to the semester currently in session, but never override a term the
  // user picked themselves.
  useEffect(() => {
    if (!snapshot) return;
    // Defensive: a cache written by an older build may lack `terms`.
    const terms = snapshot.terms ?? [];
    const current = terms.find((t) => t.isCurrent) ?? terms[0];
    setTermFilter((prev) => {
      const stillValid = prev !== 'all' && terms.some((t) => t.id === prev);
      if (stillValid && termTouched.current) return prev;
      return current ? current.id : 'all';
    });
  }, [snapshot]);

  // --- boot -----------------------------------------------------------------
  useEffect(() => {
    if (booted.current) return;
    booted.current = true;

    const off = window.elearning.data.onProgress((p) => setProgress(p));

    void (async () => {
      const p = await window.elearning.prefs.get();
      setHideUnsubmitted(p.hideUnsubmitted === true);
      setDashboardSections(p.dashboardSections ?? {});
      // Never let a slow disk read undo a choice the user just made.
      if (!themeTouched.current) {
        if (p.theme === 'dark' || p.theme === 'light') {
          setTheme(p.theme);
        } else if (window.matchMedia?.('(prefers-color-scheme: dark)').matches) {
          setTheme('dark');
        }
      }

      const cached = await window.elearning.data.cached();
      if (cached) {
        setSnapshot(cached);
        setProfile(cached.profile);
      }

      const status = await window.elearning.auth.status();
      if (status.ok && status.data.loggedIn) {
        setProfile(status.data.profile ?? cached?.profile ?? null);
        setScreen('app');
        void refresh(false);
      } else if (cached) {
        setScreen('app');
        setNotice('登录状态已失效，重新登录后可刷新数据。你仍可查看上次同步的内容。');
      } else {
        setScreen('login');
      }
    })();

    return off;
  }, []);

  async function refresh(force: boolean) {
    setBusy(true);
    setError(null);
    try {
      const res = await window.elearning.data.snapshot({ force });
      if (!res.ok) {
        if (res.error.kind === 'session_expired') {
          setScreen('login');
          setSnapshot(null);
          setNotice('登录状态已失效，请重新登录。');
          return;
        }
        setError(res.error.message);
        return;
      }
      setSnapshot(res.data);
      setProfile(res.data.profile);
      setNotice(null);
    } finally {
      setBusy(false);
      setProgress(null);
    }
  }

  async function toggleHideUnsubmitted(value: boolean) {
    setHideUnsubmitted(value);
    try {
      await window.elearning.prefs.set({ hideUnsubmitted: value });
    } catch {
      /* a failed preference write must not break the toggle */
    }
  }

  /** 首页板块开关。未出现的板块视为显示，这样新增板块时老用户也能看到。 */
  async function toggleDashboardSection(key: string) {
    const next = { ...dashboardSections, [key]: dashboardSections[key] === false };
    setDashboardSections(next);
    try {
      await window.elearning.prefs.set({ dashboardSections: next });
    } catch {
      /* 同上：偏好写失败不该影响界面 */
    }
  }

  function toggleTheme() {
    themeTouched.current = true;
    const next: Theme = theme === 'light' ? 'dark' : 'light';
    // Apply immediately rather than waiting for the effect to commit, so the
    // switch never feels laggy and cannot be lost to a render race.
    document.documentElement.dataset.theme = next;
    setTheme(next);
    void window.elearning.prefs.set({ theme: next });
  }

  async function logout() {
    await window.elearning.auth.logout();
    setSnapshot(null);
    setProfile(null);
    setSelectedCourse(null);
    setNotice(null);
    setScreen('login');
  }

  // --- derived --------------------------------------------------------------
  const scoped = useMemo(() => {
    if (!snapshot) return { courses: 0, assignments: 0 };
    if (termFilter === 'all') {
      return { courses: snapshot.courses.length, assignments: snapshot.assignments.length };
    }
    const ids = new Set(snapshot.courses.filter((c) => c.termId === termFilter).map((c) => c.id));
    return {
      courses: ids.size,
      assignments: snapshot.assignments.filter((a) => ids.has(a.courseId)).length,
    };
  }, [snapshot, termFilter]);

  const termName =
    termFilter === 'all'
      ? '全部学期'
      : ((snapshot?.terms ?? []).find((t) => t.id === termFilter)?.name ?? '全部学期');

  const selectedCourseName =
    selectedCourse !== null
      ? (snapshot?.courses.find((c) => c.id === selectedCourse)?.displayName ?? '课程详情')
      : null;

  const title =
    selectedCourse !== null && tab === 'overview'
      ? (selectedCourseName ?? '课程详情')
      : tab === 'timeline'
        ? '作业与截止'
        : '学习总览';

  const subtitle =
    selectedCourse !== null
      ? termName
      : snapshot
        ? `${termName} · ${scoped.courses} 门课程 · ${scoped.assignments} 项作业`
        : '正在读取本地缓存…';

  // --- render ---------------------------------------------------------------

  if (screen === 'booting') {
    return (
      <div className="login-wrap">
        <div className="loading-line">
          <span className="spin" />
          正在启动…
        </div>
      </div>
    );
  }

  if (screen === 'login') {
    return (
      <LoginView
        notice={notice}
        theme={theme}
        onToggleTheme={toggleTheme}
        onSuccess={(p) => {
          setProfile(p);
          setNotice(null);
          setScreen('app');
          void refresh(true);
        }}
      />
    );
  }

  return (
    <div className="shell">
      <Sidebar
        snapshot={snapshot}
        profile={profile}
        tab={tab}
        termFilter={termFilter}
        onTab={(t) => {
          setTab(t);
          setSelectedCourse(null);
        }}
        onTerm={(value) => {
          termTouched.current = true;
          setTermFilter(value);
          setSelectedCourse(null);
        }}
        onLogout={() => void logout()}
      />

      <div className="main">
        <header className="page-head">
          {selectedCourse !== null && (
            <button className="back-link" onClick={() => setSelectedCourse(null)} title="返回总览">
              <Icon name="back" />
            </button>
          )}
          <div style={{ minWidth: 0 }}>
            <h1 className="page-title">{title}</h1>
            <div className="page-sub">{subtitle}</div>
          </div>

          <div className="spacer" />

          {progress ? (
            <div className="loading-line">
              <span className="spin" />
              读取 {progress.done}/{progress.total} 门课程…
            </div>
          ) : busy ? (
            <div className="loading-line">
              <span className="spin" />
              正在同步…
            </div>
          ) : null}

          <button
            className={`switch ${hideUnsubmitted ? 'on' : ''}`}
            onClick={() => void toggleHideUnsubmitted(!hideUnsubmitted)}
            title="隐藏尚未提交的作业。只影响列表显示，不影响得分计算。"
          >
            <span className="switch-track">
              <span className="switch-knob" />
            </span>
            忽略未提交
          </button>

          <button className="icon-btn" onClick={toggleTheme} title={theme === 'light' ? '切换到深色' : '切换到浅色'}>
            <Icon name={theme === 'light' ? 'moon' : 'sun'} size={18} />
          </button>

          <button className="icon-btn" onClick={() => setSettingsOpen(true)} title="设置（作业简介的大模型接口）">
            <Icon name="sliders" size={18} />
          </button>

          <button className="btn" onClick={() => void refresh(true)} disabled={busy}>
            <Icon name="refresh" size={16} />
            刷新
          </button>
        </header>

        <main className="content">
          {error && <div className="alert alert-error">{error}</div>}
          {notice && <div className="alert alert-warn">{notice}</div>}

          {!snapshot && !busy && (
            <div className="empty">
              还没有数据。
              <div style={{ marginTop: 14 }}>
                <button className="btn btn-primary" onClick={() => void refresh(true)}>
                  立即同步
                </button>
              </div>
            </div>
          )}

          {snapshot && tab === 'overview' && selectedCourse === null && (
            <Dashboard
              snapshot={snapshot}
              termFilter={termFilter}
              hideUnsubmitted={hideUnsubmitted}
              sections={dashboardSections}
              onToggleSection={toggleDashboardSection}
              onOpenAssignment={setOpenAssignment}
              onSelectCourse={(id) => setSelectedCourse(id)}
            />
          )}

          {snapshot && tab === 'overview' && selectedCourse !== null && (
            <CourseDetail
              snapshot={snapshot}
              courseId={selectedCourse}
              hideUnsubmitted={hideUnsubmitted}
              onBack={() => setSelectedCourse(null)}
              onOpenAssignment={setOpenAssignment}
            />
          )}

          {snapshot && tab === 'timeline' && (
            <Timeline
              snapshot={snapshot}
              termFilter={termFilter}
              hideUnsubmitted={hideUnsubmitted}
              onOpenAssignment={setOpenAssignment}
              onSelectCourse={(id) => {
                setTab('overview');
                setSelectedCourse(id);
              }}
            />
          )}
        </main>
      </div>

      {/* 作业详情浮层：点作业不再直接跳浏览器 */}
      {openAssignment && (
        <AssignmentDetail row={openAssignment} onClose={() => setOpenAssignment(null)} />
      )}

      {settingsOpen && <SettingsModal onClose={() => setSettingsOpen(false)} />}
    </div>
  );
}
