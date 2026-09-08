export const ROW_HEIGHT = 26;

export function categoryFor(category) {
  if (["compile", "link", "script", "resource", "other", "failure"].includes(category)) return category;
  if (/compilation|swiftmodule|bridgingheader/i.test(category)) return "compile";
  if (/linker|staticlibrary/i.test(category)) return "link";
  if (/script/i.test(category)) return "script";
  if (/cop|resource|asset|storyboard|xib/i.test(category)) return "resource";
  return "other";
}

export function normalizeEvents(events) {
  return events
    .filter(
      (event) =>
        Number.isFinite(event.start_ms) &&
        Number.isFinite(event.duration_ms) &&
        event.start_ms >= 0 &&
        event.duration_ms > 0,
    )
    .map((event) => ({
      ...event,
      end: event.start_ms + event.duration_ms,
      kind: categoryFor(event.category),
    }))
    .sort((a, b) => a.start_ms - b.start_ms || a.event_id - b.event_id);
}

// Minimum heaps release completed work and reuse the lowest free lane in O(log concurrency).
// Lanes represent non-overlapping intervals, never inferred worker threads.
function push(heap, entry) {
  heap.push(entry);
  let i = heap.length - 1;
  while (i > 0) {
    const parent = (i - 1) >> 1;
    if (heap[parent].end <= entry.end) break;
    heap[i] = heap[parent];
    i = parent;
  }
  heap[i] = entry;
}

function pop(heap) {
  const first = heap[0];
  const last = heap.pop();
  if (heap.length) {
    let i = 0;
    while (i * 2 + 1 < heap.length) {
      let child = i * 2 + 1;
      if (child + 1 < heap.length && heap[child + 1].end < heap[child].end) child++;
      if (last.end <= heap[child].end) break;
      heap[i] = heap[child];
      i = child;
    }
    heap[i] = last;
  }
  return first;
}

export function layoutEvents(events, range) {
  const visible = range
    ? events.filter((event) => event.end > range.start && event.start_ms < range.start + range.span)
    : events;
  const heap = [];
  const available = [];
  let lanes = 0;
  for (const event of visible) {
    while (heap.length && heap[0].end <= event.start_ms) {
      const { lane } = pop(heap);
      push(available, { end: lane, lane });
    }
    const lane = available.length ? pop(available).lane : lanes++;
    event.y = 8 + lane * ROW_HEIGHT;
    push(heap, { lane, end: event.end });
  }
  return { events: visible, lanes, height: lanes * ROW_HEIGHT + 16 };
}

export function timeLabel(ms) {
  if (ms > 0 && ms < 1) return `${ms.toFixed(2)} ms`;
  if (ms < 1000) return `${Math.round(ms)} ms`;
  if (ms < 60000) return `${(ms / 1000).toFixed(ms < 10000 ? 2 : 1)} s`;
  return `${Math.floor(ms / 60000)}m ${((ms % 60000) / 1000).toFixed(1)}s`;
}

export function clampRange(start, span, duration) {
  const width = Math.min(duration, Math.max(Math.min(1, duration), span));
  return { start: Math.max(0, Math.min(start, duration - width)), span: width };
}

export function zoomRange(range, factor, anchor, duration) {
  const span = clampRange(0, range.span * factor, duration).span;
  return clampRange(range.start + (range.span - span) * anchor, span, duration);
}

export function cursorTime(position, width, range) {
  const fraction = Math.max(0, Math.min(1, (position - 12) / Math.max(1, width - 24)));
  return range.start + fraction * range.span;
}

export function cursorTimeLabel(ms) {
  const rounded = Math.round(ms);
  return rounded < 1000
    ? `${rounded} ms`
    : `${Math.floor(rounded / 1000)} s ${String(rounded % 1000).padStart(3, "0")} ms`;
}

export function scrollGeometry(viewportWidth, range, duration) {
  const remaining = Math.max(0, duration - range.span);
  // Keep the virtual surface within browser layout limits even at millisecond zoom.
  const overflow = Math.min(8_000_000, (Math.max(1, viewportWidth - 24) * remaining) / range.span);
  return {
    width: viewportWidth + overflow,
    left: remaining ? (range.start / remaining) * overflow : 0,
  };
}

export function scrollStart(left, overflow, range, duration) {
  return overflow > 0 ? Math.max(0, Math.min(1, left / overflow)) * Math.max(0, duration - range.span) : 0;
}
