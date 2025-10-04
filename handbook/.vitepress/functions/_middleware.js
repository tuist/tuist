export async function onRequest(context) {
  const { request, env } = context;
  const accept = request.headers.get("Accept");

  // Check if the request accepts text/plain
  if (accept && accept.includes("text/plain")) {
    const url = new URL(request.url);

    // Skip if the path already ends with .md
    if (!url.pathname.endsWith(".md")) {
      // Append .md to the pathname
      const newPathname = url.pathname.endsWith("/")
        ? `${url.pathname}index.md`
        : `${url.pathname}.md`;

      // Create new request with modified path
      const newUrl = new URL(request.url);
      newUrl.pathname = newPathname;

      // Fetch from Cloudflare Pages assets
      return env.ASSETS.fetch(newUrl.toString());
    }
  }

  // Continue with the normal request
  return context.next();
}
