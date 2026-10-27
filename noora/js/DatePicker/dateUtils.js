import * as datePicker from "@zag-js/date-picker";

/**
 * Adjust a month by a delta, handling year wrap-around.
 * @param {number} year - The year
 * @param {number} month - The month (1-12)
 * @param {number} delta - Amount to adjust (-1 for previous, +1 for next)
 * @returns {{year: number, month: number}}
 */
export function adjustMonth(year, month, delta) {
  const date = new Date(year, month - 1 + delta, 1);
  return { year: date.getFullYear(), month: date.getMonth() + 1 };
}

/**
 * Compare two month objects.
 * @param {{year: number, month: number}} a
 * @param {{year: number, month: number}} b
 * @returns {number} Negative if a < b, 0 if equal, positive if a > b
 */
export function compareMonths(a, b) {
  if (a.year !== b.year) return a.year - b.year;
  return a.month - b.month;
}

/**
 * Compare two DateValue objects.
 * @param {{year: number, month: number, day: number}} a
 * @param {{year: number, month: number, day: number}} b
 * @returns {number} Negative if a < b, 0 if equal, positive if a > b
 */
export function compareDates(a, b) {
  if (a.year !== b.year) return a.year - b.year;
  if (a.month !== b.month) return a.month - b.month;
  return a.day - b.day;
}

/**
 * Format a Date object to ISO date string (YYYY-MM-DD).
 * @param {Date} date
 * @returns {string}
 */
export function toISODateString(date) {
  const year = date.getFullYear();
  const month = String(date.getMonth() + 1).padStart(2, "0");
  const day = String(date.getDate()).padStart(2, "0");
  return `${year}-${month}-${day}`;
}

/**
 * Calculate a date range based on a duration from now.
 * @param {{amount: number, unit: string}} duration - Duration with amount and unit
 * @returns {{start: Date, end: Date}}
 */
export function calculateRangeFromDuration(duration) {
  const now = new Date();
  const end = now;
  let start;

  const { amount, unit } = duration;

  switch (unit) {
    case "hour":
      start = new Date(now.getTime() - amount * 60 * 60 * 1000);
      break;
    case "day":
      start = new Date(now.getTime() - amount * 24 * 60 * 60 * 1000);
      break;
    case "week":
      start = new Date(now.getTime() - amount * 7 * 24 * 60 * 60 * 1000);
      break;
    case "month":
      start = new Date(now);
      start.setMonth(start.getMonth() - amount);
      break;
    case "year":
      start = new Date(now);
      start.setFullYear(start.getFullYear() - amount);
      break;
    default:
      start = new Date(now.getTime() - amount * 24 * 60 * 60 * 1000);
  }

  return { start, end };
}

/**
 * Format a date into day, month, year parts.
 * @param {Date|null} date
 * @returns {{day: string, month: string, year: string}}
 */
export function formatDateParts(date) {
  if (!date) return { day: "", month: "", year: "" };
  const d = new Date(date);
  return {
    day: String(d.getDate()).padStart(2, "0"),
    month: String(d.getMonth() + 1).padStart(2, "0"),
    year: String(d.getFullYear()),
  };
}

/**
 * Parse day, month, year inputs into a Date.
 * Uses Zag's parse function for validation.
 * @param {string} day
 * @param {string} month
 * @param {string} year
 * @returns {Date|null}
 */
export function parseDateFromParts(day, month, year) {
  const d = parseInt(day, 10);
  const m = parseInt(month, 10);
  const y = parseInt(year, 10);

  if (isNaN(d) || isNaN(m) || isNaN(y) || y < 1000) return null;

  const dateStr = `${y}-${String(m).padStart(2, "0")}-${String(d).padStart(2, "0")}`;

  try {
    const parsed = datePicker.parse(dateStr);
    if (!parsed) return null;
    return new Date(parsed.year, parsed.month - 1, parsed.day);
  } catch {
    return null;
  }
}

/**
 * Parse an ISO date string (with optional time) into a DateValue-like object.
 * Uses Zag's parse function for validation.
 * @param {string} str - ISO date string (e.g., "2024-01-15" or "2024-01-15T10:00:00Z")
 * @returns {{year: number, month: number, day: number}|null}
 */
export function parseISODate(str) {
  if (!str || str.length === 0) return null;

  // Extract date part (before 'T' if datetime string)
  const datePart = str.split("T")[0];

  try {
    const parsed = datePicker.parse(datePart);
    if (!parsed) return null;
    return {
      year: parsed.year,
      month: parsed.month,
      day: parsed.day,
    };
  } catch {
    return null;
  }
}

/**
 * Initialize calendar months from a date range, ensuring they show different months.
 * @param {{year: number, month: number, day: number}|null} startDate
 * @param {{year: number, month: number, day: number}|null} endDate
 * @returns {{startCalendarMonth: {year: number, month: number}, endCalendarMonth: {year: number, month: number}}}
 */
export function initCalendarMonthsFromRange(startDate, endDate) {
  const now = new Date();

  if (startDate && endDate) {
    // Check if start and end are in the same month
    const sameMonth =
      startDate.year === endDate.year && startDate.month === endDate.month;

    if (sameMonth) {
      // Show previous month in left calendar so we have two different months
      const prev = adjustMonth(endDate.year, endDate.month, -1);
      return {
        startCalendarMonth: prev,
        endCalendarMonth: { year: endDate.year, month: endDate.month },
      };
    } else {
      return {
        startCalendarMonth: { year: startDate.year, month: startDate.month },
        endCalendarMonth: { year: endDate.year, month: endDate.month },
      };
    }
  }

  // Default to previous month and current month
  const currentMonth = now.getMonth() + 1;
  const currentYear = now.getFullYear();
  const prev = adjustMonth(currentYear, currentMonth, -1);

  return {
    startCalendarMonth: prev,
    endCalendarMonth: { year: currentYear, month: currentMonth },
  };
}

/**
 * Calculate weeks for any arbitrary month.
 * Returns proper DateValue objects using Zag's parse function.
 * @param {number} year
 * @param {number} month
 * @param {number} startOfWeek - 0 for Sunday, 1 for Monday, etc.
 * @param {number} weeksToDisplay - Number of weeks to calculate (default 6)
 * @returns {Array<Array<object|null>>}
 */
export function calculateWeeksForMonth(
  year,
  month,
  startOfWeek = 0,
  weeksToDisplay = 6,
) {
  const weeks = [];

  // Get first day of month and total days
  const firstDay = new Date(year, month - 1, 1);
  const lastDay = new Date(year, month, 0);
  const totalDays = lastDay.getDate();

  // Calculate which day of week the month starts on
  const dayOfWeek = firstDay.getDay();
  // Adjust for start of week setting
  const startOffset = (dayOfWeek - startOfWeek + 7) % 7;

  // Build weeks
  let currentDay = 1 - startOffset;

  for (let weekIndex = 0; weekIndex < weeksToDisplay; weekIndex++) {
    const week = [];
    for (let dayIndex = 0; dayIndex < 7; dayIndex++) {
      if (currentDay >= 1 && currentDay <= totalDays) {
        // Day is in current month - create proper DateValue using Zag's parse
        const dateStr = `${year}-${String(month).padStart(2, "0")}-${String(currentDay).padStart(2, "0")}`;
        week.push(datePicker.parse(dateStr));
      } else {
        // Day is outside current month - push null (will be hidden)
        week.push(null);
      }
      currentDay++;
    }
    weeks.push(week);
  }

  return weeks;
}

/**
 * Get visible range for a given month (for Zag API compatibility).
 * Returns proper DateValue objects.
 * @param {number} year
 * @param {number} month
 * @returns {{start: object, end: object}}
 */
export function getVisibleRangeForMonth(year, month) {
  const lastDay = new Date(year, month, 0).getDate();
  const startStr = `${year}-${String(month).padStart(2, "0")}-01`;
  const endStr = `${year}-${String(month).padStart(2, "0")}-${String(lastDay).padStart(2, "0")}`;
  return {
    start: datePicker.parse(startStr),
    end: datePicker.parse(endStr),
  };
}
