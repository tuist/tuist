import { describe, it, expect, beforeEach, afterEach, vi } from "vitest";

vi.mock("./auth.js", () => ({
  ensureProjectAccessible: vi.fn(),
}));

import { ensureProjectAccessible } from "./auth.js";
import { handleKeyValueGet, handleKeyValuePut } from "./key-value.js";

const hasNativeCrypto = !!globalThis.crypto;

describe("KeyValue handlers", () => {
  let env;
  let request;
  let uuidSpy;

  beforeEach(() => {
    vi.clearAllMocks();
    ensureProjectAccessible.mockReset();
    ensureProjectAccessible.mockResolvedValue({ authHeader: "Bearer token" });

    env = {
      KEY_VALUE_STORE: {
        get: vi.fn().mockResolvedValue([]),
        put: vi.fn(),
      },
    };

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
      expect(ensureProjectAccessible).not.toHaveBeenCalled();
    });

    it("returns 401 when Authorization header is missing", async () => {
      request.headers.get = vi.fn(() => null);
      ensureProjectAccessible.mockResolvedValueOnce({
        error: "Missing Authorization header",
        status: 401,
      });

      const response = await handleKeyValueGet(request, env);

      expect(response.status).toBe(401);
      await expect(response.json()).resolves.toEqual({
        message: "Missing Authorization header",
      });
    });

    it("returns 404 when project access is denied", async () => {
      ensureProjectAccessible.mockResolvedValueOnce({
        error: "Unauthorized or not found",
        status: 404,
      });

      const response = await handleKeyValueGet(request, env);

      expect(response.status).toBe(404);
      await expect(response.json()).resolves.toEqual({
        message: "Unauthorized or not found",
      });
    });

    it("reads from KV and returns entries", async () => {
      env.KEY_VALUE_STORE.get.mockResolvedValue(["stored"]);

      const response = await handleKeyValueGet(request, env);

      expect(env.KEY_VALUE_STORE.get).toHaveBeenCalledWith(
        "keyvalue:my-account:my-project:cas123",
        "json",
      );
      expect(response.status).toBe(200);
      await expect(response.json()).resolves.toEqual({
        entries: [{ value: "stored" }],
      });
    });

    it("returns 404 when KV has no entries", async () => {
      env.KEY_VALUE_STORE.get.mockResolvedValue(null);

      const response = await handleKeyValueGet(request, env);

      expect(response.status).toBe(404);
      await expect(response.json()).resolves.toEqual({
        message: "No entries found for CAS ID cas123.",
      });
    });

    it("decodes cas_id path parameter before lookup", async () => {
      request.params.cas_id = encodeURIComponent("cas123==");
      env.KEY_VALUE_STORE.get.mockResolvedValue(["stored"]);

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
      expect(ensureProjectAccessible).not.toHaveBeenCalled();
    });

    it("returns 401 when Authorization header is missing", async () => {
      request.headers.get = vi.fn(() => null);
      ensureProjectAccessible.mockResolvedValueOnce({
        error: "Missing Authorization header",
        status: 401,
      });

      const response = await handleKeyValuePut(request, env);

      expect(response.status).toBe(401);
      await expect(response.json()).resolves.toEqual({
        message: "Missing Authorization header",
      });
    });

    it("returns 404 when project access is denied", async () => {
      ensureProjectAccessible.mockResolvedValueOnce({
        error: "Unauthorized or not found",
        status: 404,
      });

      const response = await handleKeyValuePut(request, env);

      expect(response.status).toBe(404);
      await expect(response.json()).resolves.toEqual({
        message: "Unauthorized or not found",
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
        ["value-1", "value-2"],
        "json",
      );
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
        ["value-1"],
        "json",
      );
      expect(response.status).toBe(204);
      expect(response.body).toBeNull();
    });

    it("replaces existing entries entirely", async () => {
      env.KEY_VALUE_STORE.get.mockResolvedValue([{ value: "old-value" }]);

      const response = await handleKeyValuePut(request, env);

      expect(env.KEY_VALUE_STORE.put).toHaveBeenCalledWith(
        "keyvalue:my-account:my-project:cas123",
        ["value-1", "value-2"],
        "json",
      );

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
          "Entries array must include at least one entry with a string value",
      });
    });
  });
});
