import { describe, it, expect, vi, beforeEach, afterEach } from "vitest";
import {
  adjustMonth,
  compareMonths,
  compareDates,
  toISODateString,
  calculateRangeFromDuration,
  formatDateParts,
  parseDateFromParts,
  parseISODate,
  initCalendarMonthsFromRange,
  calculateWeeksForMonth,
  getVisibleRangeForMonth,
} from "./dateUtils.js";

describe("adjustMonth", () => {
  it("increments month within same year", () => {
    expect(adjustMonth(2024, 5, 1)).toEqual({ year: 2024, month: 6 });
  });

  it("decrements month within same year", () => {
    expect(adjustMonth(2024, 5, -1)).toEqual({ year: 2024, month: 4 });
  });

  it("wraps from December to January of next year", () => {
    expect(adjustMonth(2024, 12, 1)).toEqual({ year: 2025, month: 1 });
  });

  it("wraps from January to December of previous year", () => {
    expect(adjustMonth(2024, 1, -1)).toEqual({ year: 2023, month: 12 });
  });

  it("handles multi-month jumps forward", () => {
    expect(adjustMonth(2024, 10, 5)).toEqual({ year: 2025, month: 3 });
  });

  it("handles multi-month jumps backward", () => {
    expect(adjustMonth(2024, 3, -5)).toEqual({ year: 2023, month: 10 });
  });

  it("handles delta of zero", () => {
    expect(adjustMonth(2024, 6, 0)).toEqual({ year: 2024, month: 6 });
  });

  it("handles jumping more than a year", () => {
    expect(adjustMonth(2024, 6, 15)).toEqual({ year: 2025, month: 9 });
  });
});

describe("compareMonths", () => {
  it("returns 0 for equal months", () => {
    expect(
      compareMonths({ year: 2024, month: 6 }, { year: 2024, month: 6 }),
    ).toBe(0);
  });

  it("returns negative when a is before b (same year)", () => {
    expect(
      compareMonths({ year: 2024, month: 3 }, { year: 2024, month: 6 }),
    ).toBeLessThan(0);
  });

  it("returns positive when a is after b (same year)", () => {
    expect(
      compareMonths({ year: 2024, month: 9 }, { year: 2024, month: 6 }),
    ).toBeGreaterThan(0);
  });

  it("returns negative when a year is before b year", () => {
    expect(
      compareMonths({ year: 2023, month: 12 }, { year: 2024, month: 1 }),
    ).toBeLessThan(0);
  });

  it("returns positive when a year is after b year", () => {
    expect(
      compareMonths({ year: 2025, month: 1 }, { year: 2024, month: 12 }),
    ).toBeGreaterThan(0);
  });
});

describe("compareDates", () => {
  it("returns 0 for equal dates", () => {
    expect(
      compareDates(
        { year: 2024, month: 6, day: 15 },
        { year: 2024, month: 6, day: 15 },
      ),
    ).toBe(0);
  });

  it("returns negative when a is before b (different year)", () => {
    expect(
      compareDates(
        { year: 2023, month: 12, day: 31 },
        { year: 2024, month: 1, day: 1 },
      ),
    ).toBeLessThan(0);
  });

  it("returns positive when a is after b (different year)", () => {
    expect(
      compareDates(
        { year: 2024, month: 1, day: 1 },
        { year: 2023, month: 12, day: 31 },
      ),
    ).toBeGreaterThan(0);
  });

  it("returns negative when a is before b (same year, different month)", () => {
    expect(
      compareDates(
        { year: 2024, month: 3, day: 15 },
        { year: 2024, month: 6, day: 10 },
      ),
    ).toBeLessThan(0);
  });

  it("returns positive when a is after b (same year, different month)", () => {
    expect(
      compareDates(
        { year: 2024, month: 6, day: 10 },
        { year: 2024, month: 3, day: 15 },
      ),
    ).toBeGreaterThan(0);
  });

  it("returns negative when a is before b (same month, different day)", () => {
    expect(
      compareDates(
        { year: 2024, month: 6, day: 10 },
        { year: 2024, month: 6, day: 20 },
      ),
    ).toBeLessThan(0);
  });

  it("returns positive when a is after b (same month, different day)", () => {
    expect(
      compareDates(
        { year: 2024, month: 6, day: 20 },
        { year: 2024, month: 6, day: 10 },
      ),
    ).toBeGreaterThan(0);
  });
});

describe("toISODateString", () => {
  it("formats a date as YYYY-MM-DD", () => {
    const date = new Date(2024, 5, 15); // June 15, 2024
    expect(toISODateString(date)).toBe("2024-06-15");
  });

  it("pads single-digit months", () => {
    const date = new Date(2024, 0, 15); // January 15, 2024
    expect(toISODateString(date)).toBe("2024-01-15");
  });

  it("pads single-digit days", () => {
    const date = new Date(2024, 5, 5); // June 5, 2024
    expect(toISODateString(date)).toBe("2024-06-05");
  });

  it("handles end of year dates", () => {
    const date = new Date(2024, 11, 31); // December 31, 2024
    expect(toISODateString(date)).toBe("2024-12-31");
  });

  it("handles start of year dates", () => {
    const date = new Date(2024, 0, 1); // January 1, 2024
    expect(toISODateString(date)).toBe("2024-01-01");
  });
});

describe("calculateRangeFromDuration", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date(2024, 5, 15, 12, 0, 0)); // June 15, 2024, noon
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("calculates range for hours", () => {
    const { start, end } = calculateRangeFromDuration({
      amount: 24,
      unit: "hour",
    });
    expect(end.getTime()).toBe(new Date(2024, 5, 15, 12, 0, 0).getTime());
    expect(start.getTime()).toBe(new Date(2024, 5, 14, 12, 0, 0).getTime());
  });

  it("calculates range for days", () => {
    const { start, end } = calculateRangeFromDuration({
      amount: 7,
      unit: "day",
    });
    expect(end.getTime()).toBe(new Date(2024, 5, 15, 12, 0, 0).getTime());
    expect(start.getTime()).toBe(new Date(2024, 5, 8, 12, 0, 0).getTime());
  });

  it("calculates range for weeks", () => {
    const { start, end } = calculateRangeFromDuration({
      amount: 2,
      unit: "week",
    });
    expect(end.getTime()).toBe(new Date(2024, 5, 15, 12, 0, 0).getTime());
    expect(start.getTime()).toBe(new Date(2024, 5, 1, 12, 0, 0).getTime());
  });

  it("calculates range for months", () => {
    const { start, end } = calculateRangeFromDuration({
      amount: 3,
      unit: "month",
    });
    expect(end.getTime()).toBe(new Date(2024, 5, 15, 12, 0, 0).getTime());
    expect(start.getMonth()).toBe(2); // March
  });

  it("calculates range for years", () => {
    const { start, end } = calculateRangeFromDuration({
      amount: 1,
      unit: "year",
    });
    expect(end.getTime()).toBe(new Date(2024, 5, 15, 12, 0, 0).getTime());
    expect(start.getFullYear()).toBe(2023);
  });

  it("defaults to days for unknown unit", () => {
    const { start, end } = calculateRangeFromDuration({
      amount: 5,
      unit: "unknown",
    });
    expect(end.getTime()).toBe(new Date(2024, 5, 15, 12, 0, 0).getTime());
    expect(start.getTime()).toBe(new Date(2024, 5, 10, 12, 0, 0).getTime());
  });
});

describe("formatDateParts", () => {
  it("returns empty strings for null date", () => {
    expect(formatDateParts(null)).toEqual({ day: "", month: "", year: "" });
  });

  it("formats date into padded parts", () => {
    const date = new Date(2024, 5, 15); // June 15, 2024
    expect(formatDateParts(date)).toEqual({
      day: "15",
      month: "06",
      year: "2024",
    });
  });

  it("pads single-digit days", () => {
    const date = new Date(2024, 5, 5); // June 5, 2024
    expect(formatDateParts(date)).toEqual({
      day: "05",
      month: "06",
      year: "2024",
    });
  });

  it("pads single-digit months", () => {
    const date = new Date(2024, 0, 15); // January 15, 2024
    expect(formatDateParts(date)).toEqual({
      day: "15",
      month: "01",
      year: "2024",
    });
  });

  it("handles date strings", () => {
    expect(formatDateParts("2024-06-15")).toEqual({
      day: "15",
      month: "06",
      year: "2024",
    });
  });
});

describe("parseDateFromParts", () => {
  it("parses valid date parts", () => {
    const date = parseDateFromParts("15", "06", "2024");
    expect(date).toBeInstanceOf(Date);
    expect(date.getDate()).toBe(15);
    expect(date.getMonth()).toBe(5); // June (0-indexed)
    expect(date.getFullYear()).toBe(2024);
  });

  it("returns null for non-numeric day", () => {
    expect(parseDateFromParts("abc", "06", "2024")).toBeNull();
  });

  it("returns null for non-numeric month", () => {
    expect(parseDateFromParts("15", "abc", "2024")).toBeNull();
  });

  it("returns null for non-numeric year", () => {
    expect(parseDateFromParts("15", "06", "abc")).toBeNull();
  });

  it("returns null for day out of range (0)", () => {
    expect(parseDateFromParts("0", "06", "2024")).toBeNull();
  });

  it("returns null for day out of range (32)", () => {
    expect(parseDateFromParts("32", "06", "2024")).toBeNull();
  });

  it("returns null for month out of range (0)", () => {
    expect(parseDateFromParts("15", "0", "2024")).toBeNull();
  });

  it("returns null for month out of range (13)", () => {
    expect(parseDateFromParts("15", "13", "2024")).toBeNull();
  });

  it("returns null for year below 1000", () => {
    expect(parseDateFromParts("15", "06", "999")).toBeNull();
  });

  it("returns null for invalid date (Feb 30)", () => {
    expect(parseDateFromParts("30", "02", "2024")).toBeNull();
  });

  it("returns null for invalid date (Feb 29 in non-leap year)", () => {
    expect(parseDateFromParts("29", "02", "2023")).toBeNull();
  });

  it("accepts Feb 29 in leap year", () => {
    const date = parseDateFromParts("29", "02", "2024");
    expect(date).toBeInstanceOf(Date);
    expect(date.getDate()).toBe(29);
    expect(date.getMonth()).toBe(1); // February
  });

  it("handles padded inputs", () => {
    const date = parseDateFromParts("05", "06", "2024");
    expect(date.getDate()).toBe(5);
  });
});

describe("parseISODate", () => {
  it("parses ISO date string", () => {
    expect(parseISODate("2024-06-15")).toEqual({
      year: 2024,
      month: 6,
      day: 15,
    });
  });

  it("parses ISO datetime string (strips time)", () => {
    expect(parseISODate("2024-06-15T10:30:00")).toEqual({
      year: 2024,
      month: 6,
      day: 15,
    });
  });

  it("returns null for null input", () => {
    expect(parseISODate(null)).toBeNull();
  });

  it("returns null for empty string", () => {
    expect(parseISODate("")).toBeNull();
  });

  it("returns null for invalid format", () => {
    expect(parseISODate("invalid")).toBeNull();
  });

  it("returns null for partial date", () => {
    expect(parseISODate("2024-06")).toBeNull();
  });

  it("returns null for non-padded date format", () => {
    expect(parseISODate("2024-1-5")).toBeNull();
  });
});

describe("initCalendarMonthsFromRange", () => {
  beforeEach(() => {
    vi.useFakeTimers();
    vi.setSystemTime(new Date(2024, 5, 15)); // June 15, 2024
  });

  afterEach(() => {
    vi.useRealTimers();
  });

  it("returns adjacent months when no dates provided", () => {
    const { startCalendarMonth, endCalendarMonth } =
      initCalendarMonthsFromRange(null, null);
    expect(startCalendarMonth).toEqual({ year: 2024, month: 5 }); // May
    expect(endCalendarMonth).toEqual({ year: 2024, month: 6 }); // June
  });

  it("returns start and end months when dates are in different months", () => {
    const { startCalendarMonth, endCalendarMonth } =
      initCalendarMonthsFromRange(
        { year: 2024, month: 3, day: 10 },
        { year: 2024, month: 8, day: 20 },
      );
    expect(startCalendarMonth).toEqual({ year: 2024, month: 3 });
    expect(endCalendarMonth).toEqual({ year: 2024, month: 8 });
  });

  it("adjusts when dates are in the same month", () => {
    const { startCalendarMonth, endCalendarMonth } =
      initCalendarMonthsFromRange(
        { year: 2024, month: 6, day: 10 },
        { year: 2024, month: 6, day: 20 },
      );
    expect(startCalendarMonth).toEqual({ year: 2024, month: 5 }); // Previous month
    expect(endCalendarMonth).toEqual({ year: 2024, month: 6 });
  });

  it("handles same month in January (wraps to previous year)", () => {
    const { startCalendarMonth, endCalendarMonth } =
      initCalendarMonthsFromRange(
        { year: 2024, month: 1, day: 10 },
        { year: 2024, month: 1, day: 20 },
      );
    expect(startCalendarMonth).toEqual({ year: 2023, month: 12 }); // December of previous year
    expect(endCalendarMonth).toEqual({ year: 2024, month: 1 });
  });

  it("handles date range spanning years", () => {
    const { startCalendarMonth, endCalendarMonth } =
      initCalendarMonthsFromRange(
        { year: 2023, month: 11, day: 15 },
        { year: 2024, month: 2, day: 10 },
      );
    expect(startCalendarMonth).toEqual({ year: 2023, month: 11 });
    expect(endCalendarMonth).toEqual({ year: 2024, month: 2 });
  });
});

describe("calculateWeeksForMonth", () => {
  it("returns 6 weeks by default", () => {
    const weeks = calculateWeeksForMonth(2024, 6, 0);
    expect(weeks).toHaveLength(6);
  });

  it("returns requested number of weeks", () => {
    const weeks = calculateWeeksForMonth(2024, 6, 0, 4);
    expect(weeks).toHaveLength(4);
  });

  it("returns 7 days per week", () => {
    const weeks = calculateWeeksForMonth(2024, 6, 0);
    weeks.forEach((week) => {
      expect(week).toHaveLength(7);
    });
  });

  it("has null for days outside the month", () => {
    const weeks = calculateWeeksForMonth(2024, 6, 0); // June 2024 starts on Saturday
    // First week should have nulls for Sun-Fri
    expect(weeks[0][0]).toBeNull(); // Sunday
    expect(weeks[0][5]).toBeNull(); // Friday
    expect(weeks[0][6]).not.toBeNull(); // Saturday (June 1)
  });

  it("creates DateValue objects for days in month", () => {
    const weeks = calculateWeeksForMonth(2024, 6, 0);
    // Find a day that's definitely in the month
    const juneFirst = weeks[0][6]; // June 1, 2024 is Saturday
    expect(juneFirst).not.toBeNull();
    expect(juneFirst.year).toBe(2024);
    expect(juneFirst.month).toBe(6);
    expect(juneFirst.day).toBe(1);
  });

  it("respects startOfWeek parameter (Monday start)", () => {
    // June 2024: 1st is Saturday
    // With Monday start (1), Saturday is index 5
    const weeks = calculateWeeksForMonth(2024, 6, 1);
    // First week with Monday start should have June 1 at index 5 (Saturday position)
    expect(weeks[0][5]).not.toBeNull();
    expect(weeks[0][5].day).toBe(1);
  });

  it("contains all days of the month", () => {
    const weeks = calculateWeeksForMonth(2024, 6, 0); // June has 30 days
    const allDays = weeks.flat().filter((d) => d !== null);
    expect(allDays).toHaveLength(30);

    const dayNumbers = allDays.map((d) => d.day).sort((a, b) => a - b);
    expect(dayNumbers[0]).toBe(1);
    expect(dayNumbers[dayNumbers.length - 1]).toBe(30);
  });
});

describe("getVisibleRangeForMonth", () => {
  it("returns start and end DateValue objects for the month", () => {
    const { start, end } = getVisibleRangeForMonth(2024, 6);
    expect(start.year).toBe(2024);
    expect(start.month).toBe(6);
    expect(start.day).toBe(1);
    expect(end.year).toBe(2024);
    expect(end.month).toBe(6);
    expect(end.day).toBe(30); // June has 30 days
  });

  it("calculates correct last day for months with 31 days", () => {
    const { end } = getVisibleRangeForMonth(2024, 7); // July
    expect(end.day).toBe(31);
  });

  it("calculates correct last day for February in leap year", () => {
    const { end } = getVisibleRangeForMonth(2024, 2);
    expect(end.day).toBe(29);
  });

  it("calculates correct last day for February in non-leap year", () => {
    const { end } = getVisibleRangeForMonth(2023, 2);
    expect(end.day).toBe(28);
  });
});
