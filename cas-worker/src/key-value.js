const CACHE_TTL = 300;

function buildCacheKey(accountHandle, projectHandle, casId) {
  return `https://cache.tuist.dev/api/cache/keyvalue/${encodeURIComponent(accountHandle)}/${encodeURIComponent(projectHandle)}/${encodeURIComponent(casId)}`;
}

function buildStorageKey(accountHandle, projectHandle, casId) {
  return `keyvalue:${accountHandle}:${projectHandle}:${casId}`;
}

function generateEntryId() {
  return globalThis.crypto?.randomUUID?.() ?? Math.random().toString(36).slice(2);
}

function normalizeStoredEntries(entries) {
  if (!Array.isArray(entries)) return [];
  
  return entries
    .filter(entry => entry && typeof entry.value === 'string')
    .map(entry => ({
      id: typeof entry.id === 'string' ? entry.id : generateEntryId(),
      value: entry.value
    }));
}

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Cache-Control': `max-age=${CACHE_TTL}`,
    },
  });
}

function errorResponse(message, status) {
  return jsonResponse({ message }, status);
}

async function readCache(cacheKey) {
  if (!globalThis.caches?.default) return null;

  const cacheRequest = new Request(cacheKey, { method: 'GET' });
  const cached = await caches.default.match(cacheRequest);
  return cached?.clone() ?? null;
}

async function writeCache(cacheKey, response) {
  if (!globalThis.caches?.default) return;

  const cacheRequest = new Request(cacheKey, { method: 'GET' });
  await caches.default.put(cacheRequest, response.clone());
}

function validateQuery(request) {
  const query = request.query || {};
  const { account_handle: accountHandle, project_handle: projectHandle } = query;
  
  if (!accountHandle || !projectHandle) {
    return { error: 'Missing account_handle or project_handle query parameter', status: 400 };
  }
  
  return { accountHandle, projectHandle };
}

function validateAuth(request) {
  const authorization = request.headers?.get?.('Authorization');
  if (!authorization) {
    return { error: 'Missing Authorization header', status: 401 };
  }
  return { authorization };
}

function validateKvStore(env) {
  const store = env.KEY_VALUE_STORE;
  if (!store || typeof store.put !== 'function' || typeof store.get !== 'function') {
    return { error: 'KEY_VALUE_STORE binding is not configured', status: 500 };
  }
  return { store };
}

function decodeCasId(rawCasId) {
  if (typeof rawCasId !== 'string') return null;
  
  try {
    return decodeURIComponent(rawCasId);
  } catch {
    return null;
  }
}

export async function handleKeyValueGet(request, env) {
  const queryValidation = validateQuery(request);
  if (queryValidation.error) {
    return errorResponse(queryValidation.error, queryValidation.status);
  }

  const authValidation = validateAuth(request);
  if (authValidation.error) {
    return errorResponse(authValidation.error, authValidation.status);
  }

  const kvValidation = validateKvStore(env);
  if (kvValidation.error) {
    return errorResponse(kvValidation.error, kvValidation.status);
  }

  const casId = decodeCasId(request.params?.cas_id);
  if (!casId) {
    return errorResponse('Missing cas_id path parameter', 400);
  }

  const { accountHandle, projectHandle } = queryValidation;
  const { store } = kvValidation;

  const cacheKey = buildCacheKey(accountHandle, projectHandle, casId);
  const cachedResponse = await readCache(cacheKey);
  if (cachedResponse) {
    return cachedResponse;
  }

  const storageKey = buildStorageKey(accountHandle, projectHandle, casId);
  let storedEntries;

  try {
    storedEntries = await store.get(storageKey, 'json');
  } catch {
    return errorResponse('Failed to read entries from KV', 500);
  }

  if (!Array.isArray(storedEntries) || storedEntries.length === 0) {
    return errorResponse(`No entries found for CAS ID ${casId}.`, 404);
  }

  const sanitizedEntries = storedEntries
    .filter(entry => entry && typeof entry.value === 'string')
    .map(entry => ({ value: entry.value }));

  if (sanitizedEntries.length === 0) {
    return errorResponse(`No entries found for CAS ID ${casId}.`, 404);
  }

  const response = jsonResponse({ entries: sanitizedEntries });
  await writeCache(cacheKey, response);

  return response;
}

export async function handleKeyValuePut(request, env) {
  const queryValidation = validateQuery(request);
  if (queryValidation.error) {
    return errorResponse(queryValidation.error, queryValidation.status);
  }

  const authValidation = validateAuth(request);
  if (authValidation.error) {
    return errorResponse(authValidation.error, authValidation.status);
  }

  const kvValidation = validateKvStore(env);
  if (kvValidation.error) {
    return errorResponse(kvValidation.error, kvValidation.status);
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return errorResponse('Invalid JSON body', 400);
  }

  const { cas_id: casId, entries } = body || {};

  if (!casId || !Array.isArray(entries)) {
    return errorResponse('Request body must include cas_id and entries array', 400);
  }

  const sanitizedEntries = entries
    .filter(entry => entry && typeof entry.value === 'string')
    .map(entry => ({ value: entry.value }));

  if (sanitizedEntries.length === 0) {
    return errorResponse('Entries array must include at least one value', 400);
  }

  const { accountHandle, projectHandle } = queryValidation;
  const { store } = kvValidation;

  const storageKey = buildStorageKey(accountHandle, projectHandle, casId);
  let existingEntriesRaw;

  try {
    existingEntriesRaw = await store.get(storageKey, 'json');
  } catch {
    return errorResponse('Failed to read entries from KV', 500);
  }

  const existingEntries = normalizeStoredEntries(existingEntriesRaw);

  const newEntries = sanitizedEntries.map(entry => ({
    id: generateEntryId(),
    value: entry.value,
  }));

  const mergedEntries = existingEntries.concat(newEntries);

  try {
    await store.put(storageKey, JSON.stringify(mergedEntries));
  } catch (error) {
    return errorResponse(error.message || 'Failed to store entries in KV', 500);
  }

  const cacheKey = buildCacheKey(accountHandle, projectHandle, casId);
  const cacheResponse = jsonResponse({
    entries: mergedEntries.map(entry => ({ value: entry.value })),
  });
  await writeCache(cacheKey, cacheResponse);

  return jsonResponse({ entries: newEntries.map(entry => ({ id: entry.id })) });
}
