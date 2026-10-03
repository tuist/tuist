// @vitest-environment happy-dom
import { afterEach, expect, it } from "vitest";
import IconTransition from "./IconTransition.js";

let hook;

afterEach(() => {
  hook?.destroyed();
  document.body.innerHTML = "";
});

it("restores the disclosure icon after LiveView patches its data attributes", async () => {
  document.body.innerHTML = `
    <div phx-hook="NooraTable">
      <table><tbody><tr data-expandable data-state="collapsed"><td>
        <span data-transition="crossfade_rotate" data-watch="tr[data-expandable]" data-active-state="expanded"></span>
      </td></tr></tbody></table>
    </div>`;
  const el = document.querySelector("span");
  const row = document.querySelector("tr");
  hook = { ...IconTransition, el };
  hook.mounted();
  expect(el.hasAttribute("data-active")).toBe(false);

  row.dataset.state = "expanded";
  await new Promise((resolve) => setTimeout(resolve, 10));
  expect(el.hasAttribute("data-active")).toBe(true);

  // A subsequent output-loading patch preserves row state but removes data-active.
  el.removeAttribute("data-active");
  hook.updated();
  expect(el.hasAttribute("data-active")).toBe(true);

  row.dataset.state = "collapsed";
  hook.updated();
  expect(el.hasAttribute("data-active")).toBe(false);
});
