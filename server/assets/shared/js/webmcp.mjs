// WebMCP (https://webmachinelearning.github.io/webmcp) lets agents built into
// the browser call tools a page registers. Pages name the Tuist endpoint that
// serves those tools in the `webmcp-endpoint` meta tag.
//
// Registration is a progressive enhancement: it never throws or rejects, so
// nothing that goes wrong here can affect the page. It resolves to the names of
// the tools it registered.
export async function registerWebMCPTools({
  modelContext = globalThis.document?.modelContext,
  endpoint = globalThis.document?.querySelector("meta[name='webmcp-endpoint']")?.getAttribute("content"),
  fetch = globalThis.fetch,
} = {}) {
  if (!modelContext?.registerTool || !endpoint) return [];

  try {
    const call = (method, params, signal) => request({ fetch, endpoint }, method, params, signal);
    const { result, error } = await call("tools/list", {});
    if (error) throw new Error(error);

    // A tool the browser refuses does not keep the others from registering.
    const registrations = await Promise.allSettled(
      result.tools.map(async (tool) => {
        await modelContext.registerTool(webMCPTool(tool, call));
        return tool.name;
      }),
    );
    return registrations.filter(({ status }) => status === "fulfilled").map(({ value }) => value);
  } catch (error) {
    console.warn("Could not register Tuist's WebMCP tools", error);
    return [];
  }
}

const webMCPTool = (tool, call) => ({
  name: tool.name,
  title: tool.annotations?.title,
  description: tool.description,
  inputSchema: tool.inputSchema,
  // Results carry content that other people write, such as community posts.
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
async function request({ fetch, endpoint }, method, params, signal) {
  let response;
  try {
    response = await fetch(endpoint, {
      method: "POST",
      headers: { "content-type": "application/json", accept: "application/json" },
      body: JSON.stringify({ jsonrpc: "2.0", id: 1, method, params }),
      signal,
    });
  } catch (error) {
    if (error?.name === "AbortError") throw error;
    return { error: `Could not reach Tuist: ${error?.message ?? error}` };
  }

  const body = await response.json().catch((error) => {
    if (error?.name === "AbortError") throw error;
    return null;
  });
  if (body?.result) return { result: body.result };
  return { error: body?.error?.message ?? `Tuist answered with HTTP status ${response.status}.` };
}

const contentText = (content = []) =>
  content.map((item) => (item.type === "text" ? item.text : JSON.stringify(item))).join("\n") || "The tool failed.";
