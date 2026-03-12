import {
  adjustMonth,
  compareMonths,
  initCalendarMonthsFromRange,
} from "./dateUtils.js";

/**
 * Manages calendar month navigation state for a dual-calendar date picker.
 * Each calendar (start/end) can be navigated independently while maintaining
 * the constraint that the start calendar must always show a month before the end calendar.
 */
export class CalendarNavigation {
  /**
   * @param {{year: number, month: number}|null} startDate
   * @param {{year: number, month: number}|null} endDate
   * @param {function} onNavigate - Callback when navigation changes
   */
  constructor(startDate, endDate, onNavigate) {
    const { startCalendarMonth, endCalendarMonth } =
      initCalendarMonthsFromRange(startDate, endDate);
    this.startCalendarMonth = startCalendarMonth;
    this.endCalendarMonth = endCalendarMonth;
    this.onNavigate = onNavigate;
  }

  /**
   * Check if we can navigate the start (left) calendar backwards.
   * @param {{year: number, month: number, day: number}|null} minDate
   * @returns {boolean}
   */
  canNavigatePrevStart(minDate) {
    if (!this.startCalendarMonth) return false;
    if (!minDate) return true;
    return (
      this.startCalendarMonth.year > minDate.year ||
      (this.startCalendarMonth.year === minDate.year &&
        this.startCalendarMonth.month > minDate.month)
    );
  }

  /**
   * Check if we can navigate the start (left) calendar forwards.
   * Must stay before the end calendar.
   * @returns {boolean}
   */
  canNavigateNextStart() {
    if (!this.startCalendarMonth || !this.endCalendarMonth) return false;
    const nextMonth = adjustMonth(
      this.startCalendarMonth.year,
      this.startCalendarMonth.month,
      1,
    );
    return compareMonths(nextMonth, this.endCalendarMonth) < 0;
  }

  /**
   * Check if we can navigate the end (right) calendar backwards.
   * Must stay after the start calendar.
   * @returns {boolean}
   */
  canNavigatePrevEnd() {
    if (!this.startCalendarMonth || !this.endCalendarMonth) return false;
    const prevMonth = adjustMonth(
      this.endCalendarMonth.year,
      this.endCalendarMonth.month,
      -1,
    );
    return compareMonths(prevMonth, this.startCalendarMonth) > 0;
  }

  /**
   * Check if we can navigate the end (right) calendar forwards.
   * @param {{year: number, month: number, day: number}|null} maxDate
   * @returns {boolean}
   */
  canNavigateNextEnd(maxDate) {
    if (!this.endCalendarMonth) return false;
    if (!maxDate) return true;
    return (
      this.endCalendarMonth.year < maxDate.year ||
      (this.endCalendarMonth.year === maxDate.year &&
        this.endCalendarMonth.month < maxDate.month)
    );
  }

  /**
   * Navigate the start (left) calendar backwards one month.
   */
  navigatePrevStart() {
    if (!this.startCalendarMonth) return;
    this.startCalendarMonth = adjustMonth(
      this.startCalendarMonth.year,
      this.startCalendarMonth.month,
      -1,
    );
    this.onNavigate();
  }

  /**
   * Navigate the start (left) calendar forwards one month.
   */
  navigateNextStart() {
    if (!this.canNavigateNextStart()) return;
    this.startCalendarMonth = adjustMonth(
      this.startCalendarMonth.year,
      this.startCalendarMonth.month,
      1,
    );
    this.onNavigate();
  }

  /**
   * Navigate the end (right) calendar backwards one month.
   */
  navigatePrevEnd() {
    if (!this.canNavigatePrevEnd()) return;
    this.endCalendarMonth = adjustMonth(
      this.endCalendarMonth.year,
      this.endCalendarMonth.month,
      -1,
    );
    this.onNavigate();
  }

  /**
   * Navigate the end (right) calendar forwards one month.
   */
  navigateNextEnd() {
    if (!this.endCalendarMonth) return;
    this.endCalendarMonth = adjustMonth(
      this.endCalendarMonth.year,
      this.endCalendarMonth.month,
      1,
    );
    this.onNavigate();
  }

  /**
   * Update calendar months to show a selected range.
   * @param {{year: number, month: number}} startDate
   * @param {{year: number, month: number}} endDate
   */
  updateForSelection(startDate, endDate) {
    const sameMonth =
      startDate.year === endDate.year && startDate.month === endDate.month;

    if (sameMonth) {
      const prev = adjustMonth(endDate.year, endDate.month, -1);
      this.startCalendarMonth = prev;
      this.endCalendarMonth = { year: endDate.year, month: endDate.month };
    } else {
      this.startCalendarMonth = {
        year: startDate.year,
        month: startDate.month,
      };
      this.endCalendarMonth = { year: endDate.year, month: endDate.month };
    }
  }
}
