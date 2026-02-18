interface Origin {
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

const ORIGINS: Origin[] = [
  { host: "cache-eu-central.tuist.dev",   lat:  50.11, lon:    8.68 }, // Frankfurt
  { host: "cache-eu-north.tuist.dev",     lat:  60.17, lon:   24.94 }, // Helsinki
  { host: "cache-us-east.tuist.dev",      lat:  39.04, lon:  -77.49 }, // Virginia
  { host: "cache-us-west.tuist.dev",      lat:  45.59, lon: -122.60 }, // Oregon
  { host: "cache-ap-southeast.tuist.dev", lat:   1.35, lon:  103.82 }, // Singapore
  { host: "cache-sa-west.tuist.dev",      lat: -33.45, lon:  -70.67 }, // Santiago
];

function toRadians(degrees: number): number {
  return (degrees * Math.PI) / 180;
}

// Haversine distance in km between two lat/lon points
function haversineDistance(lat1: number, lon1: number, lat2: number, lon2: number): number {
  const dLat = toRadians(lat2 - lat1);
  const dLon = toRadians(lon2 - lon1);
  const a =
    Math.sin(dLat / 2) ** 2 +
    Math.cos(toRadians(lat1)) * Math.cos(toRadians(lat2)) * Math.sin(dLon / 2) ** 2;
  return EARTH_RADIUS_KM * 2 * Math.atan2(Math.sqrt(a), Math.sqrt(1 - a));
}

function sortedByDistance(lat: number, lon: number): Origin[] {
  return [...ORIGINS].sort(
    (a, b) =>
      haversineDistance(lat, lon, a.lat, a.lon) - haversineDistance(lat, lon, b.lat, b.lon),
  );
}

function requestCoordinates(request: Request): { lat: number; lon: number } | null {
  const lat = typeof request.cf?.latitude === "string" ? parseFloat(request.cf.latitude) : NaN;
  const lon = typeof request.cf?.longitude === "string" ? parseFloat(request.cf.longitude) : NaN;
  return Number.isFinite(lat) && Number.isFinite(lon) ? { lat, lon } : null;
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
  const coords = requestCoordinates(request);
  const origins = coords ? sortedByDistance(coords.lat, coords.lon) : ORIGINS;

  for (const { host } of origins) {
    if (!(await isOriginHealthy(host, env))) continue;

    const response = await proxyToOrigin(request, host);
    if (response) return response;
  }

  return new Response("All origins are unavailable", { status: 502 });
}

async function handleScheduled(env: Env): Promise<void> {
  const checks = ORIGINS.map(async ({ host }) => {
    try {
      const response = await fetch(`https://${host}/up`, {
        method: "GET",
        headers: { "User-Agent": "registry-router-healthcheck" },
        signal: AbortSignal.timeout(HEALTH_CHECK_TIMEOUT),
      });
      await env.HEALTH.put(host, String(response.ok), {
        expirationTtl: HEALTH_CHECK_TTL,
      });
    } catch {
      await env.HEALTH.put(host, "false", { expirationTtl: HEALTH_CHECK_TTL });
    }
  });

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
