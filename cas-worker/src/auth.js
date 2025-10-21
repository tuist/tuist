import { serverFetch } from "./server-fetch.js";

const FAILURE_CACHE_TTL = 300;
const ACCESSIBLE_PROJECTS_SUCCESS_TTL = 600;
const ACCESSIBLE_PROJECTS_CACHE_PREFIX = "accessible-projects";

async function sha256(data) {
  const encoded = new TextEncoder().encode(data);
  const hashBuffer = await crypto.subtle.digest("SHA-256", encoded);
  return Array.from(new Uint8Array(hashBuffer))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function generateAccessibleProjectsCacheKey(authHeader) {
  const hash = await sha256(authHeader);
  return `${ACCESSIBLE_PROJECTS_CACHE_PREFIX}:${hash}`;
}

async function getAccessibleProjects(
  request,
  env,
  authHeader,
  instrumentation = {},
) {
  const cache = env.CAS_CACHE;
  const cacheKey = await generateAccessibleProjectsCacheKey(authHeader);

  if (cache) {
    const cached = await cache.get(cacheKey);
    if (cached) {
      return JSON.parse(cached);
    }
  }

  const headers = { Authorization: authHeader };
  const requestIdHeader = request.headers.get("x-request-id");
  if (requestIdHeader) {
    headers["x-request-id"] = requestIdHeader;
  }

  try {
    const performFetch = () =>
      serverFetch(
        env,
        "/api/projects",
        {
          method: "GET",
          headers,
        },
        instrumentation?.fetch,
      );

    const response = instrumentation?.measureServerFetch
      ? await instrumentation.measureServerFetch(performFetch)
      : await performFetch();

    if (!response.ok) {
      const normalizedStatus = response.status === 403 ? 404 : response.status;
      const result = {
        error: "Unauthorized or not found",
        status: normalizedStatus,
      };

      if (cache && (response.status === 401 || response.status === 403)) {
        await cache.put(cacheKey, JSON.stringify(result), {
          expirationTtl: FAILURE_CACHE_TTL,
        });
      }

      return result;
    }

    const { projects } = await response.json();
    const projectHandles = projects.map((project) => project.full_name);

    if (cache) {
      await cache.put(cacheKey, JSON.stringify({ projects: projectHandles }), {
        expirationTtl: ACCESSIBLE_PROJECTS_SUCCESS_TTL,
      });
    }

    return { projects: projectHandles };
  } catch (error) {
    return { error: error.message, status: 500 };
  }
}

async function ensureProjectAccessible(
  request,
  env,
  accountHandle,
  projectHandle,
  instrumentation = {},
) {
  const authHeader = request.headers.get("Authorization");
  if (!authHeader) {
    return {
      error: "Missing Authorization header",
      status: 401,
    };
  }

  const accessibleProjectsResult = await getAccessibleProjects(
    request,
    env,
    authHeader,
    instrumentation,
  );

  if (accessibleProjectsResult.error) {
    return accessibleProjectsResult;
  }

  const requestedHandle = `${accountHandle}/${projectHandle}`;
  const isAccessible = accessibleProjectsResult.projects.some(
    (handle) => handle.toLowerCase() === requestedHandle.toLowerCase(),
  );

  if (!isAccessible) {
    return {
      error: "Unauthorized or not found",
      status: 404,
    };
  }

  return { authHeader };
}

export { FAILURE_CACHE_TTL, ensureProjectAccessible, getAccessibleProjects };
