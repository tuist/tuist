// @vitest-environment happy-dom
import { afterEach, describe, expect, it, vi } from "vitest";
import Checkbox from "./Checkbox.js";

let hook;
afterEach(() => {
  hook?.beforeDestroy();
  hook = undefined;
  document.body.innerHTML = "";
});

// The markup Noora.Checkbox renders, with the server's state attributes.
const attrs = ({ checked, indeterminate, disabled, onChange, name }) =>
  [
    name && `name="${name}"`,
    checked && "data-default-checked",
    indeterminate && "data-indeterminate",
    disabled && "data-disabled",
    onChange && `data-on-checked-change="${onChange}"`,
  ]
    .filter(Boolean)
    .join(" ");

const mount = (state = {}) => {
  document.body.innerHTML = `<div id="select-all" class="noora-checkbox" ${attrs(state)}>
    <label data-part="root">
      <input data-peer data-part="hidden-input" />
      <div class="noora-checkbox-control" data-part="control"><div data-part="box"></div></div>
      <div><span data-part="label">Select all</span></div>
    </label>
  </div>`;
  const el = document.getElementById("select-all");
  hook = { ...Checkbox, el, pushEvent: vi.fn() };
  hook.mounted();
  return hook;
};

// A LiveView patch: the root's server attributes change, then the hook
// updates.
const patch = (state) => {
  const el = hook.el;
  for (const name of [
    "data-default-checked",
    "data-indeterminate",
    "data-disabled",
  ]) {
    el.removeAttribute(name);
  }
  if (state.checked) el.setAttribute("data-default-checked", "");
  if (state.indeterminate) el.setAttribute("data-indeterminate", "");
  hook.updated();
};

const control = () => hook.el.querySelector('[data-part="control"]');
const input = () => hook.el.querySelector('[data-part="hidden-input"]');

describe("Noora.Checkbox", () => {
  it("starts in the state the server rendered", () => {
    mount({ checked: true });
    expect(control().dataset.state).toBe("checked");

    hook.beforeDestroy();
    mount({ indeterminate: true });
    expect(control().dataset.state).toBe("indeterminate");
    // Announced as mixed from the start, not only after a change.
    expect(input().indeterminate).toBe(true);
  });

  it("goes from indeterminate to checked, then unchecked, when clicked", async () => {
    mount({ indeterminate: true, onChange: "toggle_all" });

    input().click();
    await vi.waitFor(() => expect(control().dataset.state).toBe("checked"));
    expect(input().indeterminate).toBe(false);
    expect(hook.pushEvent).toHaveBeenLastCalledWith("toggle_all", {
      checked: true,
    });

    input().click();
    await vi.waitFor(() => expect(control().dataset.state).toBe("unchecked"));
    expect(hook.pushEvent).toHaveBeenLastCalledWith("toggle_all", {
      checked: false,
    });
  });

  it("follows a new state from the server without sending it back", async () => {
    mount({ checked: false, onChange: "toggle_all" });

    patch({ indeterminate: true });
    await vi.waitFor(() =>
      expect(control().dataset.state).toBe("indeterminate"),
    );
    expect(input().indeterminate).toBe(true);

    patch({ checked: true });
    await vi.waitFor(() => expect(control().dataset.state).toBe("checked"));
    expect(hook.pushEvent).not.toHaveBeenCalled();
  });

  it("keeps the state people set when the server re-renders it unchanged", async () => {
    mount({ checked: false });

    input().click();
    await vi.waitFor(() => expect(control().dataset.state).toBe("checked"));

    patch({ checked: false });
    await Promise.resolve();
    expect(control().dataset.state).toBe("checked");
  });

  it("goes back to the server's state when the server turns a change down", async () => {
    mount({ checked: false, onChange: "toggle_all" });

    input().click();
    await vi.waitFor(() => expect(control().dataset.state).toBe("checked"));
    expect(hook.pushEvent).toHaveBeenCalledTimes(1);

    patch({ checked: false });
    await vi.waitFor(() => expect(control().dataset.state).toBe("unchecked"));
    expect(hook.pushEvent).toHaveBeenCalledTimes(1);
  });

  it("submits its name with the value true when checked", async () => {
    mount({ name: "user[remember_me]" });
    expect(input().name).toBe("user[remember_me]");
    expect(input().value).toBe("true");
    expect(input().type).toBe("checkbox");

    input().click();
    await vi.waitFor(() => expect(input().checked).toBe(true));
  });

  it("keeps the name, value and checked state of markup with its own input", () => {
    document.body.innerHTML = `<div id="reply-all" class="noora-checkbox">
      <label data-part="root">
        <input type="checkbox" name="reply[all]" value="yes" checked data-part="hidden-input" />
        <div class="noora-checkbox-control" data-part="control"><div data-part="box"></div></div>
        <span data-part="label">Reply all</span>
      </label>
    </div>`;
    hook = {
      ...Checkbox,
      el: document.getElementById("reply-all"),
      pushEvent: vi.fn(),
    };
    hook.mounted();

    expect(input().name).toBe("reply[all]");
    expect(input().value).toBe("yes");
    expect(control().dataset.state).toBe("checked");
  });

  it("waits for the server's answer before going back to its state", async () => {
    mount({ checked: false, onChange: "toggle_all" });
    let answer;
    hook.pushEvent = vi.fn(() => new Promise((resolve) => (answer = resolve)));

    input().click();
    await vi.waitFor(() => expect(control().dataset.state).toBe("checked"));

    // A re-render from something else, before the server has answered.
    patch({ checked: false });
    await new Promise((resolve) => setTimeout(resolve));
    expect(control().dataset.state).toBe("checked");

    // The server answers without having rendered the change.
    answer();
    await vi.waitFor(() => expect(control().dataset.state).toBe("unchecked"));
    expect(hook.pushEvent).toHaveBeenCalledTimes(1);
  });
});
