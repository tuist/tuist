import assert from "node:assert/strict";
import test from "node:test";

import { registerWebMCPTools } from "./webmcp.mjs";

const searchTuist = {
  name: "search_tuist",
  description: "Searches Tuist's documentation.",
  inputSchema: { type: "object", properties: { query: { type: "string" } } },
  annotations: { title: "Search Tuist", readOnlyHint: true },
};

const endpoint = "/api/webmcp/public";
const json = (body, status = 200) => new Response(JSON.stringify(body), { status });
const rpcResult = (result) => json({ jsonrpc: "2.0", id: 1, result });

function fakeModelContext({ reject = [] } = {}) {
  const tools = new Map();
  return {
    tools,
    registerTool(tool) {
      // Browsers may throw synchronously as well as reject.
      if (reject.includes(tool.name)) throw new TypeError(`Invalid tool ${tool.name}`);
      tools.set(tool.name, tool);
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

async function registeredTool(callAnswer) {
  const modelContext = fakeModelContext();
  const { fetch, requests } = fakeFetch(rpcResult({ tools: [searchTuist] }), callAnswer);
  await registerWebMCPTools({ modelContext, endpoint, fetch });
  return { tool: modelContext.tools.get(searchTuist.name), requests };
}

test("does nothing without WebMCP or an endpoint", async () => {
  const { fetch, requests } = fakeFetch();

  assert.deepEqual(await registerWebMCPTools({ modelContext: undefined, endpoint, fetch }), []);
  assert.deepEqual(await registerWebMCPTools({ modelContext: fakeModelContext(), endpoint: undefined, fetch }), []);
  assert.deepEqual(await registerWebMCPTools(), []);
  assert.equal(requests.length, 0);
});

test("registers the listed tools with their schema and annotations", async () => {
  const modelContext = fakeModelContext();
  const { fetch, requests } = fakeFetch(rpcResult({ tools: [searchTuist] }));

  assert.deepEqual(await registerWebMCPTools({ modelContext, endpoint, fetch }), ["search_tuist"]);

  const tool = modelContext.tools.get("search_tuist");
  assert.equal(tool.title, "Search Tuist");
  assert.deepEqual(tool.inputSchema, searchTuist.inputSchema);
  assert.deepEqual(tool.annotations, { readOnlyHint: true, untrustedContentHint: true });
  assert.equal(requests[0].url, endpoint);
  assert.equal(requests[0].body.method, "tools/list");
});

test("a tool the browser rejects does not stop the others", async () => {
  const modelContext = fakeModelContext({ reject: ["bad_tool"] });
  const { fetch } = fakeFetch(rpcResult({ tools: [{ ...searchTuist, name: "bad_tool" }, searchTuist] }));

  assert.deepEqual(await registerWebMCPTools({ modelContext, endpoint, fetch }), ["search_tuist"]);
});

test("never rejects when the listing fails", async (t) => {
  t.mock.method(console, "warn", () => {});
  const answers = [
    new TypeError("Failed to fetch"),
    new Response("<html>Forbidden</html>", { status: 403 }),
    json({ jsonrpc: "2.0", id: null, error: { code: -32_603, message: "Rate limit exceeded." } }, 429),
    rpcResult({ unexpected: true }),
  ];

  for (const answer of answers) {
    const modelContext = fakeModelContext();
    const { fetch } = fakeFetch(answer);
    assert.deepEqual(await registerWebMCPTools({ modelContext, endpoint, fetch }), []);
    assert.equal(modelContext.tools.size, 0);
  }
});

test("execute calls the tool and returns its structured content", async () => {
  const { tool, requests } = await registeredTool(rpcResult({ structuredContent: { results: [] }, content: [] }));

  assert.deepEqual(await tool.execute({ query: "cache" }, { signal: new AbortController().signal }), { results: [] });
  assert.deepEqual(requests[1].body.params, { name: "search_tuist", arguments: { query: "cache" } });
});

test("failures reach the agent as results with a message", async () => {
  const cases = [
    [rpcResult({ isError: true, content: [{ type: "text", text: "Search is unavailable" }] }), "Search is unavailable"],
    [
      json({ jsonrpc: "2.0", id: 1, error: { code: -32_602, message: "Tool not found: create_project" } }),
      "Tool not found: create_project",
    ],
    [
      json({ jsonrpc: "2.0", id: null, error: { code: -32_603, message: "Rate limit exceeded." } }, 429),
      "Rate limit exceeded.",
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
