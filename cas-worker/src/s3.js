import { AwsClient } from 'aws4fetch';

const REQUIRED_S3_VARS = [
  'TUIST_S3_REGION',
  'TUIST_S3_ENDPOINT',
  'TUIST_S3_ACCESS_KEY_ID',
  'TUIST_S3_SECRET_ACCESS_KEY'
];

export function createS3Client(env) {
  for (const varName of REQUIRED_S3_VARS) {
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

export function getS3Key(casId) {
  return casId.replace('~', '/');
}

export function getS3Url(endpoint, bucket, key, virtualHost = false) {
  const url = new URL(endpoint);
  
  if (virtualHost) {
    url.hostname = `${bucket}.${url.hostname}`;
    url.pathname = `/${key}`;
  } else {
    url.pathname = `/${bucket}/${key}`;
  }
  
  return url.toString();
}

export async function checkS3ObjectExists(s3Client, endpoint, bucket, key, virtualHost = false) {
  try {
    const url = getS3Url(endpoint, bucket, key, virtualHost);
    const response = await s3Client.fetch(url, { method: 'HEAD' });
    return response.ok;
  } catch {
    return false;
  }
}
