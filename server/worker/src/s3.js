import { AwsClient } from 'aws4fetch';

/**
 * Creates an AWS client from environment variables
 */
export function createS3Client(env) {
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

  return new AwsClient({
    accessKeyId: env.TUIST_S3_ACCESS_KEY_ID,
    secretAccessKey: env.TUIST_S3_SECRET_ACCESS_KEY,
    region: env.TUIST_S3_REGION,
    service: 's3',
  });
}

/**
 * Constructs S3 key from cas_id by replacing ~ with /
 * Format: {version}~{hash} -> {version}/{hash}
 * Example: 0~YWoYNXX... -> 0/YWoYNXX...
 */
export function getS3Key(casId) {
  return casId.replace('~', '/');
}

/**
 * Constructs S3 URL for an object
 */
export function getS3Url(endpoint, bucket, key, virtualHost = false) {
  if (virtualHost) {
    // Virtual host style: https://bucket.endpoint/key
    const url = new URL(endpoint);
    url.hostname = `${bucket}.${url.hostname}`;
    url.pathname = `/${key}`;
    return url.toString();
  } else {
    // Path style: https://endpoint/bucket/key
    const url = new URL(endpoint);
    url.pathname = `/${bucket}/${key}`;
    return url.toString();
  }
}

/**
 * Checks if an object exists in S3
 */
export async function checkS3ObjectExists(s3Client, endpoint, bucket, key, virtualHost = false) {
  const url = getS3Url(endpoint, bucket, key, virtualHost);

  try {
    const response = await s3Client.fetch(url, { method: 'HEAD' });
    return response.ok;
  } catch (error) {
    return false;
  }
}
