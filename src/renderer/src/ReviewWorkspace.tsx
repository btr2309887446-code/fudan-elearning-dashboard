import { useEffect, useMemo, useRef, useState } from 'react';
import type { CourseSummary } from '../../core/types';
import type { WorkspaceCommand, WorkspaceData } from '../../core/workspace';
import type { LectureItem, LectureRef } from '../../core/lectures';
import { beijingDay, emptyReview, masteryLabels, reviewedMinutes, slotActive, slotCompleted, type ReviewItem, type ReviewPlan, type ReviewAction, type SchedulePreview } from '../../core/review';
import type { ReviewGeneration } from '../../main/review-ai';
import { Modal } from './WorkspaceParts';
import { asyncView } from './AsyncView';
import './review.css';
const Markdown = asyncView(() => import('./LectureMarkdown'));
const clone = <T,>(value: T): T => structuredClone(value);
const newItem = (): ReviewItem => ({ id: crypto.randomUUID(), title: '', notes: '', minutes: 20, extraMinutes: 0, mastery: 'unassessed', questions: [], sources: [] });
type Props = { account: number; course: CourseSummary; data: WorkspaceData; now: number; saving: boolean; error: string;
  initialPlan?: string; mutate(command: WorkspaceCommand): Promise<boolean>; onBack(): void; onRead(ref: LectureRef): void; onTask(id: string): void };

export default function ReviewWorkspace({ account, course, data, now, saving, error, initialPlan, mutate, onBack, onRead, onTask }: Props) {
  const review = data.review ?? emptyReview();
  const plans = review.plans.filter(p => p.courseId === course.id);
  const [planId, setPlanId] = useState(initialPlan ?? plans[0]?.id ?? '');
  const [planDraft, setPlanDraft] = useState<ReviewPlan | null>(null);
  const [itemDraft, setItemDraft] = useState<ReviewItem | null>(null);
  const [draftRevision, setDraftRevision] = useState(review.revision);
  const [deleting, setDeleting] = useState(false);
  const [schedule, setSchedule] = useState(false);
  const [ai, setAI] = useState(false);
  const [query, setQuery] = useState('');
  const [limit, setLimit] = useState(50);
  const [study, setStudy] = useState<string | null>(null);
  const [localError, setLocalError] = useState('');
  const [sourceNotice, setSourceNotice] = useState<Record<string, string>>({});
  const [notice, setNotice] = useState('');
  const alive = useRef(true);
  useEffect(() => () => { alive.current = false; }, []);
  const plan = plans.find(p => p.id === planId);
  useEffect(() => { if (initialPlan) setPlanId(initialPlan); }, [initialPlan]);
  useEffect(() => { if (!plans.some(p => p.id === planId)) setPlanId(plans[0]?.id ?? ''); }, [plans.map(p => p.id).join('|'), planId]);
  const act = (action: ReviewAction) => mutate({ type: 'review', action });
  const savePlan = (next: ReviewPlan, revision = review.revision) => act({ kind: 'plan', plan: next, revision });
  const filtered = useMemo(() => plan?.items.filter(i => `${i.title} ${i.notes}`.toLowerCase().includes(query.toLowerCase())) ?? [], [plan, query]);
  const finished = plan?.items.filter(i => reviewedMinutes(data, plan.id, i.id) >= i.minutes + i.extraMinutes).length ?? 0;
  function editItem(item: ReviewItem) { setDraftRevision(review.revision); setItemDraft(clone(item)); }
  async function read(source: ReviewItem['sources'][number]) {
    setLocalError('');
    try { const result = await window.elearning.lectures.detail(account, source); if (!alive.current) return; if (!result.ok) throw Error(result.error.message);
      if (result.data.summaryHash !== source.summaryHash) { setSourceNotice(old => ({ ...old, [source.lectureId]: '来源已更新，清单和自测题保留原内容。' })); }
      setStudy(null); onRead(source);
    } catch (e) { if (alive.current) setLocalError(`来源暂不可用，已保存的复习内容仍可使用：${e instanceof Error ? e.message : String(e)}`); }
  }
  const studying = plan?.items.find(i => i.id === study);
  useEffect(() => {
    let current = true;
    for (const source of studying?.sources ?? []) void window.elearning.lectures.detail(account, source).then(result => {
      if (!current) return;
      const text = !result.ok ? '来源暂不可用，已保存的复习内容仍可使用。' : result.data.summaryHash !== source.summaryHash ? '来源已更新，清单和自测题保留原内容。' : '';
      setSourceNotice(old => ({ ...old, [source.lectureId]: text }));
    }).catch(() => { if (current) setSourceNotice(old => ({ ...old, [source.lectureId]: '来源读取失败，可稍后重试。' })); });
    return () => { current = false; };
  }, [study, account]);
  return <section className="rv-workspace" aria-label="课程复习工作区" data-testid="review-workspace">
    <header className="rv-header"><button onClick={onBack}>← 返回课程</button><div><small>{course.displayName}</small><h2>复习计划</h2></div><button onClick={() => setSchedule(true)}>跨课程排期</button></header>
    <div className="rv-layout"><nav aria-label="复习计划" className="rv-plans">
      <button className="primary" onClick={() => { setDraftRevision(review.revision); setPlanDraft({ id: crypto.randomUUID(), courseId: course.id, title: '', examDate: null, items: [] }); }}>新建复习计划</button>
      {plans.map(p => <button key={p.id} aria-current={p.id === planId ? 'page' : undefined} onClick={() => { setPlanId(p.id); setStudy(null); setQuery(''); setLimit(50); }}><strong>{p.title}</strong><small>{p.examDate ? `${p.examDate} 考试` : '尚未安排考试日期'}</small></button>)}
      {!plans.length && <p>从选定的课堂内容开始，也可以手动整理知识点。</p>}
    </nav><div className="rv-content">
      {(error || localError) && <p role="alert" className="rv-error">{localError || error}</p>}
      {notice && <p role="status">{notice}</p>}
      {plan ? <>
        <div className="rv-title"><div><h2>{plan.title}</h2><p>{plan.examDate ? `${plan.examDate} 考试` : '设置考试日期后可生成日程'} · 已完成复习 {finished}/{plan.items.length} 项</p></div><button onClick={() => { setDraftRevision(review.revision); setPlanDraft(clone(plan)); }}>编辑计划</button><button onClick={() => setDeleting(true)}>删除计划</button></div>
        <div className="rv-progress" aria-label="掌握程度分布">{Object.entries(masteryLabels).map(([key, name]) => <span key={key}>{name} <strong>{plan.items.filter(i => i.mastery === key).length}</strong></span>)}</div>
        <div className="rv-tools"><input aria-label="搜索复习项" placeholder="搜索知识点或备注" value={query} onChange={e => { setQuery(e.target.value); setLimit(50); }} /><button onClick={() => editItem(newItem())}>添加知识点</button><button onClick={() => setAI(true)}>从课堂摘要生成</button></div>
        {!filtered.length && <p className="rv-empty">还没有符合条件的复习项。手动添加，或选择课堂摘要生成清单与自测题。</p>}
        <ol className="rv-items">{filtered.slice(0, limit).map((item, index) => <li key={item.id}>
          <div><button className="rv-item-title" onClick={() => setStudy(item.id)}>{item.title}</button><small>{item.minutes} 分钟 · 已复习 {reviewedMinutes(data, plan.id, item.id)} 分钟{item.extraMinutes > 0 && ` · 加练 ${item.extraMinutes} 分钟`}</small><p>{item.notes}</p></div>
          <div className="rv-row-actions"><select aria-label={`${item.title} 掌握程度`} disabled={saving} value={item.mastery} onChange={e => void savePlan({ ...plan, items: plan.items.map(i => i.id === item.id ? { ...i, mastery: e.target.value as ReviewItem['mastery'] } : i) })}>{Object.entries(masteryLabels).map(([v, l]) => <option key={v} value={v}>{l}</option>)}</select>
            <button onClick={() => setStudy(item.id)}>开始自测</button><button onClick={() => editItem(item)}>编辑</button>
            <button disabled={saving} onClick={async () => { if (await savePlan({ ...plan, items: plan.items.map(i => i.id === item.id ? { ...i, extraMinutes: i.extraMinutes + i.minutes } : i) })) setNotice('已增加一次复习，请在跨课程排期中预览安排。'); }}>再复习一次</button>
            <button aria-label={`上移 ${item.title}`} disabled={saving || index === 0 || !!query} onClick={() => { const items = [...plan.items]; [items[index - 1], items[index]] = [items[index], items[index - 1]]; void savePlan({ ...plan, items }); }}>上移</button>
          </div>
        </li>)}</ol>
        {filtered.length > limit && <button onClick={() => setLimit(n => n + 50)}>加载更多（共 {filtered.length} 项）</button>}
        <details><summary>已安排的复习任务</summary>{review.slots.filter(s => s.planId === plan.id && slotActive(data, s)).sort((a, b) => a.date.localeCompare(b.date)).map(s => <div className="rv-slot" key={s.id}><button onClick={() => onTask(`personal:${s.taskId}:single`)}>{s.date} · {s.allocations.reduce((n, a) => n + a.minutes, 0)} 分钟 · {slotCompleted(data, s) ? '已完成' : '待复习'}</button><label><input type="checkbox" checked={s.locked} disabled={saving || slotCompleted(data, s)} onChange={e => void act({ kind: 'lock', slotId: s.id, locked: e.target.checked, revision: review.revision })} />锁定日期</label></div>)}</details>
      </> : <p className="rv-empty">创建一份课程复习计划，记录知识点、安排考试前的复习，并用自测检查理解。</p>}
    </div></div>
    {planDraft && <Modal title={plans.some(p => p.id === planDraft.id) ? '编辑复习计划' : '新建复习计划'} close={() => setPlanDraft(null)} saving={saving}><form onSubmit={async e => { e.preventDefault(); if (await savePlan(planDraft, draftRevision)) { setPlanId(planDraft.id); setPlanDraft(null); } }}><label>计划名称<input data-initial-focus required maxLength={200} value={planDraft.title} onChange={e => setPlanDraft({ ...planDraft, title: e.target.value })} /></label><label>考试日期（可留空）<input type="date" value={planDraft.examDate ?? ''} onChange={e => setPlanDraft({ ...planDraft, examDate: e.target.value || null })} /></label>{error && <p role="alert">{error}</p>}<button className="primary" disabled={saving}>{saving ? '保存中…' : '保存计划'}</button></form></Modal>}
    {itemDraft && plan && <Modal title="编辑知识点与自测" close={() => setItemDraft(null)} saving={saving}><form onSubmit={async e => { e.preventDefault(); const exists = plan.items.some(i => i.id === itemDraft.id); if (await savePlan({ ...plan, items: exists ? plan.items.map(i => i.id === itemDraft.id ? itemDraft : i) : [...plan.items, itemDraft] }, draftRevision)) setItemDraft(null); }}>
      <label>知识点<input data-initial-focus required maxLength={500} value={itemDraft.title} onChange={e => setItemDraft({ ...itemDraft, title: e.target.value })} /></label><label>个人备注<textarea maxLength={12000} value={itemDraft.notes} onChange={e => setItemDraft({ ...itemDraft, notes: e.target.value })} /></label><label>预计用时（分钟）<input type="number" required min={1} max={1440} value={itemDraft.minutes} onChange={e => setItemDraft({ ...itemDraft, minutes: Number(e.target.value) })} /></label>
      {itemDraft.questions.map((q, index) => <fieldset key={index}><legend>自测 {index + 1}</legend><label>问题<textarea required value={q.question} maxLength={4000} onChange={e => setItemDraft({ ...itemDraft, questions: itemDraft.questions.map((v, n) => n === index ? { ...v, question: e.target.value } : v) })} /></label><label>参考答案<textarea value={q.answer} maxLength={12000} onChange={e => setItemDraft({ ...itemDraft, questions: itemDraft.questions.map((v, n) => n === index ? { ...v, answer: e.target.value } : v) })} /></label><button type="button" onClick={() => setItemDraft({ ...itemDraft, questions: itemDraft.questions.filter((_, n) => n !== index) })}>移除此题</button></fieldset>)}
      <button type="button" disabled={itemDraft.questions.length >= 10} onClick={() => setItemDraft({ ...itemDraft, questions: [...itemDraft.questions, { question: '', answer: '' }] })}>添加自测题</button>
      {error && <p role="alert">{error}</p>}<div className="rv-tools"><button className="primary" disabled={saving}>{saving ? '保存中…' : '保存知识点'}</button>{plan.items.some(i => i.id === itemDraft.id) && <button type="button" disabled={saving} onClick={async () => { if (!confirm('删除这个知识点及自测题？未完成的关联安排须先在任务页取消。')) return; if (await savePlan({ ...plan, items: plan.items.filter(i => i.id !== itemDraft.id) }, draftRevision)) setItemDraft(null); }}>删除知识点</button>}</div>
    </form></Modal>}
    {deleting && plan && <Modal title="删除复习计划" close={() => setDeleting(false)} saving={saving}><p>删除“{plan.title}”及其 {review.slots.filter(s => s.planId === plan.id).length} 项复习任务？普通个人任务和学校作业保留。</p>{error && <p role="alert">{error}</p>}<button disabled={saving} onClick={async () => { if (await act({ kind: 'remove', planId: plan.id, revision: review.revision })) setDeleting(false); }}>确认删除</button></Modal>}
    {studying && <Modal title={`自测 · ${studying.title}`} close={() => setStudy(null)}>
      <p>先尝试回答，再展开参考答案。掌握程度由你评估。</p>{!studying.questions.length && <p>尚未添加自测题，可先回顾知识点再记录掌握程度。</p>}
      {studying.questions.map((q, index) => <section className="rv-question" key={`${studying.id}:${index}`}><Markdown text={q.question} onError={setLocalError} /><details><summary>查看参考答案</summary><Markdown text={q.answer || '暂无参考答案'} onError={setLocalError} /></details></section>)}
      <label>自评掌握程度<select value={studying.mastery} disabled={saving} onChange={e => void savePlan({ ...plan!, items: plan!.items.map(i => i.id === studying.id ? { ...i, mastery: e.target.value as ReviewItem['mastery'] } : i) })}>{Object.entries(masteryLabels).map(([v, l]) => <option key={v} value={v}>{l}</option>)}</select></label>
      {studying.sources.map((s, index) => <blockquote key={index}><p>{s.quote}</p><button onClick={() => void read(s)}>{s.title} · 返回来源</button>{sourceNotice[s.lectureId] && <p role="status">{sourceNotice[s.lectureId]}</p>}</blockquote>)}{(error || localError) && <p role="alert">{error || localError}</p>}
    </Modal>}
    {schedule && <Schedule account={account} data={data} now={now} saving={saving} error={error} close={() => setSchedule(false)} act={act} />}
    {ai && plan && <Generate account={account} courseId={course.id} plan={plan} saving={saving} error={error} close={() => setAI(false)} save={items => savePlan({ ...plan, items: [...plan.items, ...items] })} />}
  </section>;
}

function Schedule({ account, data, now, saving, error, close, act }: { account: number; data: WorkspaceData; now: number; saving: boolean; error: string; close(): void; act(action: ReviewAction): Promise<boolean> }) {
  const review = data.review ?? emptyReview();
  const [budget, setBudget] = useState([...review.budget]); const [finishTime, setTime] = useState(review.finishTime);
  const [start, setStart] = useState(beijingDay(now)); const [preview, setPreview] = useState<SchedulePreview | null>(null);
  const [localError, setError] = useState(''); const [busy, setBusy] = useState(false); const alive = useRef(true);
  useEffect(() => () => { alive.current = false; }, []);
  const dirty = JSON.stringify(budget) !== JSON.stringify(review.budget) || finishTime !== review.finishTime;
  async function prepare() { if (busy) return; setBusy(true); setError(''); try { const r = await window.elearning.review.preview(account, start); if (!alive.current) return; if (!r.ok) throw Error(r.error.message); setPreview(r.data); } catch (e) { if (alive.current) setError(String(e)); } finally { if (alive.current) setBusy(false); } }
  return <Modal title="跨课程复习排期" close={close} saving={saving}><p>所有课程共用以下每日预算。已完成与锁定的安排保留，排到各门考试前一天。</p><div className="rv-week">{['日', '一', '二', '三', '四', '五', '六'].map((day, i) => <label key={day}>周{day}<input type="number" min={0} max={720} aria-label={`周${day}复习分钟`} value={budget[i]} onChange={e => { setBudget(b => b.map((n, j) => i === j ? Number(e.target.value) : n)); setPreview(null); }} /></label>)}</div>
    <label>每天计划完成时间<input type="time" value={finishTime} onChange={e => { setTime(e.target.value); setPreview(null); }} /></label>
    <button disabled={saving || !dirty} onClick={() => void act({ kind: 'budget', budget, finishTime, revision: review.revision })}>保存每日预算</button>
    <label>开始日期<input type="date" min={beijingDay(now)} value={start} onChange={e => { setStart(e.target.value); setPreview(null); }} /></label>
    <button disabled={saving || busy || dirty} onClick={() => void prepare()}>{busy ? '正在计算…' : '预览排期／重排'}</button>{dirty && <small>请先保存预算再预览。</small>}
    {(localError || error) && <p role="alert">{localError || error}</p>}
    {preview && <div className="rv-schedule"><p>新增 {preview.changes.added} 项 · 调整内容 {preview.changes.moved} 项 · 取消旧安排 {preview.changes.removed} 项</p>
      {preview.warnings.map(w => <p role="status" key={w}>{w}</p>)}{preview.shortages.map(s => <p className="rv-error" key={s.planId}>{review.plans.find(p => p.id === s.planId)?.title}：{s.reason}，尚缺 {s.minutes} 分钟。可调整预算、考试日期或减少复习范围。</p>)}
      {preview.slots.map(s => <div className="rv-slot" key={s.id}><strong>{s.date}</strong><span>{review.plans.find(p => p.id === s.planId)?.title} · {s.allocations.reduce((n, a) => n + a.minutes, 0)} 分钟</span><details><summary>本次复习内容</summary>{s.allocations.map(a => <p key={a.itemId}>{review.plans.find(p => p.id === s.planId)?.items.find(i => i.id === a.itemId)?.title} · {a.minutes} 分钟</p>)}</details></div>)}
      {review.slots.filter(s => slotActive(data, s) && !s.locked && !slotCompleted(data, s) && !preview.slots.some(n => n.id === s.id)).map(s => <p key={s.id}>将取消旧安排：{s.date} · {review.plans.find(p => p.id === s.planId)?.title}</p>)}
      {!preview.slots.length && <p>没有新增可安排的复习内容。</p>}
      <button className="primary" disabled={saving || preview.revision !== review.revision} onClick={async () => { if (await act({ kind: 'schedule', revision: preview.revision, start: preview.start, expected: JSON.stringify(preview.slots) })) close(); }}>{saving ? '保存中…' : '确认更新复习任务'}</button>{preview.revision !== review.revision && <p>计划已变化，请重新预览。</p>}
    </div>}
  </Modal>;
}

function Generate({ account, courseId, plan, saving, error, close, save }: { account: number; courseId: number; plan: ReviewPlan; saving: boolean; error: string; close(): void; save(items: ReviewItem[]): Promise<boolean> }) {
  const [lectures, setLectures] = useState<LectureItem[]>([]), [total, setTotal] = useState(0), [selected, setSelected] = useState<Set<string>>(new Set());
  const [job, setJob] = useState<ReviewGeneration | null>(null), [busy, setBusy] = useState(false), [loading, setLoading] = useState(false), [localError, setError] = useState('');
  const [results, setResults] = useState<Record<number, ReviewItem[]>>({}), [failures, setFailures] = useState<Record<number, string>>({}), [progress, setProgress] = useState('');
  const [picked, setPicked] = useState<Set<string>>(new Set()), [drafts, setDrafts] = useState<Record<string, ReviewItem>>({});
  const materialIdentity = useRef('');
  const alive = useRef(true), running = useRef(false), jobRef = useRef<string | null>(null), stop = useRef(false);
  useEffect(() => { void load(0); return () => { alive.current = false; stop.current = true; if (jobRef.current) void window.elearning.review.cancel(account, jobRef.current); }; }, []);
  async function load(offset: number) { if (loading) return; setLoading(true); try { const r = await window.elearning.lectures.list(account, courseId, '', offset); if (!alive.current) return; if (!r.ok) throw Error(r.error.message); setLectures(old => offset ? [...old, ...r.data.items] : r.data.items); setTotal(r.data.total); } catch (e) { if (alive.current) setError(String(e)); } finally { if (alive.current) setLoading(false); } }
  async function prepare() { if (running.current) return; running.current = true; setBusy(true); setError(''); try { const refs = lectures.filter(l => selected.has(`${l.icourseCourseId}:${l.lectureId}`)); const r = await window.elearning.review.prepare(account, courseId, refs); if (!alive.current) { if (r.ok) void window.elearning.review.cancel(account, r.data.id); return; } if (!r.ok) throw Error(r.error.message); const identity = JSON.stringify(r.data.batches.map(b => b.identity)); if (materialIdentity.current && materialIdentity.current !== identity && Object.keys(results).length) { void window.elearning.review.cancel(account, r.data.id); throw Error('材料已更新，请先保存已有结果，再重新生成。'); } materialIdentity.current = identity; jobRef.current = r.data.id; setJob(r.data); } catch (e) { if (alive.current) setError(String(e)); } finally { running.current = false; if (alive.current) setBusy(false); } }
  async function generate(indices: number[]) { if (!job || running.current) return; running.current = true; setBusy(true); stop.current = false; setError('');
    try { for (const index of indices) { if (stop.current || !alive.current) break; setProgress(`正在生成第 ${index + 1}/${job.batches.length} 批…`); const r = await window.elearning.review.generate(account, job.id, index); if (!alive.current || stop.current) break;
      if (r.ok) { const items = r.data.items.filter(i => !plan.items.some(p => p.title === i.title && p.sources.some(s => i.sources.some(n => n.quote === s.quote && n.lectureId === s.lectureId && n.sourceId === s.sourceId)))); setResults(old => ({ ...old, [index]: items })); setPicked(old => new Set([...old, ...items.map(i => i.id)])); setFailures(old => { const next = { ...old }; delete next[index]; return next; }); if (r.data.rejected) setError(`${r.data.rejected} 项未通过来源或格式校验，已排除。`); }
      else setFailures(old => ({ ...old, [index]: r.error.message }));
    } } catch (e) { if (alive.current) setError(String(e)); } finally { running.current = false; if (alive.current) { setBusy(false); setProgress(stop.current ? '已停止，已完成的结果仍保留。重新选择材料后可继续生成。' : '生成结束，请检查内容后保存。'); } }
  }
  const suggestions = Object.values(results).flat();
  return <Modal title="从课堂摘要生成复习清单与自测" close={close} saving={saving}>
    {!job && !suggestions.length && <><p>仅发送选中的摘要到你配置的模型服务；生成内容需自行核对。</p>{lectures.map(l => <label className="rv-check" key={`${l.icourseCourseId}:${l.lectureId}`}><input type="checkbox" disabled={busy || !l.hasSummary} checked={selected.has(`${l.icourseCourseId}:${l.lectureId}`)} onChange={e => setSelected(old => { const next = new Set(old); const key = `${l.icourseCourseId}:${l.lectureId}`; e.target.checked ? next.add(key) : next.delete(key); return next; })} />{l.title}{!l.hasSummary && '（暂无摘要）'}</label>)}{lectures.length < total && <button disabled={loading} onClick={() => void load(lectures.length)}>加载更多课次</button>}{!lectures.length && !loading && <button onClick={() => void load(0)}>重试读取课次</button>}<button disabled={busy || !selected.size} onClick={() => void prepare()}>{busy ? '准备材料…' : '查看生成范围'}</button></>}
    {job && <><p>将发送 {selected.size} 次课的 {job.batches.reduce((n, b) => n + b.characters, 0).toLocaleString()} 字符，分为 {job.batches.length} 批。服务：{job.endpoint} · 模型：{job.model}。费用由该服务计费。</p><button className="primary" disabled={busy} onClick={() => void generate(job.batches.filter(b => !results[b.index]).map(b => b.index))}>发送摘要并生成{suggestions.length ? '剩余批次' : ''}</button></>}
    {busy && <button onClick={() => { stop.current = true; if (jobRef.current) void window.elearning.review.cancel(account, jobRef.current); setJob(null); }}>停止生成</button>}
    <p role="status">{progress}</p>{(localError || error) && <p role="alert">{localError || error}</p>}
    {!job && !busy && !!suggestions.length && <button onClick={() => void prepare()}>重新准备剩余材料（保留已生成结果）</button>}
    {Object.entries(failures).map(([index, message]) => <div key={index}><p role="alert">第 {Number(index) + 1} 批：{message}</p><button disabled={busy || !job} onClick={() => void generate([Number(index)])}>重试此批</button></div>)}
    {suggestions.map(item => { const draft = drafts[item.id] ?? item; return <fieldset key={item.id}><legend><label className="rv-check"><input type="checkbox" checked={picked.has(item.id)} onChange={e => setPicked(old => { const next = new Set(old); e.target.checked ? next.add(item.id) : next.delete(item.id); return next; })} />加入此知识点</label></legend><label>知识点<input value={draft.title} onChange={e => setDrafts(old => ({ ...old, [item.id]: { ...draft, title: e.target.value } }))} /></label><label>复习要点<textarea value={draft.notes} onChange={e => setDrafts(old => ({ ...old, [item.id]: { ...draft, notes: e.target.value } }))} /></label>{draft.questions.map((q, index) => <div key={index}><label>自测题<textarea value={q.question} onChange={e => setDrafts(old => ({ ...old, [item.id]: { ...draft, questions: draft.questions.map((v, n) => n === index ? { ...v, question: e.target.value } : v) } }))} /></label><label>参考答案<textarea value={q.answer} onChange={e => setDrafts(old => ({ ...old, [item.id]: { ...draft, questions: draft.questions.map((v, n) => n === index ? { ...v, answer: e.target.value } : v) } }))} /></label></div>)}<blockquote>{draft.sources[0]?.quote}<small>{draft.sources[0]?.title}</small></blockquote></fieldset>; })}
    {!!suggestions.length && <button className="primary" disabled={busy || saving || !picked.size} onClick={async () => { const items = suggestions.filter(i => picked.has(i.id)).map(i => drafts[i.id] ?? i); if (await save(items)) close(); }}>{saving ? '保存中…' : `保存选中 ${picked.size} 项`}</button>}
  </Modal>;
}
