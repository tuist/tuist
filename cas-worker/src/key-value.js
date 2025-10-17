/**
 * Build a cache key URL for the combination of account, project, and CAS identifier.
 */
function buildCacheKey(accountHandle, projectHandle, casId) {
  const encodedAccount = encodeURIComponent(accountHandle);
  const encodedProject = encodeURIComponent(projectHandle);
  const encodedCasId = encodeURIComponent(casId);
  return `https://cache.tuist.dev/api/cache/keyvalue/${encodedAccount}/${encodedProject}/${encodedCasId}`;
}

function buildStorageKey(accountHandle, projectHandle, casId) {
  return `keyvalue:${accountHandle}:${projectHandle}:${casId}`;
}

function generateEntryId() {
  if (globalThis.crypto?.randomUUID) {
    return globalThis.crypto.randomUUID();
  }
  return Math.random().toString(36).slice(2);
}

function normalizeStoredEntries(entries) {
  if (!Array.isArray(entries)) {
    return [];
  }

  return entries.reduce((acc, entry) => {
    if (!entry || typeof entry.value !== 'string') {
      return acc;
    }

    const id = typeof entry.id === 'string' ? entry.id : generateEntryId();
    acc.push({ id, value: entry.value });
    return acc;
  }, []);
}

function jsonResponse(body, status = 200) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      'Content-Type': 'application/json',
      'Cache-Control': 'max-age=300',
    },
  });
}

function errorResponse(message, status) {
  return jsonResponse({ message }, status);
}

function validateQuery(request) {
   const query = request.query || {};
   const accountHandle = query.account_handle;
   const projectHandle = query.project_handle;

   if (!accountHandle || !projectHandle) {
     return { error: 'Missing account_handle or project_handle query parameter', status: 400 };
   }

   return { accountHandle, projectHandle };
}

function decodeCasId(rawCasId) {
  if (typeof rawCasId !== 'string') {
    return null;
  }

  try {
    return decodeURIComponent(rawCasId);
  } catch (error) {
    console.error('Failed to decode cas_id path parameter', { rawCasId, error });
    return null;
  }
}

function ensureAuthorizationHeader(request) {
  const authorization = request.headers?.get?.('Authorization');
  if (!authorization) {
    return { error: 'Missing Authorization header', status: 401 };
  }
  return { authorization };
}

function validateKvBinding(env) {
  const store = env.KEY_VALUE_STORE;
  if (!store || typeof store.put !== 'function' || typeof store.get !== 'function') {
    return { error: 'KEY_VALUE_STORE binding is not configured', status: 500 };
  }
  return { store };
}

async function readCache(cacheKey) {
  if (!globalThis.caches?.default) {
    return null;
  }

  const cacheRequest = new Request(cacheKey, { method: 'GET' });
  const cached = await caches.default.match(cacheRequest);
  if (cached) {
    return cached.clone();
  }

  return null;
}

async function writeCache(cacheKey, response) {
  if (!globalThis.caches?.default) {
    return;
  }

  const cacheRequest = new Request(cacheKey, { method: 'GET' });
  await caches.default.put(cacheRequest, response.clone());
}

export async function handleKeyValueGet(request, env) {
  console.log('handleKeyValueGet called for:', request.url);

  const queryValidation = validateQuery(request);
  if (queryValidation.error) {
    console.log('Query validation failed:', queryValidation);
    return errorResponse(queryValidation.error, queryValidation.status);
  }

  const authValidation = ensureAuthorizationHeader(request);
  if (authValidation.error) {
    return errorResponse(authValidation.error, authValidation.status);
  }

  const kvValidation = validateKvBinding(env);
  if (kvValidation.error) {
    return errorResponse(kvValidation.error, kvValidation.status);
  }

  const { accountHandle, projectHandle } = queryValidation;
  const { store } = kvValidation;
  const casId = decodeCasId(request.params?.cas_id);

  if (!casId) {
    return errorResponse('Missing cas_id path parameter', 400);
  }

  console.log('GET request:', { casId, accountHandle, projectHandle, url: request.url });

  const cacheKey = buildCacheKey(accountHandle, projectHandle, casId);
  const cachedResponse = await readCache(cacheKey);
  if (cachedResponse) {
    console.log('GET: Cache hit');
    return cachedResponse;
  }

  const storageKey = buildStorageKey(accountHandle, projectHandle, casId);
  let storedEntries;

  try {
    storedEntries = await store.get(storageKey, 'json');
  } catch (error) {
    console.error('GET: Failed to read from KEY_VALUE_STORE', error);
    return errorResponse('Failed to read entries from KV', 500);
  }

  if (!Array.isArray(storedEntries) || storedEntries.length === 0) {
    console.log('GET: No entries found');
    return errorResponse(`No entries found for CAS ID ${casId}.`, 404);
  }

  const sanitizedEntries = storedEntries
    .filter(entry => entry && typeof entry.value === 'string')
    .map(entry => ({ value: entry.value }));

  if (sanitizedEntries.length === 0) {
    console.log('GET: No valid entries after sanitization');
    return errorResponse(`No entries found for CAS ID ${casId}.`, 404);
  }

  const response = jsonResponse({ entries: sanitizedEntries });
  await writeCache(cacheKey, response);

  console.log('GET: Returning entries');
  return response;
}

export async function handleKeyValuePut(request, env) {
  console.log('handleKeyValuePut called for:', request.url);

  const queryValidation = validateQuery(request);
  if (queryValidation.error) {
    console.log('Query validation failed:', queryValidation);
    return errorResponse(queryValidation.error, queryValidation.status);
  }

  const authValidation = ensureAuthorizationHeader(request);
  if (authValidation.error) {
    return errorResponse(authValidation.error, authValidation.status);
  }

  const kvValidation = validateKvBinding(env);
  if (kvValidation.error) {
    return errorResponse(kvValidation.error, kvValidation.status);
  }

  let body;
  try {
    body = await request.json();
  } catch (error) {
    console.error('PUT: JSON parse error:', error);
    return errorResponse('Invalid JSON body', 400);
  }

  const casId = body?.cas_id;
  const entries = body?.entries;

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
  } catch (error) {
    console.error('PUT: Failed to read existing entries from KV', error);
    return errorResponse('Failed to read entries from KV', 500);
  }

  const existingEntries = normalizeStoredEntries(existingEntriesRaw);
  console.log('PUT: Storing entries', { storageKey, casId, count: sanitizedEntries.length });

  const newEntries = sanitizedEntries.map(entry => ({
    id: generateEntryId(),
    value: entry.value,
  }));

  const mergedEntries = existingEntries.concat(newEntries);

  try {
    await store.put(storageKey, JSON.stringify(mergedEntries));
  } catch (error) {
    console.error('PUT: Failed to store entries in KV', error);
    return errorResponse(error.message || 'Failed to store entries in KV', 500);
  }

  const cacheKey = buildCacheKey(accountHandle, projectHandle, casId);
  const cacheResponse = jsonResponse({
    entries: mergedEntries.map(entry => ({ value: entry.value })),
  });
  await writeCache(cacheKey, cacheResponse);

  console.log('PUT: Stored entries successfully');
  return jsonResponse({ entries: newEntries.map(entry => ({ id: entry.id })) });
}
