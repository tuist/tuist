import { categoryFor, layoutEvents, ROW_HEIGHT } from "./BuildTimelineModel.mjs";

const kinds = ["compile", "link", "script", "resource", "other", "failure"];

// Buckets describe steps overlapping an interval, not CPU lanes or utilization.
export function densityLayout(events, range, height) {
  const layout = layoutEvents(events, range);
  if (!events.some((event) => event.aggregate) && layout.lanes * ROW_HEIGHT <= height - 16) {
    return { ...layout, grouped: false };
  }
  const buckets = new Map();
  const bins = 128;
  const width = range.span / bins;
  for (const event of layout.events) {
    if (event.aggregate) {
      buckets.set(event.event_id, event);
      continue;
    }
    const kind = event.status === "failure" ? "failure" : categoryFor(event.category);
    const first = Math.max(0, Math.floor((event.start_ms - range.start) / width));
    const last = Math.min(bins - 1, Math.ceil((event.end - range.start) / width - 1e-8) - 1);
    for (let bin = first; bin <= last; bin++) {
      const key = `${kind}:${bin}`;
      const bucket = buckets.get(key) || {
        event_id: key,
        aggregate: true,
        kind,
        category: kind,
        count: 0,
        title: "",
        target: "",
        project: "",
        status: kind === "failure" ? "failure" : "success",
        start_ms: range.start + bin * width,
        duration_ms: width,
        end: range.start + (bin + 1) * width,
      };
      bucket.count += 1;
      buckets.set(key, bucket);
    }
  }
  const activeKinds = kinds.filter((kind) => [...buckets.values()].some((event) => event.kind === kind));
  const grouped = [...buckets.values()].sort(
    (a, b) => kinds.indexOf(a.kind) - kinds.indexOf(b.kind) || a.start_ms - b.start_ms,
  );
  for (const event of grouped) event.y = 8 + activeKinds.indexOf(event.kind) * 48;
  return {
    events: grouped,
    lanes: activeKinds.length,
    height: activeKinds.length * 48 + 16,
    grouped: true,
    kinds: activeKinds,
  };
}
