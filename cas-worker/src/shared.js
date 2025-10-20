function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function readCache(cacheKey) {
  if (!globalThis.caches?.default) return null;

  const cacheRequest = new Request(cacheKey, { method: "GET" });
  const cached = await caches.default.match(cacheRequest);
  return cached?.clone() ?? null;
}

async function writeCache(cacheKey, response) {
  if (!globalThis.caches?.default) return;

  const cacheRequest = new Request(cacheKey, { method: "GET" });
  await caches.default.put(cacheRequest, response.clone());
}

function validateQuery(request) {
  const query = request.query || {};
  const { account_handle: accountHandle, project_handle: projectHandle } =
    query;

  if (!accountHandle || !projectHandle) {
    return {
      error: "Missing account_handle or project_handle query parameter",
      status: 400,
    };
  }

  return { accountHandle, projectHandle };
}

function validateAuth(request) {
  const authorization = request.headers?.get?.("Authorization");
  if (!authorization) {
    return { error: "Missing Authorization header", status: 401 };
  }
  return { authorization };
}

function decodeCasId(rawCasId) {
  if (typeof rawCasId !== "string") return null;

  try {
    return decodeURIComponent(rawCasId);
  } catch {
    return null;
  }
}

export {
  jsonResponse,
  jsonResponse,
  readCache,
  writeCache,
  validateQuery,
  validateAuth,
  decodeCasId,
};
