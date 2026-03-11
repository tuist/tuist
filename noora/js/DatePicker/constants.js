/** Abbreviated weekday names (localized, starting from Sunday) */
export const WEEKDAYS = Array.from({ length: 7 }, (_, i) => {
  // Jan 7, 2024 is a Sunday - use it as reference to get Sun-Sat in order
  const date = new Date(2024, 0, 7 + i);
  return date.toLocaleDateString(undefined, { weekday: "short" }).slice(0, 2);
});

/** Breakpoint for mobile view (in pixels) */
export const MOBILE_BREAKPOINT = 768;
