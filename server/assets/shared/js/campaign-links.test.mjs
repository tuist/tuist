import assert from "node:assert/strict";
import test from "node:test";

import { carryCampaign } from "./campaign-links.mjs";

const landing = "https://tuist.dev/pricing?utm_source=chatgpt.com&utm_campaign=business-hub";

test("carries the campaign to same-site links, keeping their own query", () => {
  assert.equal(
    carryCampaign("/users/register?plan=pro", landing),
    "https://tuist.dev/users/register?plan=pro&utm_source=chatgpt.com&utm_campaign=business-hub",
  );
});

test("leaves links to other sites alone", () => {
  assert.equal(carryCampaign("https://github.com/tuist/tuist", landing), null);
});

test("does nothing on a page without a campaign", () => {
  assert.equal(carryCampaign("/users/register", "https://tuist.dev/pricing?plan=pro"), null);
});

test("keeps a link's own campaign", () => {
  assert.equal(carryCampaign("/blog?utm_source=newsletter", landing), null);
});

test("leaves jumps within the page alone", () => {
  assert.equal(carryCampaign("#faq", landing), null);
});

test("carries ref, the source shorthand", () => {
  assert.equal(
    carryCampaign("/cache", "https://tuist.dev/?ref=producthunt"),
    "https://tuist.dev/cache?ref=producthunt",
  );
});
