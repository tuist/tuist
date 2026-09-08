import { clampRange } from "./BuildTimelineModel.mjs";

export class TimelinePrefetch {
  constructor(now = () => performance.now()) {
    this.now = now;
    this.velocity = 0;
    this.lastPan = -Infinity;
    this.latency = 250;
  }

  pan(from, to) {
    const now = this.now();
    const elapsed = now - this.lastPan;
    const speed = (to - from) / Math.max(16, Math.min(100, elapsed));
    this.velocity =
      elapsed > 250 || Math.sign(speed) !== Math.sign(this.velocity) ? speed : this.velocity * 0.5 + speed * 0.5;
    this.lastPan = now;
  }

  received(elapsed) {
    this.latency = Math.max(50, Math.min(2000, this.latency * 0.5 + elapsed * 0.5));
  }

  plan(range, duration) {
    const margin = Math.min(30_000, Math.max(15_000, range.span / 2));
    const velocity = this.now() - this.lastPan < 500 ? this.velocity : 0;
    const lead = Math.min(90_000, Math.max(margin, Math.abs(velocity) * (2 * this.latency + 100)));
    const start = Math.max(0, range.start - (velocity < 0 ? lead : margin));
    const end = Math.min(duration, range.start + range.span + (velocity > 0 ? lead : margin));
    // The server buffers 60 seconds on either side. Keep the current viewport
    // inside that response while moving more of its buffer ahead of the pointer.
    const shift = Math.sign(velocity) * Math.min(60_000, lead);
    return { needed: { start, span: end - start }, request: clampRange(range.start + shift, range.span, duration) };
  }
}
