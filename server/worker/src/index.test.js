import { describe, it, expect, beforeEach, vi } from 'vitest';
import worker from './index.js';

// Mock aws4fetch
vi.mock('aws4fetch', () => {
  const AwsClient = vi.fn();
  return {
    AwsClient,
  };
});

// Mock global fetch
global.fetch = vi.fn();

import { AwsClient } from 'aws4fetch';

describe('CAS Worker', () => {
  let env;
  let mockFetch;
  let mockSign;
  let mockKVGet;
  let mockKVPut;

  beforeEach(() => {
    vi.clearAllMocks();
    global.fetch.mockClear();

    env = {
      TUIST_S3_REGION: 'us-east-1',
      TUIST_S3_ENDPOINT: 'https://s3.amazonaws.com',
      TUIST_S3_BUCKET_NAME: 'test-bucket',
      TUIST_S3_BUCKET_AS_HOST: 'false',
      TUIST_S3_VIRTUAL_HOST: 'false',
      TUIST_S3_ACCESS_KEY_ID: 'test-key-id',
      TUIST_S3_SECRET_ACCESS_KEY: 'test-secret-key',
      SERVER_URL: 'http://localhost:8080',
      CAS_CACHE: {
        get: vi.fn(),
        put: vi.fn(),
      },
    };

    mockFetch = vi.fn();
    mockSign = vi.fn();
    mockKVGet = env.CAS_CACHE.get;
    mockKVPut = env.CAS_CACHE.put;

    AwsClient.mockImplementation(() => ({
      fetch: mockFetch,
      sign: mockSign,
    }));
  });

  describe('GET /api/projects/:account_handle/:project_handle/cas/:id', () => {
    it('should return 404 for unknown paths', async () => {
      const request = new Request('http://localhost/unknown', {
        method: 'GET',
      });

      const response = await worker.fetch(request, env, {});
      expect(response.status).toBe(404);
    });

    it('should return 401 when missing Authorization header', async () => {
      const request = new Request('http://localhost/api/projects/acme/myapp/cas/abc123', {
        method: 'GET',
      });

      const response = await worker.fetch(request, env, {});
      expect(response.status).toBe(401);

      const data = await response.json();
      expect(data.error).toContain('Missing Authorization header');
    });

    it('should use cached prefix when available', async () => {
      mockKVGet.mockResolvedValue('cached-prefix');
      mockFetch.mockResolvedValue(new Response(null, { status: 200 }));
      mockSign.mockResolvedValue({ url: 'https://s3.amazonaws.com/test-bucket/object?signed=true' });

      const request = new Request('http://localhost/api/projects/acme/myapp/cas/abc123', {
        method: 'GET',
        headers: { 'Authorization': 'Bearer token123' },
      });

      const response = await worker.fetch(request, env, {});
      expect(response.status).toBe(302);
      expect(mockKVGet).toHaveBeenCalled();
      expect(global.fetch).not.toHaveBeenCalled(); // Should not call server
    });

    it('should fetch prefix from server when not cached', async () => {
      mockKVGet.mockResolvedValue(null);
      global.fetch.mockResolvedValue(
        new Response(JSON.stringify({ prefix: 'server-prefix' }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        })
      );
      mockFetch.mockResolvedValue(new Response(null, { status: 200 }));
      mockSign.mockResolvedValue({ url: 'https://s3.amazonaws.com/test-bucket/object?signed=true' });

      const request = new Request('http://localhost/api/projects/acme/myapp/cas/abc123', {
        method: 'GET',
        headers: { 'Authorization': 'Bearer token123' },
      });

      const response = await worker.fetch(request, env, {});
      expect(response.status).toBe(302);
      expect(mockKVGet).toHaveBeenCalled();
      expect(global.fetch).toHaveBeenCalledWith(
        'http://localhost:8080/api/projects/acme/myapp/cas/prefix',
        expect.objectContaining({
          method: 'GET',
          headers: expect.objectContaining({
            'Authorization': 'Bearer token123',
          }),
        })
      );
      expect(mockKVPut).toHaveBeenCalledWith(
        expect.any(String),
        'server-prefix',
        { expirationTtl: 3600 }
      );
    });

    it('should forward x-request-id header to server', async () => {
      mockKVGet.mockResolvedValue(null);
      global.fetch.mockResolvedValue(
        new Response(JSON.stringify({ prefix: 'server-prefix' }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        })
      );
      mockFetch.mockResolvedValue(new Response(null, { status: 200 }));
      mockSign.mockResolvedValue({ url: 'https://s3.amazonaws.com/test-bucket/object?signed=true' });

      const request = new Request('http://localhost/api/projects/acme/myapp/cas/abc123', {
        method: 'GET',
        headers: {
          'Authorization': 'Bearer token123',
          'x-request-id': 'req-123',
        },
      });

      await worker.fetch(request, env, {});

      expect(global.fetch).toHaveBeenCalledWith(
        'http://localhost:8080/api/projects/acme/myapp/cas/prefix',
        expect.objectContaining({
          headers: expect.objectContaining({
            'Authorization': 'Bearer token123',
            'x-request-id': 'req-123',
          }),
        })
      );
    });

    it('should return 404 when object does not exist in S3', async () => {
      mockKVGet.mockResolvedValue('cached-prefix');
      mockFetch.mockResolvedValue(new Response(null, { status: 404 }));

      const request = new Request('http://localhost/api/projects/acme/myapp/cas/abc123', {
        method: 'GET',
        headers: { 'Authorization': 'Bearer token123' },
      });

      const response = await worker.fetch(request, env, {});
      expect(response.status).toBe(404);
      expect(response.body).toBeNull();
    });
  });

  describe('POST /api/projects/:account_handle/:project_handle/cas/:id', () => {
    it('should return upload URL when object does not exist', async () => {
      mockKVGet.mockResolvedValue('cached-prefix');
      mockFetch.mockResolvedValue(new Response(null, { status: 404 }));
      mockSign.mockResolvedValue({ url: 'https://s3.amazonaws.com/test-bucket/upload?signed=true' });

      const request = new Request('http://localhost/api/projects/acme/myapp/cas/abc123', {
        method: 'POST',
        headers: { 'Authorization': 'Bearer token123' },
      });

      const response = await worker.fetch(request, env, {});
      expect(response.status).toBe(302);
      expect(response.headers.get('Location')).toContain('s3.amazonaws.com');
    });

    it('should return 304 when object exists in S3', async () => {
      mockKVGet.mockResolvedValue('cached-prefix');
      mockFetch.mockResolvedValue(new Response(null, { status: 200 }));

      const request = new Request('http://localhost/api/projects/acme/myapp/cas/abc123', {
        method: 'POST',
        headers: { 'Authorization': 'Bearer token123' },
      });

      const response = await worker.fetch(request, env, {});
      expect(response.status).toBe(304);
      expect(response.body).toBeNull();
    });
  });
});
