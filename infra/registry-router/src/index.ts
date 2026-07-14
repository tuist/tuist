interface Env {
  HEALTH: KVNamespace;
}

const HEALTH_CHECK_TTL = 120;
const HEALTH_CHECK_TIMEOUT = 5000;
const ORIGIN_HOST = "registry-origin.tuist.dev";

// Fail-open: missing KV key (first deploy / TTL expired) = healthy
async function isOriginHealthy(host: string, env: Env): Promise<boolean> {
  const value = await env.HEALTH.get(host);
  return value !== "false";
}

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

async function handleRequest(request: Request, env: Env): Promise<Response> {
  if (!(await isOriginHealthy(ORIGIN_HOST, env))) {
    return new Response("Origin is unavailable", { status: 502 });
  }

  const response = await proxyToOrigin(request, ORIGIN_HOST);
  if (response) return response;

  return new Response("Origin is unavailable", { status: 502 });
}

async function handleScheduled(env: Env): Promise<void> {
  try {
    const response = await fetch(`https://${ORIGIN_HOST}/up`, {
      method: "GET",
      headers: { "User-Agent": "registry-router-healthcheck" },
      signal: AbortSignal.timeout(HEALTH_CHECK_TIMEOUT),
    });
    await env.HEALTH.put(ORIGIN_HOST, String(response.ok), {
      expirationTtl: HEALTH_CHECK_TTL,
    });
  } catch {
    await env.HEALTH.put(ORIGIN_HOST, "false", { expirationTtl: HEALTH_CHECK_TTL });
  }
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    return handleRequest(request, env);
  },
  async scheduled(_event: ScheduledEvent, env: Env): Promise<void> {
    return handleScheduled(env);
  },
};
