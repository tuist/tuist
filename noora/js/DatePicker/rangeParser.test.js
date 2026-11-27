import { describe, it, expect } from "vitest";
import {
  parseTypedRange,
  relativePresetPeriod,
  relativePresetId,
  relativePresetLabel,
  suggestTypedRanges,
} from "./rangeParser.js";

// Thursday, November 26, 2026, in the afternoon.
const today = new Date(2026, 10, 26, 15, 30);
const read = (text) => {
  const range = parseTypedRange(text, { today });
  if (!range) return null;
  const iso = (d) =>
    `${d.getFullYear()}-${String(d.getMonth() + 1).padStart(2, "0")}-${String(d.getDate()).padStart(2, "0")}`;
  return [iso(range.start), iso(range.end), range.preset];
};

describe("parseTypedRange", () => {
  it("applies rolling ranges as preset ids that end today", () => {
    expect(read("Last 10 days")).toEqual([
      "2026-11-16",
      "2026-11-26",
      "last-10-days",
    ]);
    expect(read("2w")).toEqual(["2026-11-12", "2026-11-26", "last-2-weeks"]);
    expect(read("10")).toEqual(["2026-11-16", "2026-11-26", "last-10-days"]);
    expect(read("past 3 months")).toEqual([
      "2026-08-26",
      "2026-11-26",
      "last-3-months",
    ]);
    expect(read("last week")).toEqual([
      "2026-11-19",
      "2026-11-26",
      "last-1-week",
    ]);
  });

  it("reads numeric dates day first, like the date inputs", () => {
    expect(read("1/9/2026 - 30/9/2026")).toEqual([
      "2026-09-01",
      "2026-09-30",
      "custom",
    ]);
  });

  it("reads dates without a year as the most recent one", () => {
    expect(read("sep 1 - 30")).toEqual(["2026-09-01", "2026-09-30", "custom"]);
    expect(read("dec 1 - 5")).toEqual(["2025-12-01", "2025-12-05", "custom"]);
  });

  it("reads a month name as the whole month, ending today at the latest", () => {
    expect(read("September")).toEqual(["2026-09-01", "2026-09-30", "custom"]);
    expect(read("this month")).toEqual(["2026-11-01", "2026-11-26", "custom"]);
  });

  it("runs ranges that start with since through today", () => {
    expect(read("since oct 3")).toEqual(["2026-10-03", "2026-11-26", "custom"]);
    expect(read("yesterday")).toEqual(["2026-11-25", "2026-11-25", "custom"]);
  });

  it("rejects text that is not only a date", () => {
    expect(read("")).toBeNull();
    expect(read("asdf")).toBeNull();
    expect(read("oct 3 maybe")).toBeNull();
    expect(read("3 minutes")).toBeNull();
    expect(read("0 days")).toBeNull();
  });

  it("rejects ranges that start after today", () => {
    expect(read("next tuesday")).toBeNull();
    expect(read("tomorrow")).toBeNull();
  });
});

describe("relative preset ids", () => {
  it("round-trips periods, and ignores other ids", () => {
    expect(relativePresetId({ amount: 10, unit: "day" })).toBe("last-10-days");
    expect(relativePresetPeriod("last-10-days")).toEqual({
      amount: 10,
      unit: "day",
    });
    expect(relativePresetPeriod("last-1-week")).toEqual({
      amount: 1,
      unit: "week",
    });
    expect(relativePresetPeriod("custom")).toBeNull();
    expect(relativePresetPeriod("last-24-minutes")).toBeNull();
  });
});

describe("suggestTypedRanges", () => {
  const labels = (text) =>
    suggestTypedRanges(text, { today }).map(({ label }) => label);

  it("offers every unit for a number alone", () => {
    expect(labels("3")).toEqual([
      "Last 3 days",
      "Last 3 hours",
      "Last 3 weeks",
      "Last 3 months",
      "Last 3 years",
    ]);
    expect(labels("4")).toEqual([
      "Last 4 days",
      "Last 4 hours",
      "Last 4 weeks",
      "Last 4 months",
    ]);
    expect(labels("last 1")).toEqual([
      "Last day",
      "Last hour",
      "Last week",
      "Last month",
      "Last year",
    ]);
  });

  it("guesses each unit only up to a sensible amount", () => {
    expect(labels("200")).toEqual(["Last 200 days"]);
    expect(labels("24")).toEqual([
      "Last 24 days",
      "Last 24 hours",
      "Last 24 weeks",
      "Last 24 months",
    ]);
    expect(labels("25")).toEqual([
      "Last 25 days",
      "Last 25 hours",
      "Last 25 weeks",
    ]);
    expect(labels("52")).toEqual([
      "Last 52 days",
      "Last 52 hours",
      "Last 52 weeks",
    ]);
    expect(labels("72")).toEqual(["Last 72 days", "Last 72 hours"]);
    expect(labels("73")).toEqual(["Last 73 days"]);
    expect(labels("500")).toEqual(["Last 500 days"]);
  });

  it("reads hours, counting back from now", () => {
    expect(labels("24 h")).toEqual(["Last 24 hours"]);
    expect(labels("last hour")).toEqual(["Last hour"]);
    expect(read("24h")).toEqual(["2026-11-25", "2026-11-26", "last-24-hours"]);
    expect(read("2 hours")).toEqual([
      "2026-11-26",
      "2026-11-26",
      "last-2-hours",
    ]);
    expect(relativePresetLabel("last-36-hours")).toBe("Last 36 hours");
  });

  it("offers a unit typed out at any amount", () => {
    expect(labels("200 w")).toEqual(["Last 200 weeks"]);
    expect(labels("200 years")).toEqual(["Last 200 years"]);
  });

  it("narrows to the units the typed letters start", () => {
    expect(labels("10 m")).toEqual(["Last 10 months"]);
    expect(labels("10w")).toEqual(["Last 10 weeks"]);
    expect(labels("3 days")).toEqual(["Last 3 days"]);
    expect(labels("last w")).toEqual(["Last week"]);
    expect(labels("10 x")).toEqual([]);
  });

  it("suggests each rolling range under its preset id, ending today", () => {
    const [months] = suggestTypedRanges("2 mo", { today });
    expect(months.preset).toBe("last-2-months");
    expect(months.start).toEqual(new Date(2026, 8, 26));
    expect(months.end).toEqual(new Date(2026, 10, 26));
  });

  it("names a typed date range in words", () => {
    expect(labels("sep 1 - 30")).toEqual(["Sep 1 - 30, 2026"]);
    expect(labels("since oct 3")).toEqual(["Oct 3 - Nov 26, 2026"]);
    expect(labels("dec 28 2025 - jan 3 2026")).toEqual([
      "Dec 28, 2025 - Jan 3, 2026",
    ]);
    expect(labels("yesterday")).toEqual(["Nov 25, 2026"]);
    expect(suggestTypedRanges("sep 1 - 30", { today })[0].preset).toBe(
      "custom",
    );
  });

  it("suggests nothing for text it can't read", () => {
    expect(labels("banana")).toEqual([]);
    expect(labels("")).toEqual([]);
  });
});

describe("relativePresetLabel", () => {
  it("names rolling preset ids and nothing else", () => {
    expect(relativePresetLabel("last-10-days")).toBe("Last 10 days");
    expect(relativePresetLabel("last-1-month")).toBe("Last month");
    expect(relativePresetLabel("custom")).toBeNull();
  });
});
