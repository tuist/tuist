import { describe, it, expect, beforeEach, vi } from 'vitest';
import worker from './index.js';

// Mock aws4fetch
vi.mock('aws4fetch', () => {
  const AwsClient = vi.fn();
  return {
    AwsClient,
  };
});

import { AwsClient } from 'aws4fetch';

describe('CAS Worker', () => {
  let env;
  let mockFetch;
  let mockSign;

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

    mockFetch = vi.fn();
    mockSign = vi.fn();

    AwsClient.mockImplementation(() => ({
      fetch: mockFetch,
      sign: mockSign,
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
      mockFetch.mockResolvedValue(new Response(null, { status: 404 }));

      const request = new Request('http://localhost/api/cas/abc123', {
        method: 'GET',
      });

      const response = await worker.fetch(request, env, {});
      expect(response.status).toBe(404);
      expect(response.body).toBeNull();
    });

    it('should return redirect when object exists', async () => {
      mockFetch.mockResolvedValue(new Response(null, { status: 200 }));
      mockSign.mockResolvedValue({ url: 'https://s3.amazonaws.com/test-bucket/test-object?signed=true' });

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
      mockFetch.mockResolvedValue(new Response(null, { status: 404 }));
      mockSign.mockResolvedValue({ url: 'https://s3.amazonaws.com/test-bucket/upload?signed=true' });

      const request = new Request('http://localhost/api/cas/abc123', {
        method: 'POST',
      });

      const response = await worker.fetch(request, env, {});
      expect(response.status).toBe(302);
      expect(response.headers.get('Location')).toContain('s3.amazonaws.com');
    });

    it('should return 304 with no body when object exists', async () => {
      mockFetch.mockResolvedValue(new Response(null, { status: 200 }));

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
    it('should construct path style URLs when TUIST_S3_BUCKET_AS_HOST is false', async () => {
      env.TUIST_S3_BUCKET_AS_HOST = 'false';
      mockFetch.mockResolvedValue(new Response(null, { status: 200 }));
      mockSign.mockResolvedValue({ url: 'https://s3.amazonaws.com/test-bucket/object?signed=true' });

      const request = new Request('http://localhost/api/cas/abc123', {
        method: 'GET',
      });

      await worker.fetch(request, env, {});

      expect(AwsClient).toHaveBeenCalledWith(
        expect.objectContaining({
          accessKeyId: 'test-key-id',
          secretAccessKey: 'test-secret-key',
          region: 'us-east-1',
          service: 's3',
        })
      );
    });

    it('should handle virtual host style when TUIST_S3_VIRTUAL_HOST is true', async () => {
      env.TUIST_S3_VIRTUAL_HOST = 'true';
      mockFetch.mockResolvedValue(new Response(null, { status: 200 }));
      mockSign.mockResolvedValue({ url: 'https://test-bucket.s3.amazonaws.com/object?signed=true' });

      const request = new Request('http://localhost/api/cas/abc123', {
        method: 'GET',
      });

      await worker.fetch(request, env, {});

      expect(mockSign).toHaveBeenCalled();
    });
  });

  describe('Unsupported HTTP Methods', () => {
    it('should return 404 for unsupported methods', async () => {
      const request = new Request('http://localhost/api/cas/abc123', {
        method: 'PUT',
      });

      const response = await worker.fetch(request, env, {});
      expect(response.status).toBe(404);
    });
  });
});
