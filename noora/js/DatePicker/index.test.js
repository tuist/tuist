// @vitest-environment happy-dom

import { afterEach, describe, expect, it, vi } from "vitest";
import DatePickerHook from "./index.js";

let hook;

afterEach(() => {
  hook.beforeDestroy();
  hook.destroyed();
  document.body.replaceChildren();
});

function mount({ presets = [] } = {}) {
  const el = document.createElement("div");
  el.id = "date-picker";
  el.dataset.presets = JSON.stringify(presets);
  el.dataset.onPeriodChange = "period_changed";
  el.dataset.periodStart = "2026-08-01";
  el.dataset.periodEnd = "2026-09-08";
  el.dataset.min = "2026-06-01";
  el.dataset.max = "2026-09-08";
  el.innerHTML = `
    <div data-part="control"><button data-part="trigger"></button></div>
    <div data-part="positioner">
      <div data-part="content">
        ${presets.map(({ id }) => `<button type="button" data-part="preset-item" data-preset-id="${id}"></button>`).join("")}
        <div data-part="month">
          <div data-part="view-control">
            <button type="button" data-part="prev-trigger"><svg><path /></svg></button>
            <span data-part="view-trigger"></span>
            <button type="button" data-part="next-trigger"><svg><path /></svg></button>
          </div>
          <table data-part="table">
            <tbody data-part="table-body">
              ${`<tr data-part="table-row">${'<td data-part="day-table-cell"><button type="button" data-part="table-cell-trigger"></button></td>'.repeat(7)}</tr>`.repeat(6)}
            </tbody>
          </table>
        </div>
      </div>
    </div>
  `;
  document.body.append(el);
  hook = { ...DatePickerHook, el, pushEvent: vi.fn() };
  hook.mounted();
  return el;
}

function month(el) {
  return el.querySelector('[data-part="view-trigger"]').textContent;
}

function shownDays(el) {
  return [...el.querySelectorAll("tbody button")]
    .filter((button) => !button.hasAttribute("data-outside-range"))
    .map((button) => Number(button.textContent));
}

function daysUpTo(last) {
  return Array.from({ length: last }, (_, index) => index + 1);
}

function clickArrow(el, direction) {
  el.querySelector(`[data-part="${direction}-trigger"] path`).dispatchEvent(
    new MouseEvent("click", { bubbles: true }),
  );
}

describe("date picker month navigation", () => {
  it("navigates months without changing the selected range", () => {
    const el = mount();
    expect(month(el)).toEqual("August 2026");

    clickArrow(el, "prev");
    expect(month(el)).toEqual("July 2026");
    clickArrow(el, "next");
    clickArrow(el, "next");
    expect(month(el)).toEqual("September 2026");

    expect(hook.datePicker.api.value.map((date) => date.toString())).toEqual([
      "2026-08-01",
      "2026-09-08",
    ]);
    expect(hook.pushEvent).not.toHaveBeenCalled();
  });

  it("keeps navigation working after LiveView replaces the calendar controls", () => {
    const el = mount();
    const control = el.querySelector('[data-part="view-control"]');
    control.replaceWith(control.cloneNode(true));
    hook.updated();

    clickArrow(el, "prev");
    expect(month(el)).toEqual("July 2026");
    hook.updated();
    hook.updated();
    clickArrow(el, "next");
    expect(month(el)).toEqual("August 2026");
  });

  it("fills every day of each month, including cells blank in the month before", () => {
    const el = mount();
    // August 2026 starts on a Saturday, so its first six cells are blank.
    // July 1 to 3 fall in those cells, and June 1 to 6 in cells blank in July.
    expect(shownDays(el)).toEqual(daysUpTo(31));
    clickArrow(el, "prev");
    expect(month(el)).toEqual("July 2026");
    expect(shownDays(el)).toEqual(daysUpTo(31));
    clickArrow(el, "prev");
    expect(shownDays(el)).toEqual(daysUpTo(30));
    clickArrow(el, "next");
    clickArrow(el, "next");
    expect(shownDays(el)).toEqual(daysUpTo(31));
  });

  it("shows the neighbouring months' days as selectable and keeps the month when one is clicked", () => {
    const el = mount();
    // August 2026 runs Saturday to Monday: July 26 to 31 lead, September 1 to 5 trail.
    const outside = [
      ...el.querySelectorAll("tbody button[data-outside-range]"),
    ];
    expect(outside.map((button) => Number(button.textContent))).toEqual([
      26, 27, 28, 29, 30, 31, 1, 2, 3, 4, 5,
    ]);

    // Zag marks days it won't select as disabled.
    expect(outside.some((button) => button.hasAttribute("data-disabled"))).toBe(
      false,
    );

    outside[5].click();
    expect(month(el)).toEqual("August 2026");
  });

  it("shows only the weeks the month needs", () => {
    const el = mount();
    const weeks = () => el.querySelectorAll("tbody tr:not([hidden])").length;
    // August 2026 starts on a Saturday and needs six weeks; July 2026 needs five.
    expect(weeks()).toEqual(6);
    clickArrow(el, "prev");
    expect(weeks()).toEqual(5);
    expect(shownDays(el)).toEqual(daysUpTo(31));
  });

  it("ignores disabled arrows at the min and max months", () => {
    const el = mount();
    clickArrow(el, "next");
    clickArrow(el, "next");
    expect(month(el)).toEqual("September 2026");

    for (let i = 0; i < 4; i++) clickArrow(el, "prev");
    expect(month(el)).toEqual("June 2026");
  });
});

describe("date picker presets", () => {
  const presets = [
    {
      id: "last-7-days",
      label: "Last 7 days",
      period: { amount: 7, unit: "day" },
    },
  ];
  const clickPreset = (el) =>
    el.querySelector('[data-preset-id="last-7-days"]').click();
  const applied = () =>
    expect(hook.pushEvent).toHaveBeenCalledWith(
      "period_changed",
      expect.objectContaining({ preset: "last-7-days" }),
    );

  it("applies a clicked preset once the panel has faded out", () => {
    const el = mount({ presets });
    const content = el.querySelector('[data-part="content"]');
    const getComputedStyle = window.getComputedStyle.bind(window);
    vi.spyOn(window, "getComputedStyle").mockImplementation((element) =>
      element === content
        ? { transitionDuration: "0.2s, 0.15s" }
        : getComputedStyle(element),
    );

    clickPreset(el);
    expect(hook.pushEvent).not.toHaveBeenCalled();
    expect(month(el)).toEqual("August 2026");

    // A button inside the panel ending its own transition is not the panel's.
    el.querySelector('[data-part="prev-trigger"]').dispatchEvent(
      new Event("transitionend", { bubbles: true }),
    );
    expect(hook.pushEvent).not.toHaveBeenCalled();

    content.dispatchEvent(new Event("transitionend", { bubbles: true }));
    applied();
    expect(hook.pushEvent).toHaveBeenCalledTimes(1);
    vi.restoreAllMocks();
  });

  it("applies a clicked preset at once when the panel has no exit transition", () => {
    const el = mount({ presets });
    clickPreset(el);
    applied();
  });
});
