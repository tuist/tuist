// @vitest-environment happy-dom
import { afterEach, beforeEach, describe, expect, it, vi } from "vitest";
import "./ButtonGroup.js";

let animations;
beforeEach(() => {
  animations = [];
  // happy-dom has no custom element states; a Set stands in for them.
  HTMLElement.prototype.attachInternals = () => ({ states: new Set() });
  HTMLElement.prototype.animate = function (keyframes, options) {
    const animation = { keyframes, options, cancel: vi.fn() };
    animations.push(animation);
    return animation;
  };
});

afterEach(() => {
  delete HTMLElement.prototype.animate;
  delete HTMLElement.prototype.attachInternals;
  document.body.innerHTML = "";
});

const mount = (selected = 0) => {
  document.body.innerHTML = `<div class="noora-button-group">
    <noora-button-group-indicator data-part="indicator"></noora-button-group-indicator>
    ${["Builds", "Tests", "Cache"]
      .map(
        (label, i) =>
          `<button class="noora-button-group-item"${i === selected ? " data-selected" : ""}>${label}</button>`,
      )
      .join("")}
  </div>`;
  return {
    indicator: document.querySelector("noora-button-group-indicator"),
    items: document.querySelectorAll(".noora-button-group-item"),
  };
};

describe("<noora-button-group-indicator>", () => {
  it("settles on the selected item without sliding", async () => {
    const { indicator } = mount();

    await vi.waitFor(() => expect(indicator.active).toBe(true));
    expect(animations.every((a) => a.options.duration === 0)).toBe(true);
  });

  it("slides when the selection moves", async () => {
    const { indicator, items } = mount();
    await vi.waitFor(() => expect(indicator.active).toBe(true));

    items[0].removeAttribute("data-selected");
    items[2].setAttribute("data-selected", "");
    await vi.waitFor(() =>
      expect(animations.at(-1).options.duration).toBe(200),
    );
    expect(animations.at(-1).options.fill).toBe("forwards");
  });

  it("jumps instead of sliding when selected from the keyboard", async () => {
    const { indicator, items } = mount();
    await vi.waitFor(() => expect(indicator.active).toBe(true));

    items[1].dispatchEvent(new KeyboardEvent("keydown", { bubbles: true }));
    items[0].removeAttribute("data-selected");
    items[1].setAttribute("data-selected", "");
    const before = animations.length;
    await vi.waitFor(() => expect(animations.length).toBeGreaterThan(before));
    expect(animations.at(-1).options.duration).toBe(0);
  });

  it("hides when nothing is selected", async () => {
    const { indicator, items } = mount();

    items[0].removeAttribute("data-selected");
    await vi.waitFor(() => expect(indicator.active).toBe(false));
  });
});
