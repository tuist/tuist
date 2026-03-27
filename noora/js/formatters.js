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
