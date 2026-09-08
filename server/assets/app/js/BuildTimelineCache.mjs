export class TimelineCache {
  constructor(limit = 3) {
    this.limit = limit;
    this.windows = [];
    this.events = [];
  }

  add(range, events) {
    this.windows.push({ ...range, events });
    if (this.windows.length > this.limit) this.windows.shift();
    const unique = new Map();
    for (const window of this.windows) for (const event of window.events) unique.set(event.event_id, event);
    this.events = [...unique.values()].sort((a, b) => a.start_ms - b.start_ms || a.event_id - b.event_id);
  }

  missing(range) {
    let start = range.start;
    const end = start + range.span;
    const missing = [];
    for (const window of [...this.windows].sort((a, b) => a.start - b.start)) {
      if (window.start + window.span <= start) continue;
      if (window.start >= end) break;
      if (window.start > start) missing.push({ start, span: window.start - start });
      start = Math.max(start, Math.min(end, window.start + window.span));
    }
    if (start < end) missing.push({ start, span: end - start });
    return missing;
  }

  contains(range) {
    return this.missing(range).every((gap) => gap.span < 0.001);
  }
}
