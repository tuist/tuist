// @vitest-environment happy-dom

import { afterEach, describe, expect, it, vi } from "vitest";
import DatePickerHook from "./index.js";

let hook;

afterEach(() => {
  hook.beforeDestroy();
  hook.destroyed();
  document.body.replaceChildren();
});

function mount() {
  const el = document.createElement("div");
  el.id = "date-picker";
  el.dataset.periodStart = "2026-08-01";
  el.dataset.periodEnd = "2026-09-08";
  el.dataset.min = "2026-06-01";
  el.dataset.max = "2026-09-08";
  el.innerHTML = `
    <div data-part="control"><button data-part="trigger"></button></div>
    <div data-part="positioner">
      <div data-part="content">
        <div data-part="months">
          ${[0, 1]
            .map(
              (index) => `
            <div data-part="month" data-index="${index}">
              <div data-part="view-control">
                <button type="button" data-part="prev-trigger"><svg><path /></svg></button>
                <span data-part="view-trigger"></span>
                <button type="button" data-part="next-trigger"><svg><path /></svg></button>
              </div>
            </div>
          `,
            )
            .join("")}
        </div>
      </div>
    </div>
  `;
  document.body.append(el);
  hook = { ...DatePickerHook, el, pushEvent: vi.fn() };
  hook.mounted();
  return el;
}

function months(el) {
  return [...el.querySelectorAll('[data-part="view-trigger"]')].map(
    (month) => month.textContent,
  );
}

function clickArrow(el, index, direction) {
  el.querySelectorAll(`[data-part="${direction}-trigger"]`)
    [index].querySelector("path")
    .dispatchEvent(new MouseEvent("click", { bubbles: true }));
}

describe("date picker month navigation", () => {
  it("navigates both calendars independently without changing the selected range", () => {
    const el = mount();
    expect(months(el)).toEqual(["August 2026", "September 2026"]);

    clickArrow(el, 0, "prev");
    expect(months(el)).toEqual(["July 2026", "September 2026"]);
    clickArrow(el, 1, "prev");
    expect(months(el)).toEqual(["July 2026", "August 2026"]);
    clickArrow(el, 1, "next");
    expect(months(el)).toEqual(["July 2026", "September 2026"]);
    clickArrow(el, 0, "next");
    expect(months(el)).toEqual(["August 2026", "September 2026"]);

    expect(hook.datePicker.api.value.map((date) => date.toString())).toEqual([
      "2026-08-01",
      "2026-09-08",
    ]);
    expect(hook.pushEvent).not.toHaveBeenCalled();
  });

  it("keeps navigation working after LiveView replaces the calendar controls", () => {
    const el = mount();
    for (const control of el.querySelectorAll('[data-part="view-control"]')) {
      control.replaceWith(control.cloneNode(true));
    }
    hook.updated();

    clickArrow(el, 0, "prev");
    expect(months(el)).toEqual(["July 2026", "September 2026"]);
    clickArrow(el, 1, "prev");
    expect(months(el)).toEqual(["July 2026", "August 2026"]);
    hook.updated();
    hook.updated();
    clickArrow(el, 1, "next");
    expect(months(el)).toEqual(["July 2026", "September 2026"]);
    clickArrow(el, 0, "next");
    expect(months(el)).toEqual(["August 2026", "September 2026"]);
  });

  it("ignores disabled arrows at date bounds and between adjacent months", () => {
    const el = mount();
    clickArrow(el, 0, "next");
    clickArrow(el, 1, "prev");
    clickArrow(el, 1, "next");
    expect(months(el)).toEqual(["August 2026", "September 2026"]);

    clickArrow(el, 0, "prev");
    clickArrow(el, 0, "prev");
    expect(months(el)).toEqual(["June 2026", "September 2026"]);
    clickArrow(el, 0, "prev");
    expect(months(el)).toEqual(["June 2026", "September 2026"]);
  });
});
