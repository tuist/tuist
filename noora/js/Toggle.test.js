// @vitest-environment happy-dom
import { afterEach, expect, it, vi } from "vitest";
import Toggle from "./Toggle.js";

let hook;

afterEach(() => {
  hook?.beforeDestroy();
  document.body.innerHTML = "";
});

function mount(checked) {
  document.body.innerHTML = `<div id="configuration" ${checked ? "data-checked" : ""} data-on-checked-change="toggle_configuration">
    <label id="switch:configuration" data-part="root">
      <input data-part="hidden-input" />
      <div data-part="control"><div data-part="track"><div data-part="thumb"></div></div></div>
      <span data-part="label">Show configuration</span>
    </label>
  </div>`;
  const events = [];
  hook = {
    ...Toggle,
    el: document.getElementById("configuration"),
    pushEvent: (_event, details) => events.push(details.checked),
  };
  hook.mounted();
  return events;
}

const input = () => hook.el.querySelector("input");
const control = () => hook.el.querySelector("[data-part=control]");

it.each([true, false])(
  "restores server checked=%s on reconnect without sending another change",
  async (checked) => {
    const events = mount(checked);
    const nativeChanges = [];
    input().addEventListener("change", (event) =>
      nativeChanges.push(event.target.checked),
    );
    await vi.waitFor(() => expect(input().checked).toBe(checked));
    control().click();
    await vi.waitFor(() => expect(input().checked).toBe(!checked));
    await vi.waitFor(() => expect(events).toEqual([!checked]));

    hook.updated();
    expect(input().checked).toBe(!checked);

    const focusedInput = input();
    focusedInput.focus();
    hook.el.toggleAttribute("data-checked", checked);
    hook.updated();
    hook.reconnected?.();
    await vi.waitFor(() => expect(input().checked).toBe(checked));
    expect(control().dataset.state).toBe(checked ? "checked" : "unchecked");
    expect(events).toEqual([!checked]);
    expect(nativeChanges).toEqual([!checked]);
    expect(document.activeElement).toBe(focusedInput);

    hook.reconnected?.();
    control().click();
    await vi.waitFor(() => expect(input().checked).toBe(!checked));
    await vi.waitFor(() => expect(events).toEqual([!checked, !checked]));
    expect(nativeChanges).toEqual([!checked, !checked]);
  },
);
