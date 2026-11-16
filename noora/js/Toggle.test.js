// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest";
import Toggle from "./Toggle.js";

let hook;
afterEach(() => {
  hook?.beforeDestroy();
  hook = undefined;
  document.body.innerHTML = "";
});

// The markup Noora.Toggle renders, with the server's state attributes.
const mount = ({ checked, name, onChange } = {}) => {
  const attrs = [
    name && `name="${name}"`,
    checked && "data-checked",
    onChange && `data-on-checked-change="${onChange}"`,
  ]
    .filter(Boolean)
    .join(" ");
  document.body.innerHTML = `<div id="reports" class="noora-toggle" ${attrs}>
    <label id="switch:reports" data-part="root">
      <input data-peer data-part="hidden-input" />
      <div class="noora-toggle-control" data-part="control">
        <div data-part="track"><div data-part="thumb"></div></div>
      </div>
      <div><span data-part="label">Slack reports</span></div>
    </label>
  </div>`;
  hook = {
    ...Toggle,
    el: document.getElementById("reports"),
    pushEvent: vi.fn(),
  };
  hook.mounted();
  return hook;
};

// A LiveView patch: the root's server attribute changes, then the hook
// updates.
const patch = ({ checked }) => {
  hook.el.toggleAttribute("data-checked", Boolean(checked));
  hook.updated();
};

const control = () => hook.el.querySelector('[data-part="control"]');
const input = () => hook.el.querySelector('[data-part="hidden-input"]');

describe("Noora.Toggle", () => {
  it("starts in the state the server rendered", () => {
    mount({ checked: true });
    expect(control().dataset.state).toBe("checked");
  });

  it("submits its name with the value true", () => {
    mount({ name: "project[reports]" });
    expect(input().name).toBe("project[reports]");
    expect(input().value).toBe("true");
  });

  it("reports a change people make", async () => {
    mount({ onChange: "toggle_reports" });

    input().click();
    await vi.waitFor(() => expect(control().dataset.state).toBe("checked"));
    expect(hook.pushEvent).toHaveBeenLastCalledWith("toggle_reports", {
      checked: true,
    });
  });

  it("follows a new state from the server without sending it back", async () => {
    mount({ onChange: "toggle_reports" });

    patch({ checked: true });
    await vi.waitFor(() => expect(control().dataset.state).toBe("checked"));

    patch({ checked: false });
    await vi.waitFor(() => expect(control().dataset.state).toBe("unchecked"));
    expect(hook.pushEvent).not.toHaveBeenCalled();
  });

  it("keeps the state people set when the server re-renders it unchanged", async () => {
    mount();

    input().click();
    await vi.waitFor(() => expect(control().dataset.state).toBe("checked"));

    patch({ checked: false });
    await new Promise((resolve) => setTimeout(resolve));
    expect(control().dataset.state).toBe("checked");
  });
});
