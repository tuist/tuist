import assert from "node:assert/strict";
import test from "node:test";
import PageFavicon from "./PageFavicon.mjs";

test("page favicons follow outcomes and reset across live navigation", () => {
  const defaults = [
    { href: "/favicon.ico", sizes: "any" },
    { href: "/favicon.svg", type: "image/svg+xml" },
    { href: "/favicon-32x32.png", type: "image/png", sizes: "32x32" },
    { href: "/favicon-16x16.png", type: "image/png", sizes: "16x16" },
  ];
  const paths = {
    "data-favicon-success": "/images/favicon-success-ab123.png?vsn=d",
    "data-favicon-failure": "/images/favicon-failure-cd456.png?vsn=d",
    "data-favicon-in-progress": "/images/favicon-in-progress-ef789.png?vsn=d",
  };
  const icons = defaults.map((attributes) => ({
    attributes: { ...attributes },
    getAttribute(name) {
      return paths[name] ?? this.attributes[name] ?? null;
    },
    setAttribute(name, value) {
      this.attributes[name] = value;
    },
    removeAttribute(name) {
      delete this.attributes[name];
    },
  }));
  const previousDocument = globalThis.document;
  globalThis.document = { querySelectorAll: () => icons };
  const page = { el: { dataset: { faviconStatus: "processing" } } };
  const nextPage = { el: { dataset: { faviconStatus: "failure" } } };
  const assertDefault = () =>
    assert.deepEqual(
      icons.map((icon) => icon.attributes),
      defaults,
    );
  const assertOutcome = (status) => {
    for (const icon of icons) {
      assert.deepEqual(icon.attributes, {
        href: paths[`data-favicon-${status}`],
        type: "image/png",
        sizes: "32x32",
      });
    }
  };

  try {
    PageFavicon.mounted.call(page);
    assertOutcome("in-progress");
    for (const status of ["success", "failure"]) {
      page.el.dataset.faviconStatus = status;
      PageFavicon.updated.call(page);
      assertOutcome(status);
    }
    for (const status of ["processing", "in_progress"]) {
      page.el.dataset.faviconStatus = status;
      PageFavicon.updated.call(page);
      assertOutcome("in-progress");
    }
    for (const status of ["cancelled", "skipped", "interrupted", "unknown", "failed_processing", undefined]) {
      page.el.dataset.faviconStatus = status;
      PageFavicon.updated.call(page);
      assertDefault();
    }
    page.el.dataset.faviconStatus = "success";
    PageFavicon.updated.call(page);
    assertOutcome("success");
    PageFavicon.mounted.call(nextPage);
    PageFavicon.destroyed.call(page);
    PageFavicon.updated.call(page);
    assertOutcome("failure");
    PageFavicon.destroyed.call(nextPage);
    assertDefault();
    PageFavicon.mounted.call(page);
    assertOutcome("success");
    PageFavicon.destroyed.call(page);
    assertDefault();
  } finally {
    globalThis.document = previousDocument;
  }
});
