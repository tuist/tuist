import { S3Client, HeadObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

/**
 * Creates an S3 client from environment variables
 */
function createS3Client(env) {
  const requiredVars = [
    'TUIST_S3_REGION',
    'TUIST_S3_ENDPOINT',
    'TUIST_S3_ACCESS_KEY_ID',
    'TUIST_S3_SECRET_ACCESS_KEY'
  ];

  for (const varName of requiredVars) {
    if (!env[varName]) {
      throw new Error(`Missing required environment variable: ${varName}`);
    }
  }

  return new S3Client({
    region: env.TUIST_S3_REGION,
    endpoint: env.TUIST_S3_ENDPOINT,
    credentials: {
      accessKeyId: env.TUIST_S3_ACCESS_KEY_ID,
      secretAccessKey: env.TUIST_S3_SECRET_ACCESS_KEY,
    },
    forcePathStyle: env.TUIST_S3_BUCKET_AS_HOST !== 'true',
  });
}

/**
 * Constructs S3 key from cas_id
 */
function getS3Key(casId) {
  // Convert bytes to hex string for S3 key
  const hex = Buffer.from(casId).toString('hex');
  // Use first 2 chars as prefix for better S3 performance
  return `${hex.substring(0, 2)}/${hex}`;
}

/**
 * Checks if an object exists in S3
 */
async function checkS3ObjectExists(s3Client, bucket, key) {
  try {
    await s3Client.send(new HeadObjectCommand({
      Bucket: bucket,
      Key: key,
    }));
    return true;
  } catch (error) {
    if (error.name === 'NotFound' || error.$metadata?.httpStatusCode === 404) {
      return false;
    }
    throw error;
  }
}

/**
 * Generates a presigned URL for S3 download
 */
async function getPresignedDownloadUrl(s3Client, bucket, key, env) {
  const command = new HeadObjectCommand({
    Bucket: bucket,
    Key: key,
  });

  const url = await getSignedUrl(s3Client, command, { expiresIn: 3600 });

  // If virtual host style is enabled, modify URL
  if (env.TUIST_S3_VIRTUAL_HOST === 'true') {
    const parsedUrl = new URL(url);
    parsedUrl.hostname = `${bucket}.${parsedUrl.hostname}`;
    return parsedUrl.toString();
  }

  return url;
}

/**
 * Handles GET request - check if artifact exists and return download URL
 */
async function handleGetValue(id, env) {
  const s3Client = createS3Client(env);
  const bucket = env.TUIST_S3_BUCKET_NAME;

  if (!bucket) {
    return new Response(
      JSON.stringify({ error: 'Missing TUIST_S3_BUCKET_NAME' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }

  const key = getS3Key(id);
  const exists = await checkS3ObjectExists(s3Client, bucket, key);

  if (!exists) {
    return new Response(null, { status: 404 });
  }

  const url = await getPresignedDownloadUrl(s3Client, bucket, key, env);
  return Response.redirect(url, 302);
}

/**
 * Handles POST request - check if artifact exists, return upload URL if needed
 */
async function handleSave(id, env) {
  const s3Client = createS3Client(env);
  const bucket = env.TUIST_S3_BUCKET_NAME;

  if (!bucket) {
    return new Response(
      JSON.stringify({ error: 'Missing TUIST_S3_BUCKET_NAME' }),
      { status: 500, headers: { 'Content-Type': 'application/json' } }
    );
  }

  const key = getS3Key(id);
  const exists = await checkS3ObjectExists(s3Client, bucket, key);

  if (exists) {
    return new Response(null, { status: 304 });
  }

  const url = await getPresignedDownloadUrl(s3Client, bucket, key, env);
  return Response.redirect(url, 302);
}

/**
 * Main request handler
 */
export default {
  async fetch(request, env, ctx) {
    const url = new URL(request.url);
    const match = url.pathname.match(/^\/api\/cas\/(.+)$/);

    try {
      if (!match) {
        return new Response(
          JSON.stringify({ error: 'Not found' }),
          { status: 404, headers: { 'Content-Type': 'application/json' } }
        );
      }

      const id = match[1];

      if (request.method === 'GET') {
        return await handleGetValue(id, env);
      } else if (request.method === 'POST') {
        return await handleSave(id, env);
      } else {
        return new Response(
          JSON.stringify({ error: 'Method not allowed' }),
          { status: 405, headers: { 'Content-Type': 'application/json' } }
        );
      }
    } catch (error) {
      console.error('Error handling request:', error);
      return new Response(
        JSON.stringify({ error: error.message }),
        { status: 500, headers: { 'Content-Type': 'application/json' } }
      );
    }
  },
};
