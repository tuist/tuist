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
} from "./dateUtils.js";
import { CalendarNavigation } from "./CalendarNavigation.js";
import { DateInputHandler } from "./DateInputHandler.js";
import {
  formatRange,
  relativePresetLabel,
  relativePresetPeriod,
  suggestTypedRanges,
} from "./rangeParser.js";
import { WEEKDAYS } from "./constants.js";

// The longest of an element's transitions, in milliseconds: 0 when it has
// none, as with reduced motion.
function transitionDuration(element) {
  const durations = getComputedStyle(element)
    .transitionDuration.split(",")
    .map((value) =>
      value.trim().endsWith("ms")
        ? parseFloat(value)
        : parseFloat(value) * 1000,
    );
  return Math.max(0, ...durations.filter(Number.isFinite));
}

export class DatePicker extends Component {
  constructor(el, props) {
    super(el, props);
    this.presets = props.presets || [];
    // Typed-range suggestions, shown in place of the presets while typing.
    this.suggestions = [];
    this.highlightedSuggestion = -1;
    this.selectedPreset = props.selectedPreset;
    this.pagePreset = props.selectedPreset;
    this.pendingRange = null;
    // Panel changes held back until it has faded out (see whenClosed).
    this.closedTasks = [];
    this.isSettingPreset = false;
    this.minDate = props.min ? datePicker.parse(props.min) : null;
    this.maxDate = props.max ? datePicker.parse(props.max) : null;

    // Calendar navigation manager - initialized with current value
    const value = this.api.value;
    this.calendarNav = new CalendarNavigation(value && value[0], () =>
      this.handleNavigate(),
    );

    // AbortController for component-level event listeners
    this.abortController = new AbortController();

    this.setupNavigationHandlers();

    // The tabs have no width while the panel is closed, so their fade is
    // measured whenever their size changes, as well as on scroll. Each time
    // the panel opens, the selected tab scrolls to the middle.
    const tabs = this.el.querySelector(
      "[data-part='presets'][data-device='mobile']",
    );
    if (tabs) {
      let shown = false;
      this.tabsObserver = new ResizeObserver(() => {
        const wasShown = shown;
        shown = tabs.clientWidth > 0;
        if (shown && !wasShown) this.centerSelectedTab("instant");
        this.renderTabsFade();
      });
      this.tabsObserver.observe(tabs);
    }
  }

  setupNavigationHandlers() {
    const signal = this.abortController.signal;

    // Delegate from the hook root so navigation survives LiveView DOM patches.
    this.el.addEventListener(
      "click",
      (e) => {
        const navigationTrigger = e.target.closest(
          "[data-part='prev-trigger'], [data-part='next-trigger']",
        );
        if (navigationTrigger) {
          if (navigationTrigger.disabled) return;

          if (navigationTrigger.dataset.part === "prev-trigger") {
            this.calendarNav.navigatePrev();
          } else {
            this.calendarNav.navigateNext();
          }
          return;
        }

        const suggestion = e.target.closest("[data-part='suggestion']");
        if (suggestion) {
          const { range, preset } = this.suggestions[suggestion.dataset.index];
          this.applyAndClose(range, preset);
          return;
        }

        const presetItem = e.target.closest("[data-part='preset-item']");
        if (presetItem) {
          const presetId = presetItem.dataset.presetId;
          this.handlePresetClickById(presetId);
        }
      },
      { signal },
    );

    this.el.addEventListener(
      "input",
      (e) => {
        if (e.target.closest("[data-part='range-input']")) {
          this.handleRangeInput(e.target.value);
        }
      },
      { signal },
    );

    this.el.addEventListener(
      "keydown",
      (e) => {
        if (!e.target.closest("[data-part='range-input']")) return;
        if (e.key === "Enter") {
          e.preventDefault();
          this.handleRangeSubmit(e.target.value);
        } else if (
          (e.key === "ArrowDown" || e.key === "ArrowUp") &&
          this.suggestions.length > 0
        ) {
          e.preventDefault();
          const step = e.key === "ArrowDown" ? 1 : -1;
          const count = this.suggestions.length;
          this.highlightSuggestion(
            (this.highlightedSuggestion + step + count) % count,
          );
        }
      },
      { signal },
    );

    this.el.addEventListener(
      "scroll",
      (e) => {
        if (e.target.matches?.("[data-part='presets'][data-device='mobile']")) {
          this.renderTabsFade();
        }
      },
      { capture: true, passive: true, signal },
    );

    // Zag moves the focused day on arrow keys, PageUp/PageDown, Home, and End.
    // When focus leaves the shown month, the calendar follows it there.
    this.el.addEventListener(
      "keydown",
      (e) => {
        if (e.target.closest("[data-part='table']")) {
          this.followFocus = true;
        }
      },
      { capture: true, signal },
    );
  }

  initMachine(context) {
    const forceOpen = getBooleanOption(this.el, "open");

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
      numOfMonths: 1,
      fixedWeeks: true,
      outsideDaySelectable: true,
      closeOnSelect: false,
      open: forceOpen || undefined,
      defaultValue: defaultValue || undefined,
      min: minDate || undefined,
      max: maxDate || undefined,
      isDateUnavailable,
      // Same placement as menus: under the trigger, start-aligned, 8px away.
      positioning: {
        zIndex: 50,
        placement: "bottom-start",
        offset: { mainAxis: 8 },
      },
      onValueChange: () => {
        if (this.isSettingPreset) return;
        // Days picked on the calendar replace what was typed.
        this.clearRangeInput();
        if (this.selectedPreset !== "custom") {
          this.selectedPreset = "custom";
          this.updatePresetSelection("custom");
        }
      },
      // The panel opens ready for typing, and forgets what was typed when it
      // closes without applying.
      onOpenChange: ({ open }) => {
        if (open) {
          // Reopened before the exit finished: catch up first.
          this.runClosedTasks();
          // Without preventScroll, the browser scrolls the field into view
          // while the panel is still being placed, shifting containers that
          // hide their overflow, such as the dashboard's content.
          requestAnimationFrame(() =>
            this.rangeInput?.focus({ preventScroll: true }),
          );
        } else {
          this.whenClosed(() => this.clearRangeInput());
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

    // A typed rolling range comes back as an id that no preset has, such as
    // "last-10-days".
    const preset =
      presets.find((p) => p.id === selectedPreset) ||
      (relativePresetPeriod(selectedPreset) && {
        period: relativePresetPeriod(selectedPreset),
      });
    return this.getPresetValue(preset);
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

  // The arrows changed the shown month. Zag's focused day moves along, so
  // Tab still reaches the calendar and arrow keys start from that month.
  handleNavigate() {
    const focused = this.api.focusedValue;
    const { year, month } = this.calendarNav.calendarMonth;
    if (focused && (focused.year !== year || focused.month !== month)) {
      const day = Math.min(focused.day, new Date(year, month, 0).getDate());
      this.api.setFocusedValue(
        datePicker.parse(
          `${year}-${String(month).padStart(2, "0")}-${String(day).padStart(2, "0")}`,
        ),
      );
    }
    this.render();
  }

  handlePresetClickById(presetId) {
    const preset = this.presets.find((p) => p.id === presetId);
    if (!preset) return;

    // A preset with a range applies at once. "Custom" has none: it waits for
    // days picked on the calendar and the Apply button.
    const value = this.getPresetValue(preset);
    if (value) {
      this.applyAndClose(value, presetId);
      return;
    }

    this.selectedPreset = presetId;
    this.updatePresetSelection(presetId);
    this.clearRangeInput();
  }

  // Applies a range picked in one click, a preset or a suggestion. The
  // calendar shows the range the next time the panel opens.
  applyAndClose(range, preset) {
    this.commit(range, preset);
    this.whenClosed(() => {
      this.selectedPreset = preset;
      this.updatePresetSelection(preset);
      this.clearRangeInput();
      this.setRangeValue(range);
    });
  }

  // Applies a range. The panel closes exactly as a click outside closes it,
  // and only once it has faded out is the range sent and named on the
  // trigger. Either would disturb the exit: the label's new width moves the
  // picker, and with it the panel, and the page's re-render replaces the
  // panel's elements, which ends the fade.
  commit([start, end], preset) {
    this.close();
    this.whenClosed(() => {
      const startDate = start.toDate();
      const endDate = end.toDate();
      startDate.setHours(0, 0, 0, 0);
      endDate.setHours(23, 59, 59, 999);
      this.emitValueChange(startDate, endDate, preset);
      this.renderTriggerLabel(start.toDate(), end.toDate(), preset);
    });
  }

  // Runs a task once the panel has faded out, so nothing changes during the
  // exit. It runs right away when the panel is reopened first, or has no
  // exit transition (reduced motion).
  whenClosed(task) {
    this.closedTasks.push(task);
    if (this.closedWait) return;

    const content = this.el.querySelector("[data-part='content']");
    const duration = content ? transitionDuration(content) : 0;
    if (duration === 0) {
      this.runClosedTasks();
      return;
    }

    this.closedWait = new AbortController();
    // Buttons inside the panel end transitions of their own, which bubble.
    content.addEventListener(
      "transitionend",
      (event) => {
        if (event.target === content) this.runClosedTasks();
      },
      { signal: this.closedWait.signal },
    );
    // In case the transition never ends, such as in a hidden tab.
    this.closedTimer = setTimeout(() => this.runClosedTasks(), duration + 100);
  }

  runClosedTasks() {
    clearTimeout(this.closedTimer);
    this.closedWait?.abort();
    this.closedWait = null;
    const tasks = this.closedTasks;
    this.closedTasks = [];
    tasks.forEach((task) => task());
  }

  // Shows a range on the calendar without counting it as days picked there.
  setRangeValue(value) {
    this.isSettingPreset = true;
    this.api.setValue(value);
    this.calendarNav.showMonthOf(value[0]);

    this.api = this.initApi();
    this.render();

    // Defer flag reset to ensure onValueChange callbacks have fired
    queueMicrotask(() => {
      this.isSettingPreset = false;
    });
  }

  get rangeInput() {
    return this.el.querySelector("[data-part='range-input']");
  }

  // While typing, the presets give way to the ranges the text could mean.
  // The highlighted one shows on the calendar, so the reading can be checked
  // before applying; arrow keys and clicks move the highlight.
  handleRangeInput(text) {
    this.setRangeError(false);
    this.suggestions = this.typedSuggestions(text);
    this.renderSuggestions(text);
    if (this.suggestions.length > 0) this.highlightSuggestion(0);
  }

  highlightSuggestion(index) {
    const suggestion = this.suggestions[index];
    if (!suggestion) return;
    this.highlightedSuggestion = index;
    this.el
      .querySelectorAll("[data-part='suggestion']")
      .forEach((option, i) => {
        option.toggleAttribute("data-highlighted", i === index);
        option.setAttribute("aria-selected", String(i === index));
      });
    this.rangeInput?.setAttribute(
      "aria-activedescendant",
      this.suggestionId(index),
    );

    this.selectedPreset = suggestion.preset;
    this.updatePresetSelection(suggestion.preset);
    this.setRangeValue(suggestion.range);
  }

  handleRangeSubmit(text) {
    if (text.trim() && this.suggestions.length === 0) {
      this.setRangeError(true);
      return;
    }
    this.handleApply();
  }

  // The suggestions as calendar values. Past max they end at max; one that
  // would start before min is left out rather than shortened.
  typedSuggestions(text) {
    return suggestTypedRanges(text).flatMap((typed) => {
      const start = datePicker.parse(toISODateString(typed.start));
      let end = datePicker.parse(toISODateString(typed.end));
      if (this.minDate && compareDates(start, this.minDate) < 0) return [];
      if (this.maxDate && compareDates(end, this.maxDate) > 0)
        end = this.maxDate;
      if (compareDates(start, end) > 0) return [];
      return [
        { range: [start, end], preset: typed.preset, label: typed.label },
      ];
    });
  }

  suggestionId(index) {
    return `${this.el.id}-suggestion-${index}`;
  }

  renderSuggestions(text) {
    const list = this.el.querySelector("[data-part='suggestions']");
    if (!list) return;
    this.highlightedSuggestion = -1;
    this.rangeInput?.removeAttribute("aria-activedescendant");
    this.rangeInput?.setAttribute("aria-expanded", String(text.trim() !== ""));

    list.replaceChildren(
      ...this.suggestions.map(({ label }, index) => {
        const option = document.createElement("button");
        option.type = "button";
        option.id = this.suggestionId(index);
        option.tabIndex = -1;
        option.dataset.part = "suggestion";
        option.dataset.index = String(index);
        option.setAttribute("role", "option");
        option.setAttribute("aria-selected", "false");
        option.textContent = label;
        return option;
      }),
    );
    if (text.trim() && this.suggestions.length === 0) {
      const empty = document.createElement("p");
      empty.dataset.part = "suggestions-empty";
      empty.textContent = "No matching range";
      list.append(empty);
    }
  }

  setRangeError(error) {
    const wrapper = this.rangeInput?.closest("[data-part='wrapper']");
    if (!wrapper) return;
    if (error) {
      wrapper.setAttribute("data-error", "true");
      this.rangeInput.setAttribute("aria-invalid", "true");
    } else {
      wrapper.removeAttribute("data-error");
      this.rangeInput.removeAttribute("aria-invalid");
    }
  }

  clearRangeInput() {
    if (!this.rangeInput) return;
    this.rangeInput.value = "";
    this.setRangeError(false);
    this.suggestions = [];
    this.renderSuggestions("");
  }

  getPresetValue(preset) {
    if (!preset) return null;

    if (preset.period) {
      const range = calculateRangeFromDuration(preset.period);
      return [
        datePicker.parse(toISODateString(range.start)),
        datePicker.parse(toISODateString(range.end)),
      ];
    }

    const start = parseISODate(preset.start);
    const end = parseISODate(preset.end);
    if (!start || !end) return null;

    return [
      datePicker.parse(
        `${start.year}-${String(start.month).padStart(2, "0")}-${String(start.day).padStart(2, "0")}`,
      ),
      datePicker.parse(
        `${end.year}-${String(end.month).padStart(2, "0")}-${String(end.day).padStart(2, "0")}`,
      ),
    ];
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
    if (value && value.length >= 2) this.commit(value, this.selectedPreset);
  }

  // The trigger names the applied range straight away, as the component
  // labels it on the server: the preset's label, a typed rolling range's
  // ("Last 10 days"), or the dates in words. A page that stores the range
  // re-renders the same label.
  renderTriggerLabel(start, end, presetId) {
    const label = this.el.querySelector("[data-part='trigger'] > span");
    if (!label) return;
    const preset =
      presetId !== "custom" && this.presets.find((p) => p.id === presetId);
    label.textContent =
      preset?.label || relativePresetLabel(presetId) || formatRange(start, end);
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

  updatePresetSelection(selectedId, { center = true } = {}) {
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
    if (center) this.centerSelectedTab("smooth");
  }

  // The page re-renders the presets when it stores an applied range, which
  // can land while the panel fades out. The selection the picker shows wins
  // until then; a new range from the page (such as the back button) is
  // adopted once nothing is waiting for the panel to close.
  syncSelectionFromPage() {
    const pagePreset = this.el.dataset.selectedPreset;
    if (pagePreset !== this.pagePreset && this.closedTasks.length === 0) {
      this.pagePreset = pagePreset;
      if (pagePreset) this.selectedPreset = pagePreset;
    }
    this.updatePresetSelection(this.selectedPreset, { center: false });
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
    this.clearRangeInput();
    this.setRangeValue(newValue);
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

    const focused = this.api.focusedValue;
    if (this.followFocus && focused) {
      this.followFocus = false;
      this.calendarNav.showMonthOf(focused);
    }

    this.renderTriggerAndPositioner();
    this.renderMonth();
    this.renderRangeDisplay();
    this.renderTabsFade();
  }

  // Scrolls the mobile tabs so the selected one sits in the middle.
  centerSelectedTab(behavior) {
    const tabs = this.el.querySelector(
      "[data-part='presets'][data-device='mobile']",
    );
    const tab = tabs?.querySelector("[data-part='preset-item'][data-selected]");
    if (!tab || tabs.clientWidth === 0) return;
    const tabBox = tab.getBoundingClientRect();
    const tabsBox = tabs.getBoundingClientRect();
    tabs.scrollBy({
      left: tabBox.left + tabBox.width / 2 - (tabsBox.left + tabsBox.width / 2),
      behavior,
    });
  }

  // The mobile preset tabs scroll sideways without a scrollbar, so each edge
  // with tabs past it fades out.
  renderTabsFade() {
    const tabs = this.el.querySelector(
      "[data-part='presets'][data-device='mobile']",
    );
    if (!tabs) return;
    // scrollLeft runs negative in right-to-left layouts.
    const scrolled = Math.abs(tabs.scrollLeft);
    const hidden = tabs.scrollWidth - tabs.clientWidth;
    tabs.toggleAttribute("data-overflow-start", scrolled > 1);
    tabs.toggleAttribute("data-overflow-end", hidden - scrolled > 1);
  }

  renderTriggerAndPositioner() {
    renderPart(this.el, "control", this.api);
    renderPart(this.el, "control:trigger", this.api);
    renderPart(this.el, "positioner", this.api);
    renderPart(this.el, "positioner:content", this.api);
    // The positioner shows and hides the panel (date_picker.css), so the
    // content keeps its exit animation. Zag's `hidden` would cut it short
    // wherever a stylesheet forces [hidden] to display: none.
    this.el.querySelector("[data-part='content']")?.removeAttribute("hidden");

    // Override Zag's z-index (positioning config doesn't always apply)
    const positioner = this.el.querySelector("[data-part='positioner']");
    if (positioner) {
      positioner.style.zIndex = "1000";
    }
  }

  renderMonth() {
    const monthEl = this.el.querySelector("[data-part='month']");
    if (!monthEl) return;

    const minDate = parseISODate(this.el.dataset.min);
    const maxDate = parseISODate(this.el.dataset.max);
    const { calendarMonth } = this.calendarNav;

    // Zag's keyboard handling lives on the table: arrow keys, PageUp/PageDown,
    // Home, and End move the focused day.
    const table = monthEl.querySelector("[data-part='table']");
    if (table) {
      const { id: _tableId, ...tableProps } = this.api.getTableProps({
        view: "day",
        columns: 7,
      });
      spreadProps(table, tableProps);
    }

    this.renderMonthHeader(monthEl, calendarMonth);
    this.renderNavigationButtons(monthEl, minDate, maxDate);
    this.renderWeekdayHeaders(monthEl);
    this.renderDayCells(monthEl, calendarMonth, minDate, maxDate);
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

  renderNavigationButtons(monthEl, minDate, maxDate) {
    const prevTrigger = monthEl.querySelector("[data-part='prev-trigger']");
    const nextTrigger = monthEl.querySelector("[data-part='next-trigger']");

    const canGoPrev = this.calendarNav.canNavigatePrev(minDate);
    const canGoNext = this.calendarNav.canNavigateNext(maxDate);

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

    // Cells before the 1st and after the month's last day hold the
    // neighbouring months' days, counted from where the 1st sits. Zag marks
    // them outside the visible month and, with outsideDaySelectable, still
    // lets them be picked; picking one keeps the shown month.
    const firstDayIndex = monthWeeks.flat().findIndex(Boolean);
    const gridDay = (index) => {
      const date = new Date(
        calendarMonth.year,
        calendarMonth.month - 1,
        1 + index - firstDayIndex,
      );
      return datePicker.parse(toISODateString(date));
    };
    const visibleRange = {
      start: gridDay(firstDayIndex),
      end: gridDay(
        firstDayIndex + monthWeeks.flat().filter(Boolean).length - 1,
      ),
    };

    rows.forEach((row, weekIndex) => {
      const cells = row.querySelectorAll("td");
      const week = monthWeeks[weekIndex];
      // A week with none of the month's days is left out, so the calendar is
      // as tall as the month needs: four, five, or six weeks.
      row.hidden = !week?.some(Boolean);

      cells.forEach((cell, dayIndex) => {
        const trigger = cell.querySelector("[data-part='table-cell-trigger']");
        if (!trigger) return;

        this.renderDayCell(
          cell,
          trigger,
          gridDay(weekIndex * 7 + dayIndex),
          visibleRange,
          rangeStart,
          rangeEnd,
          todayValue,
          minDate,
          maxDate,
        );
      });
    });
  }

  renderDayCell(
    cell,
    trigger,
    day,
    visibleRange,
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
    trigger.removeAttribute("data-today");
    trigger.disabled = false;
    cell.removeAttribute("data-disabled");
    cell.removeAttribute("aria-disabled");

    // Get base props from Zag API
    const { id: _triggerId, ...dayProps } =
      this.api.getDayTableCellTriggerProps({
        value: day,
        visibleRange: visibleRange,
      });
    const { id: _cellId, ...cellProps } = this.api.getDayTableCellProps({
      value: day,
      visibleRange: visibleRange,
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

  destroy() {
    super.destroy();
    this.abortController.abort();
    this.tabsObserver?.disconnect();
    clearTimeout(this.closedTimer);
    this.closedWait?.abort();
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
  },

  updated() {
    this.datePicker.syncSelectionFromPage();
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
