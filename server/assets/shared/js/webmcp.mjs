// WebMCP (https://webmachinelearning.github.io/webmcp) lets agents built into
// the browser call tools a page registers. Pages name a Tuist endpoint that
// serves the tools to register: an account's read-only tools on signed-in
// dashboard pages (`data-webmcp-endpoint` on the headerbar, which changes as
// LiveView navigates between accounts), and the documentation tools elsewhere
// (the `webmcp-endpoint` meta tag).
//
// Registration is a progressive enhancement: it never throws or rejects, so
// nothing that goes wrong here can affect the page.

// Registers the tools of the page's endpoint, and replaces them whenever a
// LiveView navigation changes that endpoint.
export function registerWebMCPTools({ target = globalThis, endpoint = currentEndpoint, ...options } = {}) {
  let registration;

  const sync = () => {
    try {
      const next = endpoint();
      if (registration && next === registration.endpoint) return registration.tools;

      // Aborting unregisters the previous endpoint's tools before the new
      // ones, which mostly share their names, are registered.
      registration?.controller.abort();
      const controller = new AbortController();
      const tools = registerEndpointTools({ ...options, endpoint: next, signal: controller.signal });
      registration = { endpoint: next, controller, tools };
      return tools;
    } catch (error) {
      console.warn("Could not register Tuist's WebMCP tools", error);
      return Promise.resolve([]);
    }
  };

  try {
    // A live redirect stops loading before the new view renders, so its
    // endpoint is only known at the `initial` stop that follows.
    target.addEventListener?.("phx:page-loading-stop", (event) => event.detail?.kind !== "redirect" && sync());
  } catch (error) {
    console.warn("Could not follow page navigation for Tuist's WebMCP tools", error);
  }
  return sync();
}

// Registers the tools one endpoint serves until `signal` aborts, and resolves
// to their names.
export async function registerEndpointTools(options = {}) {
  try {
    return await register(options);
  } catch (error) {
    if (error?.name !== "AbortError") console.warn("Could not register Tuist's WebMCP tools", error);
    return [];
  }
}

async function register({
  modelContext = globalThis.document?.modelContext,
  endpoint,
  csrfToken = metaContent("csrf-token"),
  fetch = globalThis.fetch,
  signal,
}) {
  if (!modelContext?.registerTool || !endpoint) return [];

  const call = (method, params, callSignal) => request({ fetch, endpoint, csrfToken }, method, params, callSignal);
  const { result, error } = await call("tools/list", {}, signal);
  if (error) throw new Error(error);

  const registrations = await Promise.allSettled(
    result.tools.map((tool) => modelContext.registerTool(webMCPTool(tool, call), { signal }).then(() => tool.name)),
  );
  return registrations.filter(({ status }) => status === "fulfilled").map(({ value }) => value);
}

const webMCPTool = (tool, call) => ({
  name: tool.name,
  title: tool.annotations?.title,
  description: tool.description,
  inputSchema: tool.inputSchema,
  // Results carry content that builds, tests and community posts produce.
  annotations: { readOnlyHint: tool.annotations?.readOnlyHint === true, untrustedContentHint: true },

  // WebMCP reports a rejected `execute` to the agent as a bare OperationError,
  // so failures are returned as results that keep their message.
  async execute(args, { signal } = {}) {
    const { result, error } = await call("tools/call", { name: tool.name, arguments: args ?? {} }, signal);
    if (error) return { isError: true, error };
    if (result.isError) return { isError: true, error: contentText(result.content) };
    return result.structuredContent ?? result.content;
  },
});

let lastRequestId = 0;

async function request({ fetch, endpoint, csrfToken }, method, params, signal) {
  let response;
  try {
    response = await fetch(endpoint, {
      method: "POST",
      headers: {
        "content-type": "application/json",
        accept: "application/json",
        ...(csrfToken && { "x-csrf-token": csrfToken }),
      },
      body: JSON.stringify({ jsonrpc: "2.0", id: ++lastRequestId, method, params }),
      credentials: "same-origin",
      signal,
    });
  } catch (error) {
    if (error?.name === "AbortError") throw error;
    return { error: `Could not reach Tuist: ${error?.message ?? error}` };
  }

  // JSON-RPC and rate-limit errors carry `error.message`, authentication
  // errors `message`, and CSRF failures are not JSON at all.
  const body = await response.json().catch(() => null);
  if (body?.result) return { result: body.result };

  const reload = [401, 403].includes(response.status) ? " Reload the page to refresh your session." : "";
  return {
    error: body?.error?.message ?? body?.message ?? `Tuist answered with HTTP status ${response.status}.${reload}`,
  };
}

const contentText = (content = []) =>
  content.map((item) => (item.type === "text" ? item.text : JSON.stringify(item))).join("\n") || "The tool failed.";

const currentEndpoint = () =>
  globalThis.document?.querySelector("[data-webmcp-endpoint]")?.getAttribute("data-webmcp-endpoint") ??
  metaContent("webmcp-endpoint");

const metaContent = (name) => globalThis.document?.querySelector(`meta[name='${name}']`)?.getAttribute("content");
