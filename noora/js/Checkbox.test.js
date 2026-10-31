// @vitest-environment happy-dom
import { afterEach, expect, it, vi } from "vitest";
import Checkbox from "./Checkbox.js";

let hook;
afterEach(() => {
  hook?.beforeDestroy();
  document.body.innerHTML = "";
});

function mount({
  checked = false,
  disabled = false,
  name = "user[remember_me]",
} = {}) {
  document.body.innerHTML = `<form><div id="remember-me" name="${name}"
    data-default-checked="${checked}" data-disabled="${disabled}">
    <label data-part="root"><input data-part="hidden-input" />
      <span data-part="control"></span><span data-part="label">Keep me logged in</span>
    </label>
  </div></form>`;
  hook = { ...Checkbox, el: document.getElementById("remember-me") };
  hook.mounted();
  return () => new FormData(document.querySelector("form")).get(name);
}

it("submits a checked Phoenix form field as true and omits it when unchecked", async () => {
  const submitted = mount();
  expect(submitted()).toBeNull();

  document.querySelector("label").click();
  await vi.waitFor(() => expect(submitted()).toBe("true"));
  hook.updated();
  expect(submitted()).toBe("true");

  document.querySelector("label").click();
  await vi.waitFor(() => expect(submitted()).toBeNull());
});

it.each([true, false])(
  "preserves the initial checked state %s through hydration",
  async (checked) => {
    const submitted = mount({ checked, name: "preferences[]" });
    await vi.waitFor(() => expect(submitted()).toBe(checked ? "true" : null));
    expect(document.querySelector("input").checked).toBe(checked);
  },
);

it("omits a disabled checked field from form submission", async () => {
  const submitted = mount({ checked: true, disabled: true });
  await vi.waitFor(() =>
    expect(document.querySelector("input").disabled).toBe(true),
  );
  expect(submitted()).toBeNull();
});
