/**
 * 设置：目前只有作业简介用的大模型接口。
 *
 * 刻意做成「不配也能用」：没填 key 时简介走截取原文，
 * 这个面板只是把可选项摆出来，而不是必需品。
 *
 * 接口按 OpenAI 兼容格式调用，所以 DeepSeek、月之暗面、智谱、
 * 通义、OpenAI 以及自建网关都只需要改 base URL 与模型名。
 */

import { useEffect, useState } from 'react';

import Icon from './Icon';

interface Props {
  onClose: () => void;
}

/** 常见服务商的预填项，省得用户自己查 base URL。 */
const PRESETS: { label: string; baseUrl: string; model: string }[] = [
  { label: 'DeepSeek', baseUrl: 'https://api.deepseek.com/v1', model: 'deepseek-chat' },
  { label: '月之暗面 Kimi', baseUrl: 'https://api.moonshot.cn/v1', model: 'moonshot-v1-8k' },
  { label: '智谱 GLM', baseUrl: 'https://open.bigmodel.cn/api/paas/v4', model: 'glm-4-flash' },
  { label: '通义千问', baseUrl: 'https://dashscope.aliyuncs.com/compatible-mode/v1', model: 'qwen-turbo' },
  { label: 'OpenAI', baseUrl: 'https://api.openai.com/v1', model: 'gpt-4o-mini' },
];

export default function SettingsModal({ onClose }: Props) {
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
    const onKey = (e: KeyboardEvent) => {
      if (e.key === 'Escape') onClose();
    };
    window.addEventListener('keydown', onKey);
    return () => window.removeEventListener('keydown', onKey);
  }, [onClose]);

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
    <div className="modal-backdrop" onClick={onClose}>
      <div className="modal" style={{ maxWidth: 580 }} onClick={(e) => e.stopPropagation()}>
        <div className="modal-head">
          <div style={{ flex: 1 }}>
            <div className="modal-title">设置</div>
            <div className="modal-sub">作业简介的生成方式</div>
          </div>
          <button className="icon-btn" onClick={onClose} title="关闭（Esc）">
            <Icon name="close" size={17} />
          </button>
        </div>

        <div className="modal-body">
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
        </div>

        <div className="modal-foot">
          <div style={{ flex: 1 }} />
          <button className="btn" onClick={onClose}>
            取消
          </button>
          <button className="btn btn-primary" onClick={() => void save()} disabled={saving || !loaded}>
            {saving ? '保存中…' : '保存'}
          </button>
        </div>
      </div>
    </div>
  );
}
