import {
  createS3Client,
  getS3Key,
  checkS3ObjectExists,
  getS3Url
} from './s3.js';
import { serverFetch } from './server-fetch.js';
import { jsonResponse, errorResponse } from './shared.js';

const FAILURE_CACHE_TTL = 300;
const SUCCESS_CACHE_TTL = 3600;

async function sha256Hash(data) {
  const encoded = new TextEncoder().encode(data);
  const hashBuffer = await crypto.subtle.digest('SHA-256', encoded);
  return Array.from(new Uint8Array(hashBuffer))
    .map(b => b.toString(16).padStart(2, '0'))
    .join('');
}

async function generateCacheKey(accountHandle, projectHandle, authToken) {
  return sha256Hash(`${accountHandle}:${projectHandle}:${authToken}`);
}

async function getS3Prefix(request, env, accountHandle, projectHandle) {
  const authHeader = request.headers.get('Authorization');
  if (!authHeader) {
    return { error: 'Missing Authorization header', status: 401 };
  }

  const cacheKey = await generateCacheKey(accountHandle, projectHandle, authHeader);

  if (env.CAS_CACHE) {
    const cached = await env.CAS_CACHE.get(cacheKey);
    if (cached) {
      return JSON.parse(cached);
    }
  }

  const headers = { Authorization: authHeader };
  const requestIdHeader = request.headers.get('x-request-id');
  if (requestIdHeader) {
    headers['x-request-id'] = requestIdHeader;
  }

  try {
    const response = await serverFetch(
      env,
      `/api/cache/prefix?account_handle=${accountHandle}&project_handle=${projectHandle}`,
      { method: 'GET', headers }
    );

    if (!response.ok) {
      const result = { error: 'Unauthorized or not found', status: response.status };
      
      if (env.CAS_CACHE && (response.status === 401 || response.status === 403)) {
        await env.CAS_CACHE.put(cacheKey, JSON.stringify(result), {
          expirationTtl: FAILURE_CACHE_TTL
        });
      }

      return result;
    }

    const { prefix } = await response.json();

    if (env.CAS_CACHE && prefix) {
      await env.CAS_CACHE.put(cacheKey, JSON.stringify({ prefix }), {
        expirationTtl: SUCCESS_CACHE_TTL
      });
    }

    return { prefix };
  } catch (error) {
    return { error: error.message, status: 500 };
  }
}



async function validateAndSetupRequest(request, env, accountHandle, projectHandle, id) {
  if (!accountHandle || !projectHandle) {
    return { error: 'Missing account_handle or project_handle query parameter', status: 400 };
  }

  const prefixResult = await getS3Prefix(request, env, accountHandle, projectHandle);
  if (prefixResult.error) {
    if (prefixResult.status === 401 || prefixResult.status === 403) {
      return { error: prefixResult.error, status: prefixResult.status };
    }
    return { error: null, status: prefixResult.status, shouldReturnEmpty: true };
  }

  const s3Client = createS3Client(env);
  const { TUIST_S3_BUCKET_NAME: bucket, TUIST_S3_ENDPOINT: endpoint, TUIST_S3_VIRTUAL_HOST: virtualHostStr } = env;
  
  if (!bucket) {
    return { error: 'Missing TUIST_S3_BUCKET_NAME', status: 500 };
  }

  const virtualHost = virtualHostStr === 'true';
  const key = `${prefixResult.prefix}${getS3Key(id)}`;

  return {
    s3Client,
    bucket,
    endpoint,
    virtualHost,
    key,
    prefix: prefixResult.prefix
  };
}

export async function handleGetValue(request, env) {
  const { params, query } = request;
  const { id } = params;
  const { account_handle: accountHandle, project_handle: projectHandle } = query || {};

  const setupResult = await validateAndSetupRequest(request, env, accountHandle, projectHandle, id);
  if (setupResult.error) {
    return errorResponse(setupResult.error, setupResult.status);
  }
  if (setupResult.shouldReturnEmpty) {
    return new Response(null, { status: setupResult.status });
  }

  const { s3Client, bucket, endpoint, virtualHost, key } = setupResult;
  const url = getS3Url(endpoint, bucket, key, virtualHost);

  let s3Response;
  try {
    s3Response = await s3Client.fetch(url, { method: 'GET' });
  } catch (e) {
    return errorResponse('S3 error', 500);
  }

  if (!s3Response.ok) {
    return errorResponse('Artifact does not exist', 404);
  }

  let arrayBuffer;
  try {
    arrayBuffer = await s3Response.arrayBuffer();
  } catch (e) {
    return errorResponse('Failed to read S3 response', 500);
  }

  const responseHeaders = new Headers(s3Response.headers);
  responseHeaders.set('Content-Type', 'application/octet-stream');

  return new Response(arrayBuffer, { status: 200, headers: responseHeaders });
}

export async function handleSave(request, env) {
  const { params, query } = request;
  const { id } = params;
  const { account_handle: accountHandle, project_handle: projectHandle } = query || {};

  const setupResult = await validateAndSetupRequest(request, env, accountHandle, projectHandle, id);
  if (setupResult.error) {
    return errorResponse(setupResult.error, setupResult.status);
  }
  if (setupResult.shouldReturnEmpty) {
    return new Response(null, { status: setupResult.status });
  }

  const { s3Client, bucket, endpoint, virtualHost, key } = setupResult;

  const exists = await checkS3ObjectExists(s3Client, endpoint, bucket, key, virtualHost);
  if (exists) {
    return jsonResponse({ id: key });
  }

  const bodyBuffer = await request.arrayBuffer();
  const url = getS3Url(endpoint, bucket, key, virtualHost);

  try {
    const s3Response = await s3Client.fetch(url, {
      method: 'PUT',
      body: bodyBuffer,
      headers: {
        'Content-Type': request.headers.get('Content-Type') || 'application/octet-stream',
      },
    });

    if (!s3Response.ok) {
      return new Response(s3Response.body, {
        status: s3Response.status,
        headers: s3Response.headers,
      });
    }

    return jsonResponse({ id: key });
  } catch (e) {
    return errorResponse('S3 error', 500);
  }
}
