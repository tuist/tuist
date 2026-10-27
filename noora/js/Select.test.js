// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest";
import Select from "./Select.js";

let hook;
afterEach(() => {
  hook?.beforeDestroy();
  document.body.innerHTML = "";
});

function mount(value = "json") {
  document.body.innerHTML = `<form><div id="language" data-name="language" data-value="${value}">
    <select data-part="hidden-select" name="language"><option value=""></option><option value="json">JSON</option><option value="javascript">JavaScript</option></select>
    <button data-part="trigger"><span data-part="label-wrapper"><span data-part="label">Language</span></span></button>
    <div data-part="positioner"><div data-part="content">
      <div data-part="item" data-value="json" data-label="JSON">JSON</div>
      <div data-part="item" data-value="javascript" data-label="JavaScript">JavaScript</div>
    </div></div>
  </div></form>`;
  const el = document.getElementById("language");
  el.querySelector("select").value = value;
  hook = { ...Select, el, pushEvent: vi.fn() };
  hook.mounted();
  return hook;
}

const submitted = () =>
  new FormData(document.querySelector("form")).get("language");

describe("Select initial and server values", () => {
  it("submits the initial selection without requiring the user to select it again", async () => {
    mount();
    await vi.waitFor(() => expect(submitted()).toBe("json"));
    expect(hook.select.api.value).toEqual(["json"]);
    expect(hook.el.querySelector("[data-part=label]").textContent).toBe("JSON");
  });

  it("preserves client changes through unchanged server echoes and honors an explicit reset", async () => {
    mount();
    hook.select.api.setValue(["javascript"]);
    await vi.waitFor(() => expect(submitted()).toBe("javascript"));
    hook.updated();
    expect(hook.select.api.value).toEqual(["javascript"]);
    hook.el.dataset.value = "javascript";
    hook.updated();
    hook.el.dataset.value = "json";
    hook.updated();
    await vi.waitFor(() => expect(submitted()).toBe("json"));
    expect(hook.el.querySelector("[data-part=label]").textContent).toBe("JSON");
  });
});
