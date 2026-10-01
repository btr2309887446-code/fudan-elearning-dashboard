import { Component, type ErrorInfo, type ReactNode } from 'react';

interface Props {
  children: ReactNode;
}

interface State {
  error: Error | null;
  stack?: string;
}

/**
 * Last line of defence.
 *
 * A stale cache once made the whole tree throw during the first render, which
 * in Electron shows up as an empty window with no hint of what went wrong. This
 * turns any such crash into a readable message plus a way out.
 */
export default class ErrorBoundary extends Component<Props, State> {
  state: State = { error: null };

  static getDerivedStateFromError(error: Error): State {
    return { error };
  }

  componentDidCatch(error: Error, info: ErrorInfo): void {
    console.error('[ui] render failed:', error, info.componentStack);
    this.setState({ stack: info.componentStack ?? undefined });
  }

  private reset = async (): Promise<void> => {
    try {
      await window.elearning.data.clear();
    } catch {
      /* clearing is best effort */
    }
    window.location.reload();
  };

  render(): ReactNode {
    const { error, stack } = this.state;
    if (!error) return this.props.children;

    return (
      <div className="login-wrap">
        <div className="login-card" style={{ maxWidth: 620 }}>
          <h1 className="login-title">界面出错了</h1>
          <p className="login-desc">
            这是程序内部的问题，不是你账号的问题。可以点下面的按钮清掉本地缓存后重试；
            如果反复出现，把下面的信息发给我。
          </p>

          <div className="alert alert-error" style={{ maxHeight: 220, overflow: 'auto' }}>
            {error.message || String(error)}
          </div>

          {stack && (
            <details style={{ marginBottom: 16 }}>
              <summary style={{ cursor: 'pointer', color: 'var(--text-dim)', fontSize: 12.5 }}>
                展开技术细节
              </summary>
              <pre
                style={{
                  fontSize: 11,
                  color: 'var(--muted)',
                  whiteSpace: 'pre-wrap',
                  maxHeight: 220,
                  overflow: 'auto',
                  marginTop: 8,
                }}
              >
                {stack}
              </pre>
            </details>
          )}

          <button className="btn btn-primary" style={{ width: '100%', padding: 11 }} onClick={() => void this.reset()}>
            清除本地缓存并重新加载
          </button>
        </div>
      </div>
    );
  }
}
