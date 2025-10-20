import {
  createS3Client,
  getS3Key,
  checkS3ObjectExists,
  getS3Url,
} from "./s3.js";
import { serverFetch } from "./server-fetch.js";
import { jsonResponse } from "./shared.js";
import {
  FAILURE_CACHE_TTL,
  ensureProjectAccessible,
} from "./auth.js";

const SUCCESS_CACHE_TTL = 3600;

async function sha256(data) {
  const encoded = new TextEncoder().encode(data);
  const hashBuffer = await crypto.subtle.digest("SHA-256", encoded);
  return Array.from(new Uint8Array(hashBuffer))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

async function buildCacheKey(accountHandle, projectHandle, authToken) {
  const hash = await sha256(`${accountHandle}:${projectHandle}:${authToken}`);
  return `cas:${hash}`;
}

async function getS3Prefix(request, env, accountHandle, projectHandle) {
  const accessResult = await ensureProjectAccessible(
    request,
    env,
    accountHandle,
    projectHandle,
  );

  if (accessResult.error) {
    return accessResult;
  }

  const { authHeader } = accessResult;

  const cacheKey = await buildCacheKey(
    accountHandle,
    projectHandle,
    authHeader,
  );

  const cache = env.CAS_CACHE;
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
    const prefixUrl =
      `/api/cache/prefix?account_handle=${accountHandle}&project_handle=${projectHandle}`;
    const response = await serverFetch(
      env,
      prefixUrl,
      { method: "GET", headers },
    );

    if (!response.ok) {
      const isServerNotFound = response.status === 404;
      const normalizedStatus = response.status === 403 ? 404 : response.status;
      const result = {
        error: "Unauthorized or not found",
        status: normalizedStatus,
        shouldReturnJson: !isServerNotFound,
      };

      if (
        cache &&
        (response.status === 401 || response.status === 403)
      ) {
        await cache.put(cacheKey, JSON.stringify(result), {
          expirationTtl: FAILURE_CACHE_TTL,
        });
      }

      return result;
    }

    const { prefix } = await response.json();

    if (cache && prefix) {
      await cache.put(cacheKey, JSON.stringify({ prefix }), {
        expirationTtl: SUCCESS_CACHE_TTL,
      });
    }

    return { prefix };
  } catch (error) {
    return { error: error.message, status: 500 };
  }
}

async function validateAndSetupRequest(
  request,
  env,
  accountHandle,
  projectHandle,
  id,
) {
  if (!accountHandle || !projectHandle) {
    return {
      error: "Missing account_handle or project_handle query parameter",
      status: 400,
    };
  }

  const prefixResult = await getS3Prefix(
    request,
    env,
    accountHandle,
    projectHandle,
  );
  if (prefixResult.error) {
    if (
      prefixResult.shouldReturnJson ||
      prefixResult.status === 401 ||
      prefixResult.status === 403
    ) {
      return { error: prefixResult.error, status: prefixResult.status };
    }
    return {
      error: null,
      status: prefixResult.status,
      shouldReturnEmpty: true,
    };
  }

  const s3Client = createS3Client(env);
  const {
    TUIST_S3_BUCKET_NAME: bucket,
    TUIST_S3_ENDPOINT: endpoint,
    TUIST_S3_VIRTUAL_HOST: virtualHostStr,
  } = env;

  if (!bucket) {
    return { error: "Missing TUIST_S3_BUCKET_NAME", status: 500 };
  }

  const virtualHost = virtualHostStr === "true";
  const key = `${prefixResult.prefix}${getS3Key(id)}`;

  return {
    s3Client,
    bucket,
    endpoint,
    virtualHost,
    key,
    prefix: prefixResult.prefix,
  };
}

export async function handleGetValue(request, env) {
  const { params, query } = request;
  const { id } = params;
  const { account_handle: accountHandle, project_handle: projectHandle } =
    query || {};

  const setupResult = await validateAndSetupRequest(
    request,
    env,
    accountHandle,
    projectHandle,
    id,
  );
  if (setupResult.error) {
    return jsonResponse(setupResult.error, setupResult.status);
  }
  if (setupResult.shouldReturnEmpty) {
    return new Response(null, { status: setupResult.status });
  }

  const { s3Client, bucket, endpoint, virtualHost, key } = setupResult;
  const url = getS3Url(endpoint, bucket, key, virtualHost);

  let s3Response;
  try {
    s3Response = await s3Client.fetch(url, { method: "GET" });
  } catch (e) {
    return jsonResponse("S3 error", 500);
  }

  if (!s3Response.ok) {
    return jsonResponse("Artifact does not exist", 404);
  }

  let arrayBuffer;
  try {
    arrayBuffer = await s3Response.arrayBuffer();
  } catch (e) {
    return jsonResponse("Failed to read S3 response", 500);
  }

  const responseHeaders = new Headers(s3Response.headers);
  responseHeaders.set("Content-Type", "application/octet-stream");

  return new Response(arrayBuffer, { status: 200, headers: responseHeaders });
}

export async function handleSave(request, env) {
  const { params, query } = request;
  const { id } = params;
  const { account_handle: accountHandle, project_handle: projectHandle } =
    query || {};

  const setupResult = await validateAndSetupRequest(
    request,
    env,
    accountHandle,
    projectHandle,
    id,
  );
  if (setupResult.error) {
    return jsonResponse(setupResult.error, setupResult.status);
  }
  if (setupResult.shouldReturnEmpty) {
    return new Response(null, { status: setupResult.status });
  }

  const { s3Client, bucket, endpoint, virtualHost, key } = setupResult;

  const exists = await checkS3ObjectExists(
    s3Client,
    endpoint,
    bucket,
    key,
    virtualHost,
  );
  if (exists) {
    return new Response(null, { status: 204 });
  }

  const bodyBuffer = await request.arrayBuffer();
  const url = getS3Url(endpoint, bucket, key, virtualHost);

  try {
    const s3Response = await s3Client.fetch(url, {
      method: "PUT",
      body: bodyBuffer,
      headers: {
        "Content-Type":
          request.headers.get("Content-Type") || "application/octet-stream",
      },
    });

    if (!s3Response.ok) {
      return new Response(s3Response.body, {
        status: s3Response.status,
        headers: s3Response.headers,
      });
    }

    return new Response(null, { status: 204 });
  } catch (e) {
    return jsonResponse("S3 error", 500);
  }
}
