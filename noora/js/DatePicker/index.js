import * as datePicker from "@zag-js/date-picker";
import {
  getOption,
  getBooleanOption,
  normalizeProps,
  spreadProps,
  renderPart,
} from "../util.js";
import { Component } from "../component.js";
import { VanillaMachine } from "../machine.js";
import {
  calculateRangeFromDuration,
  formatDateParts,
  compareDates,
  parseISODate,
  toISODateString,
  calculateWeeksForMonth,
  getVisibleRangeForMonth,
} from "./dateUtils.js";
import { CalendarNavigation } from "./CalendarNavigation.js";
import { DateInputHandler } from "./DateInputHandler.js";
import { WEEKDAYS, MOBILE_BREAKPOINT } from "./constants.js";

class DatePicker extends Component {
  constructor(el, props) {
    super(el, props);
    this.presets = props.presets || [];
    this.selectedPreset = props.selectedPreset;
    this.isMobileView = window.innerWidth < MOBILE_BREAKPOINT;
    this.pendingRange = null;
    this.isSettingPreset = false;
    this.minDate = props.min ? datePicker.parse(props.min) : null;
    this.maxDate = props.max ? datePicker.parse(props.max) : null;

    // Calendar navigation manager - initialized with current value
    const value = this.api.value;
    this.calendarNav = new CalendarNavigation(
      value && value[0],
      value && value[1],
      () => this.render(),
    );

    // AbortController for component-level event listeners
    this.abortController = new AbortController();

    this.setupNavigationHandlers();
  }

  setupNavigationHandlers() {
    const signal = this.abortController.signal;

    // Use event delegation on month elements
    const months = this.el.querySelectorAll(
      "[data-part='months'] > [data-part='month']",
    );

    months.forEach((monthEl, monthIndex) => {
      const prevTrigger = monthEl.querySelector("[data-part='prev-trigger']");
      const nextTrigger = monthEl.querySelector("[data-part='next-trigger']");

      if (prevTrigger) {
        prevTrigger.addEventListener(
          "click",
          () => {
            if (monthIndex === 0) {
              this.calendarNav.navigatePrevStart();
            } else {
              this.calendarNav.navigatePrevEnd();
            }
          },
          { signal },
        );
      }

      if (nextTrigger) {
        nextTrigger.addEventListener(
          "click",
          () => {
            if (monthIndex === 0) {
              this.calendarNav.navigateNextStart();
            } else {
              this.calendarNav.navigateNextEnd();
            }
          },
          { signal },
        );
      }
    });

    // Event delegation for preset buttons
    this.el.addEventListener(
      "click",
      (e) => {
        const presetItem = e.target.closest("[data-part='preset-item']");
        if (presetItem) {
          const presetId = presetItem.dataset.presetId;
          this.handlePresetClickById(presetId);
        }
      },
      { signal },
    );
  }

  initMachine(context) {
    const forceOpen = getBooleanOption(this.el, "open");
    const isMobile = window.innerWidth < MOBILE_BREAKPOINT;

    const minDate = context.min ? datePicker.parse(context.min) : null;
    const maxDate = context.max ? datePicker.parse(context.max) : null;

    const defaultValue = this.getDefaultValueFromPreset(
      context.presets,
      context.selectedPreset,
      context.periodStart,
      context.periodEnd,
    );

    const isDateUnavailable = (date) => {
      if (minDate) {
        if (date.year < minDate.year) return true;
        if (date.year === minDate.year && date.month < minDate.month)
          return true;
        if (
          date.year === minDate.year &&
          date.month === minDate.month &&
          date.day < minDate.day
        )
          return true;
      }
      if (maxDate) {
        if (date.year > maxDate.year) return true;
        if (date.year === maxDate.year && date.month > maxDate.month)
          return true;
        if (
          date.year === maxDate.year &&
          date.month === maxDate.month &&
          date.day > maxDate.day
        )
          return true;
      }
      return false;
    };

    const machineContext = {
      ...context,
      selectionMode: "range",
      numOfMonths: isMobile ? 1 : 2,
      fixedWeeks: true,
      closeOnSelect: false,
      open: forceOpen || undefined,
      defaultValue: defaultValue || undefined,
      min: minDate || undefined,
      max: maxDate || undefined,
      isDateUnavailable,
      positioning: {
        zIndex: 50,
        offset: { mainAxis: 0 },
      },
      onValueChange: () => {
        if (!this.isSettingPreset && this.selectedPreset !== "custom") {
          this.selectedPreset = "custom";
          this.updatePresetSelection("custom");
        }
      },
    };

    return new VanillaMachine(datePicker.machine, machineContext);
  }

  getDefaultValueFromPreset(presets, selectedPreset, periodStart, periodEnd) {
    if (periodStart && periodEnd) {
      const startParsed = parseISODate(periodStart);
      const endParsed = parseISODate(periodEnd);
      if (startParsed && endParsed) {
        const startDate = datePicker.parse(
          `${startParsed.year}-${String(startParsed.month).padStart(2, "0")}-${String(startParsed.day).padStart(2, "0")}`,
        );
        const endDate = datePicker.parse(
          `${endParsed.year}-${String(endParsed.month).padStart(2, "0")}-${String(endParsed.day).padStart(2, "0")}`,
        );
        return [startDate, endDate];
      }
    }

    const preset = presets.find((p) => p.id === selectedPreset);
    if (!preset || !preset.period) return null;

    const range = calculateRangeFromDuration(preset.period);
    return [
      datePicker.parse(toISODateString(range.start)),
      datePicker.parse(toISODateString(range.end)),
    ];
  }

  initApi() {
    return datePicker.connect(this.machine.service, normalizeProps);
  }

  open() {
    this.api.setOpen(true);
  }

  close() {
    this.api.setOpen(false);
  }

  setupResizeListener() {
    const handler = () => {
      const newIsMobile = window.innerWidth < MOBILE_BREAKPOINT;
      if (newIsMobile !== this.isMobileView) {
        this.isMobileView = newIsMobile;
        this.render();
      }
    };
    window.addEventListener("resize", handler, {
      signal: this.abortController.signal,
    });
  }

  handlePresetClickById(presetId) {
    const preset = this.presets.find((p) => p.id === presetId);
    if (!preset) return;

    this.selectedPreset = presetId;
    this.updatePresetSelection(presetId);

    if (preset.period) {
      const range = calculateRangeFromDuration(preset.period);
      const startDate = datePicker.parse(toISODateString(range.start));
      const endDate = datePicker.parse(toISODateString(range.end));

      if (startDate && endDate && this.api.setValue) {
        this.isSettingPreset = true;
        this.api.setValue([startDate, endDate]);
        this.calendarNav.updateForSelection(startDate, endDate);

        this.api = this.initApi();
        this.render();

        // Defer flag reset to ensure onValueChange callbacks have fired
        queueMicrotask(() => {
          this.isSettingPreset = false;
        });
      }
    }
  }

  handleCancel() {
    this.pendingRange = null;
    this.close();
    if (this.el.dataset.onCancel) {
      this.pushEvent(this.el.dataset.onCancel, {});
    }
  }

  handleApply() {
    const value = this.api.value;
    if (value && value.length >= 2) {
      const startDate = value[0].toDate();
      const endDate = value[1].toDate();

      startDate.setHours(0, 0, 0, 0);
      endDate.setHours(23, 59, 59, 999);

      this.emitValueChange(startDate, endDate, this.selectedPreset);
      this.close();
    }
  }

  emitValueChange(start, end, preset) {
    if (this.el.dataset.onPeriodChange) {
      this.pushEvent(this.el.dataset.onPeriodChange, {
        value: {
          start: start.toISOString(),
          end: end.toISOString(),
        },
        preset: preset,
      });
    }
  }

  updatePresetSelection(selectedId) {
    if (!selectedId) return;

    const presetButtons = this.el.querySelectorAll("[data-part='preset-item']");
    presetButtons.forEach((btn) => {
      const isSelected = btn.dataset.presetId === selectedId;
      if (isSelected) {
        btn.setAttribute("data-selected", "true");
      } else {
        btn.removeAttribute("data-selected");
      }
    });
  }

  handleDateInputChange(parsed, type) {
    const dateStr = toISODateString(parsed);
    const newDateValue = datePicker.parse(dateStr);
    if (!newDateValue) return;

    const currentValue = this.api.value || [];
    let newValue;

    if (type === "start") {
      const endDate = currentValue[1] || newDateValue;
      if (compareDates(newDateValue, endDate) > 0) {
        newValue = [newDateValue, newDateValue];
      } else {
        newValue = [newDateValue, endDate];
      }
    } else {
      const startDate = currentValue[0] || newDateValue;
      if (compareDates(newDateValue, startDate) < 0) {
        newValue = [newDateValue, newDateValue];
      } else {
        newValue = [startDate, newDateValue];
      }
    }

    if (this.selectedPreset !== "custom") {
      this.selectedPreset = "custom";
      this.updatePresetSelection("custom");
    }

    this.isSettingPreset = true;
    this.api.setValue(newValue);
    this.calendarNav.updateForSelection(newValue[0], newValue[1]);

    this.api = this.initApi();
    this.render();

    // Defer flag reset to ensure onValueChange callbacks have fired
    queueMicrotask(() => {
      this.isSettingPreset = false;
    });
  }

  render() {
    // Track partial selection state for CSS styling
    const value = this.api.value;
    const isSelectingRange = value && value.length === 1;
    if (isSelectingRange) {
      this.el.setAttribute("data-selecting-range", "");
    } else {
      this.el.removeAttribute("data-selecting-range");
    }

    this.renderTriggerAndPositioner();
    this.renderMonths();
    this.renderRangeDisplay();
    this.hideSecondMonthOnMobile();
  }

  renderTriggerAndPositioner() {
    renderPart(this.el, "control", this.api);
    renderPart(this.el, "control:trigger", this.api);
    renderPart(this.el, "positioner", this.api);
    renderPart(this.el, "positioner:content", this.api);

    // Override Zag's z-index (positioning config doesn't always apply)
    const positioner = this.el.querySelector("[data-part='positioner']");
    if (positioner) {
      positioner.style.zIndex = "1000";
    }
  }

  renderMonths() {
    const months = this.el.querySelectorAll(
      "[data-part='months'] > [data-part='month']",
    );

    const minDate = parseISODate(this.el.dataset.min);
    const maxDate = parseISODate(this.el.dataset.max);

    months.forEach((monthEl, monthIndex) => {
      if (this.isMobileView && monthIndex > 0) return;

      const calendarMonth =
        monthIndex === 0
          ? this.calendarNav.startCalendarMonth
          : this.calendarNav.endCalendarMonth;
      if (!calendarMonth) return;

      this.renderMonthHeader(monthEl, calendarMonth);
      this.renderNavigationButtons(monthEl, monthIndex, minDate, maxDate);
      this.renderWeekdayHeaders(monthEl);
      this.renderDayCells(monthEl, calendarMonth, minDate, maxDate);
    });
  }

  renderMonthHeader(monthEl, calendarMonth) {
    const viewTrigger = monthEl.querySelector("[data-part='view-trigger']");
    if (viewTrigger) {
      const date = new Date(calendarMonth.year, calendarMonth.month - 1, 1);
      const monthName = date.toLocaleDateString(undefined, {
        month: "long",
        year: "numeric",
      });
      viewTrigger.textContent = monthName;
    }
  }

  renderNavigationButtons(monthEl, monthIndex, minDate, maxDate) {
    const prevTrigger = monthEl.querySelector("[data-part='prev-trigger']");
    const nextTrigger = monthEl.querySelector("[data-part='next-trigger']");

    const canGoPrev =
      monthIndex === 0
        ? this.calendarNav.canNavigatePrevStart(minDate)
        : this.calendarNav.canNavigatePrevEnd();

    const canGoNext =
      monthIndex === 0
        ? this.calendarNav.canNavigateNextStart()
        : this.calendarNav.canNavigateNextEnd(maxDate);

    if (prevTrigger) {
      prevTrigger.disabled = !canGoPrev;
      if (canGoPrev) {
        prevTrigger.removeAttribute("data-disabled");
      } else {
        prevTrigger.setAttribute("data-disabled", "");
      }
    }

    if (nextTrigger) {
      nextTrigger.disabled = !canGoNext;
      if (canGoNext) {
        nextTrigger.removeAttribute("data-disabled");
      } else {
        nextTrigger.setAttribute("data-disabled", "");
      }
    }
  }

  renderWeekdayHeaders(monthEl) {
    const headerCells = monthEl.querySelectorAll("[data-part='table-header']");
    const startOfWeek = parseInt(this.el.dataset.startOfWeek || "0", 10);
    headerCells.forEach((cell, i) => {
      const dayIndex = (startOfWeek + i) % 7;
      cell.textContent = WEEKDAYS[dayIndex];
    });
  }

  renderDayCells(monthEl, calendarMonth, minDate, maxDate) {
    const startOfWeek = parseInt(this.el.dataset.startOfWeek || "0", 10);
    const monthWeeks = calculateWeeksForMonth(
      calendarMonth.year,
      calendarMonth.month,
      startOfWeek,
    );
    const monthVisibleRange = getVisibleRangeForMonth(
      calendarMonth.year,
      calendarMonth.month,
    );

    const selectedValue = this.api.value;
    const rangeStart = selectedValue && selectedValue[0];
    const rangeEnd = selectedValue && selectedValue[1];

    const today = new Date();
    const todayValue = {
      year: today.getFullYear(),
      month: today.getMonth() + 1,
      day: today.getDate(),
    };

    const rows = monthEl.querySelectorAll(
      "[data-part='table-body'] [data-part='table-row']",
    );

    rows.forEach((row, weekIndex) => {
      const cells = row.querySelectorAll("td");
      const week = monthWeeks[weekIndex];

      cells.forEach((cell, dayIndex) => {
        const trigger = cell.querySelector("[data-part='table-cell-trigger']");
        if (!trigger) return;

        if (week && week[dayIndex]) {
          const day = week[dayIndex];
          this.renderDayCell(
            cell,
            trigger,
            day,
            monthVisibleRange,
            rangeStart,
            rangeEnd,
            todayValue,
            minDate,
            maxDate,
          );
        } else {
          trigger.textContent = "";
          trigger.setAttribute("data-hidden", "");
          cell.setAttribute("data-hidden", "");
        }
      });
    });
  }

  renderDayCell(
    cell,
    trigger,
    day,
    monthVisibleRange,
    rangeStart,
    rangeEnd,
    todayValue,
    minDate,
    maxDate,
  ) {
    trigger.textContent = day.day;

    // Clear stale state
    trigger.removeAttribute("data-disabled");
    trigger.removeAttribute("data-unavailable");
    trigger.removeAttribute("aria-disabled");
    trigger.removeAttribute("data-outside-range");
    trigger.removeAttribute("data-today");
    trigger.disabled = false;
    cell.removeAttribute("data-disabled");
    cell.removeAttribute("aria-disabled");

    // Get base props from Zag API
    const { id: _triggerId, ...dayProps } =
      this.api.getDayTableCellTriggerProps({
        value: day,
        visibleRange: monthVisibleRange,
      });
    const { id: _cellId, ...cellProps } = this.api.getDayTableCellProps({
      value: day,
      visibleRange: monthVisibleRange,
    });

    spreadProps(trigger, dayProps);
    spreadProps(cell, cellProps);

    // Handle range selection display
    if (rangeStart && rangeEnd) {
      const isRangeStart = compareDates(day, rangeStart) === 0;
      const isRangeEnd = compareDates(day, rangeEnd) === 0;
      const isInRange =
        compareDates(day, rangeStart) >= 0 && compareDates(day, rangeEnd) <= 0;

      if (isRangeStart) {
        trigger.setAttribute("data-selected", "");
        trigger.setAttribute("data-range-start", "");
        cell.setAttribute("data-range-start", "");
      }
      if (isRangeEnd) {
        trigger.setAttribute("data-selected", "");
        trigger.setAttribute("data-range-end", "");
        cell.setAttribute("data-range-end", "");
      }
      if (isInRange) {
        trigger.setAttribute("data-in-range", "");
        cell.setAttribute("data-in-range", "");
      }
    } else if (rangeStart && !rangeEnd) {
      const isRangeStart = compareDates(day, rangeStart) === 0;
      if (isRangeStart) {
        trigger.setAttribute("data-selected", "");
        trigger.setAttribute("data-range-start", "");
        cell.setAttribute("data-range-start", "");
      }
    }

    // Mark today
    if (compareDates(day, todayValue) === 0) {
      trigger.setAttribute("data-today", "");
    }

    // Disable dates outside min/max range
    const isBeforeMin = minDate && compareDates(day, minDate) < 0;
    const isAfterMax = maxDate && compareDates(day, maxDate) > 0;

    if (isBeforeMin || isAfterMax) {
      trigger.setAttribute("data-disabled", "true");
      trigger.setAttribute("data-unavailable", "true");
      trigger.setAttribute("aria-disabled", "true");
      trigger.disabled = true;
      cell.setAttribute("data-disabled", "true");
      cell.setAttribute("aria-disabled", "true");
    }

    trigger.removeAttribute("data-hidden");
    cell.removeAttribute("data-hidden");
  }

  renderRangeDisplay() {
    const value = this.api.value;

    const startDisplay = this.el.querySelector(
      "[data-part='date-display'][data-type='start']",
    );
    if (startDisplay) {
      const parts =
        value && value[0]
          ? formatDateParts(value[0].toDate())
          : formatDateParts(null);

      if (this.dateInputHandler) {
        this.dateInputHandler.updateInputs(startDisplay, parts);
      }
    }

    const endDisplay = this.el.querySelector(
      "[data-part='date-display'][data-type='end']",
    );
    if (endDisplay) {
      const parts =
        value && value[1]
          ? formatDateParts(value[1].toDate())
          : formatDateParts(null);

      if (this.dateInputHandler) {
        this.dateInputHandler.updateInputs(endDisplay, parts);
      }
    }
  }

  hideSecondMonthOnMobile() {
    if (this.isMobileView) {
      this.el.setAttribute("data-mobile", "");
    } else {
      this.el.removeAttribute("data-mobile");
    }
  }

  destroy() {
    super.destroy();
    this.abortController.abort();
    this.dateInputHandler?.destroy();
  }
}

export default {
  mounted() {
    this.datePicker = new DatePicker(this.el, this.context());
    this.datePicker.pushEvent = (event, payload) =>
      this.pushEvent(event, payload);
    this.datePicker.init();

    // Initialize date input handler
    this.datePicker.dateInputHandler = new DateInputHandler(this.el, {
      onDateChange: (parsed, type) =>
        this.datePicker.handleDateInputChange(parsed, type),
      getCurrentValue: () => this.datePicker.api.value,
      minDate: this.datePicker.minDate,
      maxDate: this.datePicker.maxDate,
    });

    // Cancel event handler
    this.handleCancelEvent = (event) => {
      if (event.detail.id === this.el.id) {
        this.datePicker.handleCancel();
      }
    };
    window.addEventListener("phx:date-picker-cancel", this.handleCancelEvent);

    // Apply event handler
    this.handleApplyEvent = (event) => {
      if (event.detail.id === this.el.id) {
        this.datePicker.handleApply();
      }
    };
    window.addEventListener("phx:date-picker-apply", this.handleApplyEvent);

    // Outside click handler
    this.handleOutsideClick = (event) => {
      if (!this.datePicker.api.open) return;

      const trigger = this.el.querySelector("[data-part='trigger']");
      const content = this.el.querySelector("[data-part='content']");

      const clickedOutside =
        trigger &&
        !trigger.contains(event.target) &&
        (!content || !content.contains(event.target));

      if (clickedOutside) {
        this.datePicker.api.setOpen(false);
      }
    };
    document.addEventListener("mousedown", this.handleOutsideClick);

    // Resize handler for responsive layout
    this.datePicker.setupResizeListener();
  },

  updated() {
    this.datePicker.render();
  },

  beforeDestroy() {
    this.datePicker.destroy();
  },

  destroyed() {
    window.removeEventListener(
      "phx:date-picker-cancel",
      this.handleCancelEvent,
    );
    window.removeEventListener("phx:date-picker-apply", this.handleApplyEvent);
    document.removeEventListener("mousedown", this.handleOutsideClick);
  },

  context() {
    const presetsJson = this.el.dataset.presets;
    const presets = presetsJson ? JSON.parse(presetsJson) : [];

    return {
      id: this.el.id,
      startOfWeek: parseInt(getOption(this.el, "startOfWeek") || "0", 10),
      disabled: getBooleanOption(this.el, "disabled"),
      presets,
      selectedPreset: getOption(this.el, "selectedPreset"),
      periodStart: getOption(this.el, "periodStart"),
      periodEnd: getOption(this.el, "periodEnd"),
      min: getOption(this.el, "min"),
      max: getOption(this.el, "max"),
    };
  },
};
