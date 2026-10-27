import { describe, it, expect, vi, beforeEach } from "vitest";
import { CalendarNavigation } from "./CalendarNavigation.js";

describe("CalendarNavigation", () => {
  describe("canNavigatePrevStart", () => {
    let nav;
    let onNavigate;

    beforeEach(() => {
      onNavigate = vi.fn();
      nav = new CalendarNavigation(
        { year: 2024, month: 3, day: 1 },
        { year: 2024, month: 6, day: 1 },
        onNavigate,
      );
    });

    it("returns false when startCalendarMonth is null", () => {
      nav.startCalendarMonth = null;
      expect(nav.canNavigatePrevStart(null)).toBe(false);
    });

    it("returns true when no minDate is provided", () => {
      expect(nav.canNavigatePrevStart(null)).toBe(true);
    });

    it("returns true when start month is after minDate", () => {
      const minDate = { year: 2024, month: 1, day: 1 };
      expect(nav.canNavigatePrevStart(minDate)).toBe(true);
    });

    it("returns false when start month equals minDate month", () => {
      const minDate = { year: 2024, month: 3, day: 15 };
      expect(nav.canNavigatePrevStart(minDate)).toBe(false);
    });

    it("returns false when start month is before minDate", () => {
      const minDate = { year: 2024, month: 5, day: 1 };
      expect(nav.canNavigatePrevStart(minDate)).toBe(false);
    });

    it("returns true when year is greater than minDate year", () => {
      const minDate = { year: 2023, month: 12, day: 1 };
      expect(nav.canNavigatePrevStart(minDate)).toBe(true);
    });
  });

  describe("canNavigateNextStart", () => {
    let nav;
    let onNavigate;

    beforeEach(() => {
      onNavigate = vi.fn();
      nav = new CalendarNavigation(
        { year: 2024, month: 3, day: 1 },
        { year: 2024, month: 6, day: 1 },
        onNavigate,
      );
    });

    it("returns false when startCalendarMonth is null", () => {
      nav.startCalendarMonth = null;
      expect(nav.canNavigateNextStart()).toBe(false);
    });

    it("returns false when endCalendarMonth is null", () => {
      nav.endCalendarMonth = null;
      expect(nav.canNavigateNextStart()).toBe(false);
    });

    it("returns true when there is at least one month gap", () => {
      // Start: March, End: June - navigating to April still leaves gap
      expect(nav.canNavigateNextStart()).toBe(true);
    });

    it("returns false when calendars are adjacent months", () => {
      nav.startCalendarMonth = { year: 2024, month: 5 };
      nav.endCalendarMonth = { year: 2024, month: 6 };
      expect(nav.canNavigateNextStart()).toBe(false);
    });

    it("handles year boundary correctly", () => {
      nav.startCalendarMonth = { year: 2024, month: 11 };
      nav.endCalendarMonth = { year: 2025, month: 2 };
      // November -> December still before February
      expect(nav.canNavigateNextStart()).toBe(true);
    });
  });

  describe("canNavigatePrevEnd", () => {
    let nav;
    let onNavigate;

    beforeEach(() => {
      onNavigate = vi.fn();
      nav = new CalendarNavigation(
        { year: 2024, month: 3, day: 1 },
        { year: 2024, month: 6, day: 1 },
        onNavigate,
      );
    });

    it("returns false when startCalendarMonth is null", () => {
      nav.startCalendarMonth = null;
      expect(nav.canNavigatePrevEnd()).toBe(false);
    });

    it("returns false when endCalendarMonth is null", () => {
      nav.endCalendarMonth = null;
      expect(nav.canNavigatePrevEnd()).toBe(false);
    });

    it("returns true when there is at least one month gap", () => {
      // Start: March, End: June - navigating to May still leaves gap
      expect(nav.canNavigatePrevEnd()).toBe(true);
    });

    it("returns false when calendars are adjacent months", () => {
      nav.startCalendarMonth = { year: 2024, month: 5 };
      nav.endCalendarMonth = { year: 2024, month: 6 };
      expect(nav.canNavigatePrevEnd()).toBe(false);
    });

    it("handles year boundary correctly", () => {
      nav.startCalendarMonth = { year: 2024, month: 10 };
      nav.endCalendarMonth = { year: 2025, month: 1 };
      // January -> December still after October
      expect(nav.canNavigatePrevEnd()).toBe(true);
    });
  });

  describe("canNavigateNextEnd", () => {
    let nav;
    let onNavigate;

    beforeEach(() => {
      onNavigate = vi.fn();
      nav = new CalendarNavigation(
        { year: 2024, month: 3, day: 1 },
        { year: 2024, month: 6, day: 1 },
        onNavigate,
      );
    });

    it("returns false when endCalendarMonth is null", () => {
      nav.endCalendarMonth = null;
      expect(nav.canNavigateNextEnd(null)).toBe(false);
    });

    it("returns true when no maxDate is provided", () => {
      expect(nav.canNavigateNextEnd(null)).toBe(true);
    });

    it("returns true when end month is before maxDate", () => {
      const maxDate = { year: 2024, month: 12, day: 31 };
      expect(nav.canNavigateNextEnd(maxDate)).toBe(true);
    });

    it("returns false when end month equals maxDate month", () => {
      const maxDate = { year: 2024, month: 6, day: 15 };
      expect(nav.canNavigateNextEnd(maxDate)).toBe(false);
    });

    it("returns false when end month is after maxDate", () => {
      const maxDate = { year: 2024, month: 5, day: 1 };
      expect(nav.canNavigateNextEnd(maxDate)).toBe(false);
    });

    it("returns true when year is less than maxDate year", () => {
      const maxDate = { year: 2025, month: 1, day: 1 };
      expect(nav.canNavigateNextEnd(maxDate)).toBe(true);
    });
  });

  describe("navigatePrevStart", () => {
    let nav;
    let onNavigate;

    beforeEach(() => {
      onNavigate = vi.fn();
      nav = new CalendarNavigation(
        { year: 2024, month: 3, day: 1 },
        { year: 2024, month: 6, day: 1 },
        onNavigate,
      );
    });

    it("moves start calendar back one month", () => {
      nav.navigatePrevStart();
      expect(nav.startCalendarMonth).toEqual({ year: 2024, month: 2 });
    });

    it("calls onNavigate callback", () => {
      nav.navigatePrevStart();
      expect(onNavigate).toHaveBeenCalledTimes(1);
    });

    it("handles year boundary (January to December)", () => {
      nav.startCalendarMonth = { year: 2024, month: 1 };
      nav.navigatePrevStart();
      expect(nav.startCalendarMonth).toEqual({ year: 2023, month: 12 });
    });

    it("does nothing when startCalendarMonth is null", () => {
      nav.startCalendarMonth = null;
      nav.navigatePrevStart();
      expect(nav.startCalendarMonth).toBeNull();
      expect(onNavigate).not.toHaveBeenCalled();
    });
  });

  describe("navigateNextStart", () => {
    let nav;
    let onNavigate;

    beforeEach(() => {
      onNavigate = vi.fn();
      nav = new CalendarNavigation(
        { year: 2024, month: 3, day: 1 },
        { year: 2024, month: 6, day: 1 },
        onNavigate,
      );
    });

    it("moves start calendar forward one month when possible", () => {
      nav.navigateNextStart();
      expect(nav.startCalendarMonth).toEqual({ year: 2024, month: 4 });
    });

    it("calls onNavigate callback", () => {
      nav.navigateNextStart();
      expect(onNavigate).toHaveBeenCalledTimes(1);
    });

    it("handles year boundary (December to January)", () => {
      nav.startCalendarMonth = { year: 2024, month: 12 };
      nav.endCalendarMonth = { year: 2025, month: 3 };
      nav.navigateNextStart();
      expect(nav.startCalendarMonth).toEqual({ year: 2025, month: 1 });
    });

    it("does nothing when calendars would become adjacent", () => {
      nav.startCalendarMonth = { year: 2024, month: 5 };
      nav.endCalendarMonth = { year: 2024, month: 6 };
      nav.navigateNextStart();
      // Should not change since they're already adjacent
      expect(nav.startCalendarMonth).toEqual({ year: 2024, month: 5 });
      expect(onNavigate).not.toHaveBeenCalled();
    });
  });

  describe("navigatePrevEnd", () => {
    let nav;
    let onNavigate;

    beforeEach(() => {
      onNavigate = vi.fn();
      nav = new CalendarNavigation(
        { year: 2024, month: 3, day: 1 },
        { year: 2024, month: 6, day: 1 },
        onNavigate,
      );
    });

    it("moves end calendar back one month when possible", () => {
      nav.navigatePrevEnd();
      expect(nav.endCalendarMonth).toEqual({ year: 2024, month: 5 });
    });

    it("calls onNavigate callback", () => {
      nav.navigatePrevEnd();
      expect(onNavigate).toHaveBeenCalledTimes(1);
    });

    it("handles year boundary (January to December)", () => {
      nav.startCalendarMonth = { year: 2024, month: 10 };
      nav.endCalendarMonth = { year: 2025, month: 1 };
      nav.navigatePrevEnd();
      expect(nav.endCalendarMonth).toEqual({ year: 2024, month: 12 });
    });

    it("does nothing when calendars would become adjacent", () => {
      nav.startCalendarMonth = { year: 2024, month: 5 };
      nav.endCalendarMonth = { year: 2024, month: 6 };
      nav.navigatePrevEnd();
      // Should not change since they're already adjacent
      expect(nav.endCalendarMonth).toEqual({ year: 2024, month: 6 });
      expect(onNavigate).not.toHaveBeenCalled();
    });
  });

  describe("navigateNextEnd", () => {
    let nav;
    let onNavigate;

    beforeEach(() => {
      onNavigate = vi.fn();
      nav = new CalendarNavigation(
        { year: 2024, month: 3, day: 1 },
        { year: 2024, month: 6, day: 1 },
        onNavigate,
      );
    });

    it("moves end calendar forward one month", () => {
      nav.navigateNextEnd();
      expect(nav.endCalendarMonth).toEqual({ year: 2024, month: 7 });
    });

    it("calls onNavigate callback", () => {
      nav.navigateNextEnd();
      expect(onNavigate).toHaveBeenCalledTimes(1);
    });

    it("handles year boundary (December to January)", () => {
      nav.endCalendarMonth = { year: 2024, month: 12 };
      nav.navigateNextEnd();
      expect(nav.endCalendarMonth).toEqual({ year: 2025, month: 1 });
    });

    it("does nothing when endCalendarMonth is null", () => {
      nav.endCalendarMonth = null;
      nav.navigateNextEnd();
      expect(nav.endCalendarMonth).toBeNull();
      expect(onNavigate).not.toHaveBeenCalled();
    });
  });

  describe("updateForSelection", () => {
    let nav;
    let onNavigate;

    beforeEach(() => {
      onNavigate = vi.fn();
      nav = new CalendarNavigation(
        { year: 2024, month: 3, day: 1 },
        { year: 2024, month: 6, day: 1 },
        onNavigate,
      );
    });

    it("updates calendars to show selection range in different months", () => {
      nav.updateForSelection(
        { year: 2024, month: 8 },
        { year: 2024, month: 11 },
      );
      expect(nav.startCalendarMonth).toEqual({ year: 2024, month: 8 });
      expect(nav.endCalendarMonth).toEqual({ year: 2024, month: 11 });
    });

    it("adjusts when selection is in the same month", () => {
      nav.updateForSelection(
        { year: 2024, month: 9 },
        { year: 2024, month: 9 },
      );
      // Should show previous month in start calendar
      expect(nav.startCalendarMonth).toEqual({ year: 2024, month: 8 });
      expect(nav.endCalendarMonth).toEqual({ year: 2024, month: 9 });
    });

    it("handles year boundary for same-month selection in January", () => {
      nav.updateForSelection(
        { year: 2024, month: 1 },
        { year: 2024, month: 1 },
      );
      expect(nav.startCalendarMonth).toEqual({ year: 2023, month: 12 });
      expect(nav.endCalendarMonth).toEqual({ year: 2024, month: 1 });
    });

    it("handles selection spanning years", () => {
      nav.updateForSelection(
        { year: 2024, month: 11 },
        { year: 2025, month: 2 },
      );
      expect(nav.startCalendarMonth).toEqual({ year: 2024, month: 11 });
      expect(nav.endCalendarMonth).toEqual({ year: 2025, month: 2 });
    });
  });
});
