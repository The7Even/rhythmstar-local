import type { ClockPort } from "./io";

export const browserClock: ClockPort = {
  now: () => Date.now(),
  every: (milliseconds, callback, render) => {
    let previous = performance.now();
    let frame: number;
    const update = (timestamp: number): void => {
      // Schedule first so stopping or restarting inside callback cancels this loop.
      frame = window.requestAnimationFrame(update);
      const elapsed = timestamp - previous;
      if (elapsed >= milliseconds) {
        // Preserve the cadence without replaying missed ticks after a long pause.
        // The game reads elapsed wall time itself for animation and music timing.
        previous = timestamp - elapsed % milliseconds;
        callback();
      }
      render?.();
    };
    frame = window.requestAnimationFrame(update);
    return () => window.cancelAnimationFrame(frame);
  },
};
