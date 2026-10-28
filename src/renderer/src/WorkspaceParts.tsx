import { useEffect, useMemo, useRef, useState, type ReactNode } from "react";
import type { Snapshot } from "../../core/types";
import {
  dayKey,
  type TaskDraft,
  type TaskView,
  type WorkspaceCommand,
  type WorkspaceData,
} from "../../core/workspace";



import { formatDate } from "./util";
import { useDialogClose } from "./Interaction";
const blankDraft = (): TaskDraft => ({
  title: "",
  notes: "",
  courseId: null,
  dueAt: null,
  repeat: "none",
  weekdays: [],
  endDate: null,
  checklist: [],
  reminders: [],
});
const localInput = (date: string | null) =>
  date
    ? new Date(Date.parse(date) + 8 * 3600000).toISOString().slice(0, 16)
    : "";
const fromInput = (date: string) =>
  date ? new Date(`${date}:00+08:00`).toISOString() : null;
export function Deadline({
  task,
  data,
  saving,
  mutate,
}: {
  task: TaskView;
  data: WorkspaceData;
  saving: boolean;
  mutate: (c: WorkspaceCommand) => Promise<boolean>;
}) {
  const id = `${task.row!.courseId}:${task.row!.id}`,
    [value, setValue] = useState(localInput(task.dueAt));
  const [message, setMessage] = useState("");
  useEffect(() => setValue(localInput(task.dueAt)), [task.id, task.dueAt]);
  return (
    <div className="ws-deadline">
      <label>
        手动截止时间（北京时间）
        <input
          type="datetime-local"
          value={value}
          onChange={(e) => setValue(e.target.value)}
        />
      </label>
      <div className="ws-actions">
        <button
          disabled={saving || !value}
          onClick={async () => { setMessage(""); if (await mutate({ type: "deadline", id, value: fromInput(value) })) setMessage("截止时间已保存"); }}
        >
          保存截止时间
        </button>
        <button
          disabled={saving || !data.deadlines[id]}
          onClick={async () => { setMessage(""); if (await mutate({ type: "deadline", id, value: null })) setMessage("已恢复学校时间"); }}
        >
          恢复学校时间
        </button>
      </div>
      <small>学校原始时间：{formatDate(task.row!.dueAt)}</small>
      <p className="ws-muted" role="status">{message || (!value ? "请选择截止时间后保存。" : !data.deadlines[id] ? "当前使用学校时间。" : "清除手动设置后恢复最新学校时间。")}</p>
    </div>
  );
}
function Modal({
  title,
  close,
  children,
  closing = false,
  saving = false,
}: {
  title: string;
  close: () => void;
  children: ReactNode;
  closing?: boolean;
  saving?: boolean;
}) {
  const ref = useRef<HTMLDialogElement>(null);
  useEffect(() => {
    const previous = document.activeElement as HTMLElement;
    ref.current?.showModal();
    ref.current?.querySelector<HTMLElement>("[data-initial-focus]")?.focus();
    return () => {
      ref.current?.close();
      if (previous?.isConnected) previous.focus({ preventScroll: true });
      else document.querySelector<HTMLElement>(".ws-detail-toolbar button, .ws-toolbar button")?.focus({ preventScroll: true });
    };
  }, []);
  return (
    <dialog
      className="ws-dialog"
      ref={ref}
      aria-label={title}
      data-closing={closing}
      aria-busy={saving}
      onCancel={(e) => {
        e.preventDefault();
        close();
      }}
    >
      <header>
        <h2>{title}</h2>
        <button type="button" title="关闭对话框" disabled={saving || closing} aria-label="关闭对话框" onClick={close}>
          ×
        </button>
      </header>
      {children}
    </dialog>
  );
}
export function TaskEditor({
  task,
  initialDraft,
  courses,
  saving,
  error,
  close,
  save,
}: {
  task?: TaskView;
  initialDraft?: TaskDraft;
  courses: Snapshot["courses"];
  saving: boolean;
  error: string;
  close: () => void;
  save: (draft: TaskDraft, scope: "one" | "future") => Promise<boolean>;
}) {
  const [d, setD] = useState<TaskDraft>(task?.draft ?? initialDraft ?? blankDraft()),
    [scope, setScope] = useState<"one" | "future">("one"),
    [reminders, setReminders] = useState(d.reminders.join(", ")),
    [err, setErr] = useState("");
  const recurring = task?.key !== "single" && !!task;
  const { closing, dismiss } = useDialogClose(close, saving);
  return (
    <Modal title={task ? "编辑个人任务" : "新建个人任务"} close={dismiss} closing={closing} saving={saving}>
      <form
        onSubmit={(e) => {
          e.preventDefault();
          if (saving || closing) return;
          setErr("");
          const values = reminders.trim()
            ? reminders.split(/[,，]/).map((v) => Number(v.trim()))
            : [];
          if (
            values.length > 5 ||
            values.some((v) => !Number.isInteger(v) || v < 0 || v > 525600)
          ) {
            setErr("最多 5 个提醒，填写 0–525600 的整数分钟数。");
            return;
          }
          if (d.repeat === "weekly" && !d.weekdays.length) { setErr("每周重复至少选择一天。"); return; }
          void save({ ...d, reminders: values }, scope).then(ok => { if (ok) dismiss(); });
        }}
      >
        <fieldset className="ws-form-fields" disabled={saving || closing}>
        <label>
          标题
          <input
            autoFocus
            data-initial-focus
            required
            maxLength={500}
            value={d.title}
            onChange={(e) => setD({ ...d, title: e.target.value })}
          />
        </label>
        <label>
          备注
          <textarea
            rows={3}
            value={d.notes}
            onChange={(e) => setD({ ...d, notes: e.target.value })}
          />
        </label>
        <div className="ws-form-grid">
          <label>
            课程
            <select
              value={d.courseId ?? ""}
              onChange={(e) =>
                setD({
                  ...d,
                  courseId: e.target.value ? Number(e.target.value) : null,
                })
              }
            >
              <option value="">不关联课程</option>
              {courses.map((c) => (
                <option key={c.id} value={c.id}>
                  {c.displayName}
                </option>
              ))}
            </select>
          </label>
          <label>
            截止时间（北京时间）
            <input
              type="datetime-local"
              required={d.repeat !== "none"}
              value={localInput(d.dueAt)}
              onChange={(e) => setD({ ...d, dueAt: fromInput(e.target.value) })}
            />
          </label>
        </div>
        {recurring && (
          <label>
            修改范围
            <select
              value={scope}
              onChange={(e) => setScope(e.target.value as "one" | "future")}
            >
              <option value="one">仅本次</option>
              <option value="future">本次及以后</option>
            </select>
          </label>
        )}
        {(!recurring || scope === "future") && (
          <>
            <div className="ws-form-grid">
              <label>
                重复
                <select
                  value={d.repeat}
                  onChange={(e) =>
                    setD({
                      ...d,
                      repeat: e.target.value as TaskDraft["repeat"],
                    })
                  }
                >
                  <option value="none">不重复</option>
                  <option value="daily">每日</option>
                  <option value="weekly">每周</option>
                  <option value="monthly">每月（缺失日期取月末）</option>
                </select>
              </label>
              <label>
                结束日期（可选）
                <input
                  type="date"
                  value={d.endDate ?? ""}
                  onChange={(e) =>
                    setD({ ...d, endDate: e.target.value || null })
                  }
                />
              </label>
            </div>
            {d.repeat === "weekly" && (
              <fieldset>
                <legend>每周日期（至少选择一天）</legend>
                {["日", "一", "二", "三", "四", "五", "六"].map((name, i) => (
                  <label className="ws-inline-check" key={i}>
                    <input
                      type="checkbox"
                      checked={d.weekdays.includes(i + 1)}
                      onChange={(e) =>
                        setD({
                          ...d,
                          weekdays: e.target.checked
                            ? [...d.weekdays, i + 1]
                            : d.weekdays.filter((v) => v !== i + 1),
                        })
                      }
                    />
                    {name}
                  </label>
                ))}
              </fieldset>
            )}
          </>
        )}
        <fieldset>
          <legend>子任务</legend>
          {d.checklist.map((c, i) => (
            <div className="ws-actions" key={c.id}>
              <input
                aria-label={`子任务 ${i + 1}`}
                required
                value={c.title}
                onChange={(e) =>
                  setD({
                    ...d,
                    checklist: d.checklist.map((x) =>
                      x.id === c.id ? { ...x, title: e.target.value } : x,
                    ),
                  })
                }
              />
              <button
                type="button"
                onClick={() =>
                  setD({
                    ...d,
                    checklist: d.checklist.filter((x) => x.id !== c.id),
                  })
                }
              >
                移除
              </button>
            </div>
          ))}
          <button
            type="button"
            onClick={() =>
              setD({
                ...d,
                checklist: [
                  ...d.checklist,
                  { id: crypto.randomUUID(), title: "" },
                ],
              })
            }
          >
            ＋ 添加子任务
          </button>
        </fieldset>
        <label>
          提醒：提前分钟数，逗号分隔，最多 5 个
          <input
            placeholder="例如 0, 30, 1440"
            value={reminders}
            aria-describedby="task-form-error"
            aria-invalid={err.startsWith("最多 5") || undefined}
            onChange={(e) => { setReminders(e.target.value); setErr(""); }}
          />
        </label>
        <small>通知需要在设置中开启；关闭应用后不会发送。</small>
        <p id="task-form-error" className="ws-form-error" role="alert">{err || error || "\u00a0"}</p>
        </fieldset>
        <footer>
          <button type="button" disabled={saving || closing} onClick={dismiss}>
            取消
          </button>
          <button className="primary" aria-busy={saving} disabled={saving || closing} type="submit">
            {saving ? "保存中…" : "保存任务"}
          </button>
        </footer>
      </form>
    </Modal>
  );
}
export function DeleteDialog({
  tasks,
  saving,
  error,
  close,
  confirm,
}: {
  tasks: TaskView[];
  saving: boolean;
  error: string;
  close: () => void;
  confirm: (scope: "one" | "future") => Promise<boolean>;
}) {
  const [scope, setScope] = useState<"one" | "future">("one");
  const { closing, dismiss } = useDialogClose(close, saving);
  return (
    <Modal title="删除个人任务" close={dismiss} closing={closing} saving={saving}>
      <p>确定删除选中的 {tasks.length} 项任务？此操作无法撤销。</p>
      <ul>{tasks.slice(0, 5).map(t => <li key={t.id}>{t.title}</li>)}</ul>
      {tasks.length > 5 && <p>以及另外 {tasks.length - 5} 项。</p>}
      {tasks.some((t) => t.key !== "single") && (
        <label>
          删除范围
          <select
            value={scope}
            onChange={(e) => setScope(e.target.value as "one" | "future")}
          >
            <option value="one">仅本次</option>
            <option value="future">本次及以后</option>
          </select>
        </label>
      )}
      {error && <p role="alert">{error}</p>}
      <footer>
        <button disabled={saving || closing} onClick={dismiss}>取消</button>
        <button aria-busy={saving} disabled={saving || closing} onClick={() => void confirm(scope).then(ok => { if (ok) dismiss(); })}>
          {saving ? "删除中…" : "确认删除"}
        </button>
      </footer>
    </Modal>
  );
}
export function Calendar({
  tasks,
  month,
  setMonth,
  onOpen,
}: {
  tasks: TaskView[];
  month: string;
  setMonth: (m: string) => void;
  onOpen: (id: string) => void;
}) {
  const [day, setDay] = useState(""),
    [limit, setLimit] = useState(100);
  const grouped = useMemo(() => {
    const map = new Map<string, TaskView[]>();
    for (const t of tasks)
      if (t.dueAt) {
        const k = dayKey(t.dueAt);
        const bucket = map.get(k);
        if (bucket) bucket.push(t);
        else map.set(k, [t]);
      }
    return map;
  }, [tasks]);
  const date = new Date(`${month}-01T12:00:00Z`),
    count = new Date(
      Date.UTC(date.getUTCFullYear(), date.getUTCMonth() + 1, 0),
    ).getUTCDate();
  function shift(n: number) {
    const d = new Date(`${month}-15T00:00:00Z`);
    d.setUTCMonth(d.getUTCMonth() + n);
    setMonth(d.toISOString().slice(0, 7));
    setDay("");
  }
  return (
    <div className="ws-calendar">
      <div className="ws-actions">
        <button title="上个月" aria-label="上个月" onClick={() => shift(-1)}>
          ‹
        </button>
        <input
          aria-label="月份"
          type="month"
          value={month}
          onChange={(e) => {
            if (e.target.value) setMonth(e.target.value);
          }}
        />
        <button title="下个月" aria-label="下个月" onClick={() => shift(1)}>
          ›
        </button>
      </div>
      <div className="ws-calendar-grid">
        {["日", "一", "二", "三", "四", "五", "六"].map((s) => (
          <span key={s}>{s}</span>
        ))}
        {Array.from({ length: date.getUTCDay() }, (_, i) => (
          <div key={`blank${i}`} />
        ))}
        {Array.from({ length: count }, (_, i) => {
          const key = `${month}-${String(i + 1).padStart(2, "0")}`,
            rows = grouped.get(key) ?? [];
          return (
            <button
              className={day === key ? "chosen" : ""}
              aria-pressed={day === key}
              key={key}
              onClick={() => {
                setDay(key);
                setLimit(100);
              }}
              aria-label={`${key}，${rows.length} 项任务`}
            >
              <b>{i + 1}</b>
              {rows.slice(0, 2).map((t) => (
                <small key={t.id}>{t.title}</small>
              ))}
              {rows.length > 2 && <small>还有 {rows.length - 2} 项</small>}
            </button>
          );
        })}
      </div>
      {day && (
        <>
          <h3>{day}</h3>
          {(grouped.get(day) ?? []).slice(0, limit).map((t) => (
            <button
              className="ws-change-short"
              key={t.id}
              onClick={() => onOpen(t.id)}
            >
              {t.title}
              <small>{formatDate(t.dueAt)}</small>
            </button>
          ))}
          {(grouped.get(day)?.length ?? 0) > limit && (
            <button onClick={() => setLimit(limit + 100)}>加载更多</button>
          )}
        </>
      )}
      <p className="ws-muted">无日期任务请在列表查看。</p>
    </div>
  );
}

export { }
