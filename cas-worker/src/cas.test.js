import { describe, it, expect, beforeEach, vi } from 'vitest';
import { handleGetValue, handleSave } from './cas.js';

// Create mock S3 client
const mockS3Client = {
  fetch: vi.fn()
};

// Mock the dependencies
vi.mock('./s3.js', () => ({
  createS3Client: vi.fn(() => mockS3Client),
  getS3Key: vi.fn((id) => id.replace('~', '/')),
  checkS3ObjectExists: vi.fn(),
  getS3Url: vi.fn(),
}));

vi.mock('./server-fetch.js', () => ({
  serverFetch: vi.fn(),
}));

import {
  createS3Client,
  getS3Key,
  checkS3ObjectExists,
  getS3Url,
} from './s3.js';
import { serverFetch } from './server-fetch.js';

describe('CAS Module', () => {
  let env;
  let mockRequest;

  beforeEach(() => {
    vi.clearAllMocks();

    env = {
      TUIST_S3_REGION: 'us-east-1',
      TUIST_S3_ENDPOINT: 'https://s3.amazonaws.com',
      TUIST_S3_BUCKET_NAME: 'test-bucket',
      TUIST_S3_ACCESS_KEY_ID: 'test-key',
      TUIST_S3_SECRET_ACCESS_KEY: 'test-secret',
      TUIST_S3_VIRTUAL_HOST: 'false',
      SERVER_URL: 'http://localhost:8080',
      CAS_CACHE: {
        get: vi.fn(),
        put: vi.fn(),
      },
      CAS_CACHE_BLOBS: {
        get: vi.fn(),
        put: vi.fn().mockResolvedValue(undefined),
      },
    };

    mockRequest = {
      params: {
        id: '0~abc123',
      },
      query: {
        account_handle: 'acme',
        project_handle: 'myapp',
      },
      headers: {
        get: vi.fn(),
      },
      body: null,
    };
  });

  describe('handleGetValue', () => {
    it('should return 400 when query parameters are missing', async () => {
      mockRequest.query = {};
      mockRequest.headers.get.mockReturnValue('Bearer token123');

      const response = await handleGetValue(mockRequest, env, {});

      expect(response.status).toBe(400);
      const data = await response.json();
      expect(data.message).toContain('Missing account_handle or project_handle');
    });

    it('should return 401 when Authorization header is missing', async () => {
      mockRequest.headers.get.mockReturnValue(null);

      const response = await handleGetValue(mockRequest, env, {});

      expect(response.status).toBe(401);
      const data = await response.json();
      expect(data.message).toContain('Missing Authorization header');
    });

    it('should return blob from KV cache if available', async () => {
      mockRequest.headers.get.mockReturnValue('Bearer token123');
      env.CAS_CACHE.get.mockResolvedValue(JSON.stringify({ prefix: 'acme/myapp/cas/' }));

      const blobContent = new Uint8Array([1, 2, 3, 4]);
      env.CAS_CACHE_BLOBS.get.mockResolvedValue(blobContent.buffer);

      const response = await handleGetValue(mockRequest, env, {});

      expect(response.status).toBe(200);
      expect(env.CAS_CACHE_BLOBS.get).toHaveBeenCalledWith('acme/myapp/cas/0/abc123', 'arrayBuffer');
      expect(checkS3ObjectExists).not.toHaveBeenCalled();
      expect(mockS3Client.fetch).not.toHaveBeenCalled();
    });

    it('should stream download from S3 when not in KV cache', async () => {
      mockRequest.headers.get.mockReturnValue('Bearer token123');
      env.CAS_CACHE.get.mockResolvedValue(JSON.stringify({ prefix: 'acme/myapp/cas/' }));
      env.CAS_CACHE_BLOBS.get.mockResolvedValue(null);
      checkS3ObjectExists.mockResolvedValue(true);
      getS3Url.mockReturnValue('https://s3.amazonaws.com/test-bucket/acme/myapp/cas/0/abc123');

      const mockS3Response = new Response('file content', {
        status: 200,
        headers: { 'Content-Type': 'application/octet-stream' }
      });
      mockS3Client.fetch.mockResolvedValue(mockS3Response);

      const response = await handleGetValue(mockRequest, env, {});

      expect(response.status).toBe(200);
      expect(env.CAS_CACHE_BLOBS.get).toHaveBeenCalledWith('acme/myapp/cas/0/abc123', 'arrayBuffer');
      expect(env.CAS_CACHE.get).toHaveBeenCalled();
      expect(serverFetch).not.toHaveBeenCalled();
      expect(checkS3ObjectExists).toHaveBeenCalledWith(
        expect.anything(),
        'https://s3.amazonaws.com',
        'test-bucket',
        'acme/myapp/cas/0/abc123',
        false
      );
      expect(mockS3Client.fetch).toHaveBeenCalledWith(
        'https://s3.amazonaws.com/test-bucket/acme/myapp/cas/0/abc123',
        { method: 'GET' }
      );
    });

    it('should fetch prefix from server when not cached', async () => {
      mockRequest.headers.get.mockReturnValue('Bearer token123');
      env.CAS_CACHE.get.mockResolvedValue(null);
      serverFetch.mockResolvedValue(
        new Response(JSON.stringify({ prefix: 'server-prefix/' }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        })
      );
      checkS3ObjectExists.mockResolvedValue(true);
      getS3Url.mockReturnValue('https://s3.amazonaws.com/test-bucket/server-prefix/0/abc123');

      mockS3Client.fetch.mockResolvedValue(new Response('file content', { status: 200 }));

      const response = await handleGetValue(mockRequest, env, {});

      expect(response.status).toBe(200);
      expect(serverFetch).toHaveBeenCalledWith(
        env,
        '/api/cache/cas/prefix?account_handle=acme&project_handle=myapp',
        expect.objectContaining({
          method: 'GET',
          headers: expect.objectContaining({
            Authorization: 'Bearer token123',
          }),
        })
      );
      expect(env.CAS_CACHE.put).toHaveBeenCalledWith(
        expect.any(String),
        JSON.stringify({ prefix: 'server-prefix/' }),
        { expirationTtl: 3600 }
      );
    });

    it('should use cached authorization success', async () => {
      mockRequest.headers.get.mockReturnValue('Bearer token123');
      env.CAS_CACHE.get.mockResolvedValue(JSON.stringify({ prefix: 'cached-prefix/' }));
      checkS3ObjectExists.mockResolvedValue(true);
      getS3Url.mockReturnValue('https://s3.amazonaws.com/test-bucket/cached-prefix/0/abc123');

      mockS3Client.fetch.mockResolvedValue(new Response('content', { status: 200 }));

      const response = await handleGetValue(mockRequest, env, {});

      expect(response.status).toBe(200);
      expect(serverFetch).not.toHaveBeenCalled();
      expect(checkS3ObjectExists).toHaveBeenCalledWith(
        expect.anything(),
        'https://s3.amazonaws.com',
        'test-bucket',
        'cached-prefix/0/abc123',
        false
      );
    });

    it('should cache authorization failures with shorter TTL', async () => {
      mockRequest.headers.get.mockReturnValue('Bearer invalid-token');
      env.CAS_CACHE.get.mockResolvedValue(null);
      serverFetch.mockResolvedValue(
        new Response(JSON.stringify({ error: 'Forbidden' }), { status: 403 })
      );

      const response = await handleGetValue(mockRequest, env, {});

      expect(response.status).toBe(403);
      expect(env.CAS_CACHE.put).toHaveBeenCalledWith(
        expect.any(String),
        JSON.stringify({ error: 'Unauthorized or not found', status: 403 }),
        { expirationTtl: 300 }
      );
    });

    it('should use cached authorization failure', async () => {
      mockRequest.headers.get.mockReturnValue('Bearer invalid-token');
      env.CAS_CACHE.get.mockResolvedValue(
        JSON.stringify({ error: 'Unauthorized or not found', status: 403 })
      );

      const response = await handleGetValue(mockRequest, env, {});

      expect(response.status).toBe(403);
      expect(serverFetch).not.toHaveBeenCalled();
      const data = await response.json();
      expect(data.message).toBe('Unauthorized or not found');
    });

    it('should forward x-request-id header to server', async () => {
      mockRequest.headers.get.mockImplementation((header) => {
        if (header === 'Authorization') return 'Bearer token123';
        if (header === 'x-request-id') return 'req-123';
        return null;
      });
      env.CAS_CACHE.get.mockResolvedValue(null);
      serverFetch.mockResolvedValue(
        new Response(JSON.stringify({ prefix: 'server-prefix/' }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        })
      );
      checkS3ObjectExists.mockResolvedValue(true);
      getS3Url.mockReturnValue('https://s3.amazonaws.com/test-bucket/server-prefix/0/abc123');

      mockS3Client.fetch.mockResolvedValue(new Response('content', { status: 200 }));

      await handleGetValue(mockRequest, env, {});

      expect(serverFetch).toHaveBeenCalledWith(
        env,
        '/api/cache/cas/prefix?account_handle=acme&project_handle=myapp',
        expect.objectContaining({
          headers: expect.objectContaining({
            Authorization: 'Bearer token123',
            'x-request-id': 'req-123',
          }),
        })
      );
    });

    it('should return 404 with JSON when artifact does not exist', async () => {
      mockRequest.headers.get.mockReturnValue('Bearer token123');
      env.CAS_CACHE.get.mockResolvedValue(JSON.stringify({ prefix: 'prefix/' }));
      checkS3ObjectExists.mockResolvedValue(false);

      const response = await handleGetValue(mockRequest, env, {});

      expect(response.status).toBe(404);
      const data = await response.json();
      expect(data.message).toBe('Artifact does not exist');
    });

    it('should return 403 with JSON when server returns forbidden', async () => {
      mockRequest.headers.get.mockReturnValue('Bearer token123');
      env.CAS_CACHE.get.mockResolvedValue(null);
      serverFetch.mockResolvedValue(
        new Response(JSON.stringify({ error: 'Forbidden' }), { status: 403 })
      );

      const response = await handleGetValue(mockRequest, env, {});

      expect(response.status).toBe(403);
      const data = await response.json();
      expect(data.message).toBe('Unauthorized or not found');
    });

    it('should return 404 with empty body when server returns not found', async () => {
      mockRequest.headers.get.mockReturnValue('Bearer token123');
      env.CAS_CACHE.get.mockResolvedValue(null);
      serverFetch.mockResolvedValue(
        new Response(JSON.stringify({ error: 'Not found' }), { status: 404 })
      );

      const response = await handleGetValue(mockRequest, env, {});

      expect(response.status).toBe(404);
      const body = await response.text();
      expect(body).toBe('');
    });

    it('should return 500 when S3 bucket is not configured', async () => {
      mockRequest.headers.get.mockReturnValue('Bearer token123');
      env.CAS_CACHE.get.mockResolvedValue(JSON.stringify({ prefix: 'prefix/' }));
      env.TUIST_S3_BUCKET_NAME = undefined;

      const response = await handleGetValue(mockRequest, env, {});

      expect(response.status).toBe(500);
      const data = await response.json();
      expect(data.message).toContain('Missing TUIST_S3_BUCKET_NAME');
    });
  });

  describe('handleSave', () => {
    it('should return 400 when query parameters are missing', async () => {
      mockRequest.query = {};
      mockRequest.headers.get.mockReturnValue('Bearer token123');

      const response = await handleSave(mockRequest, env, {});

      expect(response.status).toBe(400);
      const data = await response.json();
      expect(data.message).toContain('Missing account_handle or project_handle');
    });

    it('should return 401 when Authorization header is missing', async () => {
      mockRequest.headers.get.mockReturnValue(null);

      const response = await handleSave(mockRequest, env, {});

      expect(response.status).toBe(401);
      const data = await response.json();
      expect(data.message).toContain('Missing Authorization header');
    });

    it('should store small blob in KV when artifact does not exist', async () => {
      mockRequest.headers.get.mockImplementation((header) => {
        if (header === 'Authorization') return 'Bearer token123';
        if (header === 'Content-Type') return null;
        return null;
      });

      const smallContent = 'small file content';
      mockRequest.arrayBuffer = vi.fn().mockResolvedValue(new TextEncoder().encode(smallContent).buffer);

      env.CAS_CACHE.get.mockResolvedValue(JSON.stringify({ prefix: 'acme/myapp/cas/' }));
      env.CAS_CACHE_BLOBS.get.mockResolvedValue(null);
      checkS3ObjectExists.mockResolvedValue(false);
      getS3Url.mockReturnValue('https://s3.amazonaws.com/test-bucket/acme/myapp/cas/0/abc123');

      const mockS3Response = new Response(null, { status: 200 });
      mockS3Client.fetch.mockResolvedValue(mockS3Response);

      const response = await handleSave(mockRequest, env, {});

      expect(response.status).toBe(200);
      expect(env.CAS_CACHE_BLOBS.put).toHaveBeenCalledWith(
        'acme/myapp/cas/0/abc123',
        expect.any(ArrayBuffer)
      );
      expect(mockS3Client.fetch).toHaveBeenCalled();
    });

    it('should store large blob in S3 when exceeds KV limit', async () => {
      mockRequest.headers.get.mockImplementation((header) => {
        if (header === 'Authorization') return 'Bearer token123';
        if (header === 'Content-Type') return null;
        return null;
      });

      // Create a buffer larger than 25 MB
      const largeBuffer = new ArrayBuffer(26 * 1024 * 1024);
      mockRequest.arrayBuffer = vi.fn().mockResolvedValue(largeBuffer);

      env.CAS_CACHE.get.mockResolvedValue(JSON.stringify({ prefix: 'acme/myapp/cas/' }));
      env.CAS_CACHE_BLOBS.get.mockResolvedValue(null);
      checkS3ObjectExists.mockResolvedValue(false);
      getS3Url.mockReturnValue('https://s3.amazonaws.com/test-bucket/acme/myapp/cas/0/abc123');

      const mockS3Response = new Response(null, {
        status: 200,
        headers: { 'ETag': '"abc123"' }
      });
      mockS3Client.fetch.mockResolvedValue(mockS3Response);

      const response = await handleSave(mockRequest, env, {});

      expect(response.status).toBe(200);
      expect(env.CAS_CACHE_BLOBS.put).not.toHaveBeenCalled();
      expect(mockS3Client.fetch).toHaveBeenCalledWith(
        'https://s3.amazonaws.com/test-bucket/acme/myapp/cas/0/abc123',
        expect.objectContaining({
          method: 'PUT',
          body: largeBuffer,
          headers: {
            'Content-Type': 'application/octet-stream',
          },
        })
      );
    });

    it('should return 200 when blob already exists in KV', async () => {
      mockRequest.headers.get.mockReturnValue('Bearer token123');
      env.CAS_CACHE.get.mockResolvedValue(JSON.stringify({ prefix: 'prefix/' }));
      env.CAS_CACHE_BLOBS.get.mockResolvedValue(new ArrayBuffer(100));

      const response = await handleSave(mockRequest, env, {});

      expect(response.status).toBe(200);
      expect(checkS3ObjectExists).not.toHaveBeenCalled();
    });

    it('should return 200 when artifact already exists in S3', async () => {
      mockRequest.headers.get.mockReturnValue('Bearer token123');
      env.CAS_CACHE.get.mockResolvedValue(JSON.stringify({ prefix: 'prefix/' }));
      env.CAS_CACHE_BLOBS.get.mockResolvedValue(null);
      checkS3ObjectExists.mockResolvedValue(true);

      const response = await handleSave(mockRequest, env, {});

      expect(response.status).toBe(200);
    });

    it('should use virtual host style when enabled', async () => {
      mockRequest.headers.get.mockReturnValue('Bearer token123');
      const largeBuffer = new ArrayBuffer(26 * 1024 * 1024);
      mockRequest.arrayBuffer = vi.fn().mockResolvedValue(largeBuffer);
      env.CAS_CACHE.get.mockResolvedValue(JSON.stringify({ prefix: 'prefix/' }));
      env.CAS_CACHE_BLOBS.get.mockResolvedValue(null);
      env.TUIST_S3_VIRTUAL_HOST = 'true';
      checkS3ObjectExists.mockResolvedValue(false);
      getS3Url.mockReturnValue('https://bucket.s3.amazonaws.com/prefix/0/abc123');

      mockS3Client.fetch.mockResolvedValue(new Response(null, { status: 200 }));

      const response = await handleSave(mockRequest, env, {});

      expect(response.status).toBe(200);
      expect(checkS3ObjectExists).toHaveBeenCalledWith(
        expect.anything(),
        'https://s3.amazonaws.com',
        'test-bucket',
        'prefix/0/abc123',
        true
      );
    });

    it('should return 403 with JSON when server returns forbidden', async () => {
      mockRequest.headers.get.mockReturnValue('Bearer token123');
      env.CAS_CACHE.get.mockResolvedValue(null);
      serverFetch.mockResolvedValue(
        new Response(JSON.stringify({ error: 'Forbidden' }), { status: 403 })
      );

      const response = await handleSave(mockRequest, env, {});

      expect(response.status).toBe(403);
      const data = await response.json();
      expect(data.message).toBe('Unauthorized or not found');
    });

    it('should cache prefix with SHA-256 hash key', async () => {
      mockRequest.headers.get.mockReturnValue('Bearer token123');
      const smallContent = 'content';
      mockRequest.arrayBuffer = vi.fn().mockResolvedValue(new TextEncoder().encode(smallContent).buffer);
      env.CAS_CACHE.get.mockResolvedValue(null);
      env.CAS_CACHE_BLOBS.get.mockResolvedValue(null);
      serverFetch.mockResolvedValue(
        new Response(JSON.stringify({ prefix: 'new-prefix/' }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        })
      );
      checkS3ObjectExists.mockResolvedValue(false);
      getS3Url.mockReturnValue('https://bucket.s3.amazonaws.com/prefix/0/abc123');

      const mockS3Response = new Response(null, { status: 200 });
      mockS3Client.fetch.mockResolvedValue(mockS3Response);

      await handleSave(mockRequest, env, {});

      expect(env.CAS_CACHE.put).toHaveBeenCalledWith(
        expect.stringMatching(/^[0-9a-f]{64}$/), // SHA-256 hash
        JSON.stringify({ prefix: 'new-prefix/' }),
        { expirationTtl: 3600 }
      );
    });

    it('should cache 401 authorization failures', async () => {
      mockRequest.headers.get.mockReturnValue('Bearer bad-token');
      env.CAS_CACHE.get.mockResolvedValue(null);
      serverFetch.mockResolvedValue(
        new Response(JSON.stringify({ error: 'Unauthorized' }), { status: 401 })
      );

      const response = await handleSave(mockRequest, env, {});

      expect(response.status).toBe(401);
      expect(env.CAS_CACHE.put).toHaveBeenCalledWith(
        expect.any(String),
        JSON.stringify({ error: 'Unauthorized or not found', status: 401 }),
        { expirationTtl: 300 }
      );
    });
  });
});
