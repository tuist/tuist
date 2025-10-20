import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";
import { handleKeyValueGet, handleKeyValuePut } from "./key-value.js";

const originalCaches = globalThis.caches;
const hasNativeCrypto = !!globalThis.crypto;

describe("KeyValue handlers", () => {
  let env;
  let cache;
  let request;
  let uuidSpy;

  beforeEach(() => {
    env = {
      KEY_VALUE_STORE: {
        get: vi.fn().mockResolvedValue([]),
        put: vi.fn(),
      },
    };

    cache = {
      match: vi.fn(),
      put: vi.fn().mockResolvedValue(undefined),
    };

    globalThis.caches = { default: cache };

    let counter = 0;
    if (hasNativeCrypto && globalThis.crypto?.randomUUID) {
      uuidSpy = vi
        .spyOn(globalThis.crypto, "randomUUID")
        .mockImplementation(() => `uuid-${++counter}`);
    } else {
      globalThis.crypto = {
        randomUUID: vi.fn(() => `uuid-${++counter}`),
      };
    }

    request = {
      params: { cas_id: "cas123" },
      query: {
        account_handle: "my-account",
        project_handle: "my-project",
      },
      headers: {
        get: vi.fn(() => "Bearer token"),
      },
    };
  });

  afterEach(() => {
    if (uuidSpy) {
      uuidSpy.mockRestore();
      uuidSpy = undefined;
    } else if (!hasNativeCrypto) {
      delete globalThis.crypto;
    }

    if (originalCaches) {
      globalThis.caches = originalCaches;
    } else {
      delete globalThis.caches;
    }

    vi.restoreAllMocks();
  });

  describe("handleKeyValueGet", () => {
    it("returns 400 when query parameters are missing", async () => {
      request.query = {};

      const response = await handleKeyValueGet(request, env);

      expect(response.status).toBe(400);
      await expect(response.json()).resolves.toEqual({
        message: "Missing account_handle or project_handle query parameter",
      });
    });

    it("returns 401 when Authorization header is missing", async () => {
      request.headers.get = vi.fn(() => null);

      const response = await handleKeyValueGet(request, env);

      expect(response.status).toBe(401);
      await expect(response.json()).resolves.toEqual({
        message: "Missing Authorization header",
      });
    });

    it("returns 500 when KEY_VALUE_STORE binding missing", async () => {
      env.KEY_VALUE_STORE = null;

      const response = await handleKeyValueGet(request, env);

      expect(response.status).toBe(500);
      await expect(response.json()).resolves.toEqual({
        message: "KEY_VALUE_STORE binding is not configured",
      });
    });

    it("returns cached response when available", async () => {
      const cached = new Response(
        JSON.stringify({ entries: [{ value: "cached" }] }),
        { status: 200, headers: { "Content-Type": "application/json" } },
      );
      cache.match.mockResolvedValue(cached);

      const response = await handleKeyValueGet(request, env);

      expect(cache.match).toHaveBeenCalled();
      expect(env.KEY_VALUE_STORE.get).not.toHaveBeenCalled();
      expect(response.status).toBe(200);
      await expect(response.json()).resolves.toEqual({
        entries: [{ value: "cached" }],
      });
    });

    it("reads from KV and populates cache when not cached", async () => {
      cache.match.mockResolvedValue(null);
      env.KEY_VALUE_STORE.get.mockResolvedValue([{ value: "stored" }]);

      const response = await handleKeyValueGet(request, env);

      expect(env.KEY_VALUE_STORE.get).toHaveBeenCalledWith(
        "keyvalue:my-account:my-project:cas123",
        "json",
      );
      expect(cache.put).toHaveBeenCalled();
      expect(response.status).toBe(200);
      await expect(response.json()).resolves.toEqual({
        entries: [{ value: "stored" }],
      });
    });

    it("returns 404 when KV has no entries", async () => {
      cache.match.mockResolvedValue(null);
      env.KEY_VALUE_STORE.get.mockResolvedValue(null);

      const response = await handleKeyValueGet(request, env);

      expect(response.status).toBe(404);
      await expect(response.json()).resolves.toEqual({
        message: "No entries found for CAS ID cas123.",
      });
    });

    it("decodes cas_id path parameter before lookup", async () => {
      cache.match.mockResolvedValue(null);
      request.params.cas_id = encodeURIComponent("cas123==");
      env.KEY_VALUE_STORE.get.mockResolvedValue([{ value: "stored" }]);

      const response = await handleKeyValueGet(request, env);

      expect(env.KEY_VALUE_STORE.get).toHaveBeenCalledWith(
        "keyvalue:my-account:my-project:cas123==",
        "json",
      );
      expect(response.status).toBe(200);
      await expect(response.json()).resolves.toEqual({
        entries: [{ value: "stored" }],
      });
    });
  });

  describe("handleKeyValuePut", () => {
    beforeEach(() => {
      request.json = vi.fn().mockResolvedValue({
        cas_id: "cas123",
        entries: [
          { id: "id-1", value: "value-1" },
          { id: "id-2", value: "value-2" },
        ],
      });
    });

    it("returns 400 when query parameters are missing", async () => {
      request.query = {};

      const response = await handleKeyValuePut(request, env);

      expect(response.status).toBe(400);
      await expect(response.json()).resolves.toEqual({
        message: "Missing account_handle or project_handle query parameter",
      });
    });

    it("returns 401 when Authorization header is missing", async () => {
      request.headers.get = vi.fn(() => null);

      const response = await handleKeyValuePut(request, env);

      expect(response.status).toBe(401);
      await expect(response.json()).resolves.toEqual({
        message: "Missing Authorization header",
      });
    });

    it("returns 500 when KEY_VALUE_STORE binding missing", async () => {
      env.KEY_VALUE_STORE = null;

      const response = await handleKeyValuePut(request, env);

      expect(response.status).toBe(500);
      await expect(response.json()).resolves.toEqual({
        message: "KEY_VALUE_STORE binding is not configured",
      });
    });

    it("returns 400 when request body cannot be parsed", async () => {
      request.json = vi.fn().mockRejectedValue(new Error("bad json"));

      const response = await handleKeyValuePut(request, env);

      expect(response.status).toBe(400);
      await expect(response.json()).resolves.toEqual({
        message: "Invalid JSON body",
      });
    });

    it("returns 400 when entries array is missing", async () => {
      request.json = vi.fn().mockResolvedValue({ cas_id: "cas123" });

      const response = await handleKeyValuePut(request, env);

      expect(response.status).toBe(400);
      await expect(response.json()).resolves.toEqual({
        message: "Request body must include cas_id and entries array",
      });
    });

    it("stores entries in KV and cache", async () => {
      const response = await handleKeyValuePut(request, env);

      expect(env.KEY_VALUE_STORE.get).toHaveBeenCalledWith(
        "keyvalue:my-account:my-project:cas123",
        "json",
      );
      expect(env.KEY_VALUE_STORE.put).toHaveBeenCalledWith(
        "keyvalue:my-account:my-project:cas123",
        JSON.stringify([{ value: "value-1" }, { value: "value-2" }]),
      );
      expect(cache.put).toHaveBeenCalled();
      expect(response.status).toBe(204);
      expect(response.body).toBeNull();
    });

    it("filters out entries without string values", async () => {
      request.json = vi.fn().mockResolvedValue({
        cas_id: "cas123",
        entries: [{ value: "value-1" }, { value: 123 }, null],
      });

      const response = await handleKeyValuePut(request, env);

      expect(env.KEY_VALUE_STORE.get).toHaveBeenCalledWith(
        "keyvalue:my-account:my-project:cas123",
        "json",
      );
      expect(env.KEY_VALUE_STORE.put).toHaveBeenCalledWith(
        "keyvalue:my-account:my-project:cas123",
        JSON.stringify([{ value: "value-1" }]),
      );
      expect(response.status).toBe(204);
      expect(response.body).toBeNull();
    });

    it("replaces existing entries entirely", async () => {
      env.KEY_VALUE_STORE.get.mockResolvedValue([{ value: "old-value" }]);

      const response = await handleKeyValuePut(request, env);

      expect(env.KEY_VALUE_STORE.put).toHaveBeenCalledWith(
        "keyvalue:my-account:my-project:cas123",
        JSON.stringify([{ value: "value-1" }, { value: "value-2" }]),
      );

      const [, cachedResponse] = cache.put.mock.calls[0];
      await expect(cachedResponse.json()).resolves.toEqual({
        entries: [{ value: "value-1" }, { value: "value-2" }],
      });

      expect(response.status).toBe(204);
      expect(response.body).toBeNull();
    });

    it("returns 400 when filtered entries array is empty", async () => {
      request.json = vi.fn().mockResolvedValue({
        cas_id: "cas123",
        entries: [{ value: 123 }],
      });

      const response = await handleKeyValuePut(request, env);

      expect(response.status).toBe(400);
      await expect(response.json()).resolves.toEqual({
        message:
          "Entries array must include at least one entry with id and value",
      });
    });
  });
});
