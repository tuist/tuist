import { layoutEvents, ROW_HEIGHT } from "./BuildTimelineModel.mjs";

// Preserve individual operations and overlap lanes. Keep the first lanes readable,
// then compress excess concurrency into the remaining height instead of grouping by type.
export function densityLayout(events, range, height) {
  const layout = layoutEvents(events, range);
  const available = Math.max(1, height - 16);
  const full =
    layout.lanes * ROW_HEIGHT <= available ? layout.lanes : Math.min(8, Math.floor(available / ROW_HEIGHT / 2));
  const compact = (available - full * ROW_HEIGHT) / Math.max(1, layout.lanes - full);
  const rows = Array.from({ length: layout.lanes }, (_, lane) => ({
    y: 8 + (lane < full ? lane * ROW_HEIGHT : full * ROW_HEIGHT + (lane - full) * compact),
    height: lane < full ? ROW_HEIGHT : compact,
  }));
  for (const event of layout.events) {
    event.lane = Math.round((event.y - 8) / ROW_HEIGHT);
    event.y = rows[event.lane].y;
    event.rowHeight = rows[event.lane].height;
  }
  return { ...layout, rows, height };
}
