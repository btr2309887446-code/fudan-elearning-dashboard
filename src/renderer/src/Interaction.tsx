import { useEffect, useRef, useState, type ReactNode } from "react";

export function Surface({ identity, children }: { identity: string; children: ReactNode }) {
  const ref = useRef<HTMLDivElement>(null);
  useEffect(() => {
    if (matchMedia("(prefers-reduced-motion: reduce)").matches) return;
    const animation = ref.current?.animate([
      { opacity: .25, transform: innerWidth < 960 ? "translateX(6px)" : "translateY(4px)" },
      { opacity: 1, transform: "translate(0)" },
    ], { duration: 200, easing: "cubic-bezier(.2,.7,.2,1)" });
    return () => animation?.cancel();
  }, [identity]);
  return <div ref={ref}>{children}</div>;
}

export function useDialogClose(close: () => void, saving: boolean) {
  const [closing, setClosing] = useState(false);
  const timer = useRef<ReturnType<typeof setTimeout>>();
  useEffect(() => () => clearTimeout(timer.current), []);
  function dismiss() {
    if (saving || timer.current) return;
    setClosing(true);
    timer.current = setTimeout(close, matchMedia("(prefers-reduced-motion: reduce)").matches ? 0 : 160);
  }
  return { closing, dismiss };
}
