/**
 * Client for communicating with the Tuist server
 */
export class ServerClient {
  constructor(env) {
    this.baseUrl = env.SERVER_URL || 'https://tuist.dev';
  }

  /**
   * Make a request to the server
   */
  async request(path, options = {}) {
    const url = `${this.baseUrl}${path}`;
    const response = await fetch(url, options);
    return response;
  }

  /**
   * GET request to the server
   */
  async get(path, options = {}) {
    return this.request(path, {
      ...options,
      method: 'GET',
    });
  }

  /**
   * POST request to the server
   */
  async post(path, options = {}) {
    return this.request(path, {
      ...options,
      method: 'POST',
    });
  }

  /**
   * PUT request to the server
   */
  async put(path, options = {}) {
    return this.request(path, {
      ...options,
      method: 'PUT',
    });
  }

  /**
   * DELETE request to the server
   */
  async delete(path, options = {}) {
    return this.request(path, {
      ...options,
      method: 'DELETE',
    });
  }
}

/**
 * Create a server client from environment
 */
export function createServerClient(env) {
  return new ServerClient(env);
}
