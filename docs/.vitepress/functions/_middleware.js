export async function onRequest(context) {
  const { request, next } = context;
  const accept = request.headers.get('Accept');

  // Check if the request accepts text/plain
  if (accept && accept.includes('text/plain')) {
    const url = new URL(request.url);

    // Skip if the path already ends with .md
    if (!url.pathname.endsWith('.md')) {
      // Append .md to the pathname
      url.pathname = url.pathname.endsWith('/')
        ? `${url.pathname}index.md`
        : `${url.pathname}.md`;

      // Fetch the modified URL
      return fetch(url.toString(), {
        headers: request.headers
      });
    }
  }

  // Continue with the normal request
  return next();
}
