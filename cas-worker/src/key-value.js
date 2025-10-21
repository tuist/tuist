import { jsonResponse, validateQuery, decodeCasId } from "./shared.js";
import { ensureProjectAccessible } from "./auth.js";

function buildCacheKey(accountHandle, projectHandle, casId) {
  return `keyvalue:${accountHandle}:${projectHandle}:${casId}`;
}

export async function handleKeyValueGet(request, env, instrumentation = {}) {
  const queryValidation = validateQuery(request);
  if (queryValidation.error) {
    return jsonResponse(
      { message: queryValidation.error },
      queryValidation.status,
    );
  }

  const { accountHandle, projectHandle } = queryValidation;

  const accessResult = await ensureProjectAccessible(
    request,
    env,
    accountHandle,
    projectHandle,
    instrumentation,
  );
  if (accessResult.error) {
    return jsonResponse({ message: accessResult.error }, accessResult.status);
  }

  const casId = decodeCasId(request.params?.cas_id);
  if (!casId) {
    return jsonResponse({ message: "Missing cas_id path parameter" }, 400);
  }

  const store = env.CAS_CACHE;

  const storageKey = buildCacheKey(accountHandle, projectHandle, casId);
  let storedEntries;

  try {
    storedEntries = await store.get(storageKey, "json");
  } catch {
    return jsonResponse({ message: "Failed to read entries from KV" }, 500);
  }

  if (!Array.isArray(storedEntries) || storedEntries.length === 0) {
    return jsonResponse(
      { message: `No entries found for CAS ID ${casId}.` },
      404,
    );
  }

  const entries = storedEntries
    .map((value) => (typeof value === "string" ? value : null))
    .filter((value) => typeof value === "string");

  if (entries.length === 0) {
    return jsonResponse(
      { message: `No entries found for CAS ID ${casId}.` },
      404,
    );
  }

  return jsonResponse({
    entries: entries.map((value) => ({ value })),
  });
}

export async function handleKeyValuePut(request, env, instrumentation = {}) {
  const queryValidation = validateQuery(request);
  if (queryValidation.error) {
    return jsonResponse(
      { message: queryValidation.error },
      queryValidation.status,
    );
  }

  const { accountHandle, projectHandle } = queryValidation;

  const accessResult = await ensureProjectAccessible(
    request,
    env,
    accountHandle,
    projectHandle,
    instrumentation,
  );
  if (accessResult.error) {
    return jsonResponse({ message: accessResult.error }, accessResult.status);
  }

  let body;
  try {
    body = await request.json();
  } catch {
    return jsonResponse({ message: "Invalid JSON body" }, 400);
  }

  const { cas_id: casId, entries } = body || {};

  if (!casId || !Array.isArray(entries)) {
    return jsonResponse(
      { message: "Request body must include cas_id and entries array" },
      400,
    );
  }

  const sanitizedValues = entries
    .map((entry) =>
      entry && typeof entry.value === "string" ? entry.value : null,
    )
    .filter((value) => typeof value === "string");

  if (sanitizedValues.length === 0) {
    return jsonResponse(
      {
        message:
          "Entries array must include at least one entry with a string value",
      },
      400,
    );
  }

  const store = env.CAS_CACHE;

  const storageKey = buildCacheKey(accountHandle, projectHandle, casId);
  try {
    await store.get(storageKey, "json");
  } catch {
    return jsonResponse({ message: "Failed to read entries from KV" }, 500);
  }

  try {
    await store.put(storageKey, JSON.stringify(sanitizedValues));
  } catch (error) {
    return jsonResponse(
      { message: error.message || "Failed to store entries in KV" },
      500,
    );
  }

  return new Response(null, { status: 204 });
}
