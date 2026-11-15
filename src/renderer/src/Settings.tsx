import { useEffect, useState, useRef } from "react";
import type { Prefs } from "../../preload/index.d";
export function Settings({
  prefs,
  save,
  onLogout,
  saving,
}: {
  prefs: Prefs;
  saving: boolean;
  save: (p: Partial<Prefs>) => Promise<void>;
  onLogout: () => Promise<void>;
}) {
  const [llm, setLlm] = useState<{
      enabled: boolean;
      baseUrl: string;
      model: string;
      apiKey: string;
      hasApiKey?: boolean;
    } | null>(null),
    [message, setMessage] = useState(""),
    [root, setRoot] = useState("");
  const [pending, setPending] = useState("");
  const actionLock = useRef(false);
  const mounted = useRef(true);
  useEffect(() => { mounted.current = true; return () => { mounted.current = false; }; }, []);
  async function run(label: string, action: () => Promise<void>) {
    if (actionLock.current) return;
    actionLock.current = true; setPending(label); setMessage("");
    try { await action(); }
    catch (e) { if (mounted.current) setMessage(`操作失败：${String(e)}。请重试。`); }
    finally { actionLock.current = false; if (mounted.current) setPending(""); }
  }
  useEffect(() => {
    void window.elearning.llm.get().then(v => { if (mounted.current) setLlm({ ...v, apiKey: '' }); }).catch(e => { if (mounted.current) setMessage(String(e)); });
    void window.elearning.files.root().then(v => { if (mounted.current) setRoot(v); }).catch(e => { if (mounted.current) setMessage(String(e)); });
  }, []);
  return (
    <div className="ws-settings" aria-busy={saving}>
      {prefs.storageWarning && <p role="alert">{prefs.storageWarning}</p>}
      <fieldset disabled={saving}>
      <h2>外观</h2>
      <label>
        主题
        <select
          value={prefs.followSystem ? "system" : prefs.theme}
          onChange={(e) =>
            void save(
              e.target.value === "system"
                ? { followSystem: true }
                : {
                    followSystem: false,
                    theme: e.target.value as "light" | "dark",
                  },
            )
          }
        >
          <option value="system">跟随系统</option>
          <option value="light">浅色</option>
          <option value="dark">深色</option>
        </select>
      </label>
      <h2>同步与后台运行</h2>
      <label>
        运行期间自动同步
        <select
          value={prefs.syncMinutes ?? 15}
          onChange={(e) =>
            void save({
              syncMinutes: Number(e.target.value) as Prefs["syncMinutes"],
            })
          }
        >
          <option value={0}>关闭</option>
          <option value={15}>15 分钟</option>
          <option value={30}>30 分钟</option>
          <option value={60}>60 分钟</option>
        </select>
      </label>
      {(
        [
          ["closeToTray", "关闭窗口后留在托盘"],
          ["taskNotifications", "任务提醒（学校作业默认提前一小时）"],
          ["changeNotifications", "变化通知（每次同步汇总一条）"],
        ] as const
      ).map(([key, label]) => (
        <label className="ws-check" key={key}>
          <input
            type="checkbox"
            checked={prefs[key] ?? false}
            onChange={(e) => void save({ [key]: e.target.checked })}
          />
          {label}
        </label>
      ))}
      <p className="ws-muted">
        自动同步检查当前学期；工具栏同步包含历史课程。睡眠期间可能错过提醒，唤醒后合并最近
        24 小时内的提醒。
      </p>
      </fieldset>
      <h2>下载位置</h2>
      <p>{root}</p>
      <button
        disabled={!!pending}
        aria-busy={pending === "选择文件夹…"}
        onClick={() => void run("选择文件夹…", async () => {
          const r = await window.elearning.files.pickRoot();
          if (!r.ok) throw Error(r.error.message);
          if (mounted.current) { setRoot(r.data); setMessage("下载位置已更新"); }
        })}
      >
        更改下载文件夹
      </button>
      <h2>AI 摘要</h2>
      {llm && (
        <form
          onSubmit={async (e) => {
            e.preventDefault();
            await run("保存摘要设置…", async () => {
            const r = await window.elearning.llm.set(llm);
            if (!r.ok) throw Error(r.error.message);
            if (mounted.current) {
              setLlm({ ...r.data, apiKey: '' });
              setMessage(r.data.storageWarning || "摘要设置已保存");
            }
            });
          }}
        >
          <fieldset disabled={!!pending}>
          <label className="ws-check">
            <input
              type="checkbox"
              checked={llm.enabled}
              onChange={(e) => setLlm({ ...llm, enabled: e.target.checked })}
            />
            启用 AI 摘要
          </label>
          <label>
            接口地址
            <input
              value={llm.baseUrl}
              onChange={(e) => setLlm({ ...llm, baseUrl: e.target.value })}
            />
          </label>
          <label>
            模型
            <input
              value={llm.model}
              onChange={(e) => setLlm({ ...llm, model: e.target.value })}
            />
          </label>
          <label>
            API 密钥
            <input
              type="password"
              value={llm.apiKey}
              placeholder={llm.hasApiKey ? '已保存密钥；留空保持原值' : '填写 API 密钥'}
              onChange={(e) => setLlm({ ...llm, apiKey: e.target.value })}
            />
          </label>
          {llm.hasApiKey && <button type="button" onClick={() => void run('清除密钥…', async () => {
            const r = await window.elearning.llm.set({ clearApiKey: true });
            if (!r.ok) throw Error(r.error.message);
            if (mounted.current) { setLlm({ ...r.data, apiKey: '' }); setMessage(r.data.storageWarning || '密钥已清除'); }
          })}>清除已保存密钥</button>}
          </fieldset>
          <button type="submit" disabled={!!pending} aria-busy={pending === "保存摘要设置…"}>{pending === "保存摘要设置…" ? pending : "保存摘要设置"}</button>
        </form>
      )}
      <p role="status">{pending || message}</p>
      <h2>账号</h2>
      <p>个人任务、手动截止时间与已读记录仅保存在当前设备，按学校账号隔离。</p>
      <button disabled={!!pending || saving} onClick={() => void run("正在退出…", onLogout)}>退出账号 / 重新登录</button>
    </div>
  );
}
