import assert from "node:assert/strict";
import test from "node:test";

import { registerWebMCPTools } from "./webmcp.mjs";

const listProjects = {
  name: "list_projects",
  description: "Lists projects.",
  inputSchema: { type: "object", properties: {} },
  annotations: { title: "List Projects", readOnlyHint: true },
};

const json = (body, status = 200) => new Response(JSON.stringify(body), { status });
const rpcResult = (result) => json({ jsonrpc: "2.0", id: 1, result });

function fakeModelContext({ reject = [] } = {}) {
  const tools = new Map();
  return {
    tools,
    async registerTool(tool) {
      if (reject.includes(tool.name)) throw new TypeError(`Invalid tool ${tool.name}`);
      tools.set(tool.name, tool);
    },
  };
}

// Answers requests in order. Each answer is a Response, an Error to throw, or
// a function that returns or throws one.
function fakeFetch(...answers) {
  const requests = [];
  const fetch = async (url, init) => {
    requests.push({ url, init, body: JSON.parse(init.body) });
    const answer = answers.shift();
    if (answer instanceof Error) throw answer;
    return typeof answer === "function" ? answer() : answer;
  };
  return { fetch, requests };
}

async function registeredTool(callAnswer, tool = listProjects) {
  const modelContext = fakeModelContext();
  const { fetch, requests } = fakeFetch(rpcResult({ tools: [tool] }), callAnswer);
  await registerWebMCPTools({ modelContext, endpoint: "/api/webmcp", csrfToken: "csrf", fetch });
  return { tool: modelContext.tools.get(tool.name), requests };
}

test("does nothing without WebMCP or an endpoint", async () => {
  const { fetch, requests } = fakeFetch();

  assert.deepEqual(await registerWebMCPTools({ modelContext: undefined, endpoint: "/api/webmcp", fetch }), []);
  assert.deepEqual(await registerWebMCPTools({ modelContext: fakeModelContext(), endpoint: undefined, fetch }), []);
  assert.equal(requests.length, 0);
});

test("registers the listed tools with their schema and annotations", async () => {
  const modelContext = fakeModelContext();
  const { fetch, requests } = fakeFetch(rpcResult({ tools: [listProjects] }));

  const names = await registerWebMCPTools({ modelContext, endpoint: "/api/webmcp", csrfToken: "csrf", fetch });

  assert.deepEqual(names, ["list_projects"]);
  const tool = modelContext.tools.get("list_projects");
  assert.equal(tool.title, "List Projects");
  assert.deepEqual(tool.inputSchema, listProjects.inputSchema);
  assert.deepEqual(tool.annotations, { readOnlyHint: true, untrustedContentHint: true });
  assert.equal(requests[0].url, "/api/webmcp");
  assert.equal(requests[0].body.method, "tools/list");
  assert.equal(requests[0].init.headers["x-csrf-token"], "csrf");
});

test("sends no CSRF header when the page has no token", async () => {
  const { fetch, requests } = fakeFetch(rpcResult({ tools: [] }));

  await registerWebMCPTools({ modelContext: fakeModelContext(), endpoint: "/api/webmcp/public", fetch });

  assert.equal("x-csrf-token" in requests[0].init.headers, false);
});

test("a tool the browser rejects does not stop the others", async () => {
  const modelContext = fakeModelContext({ reject: ["bad_tool"] });
  const { fetch } = fakeFetch(rpcResult({ tools: [{ ...listProjects, name: "bad_tool" }, listProjects] }));

  assert.deepEqual(await registerWebMCPTools({ modelContext, endpoint: "/api/webmcp", fetch }), ["list_projects"]);
});

test("never rejects when the listing fails", async (t) => {
  t.mock.method(console, "warn", () => {});
  const answers = [
    new TypeError("Failed to fetch"),
    new Response("<html>Forbidden</html>", { status: 403 }),
    json({ message: "Sign in with your organization's single sign-on provider." }, 403),
    rpcResult({ unexpected: true }),
  ];

  for (const answer of answers) {
    const modelContext = fakeModelContext();
    const { fetch } = fakeFetch(answer);
    assert.deepEqual(await registerWebMCPTools({ modelContext, endpoint: "/api/webmcp", fetch }), []);
    assert.equal(modelContext.tools.size, 0);
  }
});

test("never rejects when the page has no document", async (t) => {
  t.mock.method(console, "warn", () => {});
  assert.deepEqual(await registerWebMCPTools(), []);
});

test("execute calls the tool and returns its structured content", async () => {
  const { tool, requests } = await registeredTool(rpcResult({ structuredContent: { projects: [] }, content: [] }));

  assert.deepEqual(await tool.execute({ page: 2 }, { signal: new AbortController().signal }), { projects: [] });
  assert.deepEqual(requests[1].body.params, { name: "list_projects", arguments: { page: 2 } });
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
