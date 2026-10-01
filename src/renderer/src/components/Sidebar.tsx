import { useEffect, useState } from 'react';
import type { CanvasProfile, Snapshot, TermGroup } from '../../../core/types';
import brandMark from '../assets/brand-mark.png';
import type { TermFilter } from '../types';
import Icon from './Icon';

interface Props {
  snapshot: Snapshot | null;
  profile: CanvasProfile | null;
  tab: 'overview' | 'timeline';
  termFilter: TermFilter;
  onTab: (tab: 'overview' | 'timeline') => void;
  onTerm: (value: TermFilter) => void;
  onLogout: () => void;
}

export default function Sidebar({
  snapshot,
  profile,
  tab,
  termFilter,
  onTab,
  onTerm,
  onLogout,
}: Props) {
  const terms: TermGroup[] = snapshot?.terms ?? [];
  const courses = snapshot?.courses ?? [];
  const todoCount = snapshot
    ? snapshot.assignments.filter((a) => a.score === null && !a.submittedAt && !a.missing).length
    : 0;

  const initial = (profile?.name ?? '?').trim().charAt(0);

  // 版本号来自 package.json。装了两版却只差内容时，光看界面分不清，
  // 所以在这里显示出来。
  const [version, setVersion] = useState('');
  useEffect(() => {
    void window.elearning.version().then(setVersion);
  }, []);

  return (
    <aside className="sidebar">
      <div className="sb-brand">
        <img className="sb-mark" src={brandMark} alt="" />
        <div className="sb-brand-text">
          <div className="sb-brand-title">eLearning 看板</div>
          <div className="sb-brand-sub">elearning.fudan.edu.cn</div>
        </div>
      </div>

      <nav className="sb-nav">
        <button className={`sb-item ${tab === 'overview' ? 'active' : ''}`} onClick={() => onTab('overview')}>
          <Icon name="dashboard" />
          总览
          {courses.length > 0 && <span className="sb-badge">{courses.length}</span>}
        </button>
        <button className={`sb-item ${tab === 'timeline' ? 'active' : ''}`} onClick={() => onTab('timeline')}>
          <Icon name="list" />
          作业与截止
          {todoCount > 0 && <span className="sb-badge">{todoCount}</span>}
        </button>
      </nav>

      <div className="sb-divider" />

      <div className="sb-label">学期</div>
      <div className="sb-terms">
        <button
          className={`sb-term ${termFilter === 'all' ? 'active' : ''}`}
          onClick={() => onTerm('all')}
        >
          <Icon name="layers" size={15} />
          <span className="sb-term-name">全部学期</span>
          <span className="sb-term-count">{courses.length}</span>
        </button>

        {terms.map((t) => (
          <button
            key={String(t.id)}
            className={`sb-term ${termFilter === t.id ? 'active' : ''}`}
            onClick={() => onTerm(t.id)}
            title={t.name}
          >
            {t.isCurrent ? <span className="sb-dot" /> : <Icon name="book" size={15} />}
            <span className="sb-term-name">{t.name}</span>
            <span className="sb-term-count">{t.courseCount}</span>
          </button>
        ))}

        {terms.length === 0 && (
          <div style={{ padding: '6px 11px', fontSize: 12, color: 'var(--muted)' }}>暂无学期数据</div>
        )}
      </div>

      <div className="sb-user">
        <div className="sb-avatar">{initial}</div>
        <div className="sb-user-text">
          <div className="sb-user-name">{profile?.name ?? '未登录'}</div>
          <div className="sb-user-meta">
            {snapshot ? `${snapshot.assignments.length} 项作业` : '尚未同步'}
            {version ? ` · v${version}` : ''}
          </div>
        </div>
        <button className="icon-btn" onClick={onLogout} title="退出并清除本机登录状态">
          <Icon name="logout" size={17} />
        </button>
      </div>
    </aside>
  );
}
