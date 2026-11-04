import assert from "node:assert/strict";
import test from "node:test";

import { registerNavigationTools, registerWebMCPTools } from "./webmcp.mjs";

const listProjects = {
  name: "list_projects",
  description: "Lists projects.",
  inputSchema: { type: "object", properties: {} },
  annotations: { title: "List Projects", readOnlyHint: true },
};

const accountEndpoint = "/api/webmcp/accounts/acme";
const json = (body, status = 200) => new Response(JSON.stringify(body), { status });
const rpcResult = (result) => json({ jsonrpc: "2.0", id: 1, result });
const listing = (...names) => rpcResult({ tools: names.map((name) => ({ ...listProjects, name })) });
const settle = () => new Promise((resolve) => setTimeout(resolve));

function fakeModelContext({ reject = [] } = {}) {
  const tools = new Map();
  return {
    tools,
    registerTool(tool, { signal } = {}) {
      // Browsers may throw synchronously as well as reject.
      if (reject.includes(tool.name)) throw new TypeError(`Invalid tool ${tool.name}`);
      if (signal?.aborted) return Promise.reject(signal.reason);
      if (tools.has(tool.name)) return Promise.reject(new DOMException(`Duplicate ${tool.name}`, "InvalidStateError"));
      tools.set(tool.name, tool);
      signal?.addEventListener("abort", () => tools.delete(tool.name));
      return Promise.resolve();
    },
  };
}

// Answers requests in order. Each answer is a Response or an Error to throw.
function fakeFetch(...answers) {
  const requests = [];
  const fetch = async (url, init) => {
    requests.push({ url, init, body: JSON.parse(init.body) });
    const answer = answers.shift();
    if (answer instanceof Error) throw answer;
    return answer;
  };
  return { fetch, requests };
}

const register = (options) =>
  registerWebMCPTools({ target: new EventTarget(), endpoint: () => accountEndpoint, ...options });

async function registeredTool(callAnswer) {
  const modelContext = fakeModelContext();
  const { fetch, requests } = fakeFetch(listing("list_projects"), callAnswer);
  await register({ modelContext, csrfToken: "csrf", fetch });
  return { tool: modelContext.tools.get("list_projects"), requests };
}

test("does nothing without WebMCP or an endpoint", async () => {
  const { fetch, requests } = fakeFetch();

  assert.deepEqual(await register({ modelContext: undefined, fetch }), []);
  assert.deepEqual(await register({ modelContext: fakeModelContext(), endpoint: () => undefined, fetch }), []);
  assert.deepEqual(await registerWebMCPTools(), []);
  assert.equal(requests.length, 0);
});

test("registers the listed tools with their schema and annotations", async () => {
  const modelContext = fakeModelContext();
  const { fetch, requests } = fakeFetch(listing("list_projects"));

  assert.deepEqual(await register({ modelContext, csrfToken: "csrf", fetch }), ["list_projects"]);

  const tool = modelContext.tools.get("list_projects");
  assert.equal(tool.title, "List Projects");
  assert.deepEqual(tool.inputSchema, listProjects.inputSchema);
  assert.deepEqual(tool.annotations, { readOnlyHint: true, untrustedContentHint: true });
  assert.equal(requests[0].url, accountEndpoint);
  assert.equal(requests[0].body.method, "tools/list");
  assert.equal(requests[0].init.headers["x-csrf-token"], "csrf");
});

test("sends no CSRF header when the page has no token", async () => {
  const { fetch, requests } = fakeFetch(listing());

  await register({ modelContext: fakeModelContext(), fetch });

  assert.equal("x-csrf-token" in requests[0].init.headers, false);
});

test("a tool the browser rejects does not stop the others", async () => {
  const modelContext = fakeModelContext({ reject: ["bad_tool"] });
  const { fetch } = fakeFetch(listing("bad_tool", "list_projects"));

  assert.deepEqual(await register({ modelContext, fetch }), ["list_projects"]);
});

test("never rejects when the listing fails", async (t) => {
  t.mock.method(console, "warn", () => {});
  const answers = [
    new TypeError("Failed to fetch"),
    new Response("<html>Forbidden</html>", { status: 403 }),
    json({ message: "Sign in with this organization's single sign-on provider." }, 403),
    rpcResult({ unexpected: true }),
  ];

  for (const answer of answers) {
    const modelContext = fakeModelContext();
    const { fetch } = fakeFetch(answer);
    assert.deepEqual(await register({ modelContext, fetch }), []);
    assert.equal(modelContext.tools.size, 0);
  }
});

test("replaces the tools when navigation changes the page's endpoint", async () => {
  const modelContext = fakeModelContext();
  const target = new EventTarget();
  let endpoint = accountEndpoint;
  const { fetch, requests } = fakeFetch(listing("acme_tool"), listing("other_tool"));
  const navigate = async () => {
    target.dispatchEvent(new Event("phx:page-loading-stop"));
    await settle();
  };

  assert.deepEqual(await registerWebMCPTools({ modelContext, target, endpoint: () => endpoint, fetch }), ["acme_tool"]);

  // A navigation within the account keeps the registered tools.
  await navigate();
  assert.equal(requests.length, 1);

  // A live redirect stops loading before the next view renders its endpoint.
  endpoint = undefined;
  target.dispatchEvent(new CustomEvent("phx:page-loading-stop", { detail: { kind: "redirect" } }));
  assert.equal(requests.length, 1);
  assert.deepEqual([...modelContext.tools.keys()], ["acme_tool"]);

  endpoint = "/api/webmcp/accounts/other";
  await navigate();
  assert.deepEqual([...modelContext.tools.keys()], ["other_tool"]);
  assert.equal(requests[1].url, "/api/webmcp/accounts/other");
});

test("a failed listing is retried at the next navigation, an empty one is not", async (t) => {
  t.mock.method(console, "warn", () => {});
  const modelContext = fakeModelContext();
  const target = new EventTarget();
  const { fetch, requests } = fakeFetch(
    json({ jsonrpc: "2.0", id: null, error: { code: -32_603, message: "Rate limit exceeded." } }, 429),
    listing(),
  );

  assert.deepEqual(await register({ modelContext, target, fetch }), []);

  target.dispatchEvent(new Event("phx:page-loading-stop"));
  await settle();
  target.dispatchEvent(new Event("phx:page-loading-stop"));
  await settle();

  assert.equal(requests.length, 2);
});

test("a navigation during the listing drops the stale endpoint's tools", async () => {
  const modelContext = fakeModelContext();
  const target = new EventTarget();
  let endpoint = accountEndpoint;
  let answerAcme;
  const fetch = async (url, init) => {
    if (url.endsWith("/other")) return listing("other_tool");
    return new Promise((resolve, reject) => {
      init.signal.addEventListener("abort", () => reject(new DOMException("Aborted", "AbortError")));
      answerAcme = () => resolve(listing("acme_tool"));
    });
  };

  const acme = registerWebMCPTools({ modelContext, target, endpoint: () => endpoint, fetch });
  endpoint = "/api/webmcp/accounts/other";
  target.dispatchEvent(new Event("phx:page-loading-stop"));
  answerAcme();

  assert.deepEqual(await acme, []);
  await settle();
  assert.deepEqual([...modelContext.tools.keys()], ["other_tool"]);
});

test("execute calls the tool and returns its structured content", async () => {
  const { tool, requests } = await registeredTool(rpcResult({ structuredContent: { projects: [] }, content: [] }));

  assert.deepEqual(await tool.execute({ page: 2 }, { signal: new AbortController().signal }), { projects: [] });
  assert.deepEqual(requests[1].body.params, { name: "list_projects", arguments: { page: 2 } });
  assert.equal(requests[1].init.headers["x-csrf-token"], "csrf");
});

test("failures reach the agent as results with a message", async () => {
  const cases = [
    [rpcResult({ isError: true, content: [{ type: "text", text: "Project not found" }] }), "Project not found"],
    [
      json({ jsonrpc: "2.0", id: 1, error: { code: -32_602, message: "Tool not found: create_project" } }),
      "Tool not found: create_project",
    ],
    [
      json({ jsonrpc: "2.0", id: null, error: { code: -32_603, message: "Rate limit exceeded." } }, 429),
      "Rate limit exceeded.",
    ],
    [
      json({ message: "You need to be authenticated to access this resource." }, 401),
      "You need to be authenticated to access this resource.",
    ],
    [
      new Response("<html>Forbidden</html>", { status: 403 }),
      "Tuist answered with HTTP status 403. Reload the page to refresh your session.",
    ],
    [new Response("Bad gateway", { status: 502 }), "Tuist answered with HTTP status 502."],
    [new TypeError("Failed to fetch"), "Could not reach Tuist: Failed to fetch"],
  ];

  for (const [answer, message] of cases) {
    const { tool } = await registeredTool(answer);
    assert.deepEqual(await tool.execute({}), { isError: true, error: message });
  }
});

test("an aborted call rejects with the abort", async () => {
  const { tool } = await registeredTool(new DOMException("The operation was aborted.", "AbortError"));

  await assert.rejects(tool.execute({}), { name: "AbortError" });
});

// A dashboard page with the elements the navigation tools read, keyed by the
// selectors they use.
function fakeDashboard({ endpoint = accountEndpoint } = {}) {
  const clicks = [];
  const link = (href, label, { live = true, group } = {}) => ({
    href,
    label,
    getAttribute: (name) => ({ href, "data-label": label })[name] ?? null,
    hasAttribute: (name) => name === "data-phx-link" && live,
    querySelector: (selector) => (selector === "[data-part='label']" ? { textContent: ` ${label} ` } : null),
    closest: (selector) => (selector === "[data-part='collapsible-group']" ? (group ?? null) : null),
    click: () => clicks.push(href),
  });
  const buildsHeader = link("/acme/app/builds", "Builds");
  const builds = { querySelector: () => buildsHeader };
  Object.assign(buildsHeader, link("/acme/app/builds", "Builds", { group: builds }));

  const sidebar = [
    link("/acme/app", "Overview"),
    buildsHeader,
    link("/acme/app/builds/build-runs", "Build Runs", { group: builds }),
  ];
  const breadcrumb = (items) => ({
    querySelectorAll: (selector) => (selector === "[data-part='items'] a[href^='/']" ? items : []),
  });
  const headerbar = {
    querySelectorAll: (selector) =>
      selector === ".noora-breadcrumb"
        ? [
            breadcrumb([
              link("/acme/projects", "acme", { live: false }),
              link("/other/projects", "other", { live: false }),
            ]),
            breadcrumb([link("/acme/app", "app", { live: false }), link("/acme/web", "web", { live: false })]),
          ]
        : [],
  };
  const document = {
    querySelector: (selector) => (selector === "header[data-webmcp-endpoint]" && endpoint ? headerbar : null),
    querySelectorAll: (selector) => (selector === ".layout .noora-sidebar a[href^='/']" ? sidebar : []),
  };
  return { document, clicks };
}

async function navigationTools(options = {}) {
  const modelContext = fakeModelContext();
  const { document, clicks } = fakeDashboard(options);
  const target = new EventTarget();
  const location = { pathname: "/acme/app/builds/build-runs", search: "" };
  const names = await registerNavigationTools({ modelContext, document, location, target, timeout: 50, ...options });
  return { names, tools: modelContext.tools, clicks, target, location };
}

test("registers navigation tools only on signed-in dashboard pages", async () => {
  assert.deepEqual((await navigationTools()).names, ["list_dashboard_pages", "navigate_to_dashboard_page"]);
  assert.deepEqual((await navigationTools({ endpoint: null })).names, []);
  assert.deepEqual(await registerNavigationTools({ modelContext: undefined }), []);
});

test("lists the sidebar's pages and the breadcrumbs' accounts and projects once each", async () => {
  const { tools } = await navigationTools();
  const { pages } = await tools.get("list_dashboard_pages").execute({});

  assert.deepEqual(pages, [
    { path: "/acme/app", title: "Overview", description: "Overview", current: false },
    { path: "/acme/app/builds", title: "Builds", description: "Builds", current: false },
    { path: "/acme/app/builds/build-runs", title: "Build Runs", description: "Builds › Build Runs", current: true },
    { path: "/acme/projects", title: "acme", description: "The acme account", current: false },
    { path: "/other/projects", title: "other", description: "The other account", current: false },
    // The current project's breadcrumb entry is the Overview link above.
    { path: "/acme/web", title: "web", description: "The web project", current: false },
  ]);
});

test("navigates only to listed pages, and resolves once a live navigation has rendered", async () => {
  const { tools, clicks, target, location } = await navigationTools();
  const navigate = tools.get("navigate_to_dashboard_page");

  assert.deepEqual(await navigate.execute({ path: "/acme/app/settings/tokens" }), {
    isError: true,
    error: "/acme/app/settings/tokens is not a page list_dashboard_pages offers from here.",
  });
  assert.deepEqual(clicks, []);

  let resolved = false;
  const navigation = navigate.execute({ path: "/acme/app" }).then((result) => {
    resolved = true;
    return result;
  });
  assert.deepEqual(clicks, ["/acme/app"]);

  // The redirect's own stop comes before the new view renders.
  target.dispatchEvent(new CustomEvent("phx:page-loading-stop", { detail: { kind: "redirect" } }));
  await settle();
  assert.equal(resolved, false);

  location.pathname = "/acme/app";
  target.dispatchEvent(new CustomEvent("phx:page-loading-stop", { detail: { kind: "initial" } }));
  assert.deepEqual(await navigation, { path: "/acme/app", title: "Overview" });

  // A link that loads a new document does not wait for LiveView.
  assert.deepEqual(await navigate.execute({ path: "/other/projects" }), {
    path: "/other/projects",
    title: "other",
    reloading: true,
  });
  assert.deepEqual(clicks, ["/acme/app", "/other/projects"]);
});
