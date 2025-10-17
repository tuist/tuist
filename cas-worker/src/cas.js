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
      console.log('Prefix cache hit', cacheKey);
      const parsed = JSON.parse(cached);
      // Cached value can be either { prefix: "..." } or { error: "...", status: 403 }
      return parsed;
    }
  }

  console.log('Prefix cache miss', cacheKey);

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
      const body = await response.json();
      console.log("Error getting prefix from Tuist", body);
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

    console.log('Successfully got prefix', prefix);

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
    console.log("Error getting prefix from Tuist", error);
    return { error: error.message, status: 500 };
  }
}

/**
 * Handles GET request - check if artifact exists and return download URL
 */
export async function handleGetValue(request, env, ctx) {
  console.log('Handling get request');
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

  console.log('Prefix', prefixResult.prefix);

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

  // Fallback to S3
  console.log('Checking S3 for key:', key);
  const exists = await checkS3ObjectExists(s3Client, endpoint, bucket, key, virtualHost);
  console.log('S3 exists check returned:', exists);

  if (!exists) {
    return new Response(
      JSON.stringify({ message: 'Artifact does not exist' }),
      { status: 404, headers: { 'Content-Type': 'application/json' } }
    );
  }

  const url = getS3Url(endpoint, bucket, key, virtualHost);

  // Stream the GET request from S3 with proper AWS signature
  console.log('Fetching blob from S3', url);
  let s3Response;
  try {
    s3Response = await s3Client.fetch(url, { method: 'GET' });
    console.log('S3 response status:', s3Response.status);
  } catch (e) {
    console.error('S3 fetch threw error:', e.message);
    return new Response(
      JSON.stringify({ message: 'S3 error' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }

  if (!s3Response.ok) {
    console.error(`S3 fetch failed with status ${s3Response.status}`);
    return new Response(
      JSON.stringify({ message: 'Artifact does not exist' }),
      { status: 404, headers: { 'Content-Type': 'application/json' } }
    );
  }

  // Buffer the entire response to validate it before returning
  let arrayBuffer;
  try {
    arrayBuffer = await s3Response.arrayBuffer();
    console.log(`S3 fetch succeeded, got ${arrayBuffer.byteLength} bytes`);
  } catch (e) {
    console.error('Failed to read S3 response body:', e.message);
    return new Response(
      JSON.stringify({ message: 'Failed to read S3 response' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }

  // Return the response with buffered body, ensuring correct content type
  const responseHeaders = new Headers(s3Response.headers);
  responseHeaders.set('Content-Type', 'application/octet-stream');

  return new Response(arrayBuffer, {
    status: 200,
    headers: responseHeaders,
  });
}

/**
 * Handles POST request - check if artifact exists, return upload URL if needed
 */
export async function handleSave(request, env, ctx) {
  console.log('Handling save request');
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

  // Check S3
  console.log('Checking if S3 object exists for key:', key);
  const exists = await checkS3ObjectExists(s3Client, endpoint, bucket, key, virtualHost);
  console.log('S3 exists check returned:', exists);

  if (exists) {
    console.log('S3 object already exists, returning 200');
    return new Response(
      JSON.stringify({ id: key }),
      { status: 200, headers: { 'Content-Type': 'application/json' } }
    );
  }

  // Read the body to determine size and store appropriately
  const bodyBuffer = await request.arrayBuffer();
  const url = getS3Url(endpoint, bucket, key, virtualHost);

  // Always store in S3 as the primary storage
  console.log(`Storing ${bodyBuffer.byteLength} bytes in S3 at ${url}`);

  let s3Response;
  try {
    s3Response = await s3Client.fetch(url, {
      method: 'PUT',
      body: bodyBuffer,
      headers: {
        'Content-Type': request.headers.get('Content-Type') || 'application/octet-stream',
      },
    });
    console.log(`S3 PUT returned ${s3Response.status}`);
  } catch (e) {
    console.error('S3 PUT threw error:', e.message);
    return new Response(
      JSON.stringify({ message: `S3 error: ${e.message}` }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }

  if (!s3Response.ok) {
    console.error(`S3 PUT failed with ${s3Response.status}`);
    return new Response(s3Response.body, {
      status: s3Response.status,
      headers: s3Response.headers,
    });
  }

  // Return success response matching server behavior
  return new Response(
    JSON.stringify({ id: key }),
    { status: 200, headers: { 'Content-Type': 'application/json' } }
  );
}
