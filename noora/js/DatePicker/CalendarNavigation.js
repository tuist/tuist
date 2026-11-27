import { adjustMonth, compareMonths, initCalendarMonth } from "./dateUtils.js";

/**
 * Tracks the month the calendar shows. It starts at the selected range's
 * start month (or the current month) and moves one month at a time within
 * the min and max dates.
 */
export class CalendarNavigation {
  /**
   * @param {{year: number, month: number}|null} startDate
   * @param {function} onNavigate - Callback when the month changes
   */
  constructor(startDate, onNavigate) {
    this.calendarMonth = initCalendarMonth(startDate);
    this.onNavigate = onNavigate;
  }

  /**
   * @param {{year: number, month: number}|null} minDate
   * @returns {boolean}
   */
  canNavigatePrev(minDate) {
    return !minDate || compareMonths(this.calendarMonth, minDate) > 0;
  }

  /**
   * @param {{year: number, month: number}|null} maxDate
   * @returns {boolean}
   */
  canNavigateNext(maxDate) {
    return !maxDate || compareMonths(this.calendarMonth, maxDate) < 0;
  }

  navigatePrev() {
    this.navigateBy(-1);
  }

  navigateNext() {
    this.navigateBy(1);
  }

  navigateBy(months) {
    this.calendarMonth = adjustMonth(
      this.calendarMonth.year,
      this.calendarMonth.month,
      months,
    );
    this.onNavigate();
  }

  /**
   * Shows the month of a date, such as a newly selected range's start or the
   * day keyboard focus moved to.
   * @param {{year: number, month: number}} date
   */
  showMonthOf(date) {
    this.calendarMonth = { year: date.year, month: date.month };
  }
}
