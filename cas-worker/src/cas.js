import {
  createS3Client,
  getS3Key,
  checkS3ObjectExists,
  getS3Url,
} from "./s3.js";
import { jsonResponse } from "./shared.js";
import { ensureProjectAccessible } from "./auth.js";

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

  const accessResult = await ensureProjectAccessible(
    request,
    env,
    accountHandle,
    projectHandle,
  );
  if (accessResult.error) {
    return { error: accessResult.error, status: accessResult.status };
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
  const prefix = `${accountHandle}/${projectHandle}/cas/`;
  const key = `${prefix}${getS3Key(id)}`;

  return {
    s3Client,
    bucket,
    endpoint,
    virtualHost,
    key,
    prefix,
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
    return jsonResponse({ message: setupResult.error }, setupResult.status);
  }

  const { s3Client, bucket, endpoint, virtualHost, key } = setupResult;
  const url = getS3Url(endpoint, bucket, key, virtualHost);

  let s3Response;
  try {
    s3Response = await s3Client.fetch(url, { method: "GET" });
  } catch (e) {
    return jsonResponse({ message: "S3 error" }, 500);
  }

  if (!s3Response.ok) {
    return jsonResponse({ message: "Artifact does not exist" }, 404);
  }

  let arrayBuffer;
  try {
    arrayBuffer = await s3Response.arrayBuffer();
  } catch (e) {
    return jsonResponse({ message: "Failed to read S3 response" }, 500);
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
    return jsonResponse({ message: setupResult.error }, setupResult.status);
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
    return jsonResponse({ message: "S3 error" }, 500);
  }
}
