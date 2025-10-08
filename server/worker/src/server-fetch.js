/**
 * Make a fetch request to the Tuist server
 * @param {Object} env - Environment variables
 * @param {string} path - Request path
 * @param {Object} options - Fetch options
 * @param {Function} fetchFn - Fetch function (defaults to global fetch)
 * @returns {Promise<Response>}
 */
export function serverFetch(env, path, options = {}, fetchFn = fetch) {
  const baseUrl = env.SERVER_URL || 'https://tuist.dev';
  const url = `${baseUrl}${path}`;
  return fetchFn(url, options);
}
