import { Component, Suspense, lazy, useMemo, useState, type ComponentType, type ComponentProps, type ReactNode } from 'react';

class LoadBoundary extends Component<{ children: ReactNode; retry: () => void }, { failed: boolean }> {
  state = { failed: false };
  static getDerivedStateFromError() { return { failed: true }; }
  render() {
    return this.state.failed ? <div role="alert" style={{ minHeight: 120, padding: 16 }}>
      <p>这一部分暂时无法显示。</p><button onClick={this.props.retry}>重试加载</button>
    </div> : this.props.children;
  }
}
export function asyncView<T extends ComponentType<any>>(load: () => Promise<{ default: T }>): ComponentType<ComponentProps<T>> {
  return function AsyncView(props: ComponentProps<T>) {
    const [attempt, setAttempt] = useState(0);
    const View: ComponentType<any> = useMemo(() => lazy(load), [attempt]);
    return <LoadBoundary key={attempt} retry={() => setAttempt(n=>n+1)}>
      <Suspense fallback={<div role="status" style={{ minHeight: 120, padding: 16 }}>正在载入…</div>}><View {...props} /></Suspense>
    </LoadBoundary>;
  };
}
