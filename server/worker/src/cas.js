import {
  createS3Client,
  getS3Key,
  checkS3ObjectExists,
  getPresignedDownloadUrl,
  getPresignedUploadUrl
} from './s3.js';
import { serverFetch } from './server-fetch.js';

/**
 * Generate cache key from account, project, and authorization token
 */
async function generateCacheKey(accountHandle, projectHandle, authToken) {
  const data = `${accountHandle}:${projectHandle}:${authToken}`;
  const encoder = new TextEncoder();
  const dataBuffer = encoder.encode(data);
  const hashBuffer = await crypto.subtle.digest('SHA-256', dataBuffer);
  const hashArray = Array.from(new Uint8Array(hashBuffer));
  return hashArray.map(b => b.toString(16).padStart(2, '0')).join('');
}

/**
 * Get S3 prefix from cache or server
 */
async function getS3Prefix(request, env, accountHandle, projectHandle) {
  const authHeader = request.headers.get('Authorization');
  const requestIdHeader = request.headers.get('x-request-id');

  if (!authHeader) {
    return { error: 'Missing Authorization header', status: 401 };
  }

  // Generate cache key
  const cacheKey = await generateCacheKey(accountHandle, projectHandle, authHeader);

  // Check KV cache first
  if (env.CAS_CACHE) {
    const cachedPrefix = await env.CAS_CACHE.get(cacheKey);
    if (cachedPrefix) {
      return { prefix: cachedPrefix };
    }
  }

  // Query server for prefix
  const headers = {
    'Authorization': authHeader,
  };

  if (requestIdHeader) {
    headers['x-request-id'] = requestIdHeader;
  }

  try {
    const response = await serverFetch(
      env,
      `/api/projects/${accountHandle}/${projectHandle}/cas/prefix`,
      { method: 'GET', headers }
    );

    if (!response.ok) {
      return { error: 'Unauthorized or not found', status: response.status };
    }

    const data = await response.json();
    const prefix = data.prefix;

    // Cache the prefix in KV
    if (env.CAS_CACHE && prefix) {
      await env.CAS_CACHE.put(cacheKey, prefix, { expirationTtl: 3600 }); // Cache for 1 hour
    }

    return { prefix };
  } catch (error) {
    return { error: error.message, status: 500 };
  }
}

/**
 * Handles GET request - check if artifact exists and return download URL
 */
export async function handleGetValue(request, env, ctx) {
  const { params } = request;
  const { id, account_handle: accountHandle, project_handle: projectHandle } = params;

  // Get S3 prefix (from cache or server)
  const prefixResult = await getS3Prefix(request, env, accountHandle, projectHandle);
  if (prefixResult.error) {
    // Match Phoenix behavior: 401/403 with JSON, 404 with empty body
    if (prefixResult.status === 401 || prefixResult.status === 403) {
      return new Response(
        JSON.stringify({ message: prefixResult.error }),
        { status: prefixResult.status, headers: { 'Content-Type': 'application/json' } }
      );
    }
    // 404 or other errors: empty body
    return new Response(null, { status: prefixResult.status });
  }

  const s3Client = createS3Client(env);
  const bucket = env.TUIST_S3_BUCKET_NAME;
  const endpoint = env.TUIST_S3_ENDPOINT;
  const virtualHost = env.TUIST_S3_VIRTUAL_HOST === 'true';

  if (!bucket) {
    return new Response(
      JSON.stringify({ message: 'Missing TUIST_S3_BUCKET_NAME' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }

  const key = `${prefixResult.prefix}${getS3Key(id)}`;
  const exists = await checkS3ObjectExists(s3Client, endpoint, bucket, key, virtualHost);

  if (!exists) {
    return new Response(null, { status: 404 });
  }

  const url = await getPresignedDownloadUrl(s3Client, endpoint, bucket, key, virtualHost);
  return Response.redirect(url, 302);
}

/**
 * Handles POST request - check if artifact exists, return upload URL if needed
 */
export async function handleSave(request, env, ctx) {
  const { params } = request;
  const { id, account_handle: accountHandle, project_handle: projectHandle } = params;

  // Get S3 prefix (from cache or server)
  const prefixResult = await getS3Prefix(request, env, accountHandle, projectHandle);
  if (prefixResult.error) {
    // Match Phoenix behavior: 401/403 with JSON, 404 with empty body
    if (prefixResult.status === 401 || prefixResult.status === 403) {
      return new Response(
        JSON.stringify({ message: prefixResult.error }),
        { status: prefixResult.status, headers: { 'Content-Type': 'application/json' } }
      );
    }
    // 404 or other errors: empty body
    return new Response(null, { status: prefixResult.status });
  }

  const s3Client = createS3Client(env);
  const bucket = env.TUIST_S3_BUCKET_NAME;
  const endpoint = env.TUIST_S3_ENDPOINT;
  const virtualHost = env.TUIST_S3_VIRTUAL_HOST === 'true';

  if (!bucket) {
    return new Response(
      JSON.stringify({ message: 'Missing TUIST_S3_BUCKET_NAME' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }

  const key = `${prefixResult.prefix}${getS3Key(id)}`;
  const exists = await checkS3ObjectExists(s3Client, endpoint, bucket, key, virtualHost);

  if (exists) {
    return new Response(null, { status: 304 });
  }

  const url = await getPresignedUploadUrl(s3Client, endpoint, bucket, key, virtualHost);
  return Response.redirect(url, 302);
}
