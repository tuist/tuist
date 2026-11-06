import test from "node:test";
import assert from "node:assert/strict";
import { trackBrowserSessionPath } from "./BrowserSessionPath.mjs";

test("tracks pending main-view joins, patches and history without relying on the old address bar", () => {
  const browser = new EventTarget();
  browser.location = new URL("https://tuist.example/account/projects?old=1#ignored");
  const path = trackBrowserSessionPath(browser);
  const emit = (type, detail) => browser.dispatchEvent(Object.assign(new Event(type), { detail }));

  assert.equal(path(), "/account/projects?old=1");
  emit("phx:page-loading-start", { kind: "initial", to: "https://tuist.example/account/project/tests?filter=a%2Bb" });
  assert.equal(path(), "/account/project/tests?filter=a%2Bb");
  assert.equal(browser.location.pathname, "/account/projects");

  // A loading completion or a reconnect must not restore the stale address bar.
  emit("phx:page-loading-stop", {});
  emit("phx:page-loading-start", { kind: "initial", to: null });
  assert.equal(path(), "/account/project/tests?filter=a%2Bb");

  emit("phx:navigate", { href: "https://tuist.example/account/project/tests?filter=patched#ignored" });
  assert.equal(path(), "/account/project/tests?filter=patched");
  emit("phx:navigate", { href: "https://tuist.example/account/projects?old=1" });
  assert.equal(path(), "/account/projects?old=1");

  emit("phx:page-loading-start", { kind: "initial", to: "/account/settings" });
  emit("phx:page-loading-start", { kind: "initial", to: "/account/members" });
  assert.equal(path(), "/account/members");
  emit("phx:page-loading-start", { kind: "initial", to: "https://evil.example/account/members" });
  assert.equal(path(), null);
});
