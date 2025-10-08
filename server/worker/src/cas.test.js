import { describe, it, expect, beforeEach, vi } from 'vitest';
import { handleGetValue, handleSave } from './cas.js';

// Mock the dependencies
vi.mock('./s3.js', () => ({
  createS3Client: vi.fn(() => ({ mockClient: true })),
  getS3Key: vi.fn((id) => id.replace('~', '/')),
  checkS3ObjectExists: vi.fn(),
  getPresignedDownloadUrl: vi.fn(),
  getPresignedUploadUrl: vi.fn(),
}));

vi.mock('./server-fetch.js', () => ({
  serverFetch: vi.fn(),
}));

import {
  createS3Client,
  getS3Key,
  checkS3ObjectExists,
  getPresignedDownloadUrl,
  getPresignedUploadUrl,
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
    };

    mockRequest = {
      params: {
        account_handle: 'acme',
        project_handle: 'myapp',
        id: '0~abc123',
      },
      headers: {
        get: vi.fn(),
      },
    };
  });

  describe('handleGetValue', () => {
    it('should return 401 when Authorization header is missing', async () => {
      mockRequest.headers.get.mockReturnValue(null);

      const response = await handleGetValue(mockRequest, env, {});

      expect(response.status).toBe(401);
      const data = await response.json();
      expect(data.message).toContain('Missing Authorization header');
    });

    it('should return 302 redirect when artifact exists (cached prefix)', async () => {
      mockRequest.headers.get.mockReturnValue('Bearer token123');
      env.CAS_CACHE.get.mockResolvedValue('projects/acme/myapp/xcode/cas');
      checkS3ObjectExists.mockResolvedValue(true);
      getPresignedDownloadUrl.mockResolvedValue('https://s3.amazonaws.com/signed-url');

      const response = await handleGetValue(mockRequest, env, {});

      expect(response.status).toBe(302);
      expect(response.headers.get('Location')).toBe('https://s3.amazonaws.com/signed-url');
      expect(env.CAS_CACHE.get).toHaveBeenCalled();
      expect(serverFetch).not.toHaveBeenCalled();
      expect(checkS3ObjectExists).toHaveBeenCalledWith(
        expect.anything(),
        'https://s3.amazonaws.com',
        'test-bucket',
        'projects/acme/myapp/xcode/cas0/abc123',
        false
      );
    });

    it('should fetch prefix from server when not cached', async () => {
      mockRequest.headers.get.mockReturnValue('Bearer token123');
      env.CAS_CACHE.get.mockResolvedValue(null);
      serverFetch.mockResolvedValue(
        new Response(JSON.stringify({ prefix: 'server-prefix' }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        })
      );
      checkS3ObjectExists.mockResolvedValue(true);
      getPresignedDownloadUrl.mockResolvedValue('https://s3.amazonaws.com/signed-url');

      const response = await handleGetValue(mockRequest, env, {});

      expect(response.status).toBe(302);
      expect(serverFetch).toHaveBeenCalledWith(
        env,
        '/api/projects/acme/myapp/cas/prefix',
        expect.objectContaining({
          method: 'GET',
          headers: expect.objectContaining({
            Authorization: 'Bearer token123',
          }),
        })
      );
      expect(env.CAS_CACHE.put).toHaveBeenCalledWith(
        expect.any(String),
        'server-prefix',
        { expirationTtl: 3600 }
      );
    });

    it('should forward x-request-id header to server', async () => {
      mockRequest.headers.get.mockImplementation((header) => {
        if (header === 'Authorization') return 'Bearer token123';
        if (header === 'x-request-id') return 'req-123';
        return null;
      });
      env.CAS_CACHE.get.mockResolvedValue(null);
      serverFetch.mockResolvedValue(
        new Response(JSON.stringify({ prefix: 'server-prefix' }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        })
      );
      checkS3ObjectExists.mockResolvedValue(true);
      getPresignedDownloadUrl.mockResolvedValue('https://s3.amazonaws.com/signed-url');

      await handleGetValue(mockRequest, env, {});

      expect(serverFetch).toHaveBeenCalledWith(
        env,
        '/api/projects/acme/myapp/cas/prefix',
        expect.objectContaining({
          headers: expect.objectContaining({
            Authorization: 'Bearer token123',
            'x-request-id': 'req-123',
          }),
        })
      );
    });

    it('should return 404 with empty body when artifact does not exist', async () => {
      mockRequest.headers.get.mockReturnValue('Bearer token123');
      env.CAS_CACHE.get.mockResolvedValue('projects/acme/myapp/xcode/cas');
      checkS3ObjectExists.mockResolvedValue(false);

      const response = await handleGetValue(mockRequest, env, {});

      expect(response.status).toBe(404);
      expect(response.body).toBeNull();
    });

    it('should return 403 with JSON when server returns forbidden', async () => {
      mockRequest.headers.get.mockReturnValue('Bearer token123');
      env.CAS_CACHE.get.mockResolvedValue(null);
      serverFetch.mockResolvedValue(
        new Response(null, { status: 403 })
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
        new Response(null, { status: 404 })
      );

      const response = await handleGetValue(mockRequest, env, {});

      expect(response.status).toBe(404);
      expect(response.body).toBeNull();
    });

    it('should return 500 when S3 bucket is not configured', async () => {
      mockRequest.headers.get.mockReturnValue('Bearer token123');
      env.CAS_CACHE.get.mockResolvedValue('prefix');
      env.TUIST_S3_BUCKET_NAME = undefined;

      const response = await handleGetValue(mockRequest, env, {});

      expect(response.status).toBe(500);
      const data = await response.json();
      expect(data.message).toContain('Missing TUIST_S3_BUCKET_NAME');
    });
  });

  describe('handleSave', () => {
    it('should return 401 when Authorization header is missing', async () => {
      mockRequest.headers.get.mockReturnValue(null);

      const response = await handleSave(mockRequest, env, {});

      expect(response.status).toBe(401);
      const data = await response.json();
      expect(data.message).toContain('Missing Authorization header');
    });

    it('should return 302 redirect to upload URL when artifact does not exist', async () => {
      mockRequest.headers.get.mockReturnValue('Bearer token123');
      env.CAS_CACHE.get.mockResolvedValue('projects/acme/myapp/xcode/cas');
      checkS3ObjectExists.mockResolvedValue(false);
      getPresignedUploadUrl.mockResolvedValue('https://s3.amazonaws.com/upload-url');

      const response = await handleSave(mockRequest, env, {});

      expect(response.status).toBe(302);
      expect(response.headers.get('Location')).toBe('https://s3.amazonaws.com/upload-url');
      expect(getPresignedUploadUrl).toHaveBeenCalledWith(
        expect.anything(),
        'https://s3.amazonaws.com',
        'test-bucket',
        'projects/acme/myapp/xcode/cas0/abc123',
        false
      );
    });

    it('should return 304 with empty body when artifact already exists', async () => {
      mockRequest.headers.get.mockReturnValue('Bearer token123');
      env.CAS_CACHE.get.mockResolvedValue('projects/acme/myapp/xcode/cas');
      checkS3ObjectExists.mockResolvedValue(true);

      const response = await handleSave(mockRequest, env, {});

      expect(response.status).toBe(304);
      expect(response.body).toBeNull();
      expect(getPresignedUploadUrl).not.toHaveBeenCalled();
    });

    it('should use virtual host style when enabled', async () => {
      mockRequest.headers.get.mockReturnValue('Bearer token123');
      env.CAS_CACHE.get.mockResolvedValue('projects/acme/myapp/xcode/cas');
      env.TUIST_S3_VIRTUAL_HOST = 'true';
      checkS3ObjectExists.mockResolvedValue(false);
      getPresignedUploadUrl.mockResolvedValue('https://bucket.s3.amazonaws.com/upload-url');

      const response = await handleSave(mockRequest, env, {});

      expect(response.status).toBe(302);
      expect(checkS3ObjectExists).toHaveBeenCalledWith(
        expect.anything(),
        'https://s3.amazonaws.com',
        'test-bucket',
        'projects/acme/myapp/xcode/cas0/abc123',
        true
      );
    });

    it('should return 403 with JSON when server returns forbidden', async () => {
      mockRequest.headers.get.mockReturnValue('Bearer token123');
      env.CAS_CACHE.get.mockResolvedValue(null);
      serverFetch.mockResolvedValue(
        new Response(null, { status: 403 })
      );

      const response = await handleSave(mockRequest, env, {});

      expect(response.status).toBe(403);
      const data = await response.json();
      expect(data.message).toBe('Unauthorized or not found');
    });

    it('should cache prefix with SHA-256 hash key', async () => {
      mockRequest.headers.get.mockReturnValue('Bearer token123');
      env.CAS_CACHE.get.mockResolvedValue(null);
      serverFetch.mockResolvedValue(
        new Response(JSON.stringify({ prefix: 'new-prefix' }), {
          status: 200,
          headers: { 'Content-Type': 'application/json' },
        })
      );
      checkS3ObjectExists.mockResolvedValue(false);
      getPresignedUploadUrl.mockResolvedValue('https://s3.amazonaws.com/upload-url');

      await handleSave(mockRequest, env, {});

      expect(env.CAS_CACHE.put).toHaveBeenCalledWith(
        expect.stringMatching(/^[0-9a-f]{64}$/), // SHA-256 hash
        'new-prefix',
        { expirationTtl: 3600 }
      );
    });
  });
});
