import {
  createS3Client,
  getS3Key,
  checkS3ObjectExists,
  getPresignedDownloadUrl,
  getPresignedUploadUrl
} from './s3.js';

/**
 * Handles GET request - check if artifact exists and return download URL
 */
export async function handleGetValue({ params }, env, ctx) {
  const { id } = params;
  const s3Client = createS3Client(env);
  const bucket = env.TUIST_S3_BUCKET_NAME;
  const endpoint = env.TUIST_S3_ENDPOINT;
  const virtualHost = env.TUIST_S3_VIRTUAL_HOST === 'true';

  if (!bucket) {
    return new Response(
      JSON.stringify({ error: 'Missing TUIST_S3_BUCKET_NAME' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }

  const key = getS3Key(id);
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
export async function handleSave({ params }, env, ctx) {
  const { id } = params;
  const s3Client = createS3Client(env);
  const bucket = env.TUIST_S3_BUCKET_NAME;
  const endpoint = env.TUIST_S3_ENDPOINT;
  const virtualHost = env.TUIST_S3_VIRTUAL_HOST === 'true';

  if (!bucket) {
    return new Response(
      JSON.stringify({ error: 'Missing TUIST_S3_BUCKET_NAME' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }

  const key = getS3Key(id);
  const exists = await checkS3ObjectExists(s3Client, endpoint, bucket, key, virtualHost);

  if (exists) {
    return new Response(null, { status: 304 });
  }

  const url = await getPresignedUploadUrl(s3Client, endpoint, bucket, key, virtualHost);
  return Response.redirect(url, 302);
}
