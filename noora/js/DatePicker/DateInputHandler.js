import { formatDateParts, parseDateFromParts } from "./dateUtils.js";

/**
 * Handles date input fields (DD/MM/YYYY) for a date picker.
 * Manages event listeners, validation, and keyboard navigation.
 */
export class DateInputHandler {
  /**
   * @param {HTMLElement} rootEl - Root element containing date displays
   * @param {object} options
   * @param {function} options.onDateChange - Callback when a valid date is entered
   * @param {function} options.getCurrentValue - Get current date value for restoration
   * @param {{year: number, month: number, day: number}|null} options.minDate
   * @param {{year: number, month: number, day: number}|null} options.maxDate
   */
  constructor(rootEl, options) {
    this.rootEl = rootEl;
    this.onDateChange = options.onDateChange;
    this.getCurrentValue = options.getCurrentValue;
    this.minDate = options.minDate;
    this.maxDate = options.maxDate;
    this.abortController = new AbortController();

    const startDisplay = this.rootEl.querySelector(
      "[data-part='date-display'][data-type='start']",
    );
    const endDisplay = this.rootEl.querySelector(
      "[data-part='date-display'][data-type='end']",
    );

    if (startDisplay) {
      this.attachToContainer(startDisplay, "start");
    }
    if (endDisplay) {
      this.attachToContainer(endDisplay, "end");
    }
  }

  /**
   * Attach handlers to inputs within a container.
   * @param {HTMLElement} container
   * @param {string} type - "start" or "end"
   */
  attachToContainer(container, type) {
    const inputs = container.querySelectorAll("[data-part='date-input']");
    const signal = this.abortController.signal;

    inputs.forEach((input) => {
      // Handle blur to parse and apply the date
      input.addEventListener(
        "blur",
        () => this.handleFieldChange(container, type),
        { signal },
      );

      // Handle keyboard navigation
      input.addEventListener(
        "keydown",
        (e) => this.handleKeydown(e, input, container, type),
        { signal },
      );

      // Auto-advance to next field when maxlength reached
      input.addEventListener(
        "input",
        () => this.handleInput(input, container, type),
        { signal },
      );
    });
  }

  /**
   * Handle keydown for navigation between fields.
   */
  handleKeydown(e, input, container, type) {
    if (e.key === "Enter") {
      e.preventDefault();
      this.handleFieldChange(container, type);
      input.blur();
      return;
    }

    const cursorPos = input.selectionStart;
    const valueLen = input.value.length;
    const inputs = Array.from(
      container.querySelectorAll("[data-part='date-input']"),
    );
    const currentIndex = inputs.indexOf(input);

    // Left arrow at start of field -> go to previous field
    if (e.key === "ArrowLeft" && cursorPos === 0) {
      e.preventDefault();
      if (currentIndex > 0) {
        const prevInput = inputs[currentIndex - 1];
        prevInput.focus();
        prevInput.setSelectionRange(
          prevInput.value.length,
          prevInput.value.length,
        );
      } else if (type === "end") {
        // Jump to start date's last field
        const startDisplay = this.rootEl.querySelector(
          "[data-part='date-display'][data-type='start']",
        );
        if (startDisplay) {
          const startInputs = startDisplay.querySelectorAll(
            "[data-part='date-input']",
          );
          const lastInput = startInputs[startInputs.length - 1];
          if (lastInput) {
            lastInput.focus();
            lastInput.setSelectionRange(
              lastInput.value.length,
              lastInput.value.length,
            );
          }
        }
      }
      return;
    }

    // Right arrow at end of field -> go to next field
    if (e.key === "ArrowRight" && cursorPos === valueLen) {
      e.preventDefault();
      if (currentIndex < inputs.length - 1) {
        const nextInput = inputs[currentIndex + 1];
        nextInput.focus();
        nextInput.setSelectionRange(0, 0);
      } else if (type === "start") {
        // Jump to end date's first field
        const endDisplay = this.rootEl.querySelector(
          "[data-part='date-display'][data-type='end']",
        );
        if (endDisplay) {
          const firstInput = endDisplay.querySelector(
            "[data-part='date-input']",
          );
          if (firstInput) {
            firstInput.focus();
            firstInput.setSelectionRange(0, 0);
          }
        }
      }
    }
  }

  /**
   * Handle input event for auto-advance.
   */
  handleInput(input, container, type) {
    if (input.value.length >= parseInt(input.maxLength, 10)) {
      const inputs = Array.from(
        container.querySelectorAll("[data-part='date-input']"),
      );
      const currentIndex = inputs.indexOf(input);

      if (currentIndex < inputs.length - 1) {
        inputs[currentIndex + 1].focus();
      } else {
        // Last field (year) complete - update the calendar immediately
        this.handleFieldChange(container, type);
      }
    }
  }

  /**
   * Handle field change - validate and apply the date.
   */
  handleFieldChange(container, type) {
    const dayInput = container.querySelector("[data-field='day']");
    const monthInput = container.querySelector("[data-field='month']");
    const yearInput = container.querySelector("[data-field='year']");

    const day = dayInput?.value || "";
    const month = monthInput?.value || "";
    const year = yearInput?.value || "";

    // Don't validate if fields are incomplete
    if (!day || !month || !year || year.length < 4) return;

    const parsed = parseDateFromParts(day, month, year);
    if (!parsed) {
      this.restoreInputs(container, type);
      return;
    }

    // Check against min/max constraints
    if (this.minDate) {
      const minJs = new Date(
        this.minDate.year,
        this.minDate.month - 1,
        this.minDate.day,
      );
      if (parsed < minJs) {
        this.restoreInputs(container, type);
        return;
      }
    }
    if (this.maxDate) {
      const maxJs = new Date(
        this.maxDate.year,
        this.maxDate.month - 1,
        this.maxDate.day,
      );
      if (parsed > maxJs) {
        this.restoreInputs(container, type);
        return;
      }
    }

    this.onDateChange?.(parsed, type);
  }

  /**
   * Restore input values from current selection.
   */
  restoreInputs(container, type) {
    const value = this.getCurrentValue?.();
    let parts;

    if (type === "start" && value && value[0]) {
      parts = formatDateParts(value[0].toDate());
    } else if (type === "end" && value && value[1]) {
      parts = formatDateParts(value[1].toDate());
    } else {
      parts = { day: "", month: "", year: "" };
    }

    const dayInput = container.querySelector("[data-field='day']");
    const monthInput = container.querySelector("[data-field='month']");
    const yearInput = container.querySelector("[data-field='year']");

    if (dayInput) dayInput.value = parts.day;
    if (monthInput) monthInput.value = parts.month;
    if (yearInput) yearInput.value = parts.year;
  }

  /**
   * Update input values from date parts (only if not focused).
   */
  updateInputs(container, parts) {
    const dayInput = container.querySelector("[data-field='day']");
    const monthInput = container.querySelector("[data-field='month']");
    const yearInput = container.querySelector("[data-field='year']");

    if (dayInput && document.activeElement !== dayInput) {
      dayInput.value = parts.day;
    }
    if (monthInput && document.activeElement !== monthInput) {
      monthInput.value = parts.month;
    }
    if (yearInput && document.activeElement !== yearInput) {
      yearInput.value = parts.year;
    }
  }

  /**
   * Clean up all event listeners.
   */
  destroy() {
    this.abortController.abort();
  }
}
