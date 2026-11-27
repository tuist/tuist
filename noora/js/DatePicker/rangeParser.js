import * as chrono from "chrono-node";

// Typed ranges are whole days, in English. "Last 10 days", "24h", "2w", or a
// bare "10" is rolling: it keeps ending today, so it is applied as a preset id
// ("last-10-days") that the page stores in its URL. Anything else that chrono
// reads ("Sep 1 - 30", "since Oct 3", "yesterday") is a fixed custom range.

const UNITS = {
  h: "hour",
  hr: "hour",
  hrs: "hour",
  hour: "hour",
  hours: "hour",
  d: "day",
  day: "day",
  days: "day",
  w: "week",
  wk: "week",
  wks: "week",
  week: "week",
  weeks: "week",
  m: "month",
  mo: "month",
  mos: "month",
  month: "month",
  months: "month",
  y: "year",
  yr: "year",
  yrs: "year",
  year: "year",
  years: "year",
};

const RELATIVE_ID = /^last-(\d{1,4})-(hour|day|week|month|year)s?$/;

/**
 * The period of a rolling preset id such as "last-10-days".
 * @param {string} id
 * @returns {{amount: number, unit: string}|null}
 */
export function relativePresetPeriod(id) {
  const match = RELATIVE_ID.exec(id || "");
  if (!match || Number(match[1]) < 1) return null;
  return { amount: Number(match[1]), unit: match[2] };
}

/**
 * The preset id for a rolling period, such as "last-10-days".
 * @param {{amount: number, unit: string}} period
 * @returns {string}
 */
export function relativePresetId({ amount, unit }) {
  return `last-${amount}-${unit}${amount === 1 ? "" : "s"}`;
}

function rollingPeriod(text) {
  let match = text.match(
    /^(?:(?:last|past|previous)\s+)?(\d{1,4})\s*([a-z]+)?$/,
  );
  if (match) {
    const unit = match[2] ? UNITS[match[2]] : "day";
    const amount = Number(match[1]);
    return unit && amount > 0 ? { amount, unit } : null;
  }
  match = text.match(/^(?:last|past|previous)\s+(hour|day|week|month|year)$/);
  return match ? { amount: 1, unit: match[1] } : null;
}

const day = (date) =>
  new Date(date.getFullYear(), date.getMonth(), date.getDate());
const lastDayOfMonth = (date) =>
  new Date(date.getFullYear(), date.getMonth() + 1, 0);

// The first day a rolling period touches. Hours count back from the moment
// itself: the last 24 hours start yesterday.
function startOfPeriod(now, { amount, unit }) {
  if (unit === "hour") return day(new Date(now.getTime() - amount * 3600000));
  const start = day(now);
  if (unit === "day") start.setDate(start.getDate() - amount);
  if (unit === "week") start.setDate(start.getDate() - amount * 7);
  if (unit === "month") start.setMonth(start.getMonth() - amount);
  if (unit === "year") start.setFullYear(start.getFullYear() - amount);
  return start;
}

/**
 * Reads a typed range.
 * @param {string} input - What the person typed
 * @param {{today?: Date}} [options]
 * @returns {{start: Date, end: Date, preset: string}|null} The range in whole
 *   days, and the preset id to apply it under: a rolling id, or "custom".
 */
export function parseTypedRange(input, { today = new Date() } = {}) {
  const text = input.trim().toLowerCase().replace(/\s+/g, " ");
  if (!text) return null;
  const todayDay = day(today);

  const period = rollingPeriod(text);
  if (period) {
    return {
      start: startOfPeriod(today, period),
      end: todayDay,
      preset: relativePresetId(period),
    };
  }

  const growing = /^(?:since|from)\s/.test(text);
  const results = chrono.en.GB.parse(text, today);
  if (results.length !== 1) return null;
  const [result] = results;

  // The date must be all that was typed, apart from "since" or "from".
  const rest = text.replace(result.text, "").trim();
  if (rest !== "" && !(growing && /^(since|from)$/.test(rest))) return null;

  let start = day(result.start.date());
  let end = result.end ? day(result.end.date()) : start;
  // "September" names the whole month.
  if (!result.end && !result.start.isCertain("day"))
    end = lastDayOfMonth(start);
  if (growing && !result.end) end = todayDay;

  // A month named without a year, ahead of today, means last year's: these
  // ranges look back. Relative dates such as "next tuesday" stay put.
  if (
    result.start.isCertain("month") &&
    !result.start.isCertain("year") &&
    start > todayDay
  ) {
    start.setFullYear(start.getFullYear() - 1);
    end.setFullYear(end.getFullYear() - 1);
  }
  if (end < start) [start, end] = [end, start];
  if (start > todayDay) return null;
  // A range that reaches past today ends today, as in "this month".
  if (start <= todayDay && end > todayDay) end = todayDay;

  return { start, end, preset: "custom" };
}

const UNIT_NAMES = ["day", "hour", "week", "month", "year"];
const MONTHS = [
  "Jan",
  "Feb",
  "Mar",
  "Apr",
  "May",
  "Jun",
  "Jul",
  "Aug",
  "Sep",
  "Oct",
  "Nov",
  "Dec",
];

// The largest amount of each unit worth guessing. Past it, the unit reads
// oddly ("200 weeks") or reaches back further than any data ("10 years").
// Pages that know where their data starts pass `min`, which drops longer
// suggestions too.
// Days have no limit: a number alone always means days.
const LARGEST_GUESS = {
  day: Infinity,
  hour: 72,
  week: 52,
  month: 24,
  year: 3,
};

// The rolling periods a partly typed text could mean: a number alone could
// be any unit ("10" is 10 days, hours, weeks, months, or years), and the start of a
// unit narrows it ("10 m" is 10 months). "last" alone means one of each.
// Guessed units stop at their largest sensible amount; a unit narrowed down
// to one is offered at any amount.
function rollingCandidates(text) {
  const match = text.match(
    /^(?:(last|past|previous)\s*)?(\d{1,4})?\s*([a-z]*)$/,
  );
  if (!match || (!match[1] && !match[2])) return [];
  const amount = match[2] ? Number(match[2]) : 1;
  if (amount < 1) return [];
  const word = match[3];
  const units = UNIT_NAMES.filter(
    (unit) => `${unit}s`.startsWith(word) || UNITS[word] === unit,
  );
  return units
    .filter((unit) => units.length === 1 || amount <= LARGEST_GUESS[unit])
    .map((unit) => ({ amount, unit }));
}

const relativeLabel = ({ amount, unit }) =>
  amount === 1 ? `Last ${unit}` : `Last ${amount} ${unit}s`;

/**
 * The label of a rolling preset id, such as "Last 10 days" for
 * "last-10-days", or null for any other id.
 * @param {string} id
 * @returns {string|null}
 */
export function relativePresetLabel(id) {
  const period = relativePresetPeriod(id);
  return period ? relativeLabel(period) : null;
}

// The range in words, naming the month and year only where they change, as
// the trigger does: "Sep 1 - 30, 2026", "Dec 28, 2025 - Jan 3, 2026".
export function formatRange(start, end) {
  const monthDay = (date) => `${MONTHS[date.getMonth()]} ${date.getDate()}`;
  const year = end.getFullYear();
  if (start.getTime() === end.getTime()) return `${monthDay(start)}, ${year}`;
  if (start.getFullYear() !== year)
    return `${monthDay(start)}, ${start.getFullYear()} - ${monthDay(end)}, ${year}`;
  if (start.getMonth() !== end.getMonth())
    return `${monthDay(start)} - ${monthDay(end)}, ${year}`;
  return `${monthDay(start)} - ${end.getDate()}, ${year}`;
}

/**
 * The ranges a partly typed text could mean, to offer in place of the
 * presets while typing.
 * @param {string} input - What the person typed so far
 * @param {{today?: Date}} [options]
 * @returns {Array<{start: Date, end: Date, preset: string, label: string}>}
 */
export function suggestTypedRanges(input, { today = new Date() } = {}) {
  const text = input.trim().toLowerCase().replace(/\s+/g, " ");
  if (!text) return [];
  const todayDay = day(today);

  const rolling = rollingCandidates(text);
  if (rolling.length > 0) {
    return rolling.map((period) => ({
      start: startOfPeriod(today, period),
      end: todayDay,
      preset: relativePresetId(period),
      label: relativeLabel(period),
    }));
  }

  const typed = parseTypedRange(text, { today });
  if (!typed) return [];
  const period = relativePresetPeriod(typed.preset);
  return [
    {
      ...typed,
      label: period
        ? relativeLabel(period)
        : formatRange(typed.start, typed.end),
    },
  ];
}
