export function serverFetch(env, path, options = {}, fetchFn = fetch) {
  const baseUrl = env.SERVER_URL || "https://tuist.dev";
  const url = new URL(path, baseUrl);
  return fetchFn(url.toString(), options);
}
