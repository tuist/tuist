import { expect, open, test } from "nsh/test";

for (const [kind, title] of [
  ["test_results", "17 tests passed"],
  ["change_summary", "Ready for review"],
]) {
  test(`${kind} shows response data and expands details`, async () => {
    const app = await open("./App.tsx", {
      host: {
        params: {
          kind,
          title,
          summary: "A focused change in the selected worktree.",
          facts: [{ label: "Changed file", value: "CacheDiagnostics.swift" }],
          details: ["The unchanged-target control still reports a cache hit."],
        },
        handlers: { "layout.height": () => null },
      },
    });
    expect(app.shows(title)).toBe(true);
    expect(app.shows("CacheDiagnostics.swift")).toBe(true);
    expect(app.shows("The unchanged-target control still reports a cache hit.")).toBe(false);
    await app.press("Show card details");
    expect(app.shows("The unchanged-target control still reports a cache hit.")).toBe(true);
    await app.press("Hide card details");
    expect(app.shows("The unchanged-target control still reports a cache hit.")).toBe(false);
  });
}
