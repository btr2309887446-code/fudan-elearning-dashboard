/**
 * 动效工具。
 *
 * 用 Chromium 的 View Transitions API 做「从触发点展开」这类过渡——
 * Electron 33 用的是 Chromium 130，原生支持，不需要额外依赖。
 *
 * 两个前提保证了它不会成为负担：
 *  - 浏览器不支持时直接同步执行，功能完全不受影响；
 *  - 用户开了「减少动态效果」时同样跳过，尊重系统设置。
 *
 * 类型直接用 lib.dom 自带的 `ViewTransition`，不再自定义同名接口——
 * 自定义的会和 DOM 里已有的声明冲突（TS2430）。
 */

export function prefersReducedMotion(): boolean {
  return window.matchMedia?.('(prefers-reduced-motion: reduce)').matches === true;
}

/** 能不能用 View Transitions。在旧内核或用户关掉动效时返回 false。 */
export function canTransition(): boolean {
  return typeof document.startViewTransition === 'function' && !prefersReducedMotion();
}

/**
 * 切换主题：新主题从点击处圆形扩散开。
 *
 * 扩散是一种「因果」表达——你点的那个按钮就是变化发生的地方，
 * 整页突然变色则会让人一愣。
 *
 * @param x 扩散中心（视口坐标），通常是点击位置
 */
export function revealThemeFrom(x: number, y: number, apply: () => void): void {
  if (!canTransition()) {
    apply();
    return;
  }

  // 半径要盖住最远的那个角，否则扩散到一半就停住了。
  const radius = Math.hypot(
    Math.max(x, window.innerWidth - x),
    Math.max(y, window.innerHeight - y)
  );

  const transition = document.startViewTransition(apply);

  transition.ready
    .then(() => {
      document.documentElement.animate(
        {
          clipPath: [
            `circle(0px at ${x}px ${y}px)`,
            `circle(${radius}px at ${x}px ${y}px)`,
          ],
        },
        {
          duration: 480,
          easing: 'cubic-bezier(0.32, 0.72, 0, 1)',
          pseudoElement: '::view-transition-new(root)',
        }
      );
    })
    .catch(() => {
      /* 过渡被中断（比如用户连点）不算错误 */
    });
}

/**
 * 带退场动画地关闭弹层。
 *
 * 直接卸载会让弹层「啪」地消失；这里先挂上 closing 类播完退场再真正卸载。
 * 时长要和 CSS 里的 `.modal-backdrop.closing` 对齐。
 */
export function closeWithAnimation(
  backdrop: HTMLElement | null,
  done: () => void,
  ms = 150
): void {
  if (!backdrop || prefersReducedMotion()) {
    done();
    return;
  }
  backdrop.classList.add('closing');
  window.setTimeout(done, ms);
}

/**
 * 页面级切换：列表进详情、详情回列表。
 *
 * 位移方向暗示层级：进入时从右侧滑入，返回时向左退出。
 *
 * `view-transition-name` 只在切换期间挂到内容区上——如果常驻，
 * 主题切换的整页圆形扩散会被拆成「内容区自己动、其余部分另动」，
 * 效果就散了。
 */
export function slidePage(apply: () => void): void {
  if (!canTransition()) {
    apply();
    return;
  }

  const content = document.querySelector('.content');
  content?.classList.add('vt-page');

  const transition = document.startViewTransition(apply);

  const cleanup = () => content?.classList.remove('vt-page');
  transition.finished.then(cleanup).catch(cleanup);

  const easing = 'cubic-bezier(0.22, 1, 0.36, 1)';
  transition.ready
    .then(() => {
      document.documentElement.animate(
        { opacity: [0, 1], transform: ['translateX(16px)', 'translateX(0)'] },
        { duration: 280, easing, pseudoElement: '::view-transition-new(page)' }
      );
      document.documentElement.animate(
        { opacity: [1, 0], transform: ['translateX(0)', 'translateX(-10px)'] },
        { duration: 280, easing, pseudoElement: '::view-transition-old(page)' }
      );
    })
    .catch(() => {
      cleanup();
    });
}
