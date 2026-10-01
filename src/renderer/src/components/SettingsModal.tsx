/**
 * 设置：目前只有作业简介用的大模型接口。
 *
 * 刻意做成「不配也能用」：没填 key 时简介走截取原文，
 * 这个面板只是把可选项摆出来，而不是必需品。
 *
 * 接口按 OpenAI 兼容格式调用，所以 DeepSeek、月之暗面、智谱、
 * 通义、OpenAI 以及自建网关都只需要改 base URL 与模型名。
 */

import { useEffect, useRef, useState } from 'react';

import { closeWithAnimation } from '../motion';
import { SECTIONS } from './Dashboard';
import Icon from './Icon';

interface Props {
  onClose: () => void;
  /* --- 外观 --- */
  theme: 'light' | 'dark';
  onToggleTheme: () => void;
  /** 首页各板块的显示开关（key -> 是否显示）。 */
  sections: Record<string, boolean>;
  /** 已算好的完整板块顺序。 */
  sectionOrder: string[];
  onToggleSection: (key: string) => void;
  onMoveSection: (key: string, direction: -1 | 1) => void;
  onResetOrder: () => void;
}

/** 常见服务商的预填项，省得用户自己查 base URL。 */
const PRESETS: { label: string; baseUrl: string; model: string }[] = [
  { label: 'DeepSeek', baseUrl: 'https://api.deepseek.com/v1', model: 'deepseek-chat' },
  { label: '月之暗面 Kimi', baseUrl: 'https://api.moonshot.cn/v1', model: 'moonshot-v1-8k' },
  { label: '智谱 GLM', baseUrl: 'https://open.bigmodel.cn/api/paas/v4', model: 'glm-4-flash' },
  { label: '通义千问', baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1', model: 'qwen-turbo' },
  { label: 'OpenAI', baseUrl: 'https://api.openai.com/v1', model: 'gpt-4o-mini' },
];

export default function SettingsModal({
  onClose,
  theme,
  onToggleTheme,
  sections,
  sectionOrder,
  onToggleSection,
  onMoveSection,
  onResetOrder,
}: Props) {
  // 退场动画期间先别卸载：直接消失和入场动画不对称。
  const backdropRef = useRef<HTMLDivElement>(null);
  const closing = useRef(false);

  function requestClose() {
    if (closing.current) return;
    closing.current = true;
    closeWithAnimation(backdropRef.current, onClose);
  }
  /** 分页放，否则一屏塞不下。 */
  const [tab, setTab] = useState<'appearance' | 'llm'>('appearance');
  /** 刷新范围：默认只拉当前及未来学期。 */
  const [scope, setScope] = useState<'current' | 'all'>('current');
  const [baseUrl, setBaseUrl] = useState('');
  const [model, setModel] = useState('');
  const [apiKey, setApiKey] = useState('');
  const [enabled, setEnabled] = useState(false);
  const [loaded, setLoaded] = useState(false);
  const [saving, setSaving] = useState(false);
  const [msg, setMsg] = useState<{ tone: 'ok' | 'bad'; text: string } | null>(null);

  useEffect(() => {
    void (async () => {
      const cfg = await window.elearning.llm.get();
      setBaseUrl(cfg.baseUrl);
      setModel(cfg.model);
      setApiKey(cfg.apiKey);
      setEnabled(cfg.enabled);
      setLoaded(true);
    })();
  }, []);

  useEffect(() => {
    void (async () => {
      try {
        const p = await window.elearning.prefs.get();
        setScope(p.refreshScope === 'all' ? 'all' : 'current');
      } catch {
        /* 读不到就用默认值 */
      }
    })();
  }, []);

  /** 改刷新范围：立即生效并落盘，不需要点保存。 */
  async function changeScope(v: 'current' | 'all') {
    setScope(v);
    try {
      await window.elearning.prefs.set({ refreshScope: v });
    } catch {
      /* 偏好写失败不该影响界面 */
    }
  }

  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') requestClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [requestClose]);

  async function save() {
    setSaving(true);
    setMsg(null);
    const res = await window.elearning.llm.set({ baseUrl, model, apiKey, enabled });
    setSaving(false);
    if (res.ok) {
      setApiKey(res.data.apiKey);
      setMsg({ tone: 'ok', text: '已保存。下次打开作业详情会用大模型生成简介。' });
    } else {
      setMsg({ tone: 'bad', text: res.error.message });
    }
  }

  return (
    <div className="modal-backdrop" ref={backdropRef} onClick={requestClose}>
      <div className="modal" style={{ maxWidth: 580 }} onClick={(e) => e.stopPropagation()}>
        <div className="modal-head">
          <div style={{ flex: 1 }}>
            <div className="modal-title">设置</div>
            <div className="modal-sub">
              {tab === 'appearance' ? '外观与首页板块' : '作业简介的生成方式'}
            </div>
          </div>
          <button className="icon-btn" onClick={requestClose} title="关闭（Esc）">
            <Icon name="close" size={17} />
          </button>
        </div>

        {/* 分页：外观与简介是两件不相干的事，堆在一屏里只会都看不全。 */}
        <div className="settings-tabs">
          <button
            className={`settings-tab ${tab === 'appearance' ? 'on' : ''}`}
            onClick={() => setTab('appearance')}
          >
            <Icon name="sliders" size={15} /> 外观
          </button>
          <button
            className={`settings-tab ${tab === 'llm' ? 'on' : ''}`}
            onClick={() => setTab('llm')}
          >
            <Icon name="sparkle" size={15} /> 作业简介
          </button>
        </div>

        <div className="modal-body">
          {tab === 'appearance' && (
            <>
              <div className="field">
                <label>主题</label>
                <div className="settings-inline">
                  <button className="btn" onClick={onToggleTheme}>
                    <Icon name={theme === 'dark' ? 'sun' : 'moon'} size={15} />
                    {theme === 'dark' ? '切换到浅色' : '切换到深色'}
                  </button>
                  <span className="settings-hint">
                    当前：{theme === 'dark' ? '深色' : '浅色'}
                  </span>
                </div>
              </div>

              <div className="field" style={{ marginTop: 20 }}>
                <label>刷新范围</label>
                <div className="settings-hint" style={{ marginBottom: 8 }}>
                  已结束学期的成绩和作业不会再变，刷新时直接沿用上次的数据，
                  不再逐门课发请求。一门课要发两个请求，省下的就是这么多。
                </div>
                <div className="settings-inline">
                  <button
                    className={`dash-toggle ${scope === 'current' ? 'on' : ''}`}
                    onClick={() => void changeScope('current')}
                  >
                    只刷新当前学期
                  </button>
                  <button
                    className={`dash-toggle ${scope === 'all' ? 'on' : ''}`}
                    onClick={() => void changeScope('all')}
                  >
                    全部学期
                  </button>
                </div>
                <div className="settings-hint" style={{ marginTop: 6 }}>
                  {scope === 'current'
                    ? '历史学期只有在缓存缺失时才会重新拉取。'
                    : '每次刷新都重新拉取全部课程，比较慢。'}
                </div>
              </div>

              <div className="field" style={{ marginTop: 20 }}>
                <label>首页板块</label>
                <div className="settings-hint" style={{ marginBottom: 8 }}>
                  点名字开关板块，点 ▲▼ 调整顺序。改动会记住。
                </div>
                <div className="settings-sections">
                  {sectionOrder.map((key, i) => {
                    const meta = SECTIONS.find((s) => s.key === key);
                    if (!meta) return null;
                    const on = sections[key] !== false;
                    return (
                      <div key={key} className={`settings-section-row ${on ? '' : 'off'}`}>
                        <button
                          className="settings-section-name"
                          onClick={() => onToggleSection(key)}
                          title={on ? '点击隐藏' : '点击显示'}
                        >
                          <span className={`settings-check ${on ? 'on' : ''}`}>
                            {on && <Icon name="check" size={11} />}
                          </span>
                          <Icon name={meta.icon} size={14} />
                          {meta.label}
                        </button>
                        <div className="settings-section-move">
                          <button
                            className="dash-move"
                            onClick={() => onMoveSection(key, -1)}
                            disabled={i === 0}
                            title="上移"
                          >
                            ▲
                          </button>
                          <button
                            className="dash-move"
                            onClick={() => onMoveSection(key, 1)}
                            disabled={i === sectionOrder.length - 1}
                            title="下移"
                          >
                            ▼
                          </button>
                        </div>
                      </div>
                    );
                  })}
                </div>
                <button
                  className="btn"
                  style={{ marginTop: 10 }}
                  onClick={onResetOrder}
                >
                  恢复默认顺序
                </button>
              </div>
            </>
          )}

          {tab === 'llm' && (
            <>
          <div className="summary-block" style={{ marginBottom: 16 }}>
            <div className="summary-head">
              <Icon name="sparkle" size={15} />
              不配置也能用
            </div>
            <div className="summary-text" style={{ fontSize: 13, lineHeight: 1.6 }}>
              作业详情里的简介默认直接截取作业说明的前 100 字。
              填入下面的大模型接口后，会改由模型压缩成更凝练的一句话。
              任何情况下接口调不通都会自动退回截取，不影响阅读。
            </div>
          </div>

          <div className="field">
            <label>服务商预设</label>
            <div style={{ display: 'flex', flexWrap: 'wrap', gap: 7, marginTop: 4 }}>
              {PRESETS.map((p) => (
                <button
                  key={p.label}
                  className={`dash-toggle ${baseUrl === p.baseUrl ? 'on' : ''}`}
                  onClick={() => {
                    setBaseUrl(p.baseUrl);
                    setModel(p.model);
                  }}
                >
                  {p.label}
                </button>
              ))}
            </div>
          </div>

          <div className="field" style={{ marginTop: 14 }}>
            <label htmlFor="llm-base">接口地址（OpenAI 兼容）</label>
            <input
              id="llm-base"
              value={loaded ? baseUrl : ''}
              onChange={(e) => setBaseUrl(e.target.value)}
              placeholder="https://api.deepseek.com/v1"
              spellCheck={false}
            />
          </div>

          <div className="field" style={{ marginTop: 12 }}>
            <label htmlFor="llm-model">模型名</label>
            <input
              id="llm-model"
              value={loaded ? model : ''}
              onChange={(e) => setModel(e.target.value)}
              placeholder="deepseek-chat"
              spellCheck={false}
            />
          </div>

          <div className="field" style={{ marginTop: 12 }}>
            <label htmlFor="llm-key">API Key</label>
            <input
              id="llm-key"
              type="password"
              value={loaded ? apiKey : ''}
              onChange={(e) => setApiKey(e.target.value)}
              placeholder="sk-..."
              spellCheck={false}
              autoComplete="off"
            />
            <div style={{ marginTop: 6, fontSize: 11.5, color: 'var(--muted)', lineHeight: 1.6 }}>
              密钥只保存在本机（<code>prefs.json</code>），调用时直接发往你填的这个地址，
              不经过任何第三方服务器。已保存时显示为 <code>********</code>，不改动就会沿用原值。
            </div>
          </div>

          <label className="checkbox" style={{ marginTop: 14 }}>
            <input type="checkbox" checked={enabled} onChange={(e) => setEnabled(e.target.checked)} />
            启用大模型生成简介
          </label>

          {msg && (
            <div className={`alert ${msg.tone === 'ok' ? 'alert-info' : 'alert-error'}`} style={{ marginTop: 12 }}>
              {msg.text}
            </div>
          )}
            </>
          )}
        </div>

        <div className="modal-foot">
          <div style={{ flex: 1 }} />
          <button className="btn" onClick={requestClose}>
            {tab === 'llm' ? '取消' : '关闭'}
          </button>
          {tab === 'llm' && (
            <button className="btn btn-primary" onClick={() => void save()} disabled={saving || !loaded}>
              {saving ? '保存中…' : '保存'}
            </button>
          )}
        </div>
      </div>
    </div>
  );
}
