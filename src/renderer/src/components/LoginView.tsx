import { useEffect, useRef, useState } from 'react';
import type { CanvasProfile } from '../../../core/types';
import brandMark from '../assets/brand-mark.png';
import type { Theme } from '../types';
import Icon from './Icon';

interface Props {
  onSuccess: (profile: CanvasProfile) => void;
  notice?: string | null;
  theme: Theme;
  onToggleTheme: () => void;
}

export default function LoginView({ onSuccess, notice, theme, onToggleTheme }: Props) {
  const [username, setUsername] = useState('');
  const [password, setPassword] = useState('');
  const [remember, setRemember] = useState(false);
  const [captcha, setCaptcha] = useState<{ image?: string } | null>(null);
  const [captchaCode, setCaptchaCode] = useState('');
  const [busy, setBusy] = useState(false);
  const [stage, setStage] = useState('正在检查登录状态…');
  const [error, setError] = useState<string | null>(null);
  const [detail, setDetail] = useState<string | null>(null);
  const preparedFor = useRef<string>('');

  useEffect(() => {
    void (async () => {
      const remembered = await window.elearning.auth.remembered();
      if (remembered.username) setUsername(remembered.username);
      if (remembered.password) {
        setPassword(remembered.password);
        setRemember(true);
      }
      setStage('');
    })();
  }, []);

  /** Mirrors the official page: it asks about the captcha when the 学号 loses focus. */
  async function onUsernameBlur() {
    const name = username.trim();
    if (!name || name === preparedFor.current) return;
    preparedFor.current = name;
    const res = await window.elearning.auth.checkCaptcha(name);
    if (res.ok && res.data.captchaRequired) {
      setCaptcha({ image: res.data.captchaImage });
    } else if (res.ok) {
      setCaptcha(null);
    }
  }

  async function refreshCaptcha() {
    const name = username.trim();
    if (!name) return;
    const res = await window.elearning.auth.checkCaptcha(name);
    if (res.ok && res.data.captchaRequired) {
      setCaptcha({ image: res.data.captchaImage });
      setCaptchaCode('');
    }
  }

  async function submit(e: React.FormEvent) {
    e.preventDefault();
    if (busy) return;
    setError(null);
    setDetail(null);

    const name = username.trim();
    if (!name || !password) {
      setError('请填写学号和密码。');
      return;
    }
    if (captcha && !captchaCode.trim()) {
      setError('请输入图中验证码。');
      return;
    }

    setBusy(true);
    try {
      // No captcha on screen yet: ask first, so a doomed attempt is never spent.
      if (!captcha) {
        setStage('正在连接统一身份认证…');
        const prepared = await window.elearning.auth.prepare(name);
        if (!prepared.ok) {
          setError(prepared.error.message);
          setDetail(prepared.error.detail ?? null);
          return;
        }
        if (prepared.data.captchaRequired) {
          setCaptcha({ image: prepared.data.captchaImage });
          setStage('');
          setError('该账号当前需要验证码，请填写图中字符后再提交。');
          return;
        }
      }

      setStage('正在验证身份…');
      const res = await window.elearning.auth.submit({
        username: name,
        password,
        captchaCode: captcha ? captchaCode.trim() : undefined,
        remember,
      });

      if (!res.ok) {
        setError(res.error.message);
        setDetail(res.error.detail ?? null);
        if (res.error.kind === 'captcha_required') await refreshCaptcha();
        return;
      }

      setStage('登录成功，正在载入…');
      onSuccess(res.data.profile);
    } catch (err) {
      setError((err as Error).message);
    } finally {
      setBusy(false);
      setStage('');
    }
  }

  return (
    <div className="login-wrap">
      <button
        className="icon-btn"
        onClick={onToggleTheme}
        title={theme === 'light' ? '切换到深色' : '切换到浅色'}
        style={{ position: 'fixed', top: 22, right: 24, zIndex: 5 }}
      >
        <Icon name={theme === 'light' ? 'moon' : 'sun'} size={19} />
      </button>

      <form className="login-card" onSubmit={submit}>
        <div className="sb-brand" style={{ padding: '0 0 20px' }}>
          <img className="sb-mark" src={brandMark} alt="" />
          <div className="sb-brand-text">
            <div style={{ fontSize: 14.5, fontWeight: 640 }}>eLearning 学习看板</div>
            <div className="sb-brand-sub">elearning.fudan.edu.cn</div>
          </div>
        </div>

        <h1 className="login-title">登录统一身份认证</h1>
        <p className="login-desc">
          使用你的复旦 UIS 学号和密码登录，数据直接来自 eLearning（Canvas）官方接口。
          <br />
          密码只在本机内存中使用，不会写入磁盘，也不会发送到除复旦认证服务器以外的任何地方。
        </p>

        {notice && <div className="alert alert-warn">{notice}</div>}
        {error && <div className="alert alert-error">{error}</div>}
        {detail && (
          <div className="alert alert-info" style={{ fontSize: 12, maxHeight: 130, overflow: 'auto' }}>
            {detail}
          </div>
        )}

        <div className="field">
          <label htmlFor="username">学号</label>
          <input
            id="username"
            value={username}
            autoComplete="username"
            onChange={(e) => setUsername(e.target.value)}
            onBlur={onUsernameBlur}
            placeholder="例如 20302010001"
            disabled={busy}
          />
        </div>

        <div className="field">
          <label htmlFor="password">密码</label>
          <input
            id="password"
            type="password"
            value={password}
            autoComplete="current-password"
            onChange={(e) => setPassword(e.target.value)}
            placeholder="统一身份认证密码"
            disabled={busy}
          />
        </div>

        {captcha && (
          <div className="field">
            <label htmlFor="captcha">验证码</label>
            <div className="captcha-row">
              <input
                id="captcha"
                value={captchaCode}
                onChange={(e) => setCaptchaCode(e.target.value)}
                placeholder="输入图中字符"
                disabled={busy}
                autoFocus
              />
              {captcha.image ? (
                <img
                  className="captcha-img"
                  src={captcha.image}
                  alt="验证码"
                  title="点击刷新"
                  onClick={refreshCaptcha}
                />
              ) : (
                <button type="button" className="btn" onClick={refreshCaptcha} disabled={busy}>
                  刷新验证码
                </button>
              )}
            </div>
          </div>
        )}

        <label className="checkbox">
          <input type="checkbox" checked={remember} onChange={(e) => setRemember(e.target.checked)} />
          记住密码（使用 Windows 凭据加密后保存在本机）
        </label>

        <button type="submit" className="btn btn-primary" style={{ width: '100%', padding: '11px' }} disabled={busy}>
          {busy ? '请稍候…' : '登录'}
        </button>

        {stage && (
          <div className="loading-line" style={{ marginTop: 14, justifyContent: 'center' }}>
            <span className="spin" />
            {stage}
          </div>
        )}

        <p className="login-desc" style={{ marginTop: 18, marginBottom: 0, fontSize: 12 }}>
          提示：如果多次输错密码，学校认证系统会要求验证码甚至临时锁定账号。本应用会在提交前先向认证服务器确认是否需要验证码，尽量避免浪费尝试次数。
        </p>
      </form>
    </div>
  );
}
