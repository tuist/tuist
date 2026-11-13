import assert from "node:assert/strict";
import test from "node:test";
import DashboardSearch, {
  matchingPages,
  searchShortcut,
  projectDestinations,
  filterSuggestions,
  queryParts,
  navigationStep,
} from "./DashboardSearch.mjs";

const pages = [
  { title: "Billing settings", description: "acme", path: "/acme/settings/billing" },
  { title: "Billing", description: "acme", path: "/acme/billing" },
  { title: "Authentication", description: "acme SSO SCIM OIDC", path: "/acme/settings/authentication" },
  {
    title: "Integrations",
    description: "Connect repositories",
    keywords: "GitHub Origin",
    path: "/acme/settings/integrations",
  },
];

test("searches page titles, aliases and context, ranking an exact title ahead of prefixes", () => {
  assert.deepEqual(
    matchingPages(pages, "BILLING").map((page) => page.title),
    ["Billing", "Billing settings"],
  );
  assert.equal(matchingPages(pages, "sso acme")[0].path, "/acme/settings/authentication");
  assert.equal(matchingPages(pages, "/acme/settings/integrations")[0].title, "Integrations");
  assert.equal(matchingPages(pages, "github")[0].title, "Integrations");
  assert.equal(
    matchingPages(
      [{ title: "Integrations", hierarchy: "Settings", description: "", path: "/destination" }],
      "settings integrations",
    )[0].path,
    "/destination",
  );
  assert.deepEqual(matchingPages(pages, "sso other-account"), []);
});

test("empty search resolves recent visits against authorized pages without filter or help clutter", () => {
  const context = {
    input: { value: "", selectionStart: 0 },
    filters: [],
    projects: [],
    catalogLoaded: true,
    preferred: null,
    recentPages: ["/other/private", "/acme/settings/integrations", "/acme/billing"],
    el: { dataset: { pages: JSON.stringify(pages) } },
    labels: { documentation: "Documentation" },
    resources: [],
    queryError: null,
  };
  const results = DashboardSearch.searchResults.call(context);
  assert.deepEqual(
    results.slice(0, 2).map((result) => result.path),
    ["/acme/settings/integrations", "/acme/billing"],
  );
  assert.ok(results.every((result) => result.type === "page"));
  assert.deepEqual(
    results.map((result) => result.group),
    [...Array(2).fill("recent"), ...Array(results.length - 2).fill(undefined)],
  );
  assert.equal(new Set(results.map((result) => result.path)).size, results.length);
  assert.ok(!results.some((result) => result.path === "/other/private"));
  context.resources = [{ type: "project", title: "ios", path: "/acme/ios" }];
  assert.deepEqual(DashboardSearch.searchResults.call(context), results);
});

test("project pages stay scoped, hide redundant projects and allow an explicit project switch", () => {
  const projects = ["ios", "android"].map((name) => ({
    name,
    pages: [{ title: "Builds", description: "", project: name, destination: "/builds", path: `/acme/${name}/builds` }],
  }));
  const context = {
    input: { value: "", selectionStart: 0 },
    filters: [],
    projects,
    catalogLoaded: true,
    recentPages: ["/acme/android/builds"],
    el: { dataset: { project: "ios", pages: "[]" } },
    labels: { documentation: "Documentation" },
    resources: [{ type: "project", title: "ios", path: "/acme/ios" }],
  };
  assert.deepEqual(
    DashboardSearch.searchResults.call(context).map((r) => r.path),
    ["/acme/ios/builds"],
  );
  context.input.value = "project:android ";
  const switched = DashboardSearch.searchResults.call(context);
  assert.deepEqual(
    switched.map((r) => r.path),
    ["/acme/android/builds"],
  );
  assert.equal(switched[0].projectBadge, null);
  context.el.dataset.project = "";
  context.input.value = "";
  assert.deepEqual(
    DashboardSearch.searchResults.call(context).map((r) => r.path),
    [],
  );
  context.input.value = "ios";
  assert.deepEqual(
    DashboardSearch.searchResults.call(context).map((r) => r.path),
    ["/acme/ios"],
  );
});

test("Command-K and Ctrl-K work without consuming repeated, composed or remote-session keys", () => {
  const key = { key: "k", metaKey: true };
  assert.equal(searchShortcut(key), true);
  assert.equal(searchShortcut({ key: "K", ctrlKey: true }), true);
  for (const change of [
    { metaKey: false },
    { repeat: true },
    { isComposing: true },
    { altKey: true },
    { shiftKey: true },
    { key: "j" },
    { target: { closest: () => ({}) } },
  ]) {
    assert.equal(searchShortcut({ ...key, ...change }), false);
  }
});

test("page destinations use the preferred project without substituting unsupported or unauthorized projects", () => {
  const projects = [
    {
      name: "ios",
      pages: [
        { title: "Test Runs", destination: "/tests/test-runs", path: "/acme/ios/tests/test-runs" },
        { title: "Xcode Cache", destination: "/xcode-cache", path: "/acme/ios/xcode-cache" },
      ],
    },
    {
      name: "native",
      pages: [{ title: "Test Runs", destination: "/tests/test-runs", path: "/acme/native/once/test-runs" }],
    },
  ];
  assert.deepEqual(
    projectDestinations(projects, "native").map(({ path, project }) => ({ path, project })),
    [
      { path: "/acme/native/once/test-runs", project: "native" },
      { path: null, project: null },
    ],
  );
  assert.equal(projectDestinations(projects, "removed")[0].path, null);
  assert.deepEqual(projectDestinations(projects, "ios", "removed"), []);
  assert.equal(projectDestinations(projects, "ios", "native")[0].path, "/acme/native/once/test-runs");
});

test("filter completion preserves terms and other filters and replaces only the edited token", () => {
  const definitions = ["is", "project", "branch", "status", "date", "commit", "pr"].map((key) => ({
    key,
    example: `${key}:example`,
    description: key,
  }));
  const query = 'login branch:"release candidate" is:te';
  assert.deepEqual(filterSuggestions("", 0, definitions, []), []);
  assert.deepEqual(filterSuggestions("settings ", 9, definitions, []), []);
  assert.deepEqual(filterSuggestions("settings", 8, definitions, []), []);
  assert.equal(filterSuggestions("pro", 3, definitions, [])[0].title, "project:");
  const suggestions = filterSuggestions(query, query.length, definitions, []);
  assert.deepEqual(
    suggestions.map((item) => item.query),
    ['login branch:"release candidate" is:test-case', 'login branch:"release candidate" is:test-run'],
  );
  assert.equal(filterSuggestions("pr:", 3, definitions, []).length, 0);
  assert.equal(
    filterSuggestions("pr:42 ", 6, definitions, []).some((item) => item.title === "pr:"),
    false,
  );
  const middle = "is:b status:failed";
  assert.equal(filterSuggestions(middle, 4, definitions, [])[0].query, "is:build status:failed");
  assert.equal(
    filterSuggestions("project:n", 9, definitions, [{ name: "native app" }])[0].query,
    'project:"native app"',
  );
  assert.deepEqual(queryParts("Tests project:ios is:page"), {
    terms: ["Tests"],
    filters: { project: "ios", is: "page" },
    valid: true,
  });
  assert.equal(queryParts('project:"unfinished').valid, false);
  assert.equal(queryParts("status:failed status:passed").valid, false);
  assert.equal(matchingPages(pages, "billing is:page")[0].title, "Billing");
});

test("throttling honors Retry-After without retry storms and recovers on the next search", async (t) => {
  const message = { textContent: "" };
  const context = {
    sequence: 0,
    input: { value: "settings", setAttribute() {} },
    dialog: { open: true },
    el: { dataset: { endpoint: "/search" } },
    status: { removeAttribute() {}, setAttribute() {} },
    empty: {},
    error: { hidden: true, querySelector: () => message },
    labels: { loading: "Loading", unavailable: "Unavailable", throttled: "Try again shortly" },
    stopSearch() {
      this.sequence++;
      this.loading = false;
    },
    render() {},
  };
  t.mock.method(globalThis, "fetch", async () => ({
    status: 429,
    ok: false,
    headers: new Headers({ "retry-after": "2" }),
  }));
  const originalDocument = globalThis.document;
  globalThis.document = { querySelector: () => ({ content: "csrf" }) };
  t.after(() => {
    if (originalDocument === undefined) delete globalThis.document;
    else globalThis.document = originalDocument;
  });
  t.mock.method(Date, "now", () => 1000);

  await DashboardSearch.load.call(context);
  assert.equal(context.retryAt, 3000);
  assert.equal(context.loading, false);
  assert.equal(context.error.hidden, false);
  assert.equal(message.textContent, "Try again shortly");
  context.input.value = "builds";
  await DashboardSearch.load.call(context);
  assert.equal(fetch.mock.callCount(), 1);

  Date.now.mock.mockImplementation(() => 3000);
  fetch.mock.mockImplementation(async () => ({
    status: 200,
    ok: true,
    json: async () => ({ results: [{ title: "Build" }], unavailable: [] }),
  }));
  await DashboardSearch.load.call(context);
  assert.equal(fetch.mock.callCount(), 2);
  assert.deepEqual(context.resources, [{ title: "Build" }]);
  assert.equal(context.error.hidden, true);
});

test("only arrow keys navigate, leaving J/K typing and shortcuts untouched", () => {
  for (const key of ["j", "k", "J", "K"]) {
    assert.equal(navigationStep({ key }), 0);
    assert.equal(navigationStep({ key, ctrlKey: true }), 0);
  }
  assert.equal(navigationStep({ key: "ArrowDown" }), 1);
  assert.equal(navigationStep({ key: "ArrowUp" }), -1);
  assert.equal(navigationStep({ key: "ArrowDown", metaKey: true }), 0);
  assert.equal(navigationStep({ key: "ArrowUp", isComposing: true }), 0);
});
