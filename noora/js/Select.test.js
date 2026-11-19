// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest";
import Select from "./Select.js";

let hook;
afterEach(() => {
  hook?.beforeDestroy();
  document.body.innerHTML = "";
});

function mount(value = "json", disabled = false) {
  document.body.innerHTML = `<form><div id="language" data-name="language" data-value="${value}" data-disabled="${disabled}">
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

  it("honors disabled state on mount and after a server patch", async () => {
    mount("json", true);
    const trigger = hook.el.querySelector("[data-part=trigger]");
    expect(trigger.disabled).toBe(true);
    hook.el.dataset.disabled = "false";
    hook.updated();
    expect(trigger.disabled).toBe(false);
    hook.el.dataset.disabled = "true";
    hook.updated();
    expect(trigger.disabled).toBe(true);
  });

  it("accepts refreshed options without losing an unacknowledged client selection", async () => {
    mount();
    hook.select.api.setValue(["javascript"]);
    await vi.waitFor(() => expect(submitted()).toBe("javascript"));
    hook.el
      .querySelector("select")
      .insertAdjacentHTML("beforeend", '<option value="text">Text</option>');
    hook.el
      .querySelector("[data-part=content]")
      .insertAdjacentHTML(
        "beforeend",
        '<div data-part="item" data-value="text" data-label="Text">Text</div>',
      );
    hook.updated();
    await vi.waitFor(() => expect(submitted()).toBe("javascript"));
    hook.el.querySelector("[data-part=trigger]").click();
    await vi.waitFor(() =>
      expect(hook.el.querySelector("[data-part=content]").dataset.state).toBe(
        "open",
      ),
    );
    hook.el.querySelector('[data-value="text"]').click();
    await vi.waitFor(() => expect(submitted()).toBe("text"));
    expect(hook.el.querySelector("[data-part=label]").textContent).toBe("Text");
  });
});
