import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { runInNewContext } from "node:vm";

const source = readFileSync(new URL("./google-one-tap.js", import.meta.url), "utf8").replace(
  "export const GoogleOneTap =",
  "globalThis.hook =",
);

function fixture() {
  const state = { submitted: 0, cancelled: 0, listeners: new Set() };
  const form = {
    isConnected: true,
    elements: { credential: { value: "" }, nonce: { value: "" } },
    requestSubmit() {
      state.submitted++;
    },
  };
  const identity = {
    initialize(options) {
      state.callback = options.callback;
    },
    prompt() {},
    cancel() {
      state.cancelled++;
      throw new Error("Google cleanup failed");
    },
  };
  const window = {
    isSecureContext: true,
    IdentityCredential: class {},
    google: { accounts: { id: identity } },
    addEventListener: (_, listener) => state.listeners.add(listener),
    removeEventListener: (_, listener) => state.listeners.delete(listener),
  };
  window.top = window.self = window;
  const context = {
    window,
    google: window.google,
    AbortController,
    document: {
      querySelector: () => ({ content: "test-token" }),
      createElement: () => ({ remove() {} }),
      head: { appendChild: (script) => queueMicrotask(() => script.onerror()) },
    },
    fetch: async () => ({ ok: true, json: async () => ({ client_id: "test-client", nonce: "test-nonce" }) }),
  };
  runInNewContext(source, context);
  const hook = Object.assign(Object.create(context.hook), {
    el: { isConnected: true, dataset: { startUrl: "/start" }, querySelector: () => form },
  });
  return { hook, context, identity, window, state, form };
}

for (const failure of ["setup", "fetch", "script", "initialize", "prompt"]) {
  test(`${failure} failure does not reject mounting or throw during teardown`, async () => {
    const { hook, context, identity, window } = fixture();
    const fail = () => {
      throw new Error("Injected failure");
    };
    if (failure === "setup")
      context.AbortController = class {
        constructor() {
          fail();
        }
      };
    if (failure === "fetch") context.fetch = fail;
    if (failure === "script") window.google = undefined;
    if (["initialize", "prompt"].includes(failure)) identity[failure] = fail;
    await assert.doesNotReject(() => hook.mounted());
    assert.doesNotThrow(() => hook.destroyed());
  });
}

test("malformed responses and submission failures do not escape Google's callback", async () => {
  const { hook, state, form } = fixture();
  await hook.mounted();
  for (const response of [undefined, null, {}, { credential: {} }, { credential: "" }]) {
    assert.doesNotThrow(() => state.callback(response));
  }
  assert.equal(state.submitted, 0);
  form.requestSubmit = () => {
    throw new Error("Submission failed");
  };
  assert.doesNotThrow(() => state.callback({ credential: "signed-token" }));
  delete form.elements.credential;
  assert.doesNotThrow(() => state.callback({ credential: "signed-token" }));
});

test("valid credentials still submit the protected form", async () => {
  const { hook, state, form } = fixture();
  await hook.mounted();
  state.callback({ credential: "signed-token" });
  assert.equal(form.elements.credential.value, "signed-token");
  assert.equal(form.elements.nonce.value, "test-nonce");
  assert.equal(state.submitted, 1);
});

test("throwing cancellation still cleans up and prevents late submission", async () => {
  const { hook, state } = fixture();
  await hook.mounted();
  assert.doesNotThrow(() => hook.destroyed());
  assert.equal(hook.abortController.signal.aborted, true);
  assert.equal(hook.prompted, false);
  assert.equal(state.listeners.size, 0);
  assert.doesNotThrow(() => hook.destroyed());
  assert.equal(state.cancelled, 1);
  state.callback({ credential: "stale-token" });
  assert.equal(state.submitted, 0);
});

test("teardown tolerates Google disappearing after mounting", async () => {
  const { hook, window } = fixture();
  await hook.mounted();
  delete window.google;
  assert.doesNotThrow(() => hook.destroyed());
  assert.equal(hook.prompted, false);
});
