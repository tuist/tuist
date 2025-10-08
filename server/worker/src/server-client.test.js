import { describe, it, expect, beforeEach, vi } from 'vitest';
import { ServerClient, createServerClient } from './server-client.js';

// Mock global fetch
global.fetch = vi.fn();

describe('ServerClient', () => {
  beforeEach(() => {
    vi.clearAllMocks();
  });

  describe('constructor', () => {
    it('should use SERVER_URL from env if provided', () => {
      const env = { SERVER_URL: 'https://custom.example.com' };
      const client = new ServerClient(env);
      expect(client.baseUrl).toBe('https://custom.example.com');
    });

    it('should default to https://tuist.dev if SERVER_URL not provided', () => {
      const env = {};
      const client = new ServerClient(env);
      expect(client.baseUrl).toBe('https://tuist.dev');
    });
  });

  describe('request', () => {
    it('should make a request to the correct URL', async () => {
      const env = { SERVER_URL: 'https://example.com' };
      const client = new ServerClient(env);

      global.fetch.mockResolvedValue(new Response('OK', { status: 200 }));

      await client.request('/api/test', { method: 'GET' });

      expect(global.fetch).toHaveBeenCalledWith(
        'https://example.com/api/test',
        { method: 'GET' }
      );
    });

    it('should return the response', async () => {
      const env = {};
      const client = new ServerClient(env);

      const mockResponse = new Response('test data', { status: 200 });
      global.fetch.mockResolvedValue(mockResponse);

      const response = await client.request('/api/test');

      expect(response).toBe(mockResponse);
    });
  });

  describe('HTTP method shortcuts', () => {
    it('should make a GET request', async () => {
      const env = {};
      const client = new ServerClient(env);

      global.fetch.mockResolvedValue(new Response('OK', { status: 200 }));

      await client.get('/api/test', { headers: { 'X-Custom': 'value' } });

      expect(global.fetch).toHaveBeenCalledWith(
        'https://tuist.dev/api/test',
        { method: 'GET', headers: { 'X-Custom': 'value' } }
      );
    });

    it('should make a POST request', async () => {
      const env = {};
      const client = new ServerClient(env);

      global.fetch.mockResolvedValue(new Response('OK', { status: 201 }));

      await client.post('/api/test', { body: 'test' });

      expect(global.fetch).toHaveBeenCalledWith(
        'https://tuist.dev/api/test',
        { method: 'POST', body: 'test' }
      );
    });

    it('should make a PUT request', async () => {
      const env = {};
      const client = new ServerClient(env);

      global.fetch.mockResolvedValue(new Response('OK', { status: 200 }));

      await client.put('/api/test', { body: 'updated' });

      expect(global.fetch).toHaveBeenCalledWith(
        'https://tuist.dev/api/test',
        { method: 'PUT', body: 'updated' }
      );
    });

    it('should make a DELETE request', async () => {
      const env = {};
      const client = new ServerClient(env);

      global.fetch.mockResolvedValue(new Response(null, { status: 204 }));

      await client.delete('/api/test');

      expect(global.fetch).toHaveBeenCalledWith(
        'https://tuist.dev/api/test',
        { method: 'DELETE' }
      );
    });
  });

  describe('createServerClient', () => {
    it('should create a new ServerClient instance', () => {
      const env = { SERVER_URL: 'https://test.com' };
      const client = createServerClient(env);

      expect(client).toBeInstanceOf(ServerClient);
      expect(client.baseUrl).toBe('https://test.com');
    });
  });
});
