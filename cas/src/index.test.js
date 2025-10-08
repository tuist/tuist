import { describe, it, expect, beforeEach, vi } from 'vitest';
import worker from './index.js';

// Mock AWS SDK
vi.mock('@aws-sdk/client-s3', () => {
  const HeadObjectCommand = vi.fn();
  const S3Client = vi.fn();
  return {
    S3Client,
    HeadObjectCommand,
  };
});

vi.mock('@aws-sdk/s3-request-presigner', () => ({
  getSignedUrl: vi.fn(),
}));

import { S3Client, HeadObjectCommand } from '@aws-sdk/client-s3';
import { getSignedUrl } from '@aws-sdk/s3-request-presigner';

describe('CAS Worker', () => {
  let env;
  let mockS3Send;

  beforeEach(() => {
    vi.clearAllMocks();

    env = {
      TUIST_S3_REGION: 'us-east-1',
      TUIST_S3_ENDPOINT: 'https://s3.amazonaws.com',
      TUIST_S3_BUCKET_NAME: 'test-bucket',
      TUIST_S3_BUCKET_AS_HOST: 'false',
      TUIST_S3_VIRTUAL_HOST: 'false',
      TUIST_S3_ACCESS_KEY_ID: 'test-key-id',
      TUIST_S3_SECRET_ACCESS_KEY: 'test-secret-key',
    };

    mockS3Send = vi.fn();
    S3Client.mockImplementation(() => ({
      send: mockS3Send,
    }));
  });

  describe('GET /api/cas/:id', () => {
    it('should return 404 for unknown paths', async () => {
      const request = new Request('http://localhost/unknown', {
        method: 'GET',
      });

      const response = await worker.fetch(request, env, {});
      expect(response.status).toBe(404);
    });

    it('should return 404 with no body when object does not exist', async () => {
      const notFoundError = new Error('Not found');
      notFoundError.name = 'NotFound';
      mockS3Send.mockRejectedValue(notFoundError);

      const request = new Request('http://localhost/api/cas/abc123', {
        method: 'GET',
      });

      const response = await worker.fetch(request, env, {});
      expect(response.status).toBe(404);
      expect(response.body).toBeNull();
    });

    it('should return redirect when object exists', async () => {
      mockS3Send.mockResolvedValue({});
      getSignedUrl.mockResolvedValue('https://s3.amazonaws.com/test-bucket/test-object?signed=true');

      const request = new Request('http://localhost/api/cas/abc123', {
        method: 'GET',
      });

      const response = await worker.fetch(request, env, {});
      expect(response.status).toBe(302);
      expect(response.headers.get('Location')).toContain('s3.amazonaws.com');
    });

    it('should return 500 when missing required environment variables', async () => {
      const invalidEnv = { ...env };
      delete invalidEnv.TUIST_S3_REGION;

      const request = new Request('http://localhost/api/cas/abc123', {
        method: 'GET',
      });

      const response = await worker.fetch(request, invalidEnv, {});
      expect(response.status).toBe(500);

      const data = await response.json();
      expect(data.error).toContain('Missing required environment variable');
    });
  });

  describe('POST /api/cas/:id', () => {
    it('should return 302 redirect to upload URL when object does not exist', async () => {
      const notFoundError = new Error('Not found');
      notFoundError.name = 'NotFound';
      mockS3Send.mockRejectedValue(notFoundError);
      getSignedUrl.mockResolvedValue('https://s3.amazonaws.com/test-bucket/upload?signed=true');

      const request = new Request('http://localhost/api/cas/abc123', {
        method: 'POST',
      });

      const response = await worker.fetch(request, env, {});
      expect(response.status).toBe(302);
      expect(response.headers.get('Location')).toContain('s3.amazonaws.com');
    });

    it('should return 304 with no body when object exists', async () => {
      mockS3Send.mockResolvedValue({});

      const request = new Request('http://localhost/api/cas/abc123', {
        method: 'POST',
      });

      const response = await worker.fetch(request, env, {});
      expect(response.status).toBe(304);
      expect(response.body).toBeNull();
    });

    it('should return 500 when bucket name is missing', async () => {
      const invalidEnv = { ...env };
      delete invalidEnv.TUIST_S3_BUCKET_NAME;

      const request = new Request('http://localhost/api/cas/abc123', {
        method: 'POST',
      });

      const response = await worker.fetch(request, invalidEnv, {});
      expect(response.status).toBe(500);

      const data = await response.json();
      expect(data.error).toContain('Missing TUIST_S3_BUCKET_NAME');
    });
  });

  describe('S3 Configuration', () => {
    it('should use path style when TUIST_S3_BUCKET_AS_HOST is false', async () => {
      env.TUIST_S3_BUCKET_AS_HOST = 'false';
      mockS3Send.mockResolvedValue({});
      getSignedUrl.mockResolvedValue('https://s3.amazonaws.com/test-bucket/object');

      const request = new Request('http://localhost/api/cas/abc123', {
        method: 'GET',
      });

      await worker.fetch(request, env, {});

      expect(S3Client).toHaveBeenCalledWith(
        expect.objectContaining({
          forcePathStyle: true,
        })
      );
    });

    it('should use virtual host style when TUIST_S3_BUCKET_AS_HOST is true', async () => {
      env.TUIST_S3_BUCKET_AS_HOST = 'true';
      mockS3Send.mockResolvedValue({});
      getSignedUrl.mockResolvedValue('https://s3.amazonaws.com/test-bucket/object');

      const request = new Request('http://localhost/api/cas/abc123', {
        method: 'GET',
      });

      await worker.fetch(request, env, {});

      expect(S3Client).toHaveBeenCalledWith(
        expect.objectContaining({
          forcePathStyle: false,
        })
      );
    });
  });
});
