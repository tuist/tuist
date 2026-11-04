// WebMCP (https://webmachinelearning.github.io/webmcp) lets agents built into
// the browser call tools a page registers. Pages name the Tuist endpoint that
// serves those tools: on an account's signed-in dashboard pages, the read-only
// tools for what the page shows (`data-webmcp-endpoint` on the headerbar, which
// changes as LiveView navigates between pages and accounts, but not when a
// filter or sort changes), and the documentation tools elsewhere (the
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

// Registers tools that let the agent move between the dashboard pages the user
// can reach from the current one, as the sidebar and the breadcrumbs' account
// and project menus offer them. They run in the page, read the links when
// called, and change no data, so they stay registered across navigations.
export function registerNavigationTools({
  modelContext = globalThis.document?.modelContext,
  document = globalThis.document,
  location = globalThis.location,
  target = globalThis,
  timeout = 10_000,
} = {}) {
  if (!modelContext?.registerTool || !dashboardHeaderbar(document)) return Promise.resolve([]);

  const pages = () => dashboardLinks(document, location);
  const tools = [
    {
      name: "list_dashboard_pages",
      title: "List Dashboard Pages",
      description:
        "Lists the Tuist dashboard pages the user can open from the current page: the account's or project's sections, and the user's other accounts and projects. Each page has a path, a title and a description, and the current page is marked. Open one with navigate_to_dashboard_page.",
      inputSchema: { type: "object", properties: {} },
      annotations: { readOnlyHint: true },
      execute: async () => ({ pages: pages().map(({ link: _link, ...page }) => page) }),
    },
    {
      name: "navigate_to_dashboard_page",
      title: "Navigate to Dashboard Page",
      description:
        "Opens a Tuist dashboard page in this tab, as clicking its link would. The path must be one list_dashboard_pages returned. The page's tools replace the current page's once it has loaded. Another account's or project's page loads as a new document, and the result says `reloading: true`.",
      inputSchema: {
        type: "object",
        properties: { path: { type: "string", description: "A path from list_dashboard_pages." } },
        required: ["path"],
      },
      // Navigating changes what the tab shows, not any data.
      annotations: { readOnlyHint: true },
      async execute({ path } = {}) {
        const page = pages().find((candidate) => candidate.path === path);
        if (!page) {
          return { isError: true, error: `${path} is not a page list_dashboard_pages offers from here.` };
        }

        // A live link reports when the next page has rendered. Any other link,
        // such as another account's or project's, loads a new document, which
        // ends this one and registers that page's tools.
        page.link.click();
        if (!page.link.hasAttribute("data-phx-link")) {
          return { path: page.path, title: page.title, reloading: true };
        }
        await pageLoaded(target, timeout);
        return { path: `${location.pathname}${location.search}`, title: page.title };
      },
    },
  ];

  return Promise.allSettled(tools.map((tool) => modelContext.registerTool(tool))).then((registrations) =>
    registrations.flatMap(({ status }, index) => (status === "fulfilled" ? [tools[index].name] : [])),
  );
}

// Registers a tool that opens a documentation page in the tab, so an agent
// that found one with `search_tuist` can show it to the user. Other tools on
// the docs pages already read the content; this one only navigates.
export function registerDocsNavigationTool({
  modelContext = globalThis.document?.modelContext,
  liveSocket = globalThis.liveSocket,
  document = globalThis.document,
  location = globalThis.location,
  fetch = globalThis.fetch,
  target = globalThis,
  timeout = 10_000,
} = {}) {
  if (!modelContext?.registerTool || !liveSocket) return Promise.resolve([]);

  const tool = {
    name: "navigate_to_docs_page",
    title: "Navigate to Docs Page",
    description:
      "Opens a page of the Tuist documentation in this tab, so the user can read it. Find pages with search_tuist and pass a result's URL, or a documentation path such as /en/docs/guides/features/cache. Only documentation pages on this site can be opened. Resolves once the page has rendered, with its path and title.",
    inputSchema: {
      type: "object",
      properties: {
        path: { type: "string", description: "A documentation URL or path, for example from search_tuist." },
      },
      required: ["path"],
    },
    // Navigating changes what the tab shows, not any data.
    annotations: { readOnlyHint: true },
    async execute({ path } = {}) {
      const url = docsURL(path, location);
      if (!url) {
        return { isError: true, error: `${path} is not a Tuist documentation page on ${location.origin}.` };
      }

      // The page may not exist, or the site may redirect an untranslated page
      // to its English source; open where the site would end up.
      let response;
      try {
        response = await fetch(url.href, { method: "HEAD" });
      } catch (error) {
        return { isError: true, error: `Could not reach Tuist: ${error?.message ?? error}` };
      }
      const destination = response.ok && docsURL(response.url || url.href, location);
      if (!destination) return { isError: true, error: `There is no documentation page at ${url.pathname}.` };
      const href = `${destination.pathname}${destination.search}${url.hash}`;

      // Each locale's docs are their own LiveView session: pages within the
      // current locale patch like the sidebar's links, and another locale's
      // load as a new document, which ends this one.
      if (docsLocale(destination.pathname) !== docsLocale(location.pathname)) {
        liveSocket.js().navigate(href);
        return { path: href, reloading: true };
      }
      const loaded = pageLoaded(target, timeout);
      liveSocket.js().patch(href);
      await loaded;
      // LiveView updates the document's title after the content, so name the
      // page by its heading.
      const heading = document?.querySelector?.("#docs-content h1")?.textContent.trim();
      return { path: `${location.pathname}${location.hash}`, title: heading || document?.title };
    },
  };

  // A browser that refuses the tool may throw as well as reject.
  return Promise.resolve()
    .then(() => modelContext.registerTool(tool))
    .then(
      () => [tool.name],
      () => [],
    );
}

// The same-origin documentation URL `path` names, or null.
function docsURL(path, location) {
  let url;
  try {
    url = new URL(path, location.origin);
  } catch {
    return null;
  }
  return url.origin === location.origin && docsLocale(url.pathname) ? url : null;
}

const docsLocale = (pathname) => pathname.match(/^\/([^/]+)\/docs(?:\/|$)/)?.[1];

const dashboardHeaderbar = (document) => document?.querySelector("header[data-webmcp-endpoint]");

// The sidebar's pages, then the breadcrumbs' accounts and projects; only links
// to dashboard paths, so the menus' create-account and create-project entries,
// which are in the footer, are left out.
function dashboardLinks(document, location) {
  const headerbar = dashboardHeaderbar(document);
  if (!headerbar) return [];

  const sidebarPages = [...document.querySelectorAll(".layout .noora-sidebar a[href^='/']")].map((link) => {
    const group = link.closest("[data-part='collapsible-group']");
    const groupLink = group?.querySelector("[data-part='link']");
    const title = labelOf(link);
    const description = groupLink && groupLink !== link ? `${labelOf(groupLink)} › ${title}` : title;
    return { link, title, description };
  });

  const [accounts, projects] = headerbar.querySelectorAll(".noora-breadcrumb");
  const menuPages = (breadcrumb, kind) =>
    [...(breadcrumb?.querySelectorAll("[data-part='items'] a[href^='/']") ?? [])].map((link) => {
      const title = link.getAttribute("data-label") ?? labelOf(link);
      return { link, title, description: `The ${title} ${kind}` };
    });

  const seen = new Set();
  return [...sidebarPages, ...menuPages(accounts, "account"), ...menuPages(projects, "project")].flatMap((page) => {
    const path = page.link.getAttribute("href");
    if (seen.has(path)) return [];
    seen.add(path);
    return [
      { path, title: page.title, description: page.description, current: path === location.pathname, link: page.link },
    ];
  });
}

const labelOf = (link) => link.querySelector("[data-part='label']")?.textContent.trim() ?? link.textContent.trim();

// Resolves when the navigation's view has rendered (a live redirect's own stop
// comes before that, see `registerWebMCPTools`), or after `timeout`.
const pageLoaded = (target, timeout) =>
  new Promise((resolve) => {
    const done = () => {
      clearTimeout(timer);
      target.removeEventListener("phx:page-loading-stop", onStop);
      resolve();
    };
    const onStop = (event) => event.detail?.kind !== "redirect" && done();
    const timer = setTimeout(done, timeout);
    target.addEventListener("phx:page-loading-stop", onStop);
  });

const contentText = (content = []) =>
  content.map((item) => (item.type === "text" ? item.text : JSON.stringify(item))).join("\n") || "The tool failed.";

const currentEndpoint = () =>
  globalThis.document?.querySelector("[data-webmcp-endpoint]")?.getAttribute("data-webmcp-endpoint") ??
  metaContent("webmcp-endpoint");

const metaContent = (name) => globalThis.document?.querySelector(`meta[name='${name}']`)?.getAttribute("content");
