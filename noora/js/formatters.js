const numberUnits = [
  [1_000_000_000_000, "T"],
  [1_000_000_000, "B"],
  [1_000_000, "M"],
  [1_000, "K"],
];

export function formatNumber(
  value,
  locale = globalThis.document?.documentElement.lang ||
    globalThis.navigator?.language ||
    "en",
) {
  if (typeof value !== "number" || !Number.isFinite(value)) return value;
  locale = locale.replaceAll("_", "-");
  const magnitude = Math.abs(value);
  if (magnitude < 10_000) return value.toLocaleString(locale);

  // Promote rounded unit boundaries (999.95K becomes 1M, not 1000K).
  const [divisor, suffix] = numberUnits.find(
    ([divisor]) => magnitude >= divisor - divisor / 20_000,
  );
  const scaled =
    (Math.sign(value) * Math.round((magnitude / divisor) * 10)) / 10;
  return scaled.toLocaleString(locale, { maximumFractionDigits: 1 }) + suffix;
}

/**
 * Formats hours into a human readable string
 * @param {number} hours - The time duration in hours
 * @param {Object} options - Formatting options
 * @param {boolean} [options.includeMinutes=false] - Whether to include minutes in the output
 * @returns {string} Formatted time string (e.g., "1h", "1h 30m", "25h", "168h")
 */
export function formatHours(hours, options = {}) {
  const { includeMinutes = false } = options;

  if (!includeMinutes) {
    const wholeHours = Math.round(hours);
    return `${wholeHours}h`;
  }

  const isNegative = hours < 0;
  const absHours = Math.abs(hours);
  const wholeHours = Math.floor(absHours);
  const minutes = Math.round((absHours - wholeHours) * 60);

  if (minutes === 0) {
    return `${isNegative ? "-" : ""}${wholeHours}h`;
  } else if (minutes === 60) {
    return `${isNegative ? "-" : ""}${wholeHours + 1}h`;
  } else {
    return `${isNegative ? "-" : ""}${wholeHours}h ${minutes}m`;
  }
}
