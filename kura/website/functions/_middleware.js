// Cloudflare Pages middleware: Markdown content negotiation.
//
// When an agent requests an HTML page with `Accept: text/markdown`, serve the
// generated `<page>/index.md` instead. Inert on hosts that are not Cloudflare
// Pages, and fails open (always falls back to the normal response) on any error.

export async function onRequest(context) {
  const { request, next, env } = context;

  try {
    if (request.method !== "GET" && request.method !== "HEAD") {
      return next();
    }

    const accept = request.headers.get("Accept") || "";
    if (!accept.includes("text/markdown")) {
      return next();
    }

    const url = new URL(request.url);
    const pathname = url.pathname;

    // Skip requests that already target a concrete file (.md, .css, .png, ...).
    const lastSegment = pathname.split("/").pop();
    if (lastSegment && lastSegment.includes(".")) {
      return next();
    }

    const mdPath = pathname.endsWith("/")
      ? `${pathname}index.md`
      : `${pathname}/index.md`;

    const mdResponse = await env.ASSETS.fetch(
      new Request(new URL(mdPath, url.origin), request),
    );

    if (!mdResponse.ok) {
      return next();
    }

    const headers = new Headers(mdResponse.headers);
    headers.set("Content-Type", "text/markdown; charset=utf-8");
    headers.set("Vary", "Accept");
    headers.set("X-Content-Negotiation", "markdown");

    return new Response(mdResponse.body, {
      status: 200,
      headers,
    });
  } catch {
    return next();
  }
}
