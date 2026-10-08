import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { runInNewContext } from "node:vm";

const source = readFileSync(new URL("./setup-prompt.js", import.meta.url), "utf8")
  .replace(/^import .*;\n/, "")
  .replace("export const SetupPrompt =", "globalThis.hook =");

function fixture(copyTextToClipboard = async () => {}) {
  const listeners = new Map();
  const button = {
    disabled: true,
    focusCount: 0,
    addEventListener: (name, listener) => listeners.set(name, listener),
    removeEventListener: (name) => listeners.delete(name),
    focus() {
      this.focusCount++;
    },
  };
  const prompt = { textContent: "Connect my project to Tuist (https://tuist.dev)" };
  const status = { textContent: "" };
  const parts = { copy: button, prompt, status };
  const context = { copyTextToClipboard };
  runInNewContext(source, context);
  const hook = Object.assign(Object.create(context.hook), {
    el: {
      dataset: { successMessage: "Copied!", errorMessage: "Copy manually." },
      querySelector: (selector) => parts[selector.match(/data-part="([^"]+)"/)[1]],
    },
  });
  hook.mounted();
  return { hook, button, prompt, status, listeners };
}

test("enables copying and copies only the displayed prompt", async () => {
  const copied = [];
  const { button, prompt, status, listeners } = fixture(async (text) => copied.push(text));
  assert.equal(button.disabled, false);

  await listeners.get("click")();

  assert.deepEqual(copied, [prompt.textContent]);
  assert.equal(status.textContent, "Copied!");
  assert.equal(button.disabled, false);
  assert.equal(button.focusCount, 1);
});

test("clipboard failure offers manual copying and allows retry", async () => {
  let attempts = 0;
  const { hook, button, status } = fixture(async () => {
    if (attempts++ === 0) throw new Error("Clipboard permission denied");
  });

  await hook.copy();
  assert.equal(status.textContent, "Copy manually.");
  assert.equal(button.disabled, false);

  await hook.copy();
  assert.equal(status.textContent, "Copied!");
  assert.equal(attempts, 2);
});

test("ignores repeated clicks while copying and clears previous feedback", async () => {
  let resolve;
  let attempts = 0;
  const { hook, button, status } = fixture(() => {
    attempts++;
    return new Promise((done) => (resolve = done));
  });
  status.textContent = "Previous feedback";

  const pending = hook.copy();
  assert.equal(button.disabled, true);
  assert.equal(status.textContent, "");
  await hook.copy();
  assert.equal(attempts, 1);

  resolve();
  await pending;
  assert.equal(button.disabled, false);
});

for (const fails of [false, true]) {
  test(`teardown removes the listener and ignores a pending ${fails ? "failure" : "success"}`, async () => {
    let complete;
    const { hook, button, status, listeners } = fixture(
      () => new Promise((resolve, reject) => (complete = fails ? reject : resolve)),
    );
    const pending = hook.copy();

    hook.destroyed();
    assert.equal(listeners.size, 0);
    complete(fails ? new Error("Clipboard unavailable") : undefined);
    await pending;
    assert.equal(status.textContent, "");
    assert.equal(button.focusCount, 0);
  });
}
