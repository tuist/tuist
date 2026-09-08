import assert from "node:assert/strict";
import { test } from "node:test";
import { isAutomatedBrowser } from "./browser-automation.mjs";

const linuxCrawler = {
  webdriver: false,
  userAgent: "Mozilla/5.0 (X11; Linux x86_64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36",
  language: "en-US",
};
const crawlerViewport = { innerWidth: 1919, innerHeight: 992 };

test("excludes WebDriver automation regardless of fingerprint", () => {
  assert.equal(isAutomatedBrowser({ webdriver: true }, {}), true);
});

test("excludes Meta's identified crawler without the WebDriver flag", () => {
  for (const userAgent of [
    "meta-externalagent/1.1 (+https://developers.facebook.com/docs/sharing/webmasters/crawler)",
    "Meta-ExternalAgent/2.0",
  ]) {
    assert.equal(isAutomatedBrowser({ webdriver: false, userAgent }, {}), true);
  }
});

test("excludes the observed Linux crawler without the WebDriver flag", () => {
  assert.equal(isAutomatedBrowser(linuxCrawler, crawlerViewport), true);
});

test("keeps Linux browsers when any part of the fingerprint differs", () => {
  for (const [navigator, viewport] of [
    [{ ...linuxCrawler, language: "en-GB" }, crawlerViewport],
    [{ ...linuxCrawler, userAgent: linuxCrawler.userAgent.replace("150.0.0.0", "151.0.0.0") }, crawlerViewport],
    [linuxCrawler, { ...crawlerViewport, innerWidth: 1920 }],
    [linuxCrawler, { ...crawlerViewport, innerHeight: 993 }],
  ]) {
    assert.equal(isAutomatedBrowser(navigator, viewport), false);
  }
});

test("keeps ordinary desktop and mobile browsers even at the crawler viewport", () => {
  for (const userAgent of [
    "Mozilla/5.0 (Macintosh; Intel Mac OS X 10_15_7) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36",
    "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/150.0.0.0 Safari/537.36",
    "Mozilla/5.0 (iPhone; CPU iPhone OS 18_7 like Mac OS X) AppleWebKit/605.1.15 (KHTML, like Gecko) Version/27.0 Mobile/15E148 Safari/604.1",
    "Mozilla/5.0 (Linux; Android 10; K) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/152.0.0.0 Mobile Safari/537.36",
  ]) {
    assert.equal(isAutomatedBrowser({ ...linuxCrawler, userAgent }, crawlerViewport), false);
  }
});
