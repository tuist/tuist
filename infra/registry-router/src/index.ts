const ORIGIN_HOST = "registry.tuist.dev";

async function proxyToOrigin(request: Request, host: string): Promise<Response | null> {
  try {
    const url = new URL(request.url);
    url.hostname = host;

    const originRequest = new Request(url.toString(), {
      method: request.method,
      headers: request.headers,
      body: request.body,
      redirect: "manual",
    });
    originRequest.headers.set("Host", host);

    const response = await fetch(originRequest);
    if (response.status >= 500) return null;

    const proxied = new Response(response.body, response);
    proxied.headers.set("X-Served-By", host);
    return proxied;
  } catch {
    return null;
  }
}

async function handleRequest(request: Request): Promise<Response> {
  const response = await proxyToOrigin(request, ORIGIN_HOST);
  if (response) return response;

  return new Response("Registry origin is unavailable", { status: 502 });
}

export default {
  async fetch(request: Request): Promise<Response> {
    return handleRequest(request);
  },
};
