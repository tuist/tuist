import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { runInNewContext } from "node:vm";

const source = readFileSync(new URL("./language-dropdown.js", import.meta.url), "utf8").replace(
  "export default function languageDropdown",
  "globalThis.languageDropdown = function",
);

function fixture() {
  const state = { choice: "ja", events: [] };
  const link = { dataset: { glossiaLanguage: "zh-Hans" }, hasAttribute: () => false };
  const listeners = new Set();
  const context = {
    glossia: {
      selectLanguage(choice) {
        state.choice = choice;
        state.events.push({ name: "language_selection", choice });
      },
    },
  };
  runInNewContext(source, context);
  const hook = Object.assign(Object.create(context.languageDropdown({ mounted() {}, destroyed() {} })), {
    menu: { api: { open: true }, machine: { computed: () => state.typingAhead } },
    el: {
      querySelector: () => link,
      addEventListener: (_, listener) => listeners.add(listener),
      removeEventListener: (_, listener) => listeners.delete(listener),
    },
  });
  hook.mounted();
  const press = (overrides = {}) => {
    const event = {
      isTrusted: true,
      defaultPrevented: false,
      key: "Enter",
      target: { closest: () => ({}) },
      ...overrides,
    };
    for (const listener of listeners) listener(event);
  };
  return { hook, context, state, link, press };
}

test("trusted menu activation replaces the previous choice exactly once", () => {
  for (const key of ["Enter", " "]) {
    const { state, press } = fixture();
    press({ key });
    assert.equal(state.choice, "zh-Hans");
    assert.deepEqual(state.events, [{ name: "language_selection", choice: "zh-Hans" }]);
  }
});

test("navigation, synthetic keys, cancelled keys and typeahead do not select a language", () => {
  const { hook, state, link, press } = fixture();
  press({ key: "ArrowDown" });
  press({ isTrusted: false });
  press({ defaultPrevented: true });
  press({ target: { closest: () => null } });
  state.typingAhead = true;
  press({ key: " " });
  hook.menu.api.open = false;
  press();
  hook.menu.api.open = true;
  link.hasAttribute = () => true;
  press();
  assert.equal(state.choice, "ja");
  assert.deepEqual(state.events, []);
});

test("unmounting removes tracking and an unavailable SDK does not block activation", () => {
  const { hook, context, state, press } = fixture();
  delete context.glossia;
  assert.doesNotThrow(() => press());
  hook.destroyed();
  context.glossia = { selectLanguage: () => assert.fail("unmounted picker still tracks choices") };
  press();
  assert.equal(state.choice, "ja");
});
