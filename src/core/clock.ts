export interface Clock { now(): number }
export const systemClock: Clock = { now: () => Date.now() };
export const nextClockDelay = (now: number): number => Math.max(1, 60000 - (now % 60000));
