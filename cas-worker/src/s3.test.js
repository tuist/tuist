import { describe, it, expect, vi, beforeEach } from 'vitest';
import {
  createS3Client,
  getS3Key,
  checkS3ObjectExists,
} from './s3.js';
import { AwsClient } from 'aws4fetch';

// Mock aws4fetch
vi.mock('aws4fetch', () => {
  const AwsClient = vi.fn();
  return {
    AwsClient,
  };
});

describe('S3 Module', () => {
  describe('createS3Client', () => {
    it('should create an S3 client with all required environment variables', () => {
      const env = {
        TUIST_S3_REGION: 'us-east-1',
        TUIST_S3_ENDPOINT: 'https://s3.amazonaws.com',
        TUIST_S3_ACCESS_KEY_ID: 'test-access-key',
        TUIST_S3_SECRET_ACCESS_KEY: 'test-secret-key',
      };

      createS3Client(env);

      expect(AwsClient).toHaveBeenCalledWith({
        accessKeyId: 'test-access-key',
        secretAccessKey: 'test-secret-key',
        region: 'us-east-1',
        service: 's3',
      });
    });

    it('should throw error when TUIST_S3_REGION is missing', () => {
      const env = {
        TUIST_S3_ENDPOINT: 'https://s3.amazonaws.com',
        TUIST_S3_ACCESS_KEY_ID: 'test-access-key',
        TUIST_S3_SECRET_ACCESS_KEY: 'test-secret-key',
      };

      expect(() => createS3Client(env)).toThrow('Missing required environment variable: TUIST_S3_REGION');
    });

    it('should throw error when TUIST_S3_ENDPOINT is missing', () => {
      const env = {
        TUIST_S3_REGION: 'us-east-1',
        TUIST_S3_ACCESS_KEY_ID: 'test-access-key',
        TUIST_S3_SECRET_ACCESS_KEY: 'test-secret-key',
      };

      expect(() => createS3Client(env)).toThrow('Missing required environment variable: TUIST_S3_ENDPOINT');
    });

    it('should throw error when TUIST_S3_ACCESS_KEY_ID is missing', () => {
      const env = {
        TUIST_S3_REGION: 'us-east-1',
        TUIST_S3_ENDPOINT: 'https://s3.amazonaws.com',
        TUIST_S3_SECRET_ACCESS_KEY: 'test-secret-key',
      };

      expect(() => createS3Client(env)).toThrow('Missing required environment variable: TUIST_S3_ACCESS_KEY_ID');
    });

    it('should throw error when TUIST_S3_SECRET_ACCESS_KEY is missing', () => {
      const env = {
        TUIST_S3_REGION: 'us-east-1',
        TUIST_S3_ENDPOINT: 'https://s3.amazonaws.com',
        TUIST_S3_ACCESS_KEY_ID: 'test-access-key',
      };

      expect(() => createS3Client(env)).toThrow('Missing required environment variable: TUIST_S3_SECRET_ACCESS_KEY');
    });
  });

  describe('getS3Key', () => {
    it('should replace ~ with / for version 0', () => {
      const casId = '0~YWoYNXXwg7v_Gpj7EqwaHJeXMY6Q0FSYANeEC3z_Laeez9xEdOC9TWkHvdglkVr5U8HVuYxo2G9nK11Cl9N9xQ==';
      const result = getS3Key(casId);

      expect(result).toBe('0/YWoYNXXwg7v_Gpj7EqwaHJeXMY6Q0FSYANeEC3z_Laeez9xEdOC9TWkHvdglkVr5U8HVuYxo2G9nK11Cl9N9xQ==');
    });

    it('should handle different version numbers', () => {
      const casId = '1~abcdef1234567890';
      const result = getS3Key(casId);

      expect(result).toBe('1/abcdef1234567890');
    });

    it('should handle version 2', () => {
      const casId = '2~someHash123';
      const result = getS3Key(casId);

      expect(result).toBe('2/someHash123');
    });

    it('should only replace first occurrence of ~', () => {
      const casId = '0~hash~with~tildes';
      const result = getS3Key(casId);

      expect(result).toBe('0/hash~with~tildes');
    });
  });

  describe('checkS3ObjectExists', () => {
    let mockS3Client;

    beforeEach(() => {
      mockS3Client = {
        fetch: vi.fn(),
      };
    });

    it('should return true when object exists (path style)', async () => {
      mockS3Client.fetch.mockResolvedValue({ ok: true });

      const result = await checkS3ObjectExists(
        mockS3Client,
        'https://s3.amazonaws.com',
        'test-bucket',
        'path/to/object',
        false
      );

      expect(result).toBe(true);
      expect(mockS3Client.fetch).toHaveBeenCalledWith(
        'https://s3.amazonaws.com/test-bucket/path/to/object',
        { method: 'HEAD' }
      );
    });

    it('should return true when object exists (virtual host style)', async () => {
      mockS3Client.fetch.mockResolvedValue({ ok: true });

      const result = await checkS3ObjectExists(
        mockS3Client,
        'https://s3.amazonaws.com',
        'test-bucket',
        'path/to/object',
        true
      );

      expect(result).toBe(true);
      expect(mockS3Client.fetch).toHaveBeenCalledWith(
        'https://test-bucket.s3.amazonaws.com/path/to/object',
        { method: 'HEAD' }
      );
    });

    it('should return false when object does not exist', async () => {
      mockS3Client.fetch.mockResolvedValue({ ok: false });

      const result = await checkS3ObjectExists(
        mockS3Client,
        'https://s3.amazonaws.com',
        'test-bucket',
        'path/to/object',
        false
      );

      expect(result).toBe(false);
    });

    it('should return false when fetch throws error', async () => {
      mockS3Client.fetch.mockRejectedValue(new Error('Network error'));

      const result = await checkS3ObjectExists(
        mockS3Client,
        'https://s3.amazonaws.com',
        'test-bucket',
        'path/to/object',
        false
      );

      expect(result).toBe(false);
    });
  });
});
