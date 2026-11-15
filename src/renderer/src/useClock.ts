import { useEffect, useState } from 'react';
import { nextClockDelay, systemClock, type Clock } from '../../core/clock';

export function useClock(clock: Clock = systemClock): number {
  const [now, setNow] = useState(() => clock.now());
  useEffect(() => {
    let timer: ReturnType<typeof setTimeout>;
    const update = () => {
      clearTimeout(timer);
      const value = clock.now(); setNow(value);
      if (document.visibilityState !== 'hidden') timer = setTimeout(update, nextClockDelay(value));
    };
    update();
    window.addEventListener('focus', update);
    document.addEventListener('visibilitychange', update);
    const unsubscribe = window.elearning.onResume(update);
    return () => { clearTimeout(timer); window.removeEventListener('focus', update); document.removeEventListener('visibilitychange', update); unsubscribe(); };
  }, [clock]);
  return now;
}
