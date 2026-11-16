// @vitest-environment happy-dom
import { afterEach, expect, it, vi } from "vitest";
import Dropdown from "./Dropdown.js";

let hook;

afterEach(() => {
  hook?.beforeDestroy();
  hook?.destroyed();
  hook = undefined;
  document.body.innerHTML = "";
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
