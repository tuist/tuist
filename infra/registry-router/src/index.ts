interface Env {
  HEALTH: KVNamespace;
}

const HEALTH_CHECK_TTL = 120;
const HEALTH_CHECK_TIMEOUT = 5000;
const SWIFT_REGISTRY_HOST = "swift-registry.tuist.dev";

async function isSwiftRegistryHealthy(env: Env): Promise<boolean> {
  const value = await env.HEALTH.get(SWIFT_REGISTRY_HOST);
  return value !== "false";
}

async function proxyToSwiftRegistry(request: Request): Promise<Response | null> {
  try {
    const url = new URL(request.url);
    url.hostname = SWIFT_REGISTRY_HOST;

    const originRequest = new Request(url.toString(), {
      method: request.method,
      headers: request.headers,
      body: request.body,
      redirect: "manual",
    });
    originRequest.headers.set("Host", SWIFT_REGISTRY_HOST);

    const response = await fetch(originRequest);
    if (response.status >= 500) return null;

    const proxied = new Response(response.body, response);
    proxied.headers.set("X-Served-By", SWIFT_REGISTRY_HOST);
    return proxied;
  } catch {
    return null;
  }
}

async function handleRequest(request: Request, env: Env): Promise<Response> {
  if (await isSwiftRegistryHealthy(env)) {
    const response = await proxyToSwiftRegistry(request);
    if (response) return response;
  }

  return new Response("Swift registry is unavailable", { status: 502 });
}

async function handleScheduled(env: Env): Promise<void> {
  try {
    const response = await fetch(`https://${SWIFT_REGISTRY_HOST}/up`, {
      method: "GET",
      headers: { "User-Agent": "registry-router-healthcheck" },
      signal: AbortSignal.timeout(HEALTH_CHECK_TIMEOUT),
    });
    await env.HEALTH.put(SWIFT_REGISTRY_HOST, String(response.ok), {
      expirationTtl: HEALTH_CHECK_TTL,
    });
  } catch {
    await env.HEALTH.put(SWIFT_REGISTRY_HOST, "false", { expirationTtl: HEALTH_CHECK_TTL });
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
