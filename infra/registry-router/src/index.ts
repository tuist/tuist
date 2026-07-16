interface CacheOrigin {
  host: string;
  lat: number;
  lon: number;
}

interface Env {
  HEALTH: KVNamespace;
}

const HEALTH_CHECK_TTL = 120;
const HEALTH_CHECK_TIMEOUT = 5000;
const EARTH_RADIUS_KM = 6371;
const ORIGIN_HOST = "registry.tuist.dev";

const CACHE_ORIGINS: CacheOrigin[] = [
  { host: "cache-eu-central.tuist.dev",   lat:  50.11, lon:    8.68 }, // Frankfurt
  { host: "cache-eu-north.tuist.dev",     lat:  60.17, lon:   24.94 }, // Helsinki
  { host: "cache-us-east.tuist.dev",      lat:  39.04, lon:  -77.49 }, // Ashburn
  { host: "cache-us-east-2.tuist.dev",    lat:  39.04, lon:  -77.49 }, // Ashburn
  { host: "cache-us-east-3.tuist.dev",    lat:  39.04, lon:  -77.49 }, // Ashburn
  { host: "cache-us-west.tuist.dev",      lat:  45.59, lon: -122.60 }, // Oregon
  { host: "cache-ap-southeast.tuist.dev", lat:   1.35, lon:  103.82 }, // Singapore
  { host: "cache-sa-west.tuist.dev",      lat: -33.45, lon:  -70.67 }, // Santiago
  { host: "cache-au-east.tuist.dev",      lat: -33.87, lon:  151.21 }, // Sydney
];

function toRadians(degrees: number): number {
  return (degrees * Math.PI) / 180;
}

function haversineDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const dLat = toRadians(lat2 - lat1);
  const dLon = toRadians(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRadians(lat1)) * Math.cos(toRadians(lat2)) * Math.sin(dLon / 2) ** 2;
  return EARTH_RADIUS_KM * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function sortedCacheOrigins(request: Request): CacheOrigin[] {
  const lat = typeof request.cf?.latitude === "string" ? parseFloat(request.cf.latitude) : NaN;
  const lon = typeof request.cf?.longitude === "string" ? parseFloat(request.cf.longitude) : NaN;

  if (!Number.isFinite(lat) || !Number.isFinite(lon)) return CACHE_ORIGINS;

  return [...CACHE_ORIGINS].sort(
    (a, b) =>
      haversineDistance(lat, lon, a.lat, a.lon) - haversineDistance(lat, lon, b.lat, b.lon),
  );
}

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
  if (await isOriginHealthy(ORIGIN_HOST, env)) {
    const response = await proxyToOrigin(request, ORIGIN_HOST);
    if (response) return response;
  }

  for (const { host } of sortedCacheOrigins(request)) {
    if (!(await isOriginHealthy(host, env))) continue;

    const response = await proxyToOrigin(request, host);
    if (response) return response;
  }

  return new Response("All origins are unavailable", { status: 502 });
}

async function checkOrigin(
  host: string,
  healthKey: string,
  env: Env,
): Promise<void> {
  try {
    const healthRequest = new Request(`https://${host}/up`, {
      method: "GET",
      headers: { "User-Agent": "registry-router-healthcheck" },
      signal: AbortSignal.timeout(HEALTH_CHECK_TIMEOUT),
    });
    const response = await fetch(healthRequest);
    await response.body?.cancel();

    if (!response.ok) {
      console.error(
        `Health check returned ${response.status} ${response.statusText} for ${healthKey}`,
      );
    }

    await env.HEALTH.put(healthKey, String(response.ok), {
      expirationTtl: HEALTH_CHECK_TTL,
    });
  } catch (error) {
    console.error(`Health check failed for ${healthKey}`, error);
    await env.HEALTH.put(healthKey, "false", { expirationTtl: HEALTH_CHECK_TTL });
  }
}

async function handleScheduled(env: Env): Promise<void> {
  const checks = [
    checkOrigin(ORIGIN_HOST, ORIGIN_HOST, env),
    ...CACHE_ORIGINS.map(({ host }) => checkOrigin(host, host, env)),
  ];

  await Promise.allSettled(checks);
}

export default {
  async fetch(request: Request, env: Env): Promise<Response> {
    return handleRequest(request, env);
  },
  async scheduled(_event: ScheduledEvent, env: Env): Promise<void> {
    return handleScheduled(env);
  },
};
