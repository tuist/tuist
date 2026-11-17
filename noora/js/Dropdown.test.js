// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest";
import Dropdown from "./Dropdown.js";

let hook;
afterEach(() => {
  hook?.beforeDestroy();
  hook?.destroyed();
  hook = undefined;
  document.body.innerHTML = "";
});

function mountMenu({ items = "", attrs = "" } = {}) {
  document.body.innerHTML = `<div id="columns" class="noora-menu" data-trigger="dropdown" data-close-on-select="true" data-on-select="toggle_column" ${attrs}>
    <button data-part="trigger" type="button">Columns</button>
    <div data-part="positioner"><div class="noora-menu-panel" data-part="content">
      <div data-part="items">${items}</div>
    </div></div>
  </div>`;
  const el = document.getElementById("columns");
  hook = { ...Dropdown, el, pushEvent: vi.fn() };
  hook.mounted();
  return hook;
}

const checkboxItem = (value, checked) =>
  `<div class="noora-menu-item" data-part="item" data-value="${value}" data-label="${value}" data-checkbox data-checked="${checked}">
    <div data-part="checkbox"><div class="noora-checkbox-control" data-state="${checked ? "checked" : "unchecked"}"></div></div>
  </div>`;

describe("Noora.Menu checkbox items", () => {
  it("toggle in place and send the state they toggle to", async () => {
    mountMenu({ items: checkboxItem("branch", false) });
    hook.menu.api.setOpen(true);
    const item = hook.el.querySelector('[data-value="branch"]');
    // Zag selects the highlighted item; a pointer highlights it on hover.
    hook.menu.api.setHighlightedValue("branch");

    item.click();

    await vi.waitFor(() => expect(item.dataset.checked).toBe("true"));
    expect(item.getAttribute("aria-checked")).toBe("true");
    expect(item.querySelector(".noora-checkbox-control").dataset.state).toBe(
      "checked",
    );
    expect(hook.pushEvent).toHaveBeenCalledWith(
      "toggle_column",
      expect.objectContaining({ value: "branch", checked: true }),
    );
    expect(hook.menu.api.open).toBe(true);

    hook.menu.api.setHighlightedValue("branch");
    item.click();

    await vi.waitFor(() => expect(item.dataset.checked).toBe("false"));
    expect(hook.pushEvent).toHaveBeenLastCalledWith(
      "toggle_column",
      expect.objectContaining({ value: "branch", checked: false }),
    );
  });
});

describe("Noora.Menu disabled and empty states", () => {
  it("disables the trigger of an empty menu and re-enables it once items arrive", () => {
    mountMenu({ attrs: "data-empty" });
    const trigger = hook.el.querySelector('[data-part="trigger"]');
    expect(trigger.disabled).toBe(true);

    hook.el.removeAttribute("data-empty");
    hook.updated();
    expect(trigger.disabled).toBe(false);
  });
});

describe("Breadcrumb menus", () => {
  function mountBreadcrumb() {
    document.body.innerHTML = `<div class="noora-breadcrumbs"><div id="project" class="noora-breadcrumb" data-close-on-select>
      <button data-part="trigger" type="button">Projects</button>
      <div data-part="positioner"><div class="noora-menu-panel" data-part="content"><div data-part="items">
        <a class="noora-menu-item" data-part="item" data-value="ios" data-label="ios-app" href="/ios" tabindex="-1" data-selected>ios-app</a>
        <a class="noora-menu-item" data-part="item" data-value="android" data-label="android-app" href="/android" tabindex="-1">android-app</a>
      </div></div></div>
    </div></div>`;
    const el = document.getElementById("project");
    hook = { ...Dropdown, el, pushEvent: vi.fn() };
    hook.mounted();
    return hook;
  }

  const keydown = (key) =>
    document.activeElement.dispatchEvent(
      new KeyboardEvent("keydown", { key, bubbles: true }),
    );

  it("focus the selected item on open without highlighting it, and highlight keyboard moves", async () => {
    mountBreadcrumb();
    const [ios, android] = hook.el.querySelectorAll('[data-part="item"]');

    hook.menu.api.setOpen(true);
    await vi.waitFor(() => expect(document.activeElement).toBe(ios));
    expect(ios.hasAttribute("data-highlighted")).toBe(false);

    keydown("ArrowDown");
    expect(document.activeElement).toBe(android);
    expect(android.hasAttribute("data-highlighted")).toBe(true);
    expect(ios.hasAttribute("data-highlighted")).toBe(false);

    hook.el.dispatchEvent(new PointerEvent("pointermove", { bubbles: true }));
    expect(android.hasAttribute("data-highlighted")).toBe(false);
  });
});

describe("Noora.Menu keyboard highlight", () => {
  it("scrolls the highlighted item into view from the keyboard, not the pointer", () => {
    mountMenu({ items: checkboxItem("branch", false) });
    const item = hook.el.querySelector('[data-value="branch"]');
    item.scrollIntoView = vi.fn();

    hook.el.dispatchEvent(new Event("pointermove", { bubbles: true }));
    hook.scrollToHighlightedItem("branch");
    expect(item.scrollIntoView).not.toHaveBeenCalled();

    hook.el.dispatchEvent(new Event("keydown", { bubbles: true }));
    hook.scrollToHighlightedItem("branch");
    expect(item.scrollIntoView).toHaveBeenCalledWith({ block: "nearest" });
  });
});

it("makes late portaled search results accessible and reapplies the current search", async () => {
  document.body.innerHTML = `
    <div id="tags">
      <button data-part="trigger" type="button">Tags</button>
      <div data-part="positioner">
        <div data-part="content">
          <input data-part="search-input" />
          <div data-part="items"></div>
        </div>
      </div>
    </div>`;
  const el = document.getElementById("tags");
  hook = Object.assign({ el }, Dropdown);
  hook.mounted();

  const search = el.querySelector("input");
  search.value = "PROD";
  search.dispatchEvent(new Event("input", { bubbles: true }));
  expect(el.querySelector('[data-part="search-empty"]').style.display).toBe("");

  // LiveView patches portal content after the root hook has updated.
  hook.updated();
  el.querySelector('[data-part="items"]').insertAdjacentHTML(
    "afterbegin",
    `<div>
      <span data-part="item" data-value="prod" data-label="z-production">z-production</span>
      <span data-part="item" data-value="debug" data-label="debug">debug</span>
    </div>`,
  );

  await vi.waitFor(() => {
    expect(el.querySelector('[data-value="prod"]').getAttribute("role")).toBe(
      "menuitem",
    );
    expect(el.querySelector('[data-value="prod"]').style.display).toBe("");
    expect(el.querySelector('[data-value="debug"]').style.display).toBe("none");
    expect(el.querySelector('[data-part="search-empty"]').style.display).toBe(
      "none",
    );
  });
});
