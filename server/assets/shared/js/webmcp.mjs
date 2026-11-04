// WebMCP (https://webmachinelearning.github.io/webmcp) lets agents built into
// the browser call tools a page registers. Pages name the Tuist endpoint that
// serves those tools: an account's read-only tools on its signed-in dashboard
// pages (`data-webmcp-endpoint` on the headerbar, which changes as LiveView
// navigates between accounts), and the documentation tools elsewhere (the
// `webmcp-endpoint` meta tag).
//
// Registration is a progressive enhancement: it never throws or rejects, so
// nothing that goes wrong here can affect the page.

// Registers the tools of the page's endpoint, replaces them whenever a LiveView
// navigation changes that endpoint, and resolves to the names it registered.
export function registerWebMCPTools({ target = globalThis, endpoint = currentEndpoint, ...options } = {}) {
  let registration;

  const sync = () => {
    const next = endpoint();
    if (registration && next === registration.endpoint) return registration.tools;

    // Aborting unregisters the previous endpoint's tools before the new ones,
    // which mostly share their names, are registered.
    registration?.controller.abort();
    const controller = new AbortController();
    const current = { endpoint: next, controller };
    current.tools = registerEndpointTools({ ...options, endpoint: next, signal: controller.signal }).catch((error) => {
      // A listing that failed, for example on a rate limit, is retried at the
      // next navigation instead of leaving the page without tools.
      if (registration === current) registration = undefined;
      if (error?.name !== "AbortError") console.warn("Could not register Tuist's WebMCP tools", error);
      return [];
    });
    registration = current;
    return current.tools;
  };

  // A live redirect stops loading before the new view renders, so its endpoint
  // is only known at the `initial` stop that follows.
  target.addEventListener?.("phx:page-loading-stop", (event) => event.detail?.kind !== "redirect" && sync());
  return sync();
}

// Registers the tools one endpoint serves until `signal` aborts. Rejects when
// the listing fails.
async function registerEndpointTools({
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

  // A tool the browser refuses does not keep the others from registering.
  const registrations = await Promise.allSettled(
    result.tools.map(async (tool) => {
      await modelContext.registerTool(webMCPTool(tool, call), { signal });
      return tool.name;
    }),
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

// Resolves to the JSON-RPC result or an error message. Only an abort rejects.
async function request({ fetch, endpoint, csrfToken }, method, params, signal) {
  let response;
  try {
    response = await fetch(endpoint, {
      method: "POST",
      // The session's CSRF token authorizes account endpoints; the public one
      // ignores it.
      headers: {
        "content-type": "application/json",
        accept: "application/json",
        ...(csrfToken && { "x-csrf-token": csrfToken }),
      },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
      signal,
    });
  } catch (error) {
    if (error?.name === "AbortError") throw error;
    return { error: `Could not reach Tuist: ${error?.message ?? error}` };
  }

  // JSON-RPC and rate-limit errors carry `error.message`, authentication and
  // SSO errors `message`, and CSRF failures are not JSON at all.
  const body = await response.json().catch((error) => {
    if (error?.name === "AbortError") throw error;
    return null;
  });
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
