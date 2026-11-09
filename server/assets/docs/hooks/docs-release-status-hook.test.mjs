import assert from "node:assert/strict";
import { test } from "node:test";
import DocsReleaseStatusHook from "./docs-release-status-hook.mjs";

test("renders UTC release instants in the reader's timezone, including DST and refreshed content", (t) => {
  const DateTimeFormat = Intl.DateTimeFormat;
  t.mock.method(Intl, "DateTimeFormat", function (locale, options) {
    assert.equal(locale, "en-US");
    return new DateTimeFormat(locale, { ...options, timeZone: "Europe/Berlin" });
  });
  const previousDocument = globalThis.document;
  globalThis.document = { documentElement: { lang: "en-US" } };
  t.after(() => {
    globalThis.document = previousDocument;
  });

  const winter = { dateTime: "2026-11-09T06:00:00Z", textContent: "UTC fallback" };
  const summer = { dateTime: "2027-06-07T06:00:00Z", textContent: "UTC fallback" };
  const zone = {};
  let times = [winter];
  const hook = {
    ...DocsReleaseStatusHook,
    el: { querySelectorAll: () => times, querySelector: () => zone },
  };

  hook.mounted();
  assert.equal(winter.textContent, "Nov 9, 2026, 7:00 AM");
  assert.equal(zone.textContent, "Europe/Berlin");

  times = [winter, summer];
  hook.updated();
  assert.equal(summer.textContent, "Jun 7, 2027, 8:00 AM");
  assert.equal(summer.dateTime, "2027-06-07T06:00:00Z");
});
