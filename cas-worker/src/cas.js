import {
  createS3Client,
  getS3Key,
  checkS3ObjectExists,
  getS3Url
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
    const cached = await env.CAS_CACHE.get(cacheKey);
    if (cached) {
      try {
        const parsed = JSON.parse(cached);
        // Cached value can be either { prefix: "..." } or { error: "...", status: 403 }
        return parsed;
      } catch {
        // Legacy cache format: just the prefix string
        return { prefix: cached };
      }
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
      `/api/cache/cas/prefix?account_handle=${accountHandle}&project_handle=${projectHandle}`,
      { method: 'GET', headers }
    );

    if (!response.ok) {
      const result = { error: 'Unauthorized or not found', status: response.status };

      // Cache authorization failures (401/403) with shorter TTL
      if (env.CAS_CACHE && (response.status === 401 || response.status === 403)) {
        await env.CAS_CACHE.put(
          cacheKey,
          JSON.stringify(result),
          { expirationTtl: 300 } // Cache failures for 5 minutes
        );
      }

      return result;
    }

    const data = await response.json();
    const prefix = data.prefix;

    // Cache the successful prefix in KV
    if (env.CAS_CACHE && prefix) {
      await env.CAS_CACHE.put(
        cacheKey,
        JSON.stringify({ prefix }),
        { expirationTtl: 3600 } // Cache success for 1 hour
      );
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
  const { params, query } = request;
  const { id } = params;
  const accountHandle = query?.account_handle;
  const projectHandle = query?.project_handle;

  if (!accountHandle || !projectHandle) {
    return new Response(
      JSON.stringify({ message: 'Missing account_handle or project_handle query parameter' }),
      { status: 400, headers: { 'Content-Type': 'application/json' } }
    );
  }

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

  // Try KV cache first for small blobs
  if (env.CAS_CACHE_BLOBS) {
    const cachedBlob = await env.CAS_CACHE_BLOBS.get(key, 'arrayBuffer');
    if (cachedBlob) {
      return new Response(cachedBlob, {
        status: 200,
        headers: { 'Content-Type': 'application/octet-stream' },
      });
    }
  }

  // Fallback to S3
  const exists = await checkS3ObjectExists(s3Client, endpoint, bucket, key, virtualHost);

  if (!exists) {
    return new Response(null, { status: 404 });
  }

  const url = getS3Url(endpoint, bucket, key, virtualHost);

  // Stream the GET request from S3 with proper AWS signature
  const s3Response = await s3Client.fetch(url, { method: 'GET' });

  // Return the response with streaming body
  return new Response(s3Response.body, {
    status: s3Response.status,
    headers: s3Response.headers,
  });
}

/**
 * Handles POST request - check if artifact exists, return upload URL if needed
 */
export async function handleSave(request, env, ctx) {
  const { params, query } = request;
  const { id } = params;
  const accountHandle = query?.account_handle;
  const projectHandle = query?.project_handle;

  if (!accountHandle || !projectHandle) {
    return new Response(
      JSON.stringify({ message: 'Missing account_handle or project_handle query parameter' }),
      { status: 400, headers: { 'Content-Type': 'application/json' } }
    );
  }

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

  // Check KV cache first
  if (env.CAS_CACHE_BLOBS) {
    const cachedBlob = await env.CAS_CACHE_BLOBS.get(key);
    if (cachedBlob) {
      return new Response(null, { status: 304 });
    }
  }

  // Check S3
  const exists = await checkS3ObjectExists(s3Client, endpoint, bucket, key, virtualHost);

  if (exists) {
    return new Response(null, { status: 304 });
  }

  // Read the body to determine size and store appropriately
  const bodyBuffer = await request.arrayBuffer();
  const KV_SIZE_LIMIT = 25 * 1024 * 1024; // 25 MB KV limit

  // Store in KV if small enough (and KV is available)
  if (env.CAS_CACHE_BLOBS && bodyBuffer.byteLength < KV_SIZE_LIMIT) {
    await env.CAS_CACHE_BLOBS.put(key, bodyBuffer);
    return new Response(null, { status: 200 });
  }

  // Store in S3 for larger files or if KV not available
  const url = getS3Url(endpoint, bucket, key, virtualHost);

  const s3Response = await s3Client.fetch(url, {
    method: 'PUT',
    body: bodyBuffer,
    headers: {
      'Content-Type': request.headers.get('Content-Type') || 'application/octet-stream',
    },
  });

  // Return the S3 response
  return new Response(s3Response.body, {
    status: s3Response.status,
    headers: s3Response.headers,
  });
}
