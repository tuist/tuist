// @vitest-environment happy-dom

import { afterEach, describe, expect, it } from "vitest";
import { DateInputHandler } from "./DateInputHandler.js";

let handler;

afterEach(() => {
  handler.destroy();
  document.body.replaceChildren();
});

function mount({ start, end }) {
  const display = (type, [day, month, year]) => `
    <div data-part="date-display" data-type="${type}">
      <input data-part="date-input" data-field="day" maxlength="2" value="${day}" />
      <input data-part="date-input" data-field="month" maxlength="2" value="${month}" />
      <input data-part="date-input" data-field="year" maxlength="4" value="${year}" />
    </div>`;
  const root = document.createElement("div");
  root.innerHTML = display("start", start) + display("end", end);
  document.body.append(root);
  handler = new DateInputHandler(root, {});

  const field = (type, name) =>
    root.querySelector(`[data-type='${type}'] [data-field='${name}']`);
  return { field };
}

// Presses Backspace with the caret where it is. Returns whether the handler
// took the key, in which case the browser deletes nothing itself.
function backspace(input) {
  const event = new KeyboardEvent("keydown", {
    key: "Backspace",
    bubbles: true,
    cancelable: true,
  });
  input.dispatchEvent(event);
  return event.defaultPrevented;
}

function focusAt(input, position) {
  input.focus();
  input.setSelectionRange(position, position);
}

describe("backspace across date fields", () => {
  it("deletes on into the previous field from the start of a field", () => {
    const { field } = mount({
      start: ["20", "11", ""],
      end: ["27", "11", "2026"],
    });
    focusAt(field("start", "year"), 0);

    expect(backspace(field("start", "year"))).toBe(true);
    expect(field("start", "month").value).toBe("1");
    expect(document.activeElement).toBe(field("start", "month"));
    expect(field("start", "month").selectionStart).toBe(1);
    // The day is untouched until the month is empty and passed too.
    expect(field("start", "day").value).toBe("20");
  });

  it("skips a field that is already empty, so every press deletes a digit", () => {
    const { field } = mount({
      start: ["20", "", ""],
      end: ["27", "11", "2026"],
    });
    focusAt(field("start", "year"), 0);

    expect(backspace(field("start", "year"))).toBe(true);
    expect(field("start", "day").value).toBe("2");
    expect(document.activeElement).toBe(field("start", "day"));
  });

  it("leaves the key to the browser inside a field and at the first field", () => {
    const { field } = mount({
      start: ["20", "11", "2026"],
      end: ["", "11", "2026"],
    });

    focusAt(field("start", "year"), 4);
    expect(backspace(field("start", "year"))).toBe(false);
    expect(field("start", "month").value).toBe("11");

    // The end date's first field does not delete from the start date.
    focusAt(field("end", "day"), 0);
    expect(backspace(field("end", "day"))).toBe(false);
    expect(field("start", "year").value).toBe("2026");
    expect(document.activeElement).toBe(field("end", "day"));
  });
});
