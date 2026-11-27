import { describe, it, expect, vi } from "vitest";
import { CalendarNavigation } from "./CalendarNavigation.js";

describe("CalendarNavigation", () => {
  it("starts at the selected range's start month", () => {
    const nav = new CalendarNavigation(
      { year: 2026, month: 8, day: 1 },
      vi.fn(),
    );
    expect(nav.calendarMonth).toEqual({ year: 2026, month: 8 });
  });

  it("moves one month at a time across year boundaries", () => {
    const onNavigate = vi.fn();
    const nav = new CalendarNavigation(
      { year: 2026, month: 1, day: 15 },
      onNavigate,
    );

    nav.navigatePrev();
    expect(nav.calendarMonth).toEqual({ year: 2025, month: 12 });
    nav.navigateNext();
    nav.navigateNext();
    expect(nav.calendarMonth).toEqual({ year: 2026, month: 2 });
    expect(onNavigate).toHaveBeenCalledTimes(3);
  });

  it("stops at the min and max months, but not one month before them", () => {
    const nav = new CalendarNavigation(
      { year: 2026, month: 6, day: 15 },
      vi.fn(),
    );
    const min = { year: 2026, month: 6, day: 20 };
    const max = { year: 2026, month: 7, day: 3 };

    expect(nav.canNavigatePrev(min)).toBe(false);
    expect(nav.canNavigateNext(max)).toBe(true);
    nav.navigateNext();
    expect(nav.canNavigatePrev(min)).toBe(true);
    expect(nav.canNavigateNext(max)).toBe(false);
    expect(nav.canNavigateNext(null)).toBe(true);
  });

  it("shows the month of a date without notifying", () => {
    const onNavigate = vi.fn();
    const nav = new CalendarNavigation(null, onNavigate);
    nav.showMonthOf({ year: 2024, month: 2, day: 29 });
    expect(nav.calendarMonth).toEqual({ year: 2024, month: 2 });
    expect(onNavigate).not.toHaveBeenCalled();
  });
});
