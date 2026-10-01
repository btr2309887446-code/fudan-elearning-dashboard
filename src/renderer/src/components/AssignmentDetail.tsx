/**
 * 作业详情。
 *
 * 以前点「打开」是直接跳浏览器，等于把人赶出应用。现在改成应用内浮层：
 * 完整描述、提交状态、成绩，外加一段 100 字以内的简介。
 *
 * 简介来源有两种，界面上会标出来：
 *  - 「AI 摘要」：配了大模型接口，由模型压缩
 *  - 「原文截取」：没配接口时直接取描述前 100 字
 *
 * 描述按纯文本渲染，不用 dangerouslySetInnerHTML——
 * Canvas 返回的是远端 HTML，塞进 Electron 渲染进程没必要冒这个险。
 * 想看富文本排版可以点「在浏览器中打开」。
 */

import { useEffect, useRef, useState } from 'react';

import { htmlToPlainText } from '../../../core/summary';
import type { AssignmentRow } from '../../../core/types';
import { dueRelative, formatDate, formatScore, isCompleted, scoreColor } from '../util';
import { closeWithAnimation } from '../motion';
import Icon from './Icon';

interface Props {
  row: AssignmentRow;
  /** 这条作业是否已被标记为「无需提交」。 */
  ignored: boolean;
  onToggleIgnored: () => void;
  onClose: () => void;
}

export default function AssignmentDetail({
  row,
  ignored,
  onToggleIgnored,
  onClose,
}: Props) {
  // 退场动画期间先别卸载：直接消失和入场动画不对称。
  const backdropRef = useRef<HTMLDivElement>(null);
  const closing = useRef(false);

  function requestClose() {
    if (closing.current) return;
    closing.current = true;
    closeWithAnimation(backdropRef.current, onClose);
  }
  const [loading, setLoading] = useState(true);
  const [description, setDescription] = useState('');
  const [summary, setSummary] = useState('');
  const [source, setSource] = useState<'llm' | 'fallback' | 'none'>('none');
  const [summaryError, setSummaryError] = useState<string | undefined>();
  const [cached, setCached] = useState(false);
  const [error, setError] = useState<string | null>(null);

  useEffect(() => {
    let alive = true;
    setLoading(true);
    setError(null);

    void (async () => {
      const res = await window.elearning.assignment.detail(row.courseId, row.id);
      if (!alive) return;
      if (res.ok) {
        setDescription(res.data.description);
        setSummary(res.data.summary);
        setSource(res.data.summarySource);
        setSummaryError(res.data.summaryError);
        setCached(res.data.cached);
      } else {
        // 拉不到完整描述也不能白屏——先用列表里存的摘录顶上。
        setError(res.error.message);
        setDescription(row.descriptionExcerpt ?? '');
      }
      setLoading(false);
    })();

    return () => {
      alive = false;
    };
  }, [row.courseId, row.id, row.descriptionExcerpt]);

  // Esc 关闭，符合浮层的习惯。
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') requestClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [requestClose]);

  const rel = dueRelative(row.dueAt, isCompleted(row));
  const done = isCompleted(row);
  const plain = htmlToPlainText(description);
  const paragraphs = plain.split('\n').filter((l) => l.trim().length > 0);

  const stateLabel = row.excused
    ? '已免修'
    : row.missing
      ? '缺交'
      : row.late
        ? '迟交'
        : row.submittedAt
          ? '已提交'
          : row.gradedAt
            ? '已评分'
            : '未提交';

  const stateTone = row.missing
    ? 'tag-bad'
    : row.late
      ? 'tag-warn'
      : done
        ? 'tag-good'
        : 'tag-neutral';

  return (
    <div className="modal-backdrop" ref={backdropRef} onClick={requestClose}>
      <div className="modal" onClick={(e) => e.stopPropagation()} role="dialog" aria-modal="true">
        <div className="modal-head">
          <div style={{ flex: 1, minWidth: 0 }}>
            <div className="modal-title">{row.name}</div>
            <div className="modal-sub">
              {row.courseName}
              {row.groupName ? ` · ${row.groupName}` : ''}
            </div>
          </div>
          <button className="icon-btn" onClick={requestClose} title="关闭（Esc）">
            <Icon name="close" size={17} />
          </button>
        </div>

        <div className="modal-chips">
          <span className={`tag ${stateTone}`}>{stateLabel}</span>
          <span className="chip">
            <Icon name="clock" size={13} /> {formatDate(row.dueAt)}
          </span>
          {row.dueAt && (
            <span className="chip" style={{ color: rel.tone === 'overdue' ? 'var(--bad)' : undefined }}>
              {rel.text}
            </span>
          )}
          {row.pointsPossible !== null && <span className="chip">满分 {row.pointsPossible}</span>}
          {row.score !== null && (
            <span className="chip" style={{ color: scoreColor(row.percent), fontWeight: 600 }}>
              得分 {formatScore(row.score)}
              {row.percent !== null ? `（${Math.round(row.percent)}%）` : ''}
            </span>
          )}
          {row.submittedAt && <span className="chip">提交于 {formatDate(row.submittedAt)}</span>}
          {row.gradedAt && <span className="chip">批改于 {formatDate(row.gradedAt)}</span>}
        </div>

        <div className="modal-body">
          {/* --- 简介 ---
              正文本来就不到 100 字时 source 是 'none'，此时摘要栏整个不出现：
              「精简」一段本来就够短的说明，得到的东西和信息量一模一样，
              只会白占一块地方。下面「完整说明」里就是原文。 */}
          {source !== 'none' && (
            <div className="summary-block">
              <div className="summary-head">
                <Icon name={source === 'llm' ? 'sparkle' : 'file'} size={15} />
                <span>{source === 'llm' ? 'AI 摘要' : '原文截取'}</span>
                {cached && <span className="summary-note">已缓存</span>}
                {source === 'fallback' && !summaryError && (
                  <span className="summary-note">未接入大模型，直接取描述前 100 字</span>
                )}
              </div>
              <div className="summary-text">
                {loading ? '正在生成简介…' : summary || '这条作业没有文字说明。'}
              </div>
              {summaryError && (
                <div className="summary-err">
                  {summaryError}
                  <span style={{ color: 'var(--muted)' }}>（已降级为截取原文）</span>
                </div>
              )}
            </div>
          )}

          {/* --- 完整说明 --- */}
          <div className="section-head" style={{ marginTop: 18, marginBottom: 8 }}>
            <h2 style={{ fontSize: 15 }}>作业说明</h2>
            {!loading && plain.length > 0 && (
              <small style={{ color: 'var(--muted)' }}>{plain.length} 字</small>
            )}
          </div>

          {loading && <div className="loading-line">正在读取作业说明…</div>}

          {!loading && paragraphs.length === 0 && (
            <div className="empty">这条作业没有附说明。</div>
          )}

          {!loading && paragraphs.length > 0 && (
            <div className="desc-body">
              {paragraphs.map((line, i) => (
                <p key={i}>{line}</p>
              ))}
            </div>
          )}

          {error && (
            <div className="alert alert-warn" style={{ marginTop: 12 }}>
              完整说明获取失败（{error}），下面是本地缓存的摘录。
            </div>
          )}
        </div>

        <div className="modal-foot">
          <div style={{ flex: 1, fontSize: 12, color: 'var(--muted)' }}>
            {ignored
              ? '已标记为「无需提交」，不会出现在未交清单里'
              : row.htmlUrl
                ? '富文本排版、附件与提交入口在网页版'
                : '这条作业没有网页版链接'}
          </div>
          {/* 有些作业本质上不用交（签到、选做、老师明说不用交的），
              但 Canvas 仍算它们 unsubmitted，于是永远挂在未交清单里。
              这里让用户手动摘掉——只影响显示，不改得分。 */}
          <button
            className={`btn ${ignored ? 'btn-primary' : ''}`}
            onClick={onToggleIgnored}
            title={
              ignored
                ? '恢复：重新计入未交清单'
                : '标记为无需提交：从未交清单与缺交统计里移除'
            }
          >
            <Icon name={ignored ? 'check' : 'inbox'} size={15} />
            {ignored ? '已标记无需提交' : '无需提交'}
          </button>
          {row.htmlUrl && (
            <button className="btn" onClick={() => void window.elearning.open(row.htmlUrl as string)}>
              <Icon name="external" size={15} /> 在浏览器中打开
            </button>
          )}
          <button className="btn btn-primary" onClick={requestClose}>
            关闭
          </button>
        </div>
      </div>
    </div>
  );
}
