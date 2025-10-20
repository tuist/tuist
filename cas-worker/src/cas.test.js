import { describe, it, expect, beforeEach, vi } from "vitest";
import { handleGetValue, handleSave } from "./cas.js";
import { checkS3ObjectExists, getS3Url } from "./s3.js";
import { serverFetch } from "./server-fetch.js";

// Create mock S3 client
const mockS3Client = {
  fetch: vi.fn(),
};

// Mock the dependencies
vi.mock("./s3.js", () => ({
  createS3Client: vi.fn(() => mockS3Client),
  getS3Key: vi.fn((id) => id.replace("~", "/")),
  checkS3ObjectExists: vi.fn(),
  getS3Url: vi.fn(),
}));

vi.mock("./server-fetch.js", () => ({
  serverFetch: vi.fn(),
}));

describe("CAS Module", () => {
  let env;
  let mockRequest;

  beforeEach(() => {
    vi.clearAllMocks();

    env = {
      TUIST_S3_REGION: "us-east-1",
      TUIST_S3_ENDPOINT: "https://s3.amazonaws.com",
      TUIST_S3_BUCKET_NAME: "test-bucket",
      TUIST_S3_ACCESS_KEY_ID: "test-key",
      TUIST_S3_SECRET_ACCESS_KEY: "test-secret",
      TUIST_S3_VIRTUAL_HOST: "false",
      SERVER_URL: "http://localhost:8080",
      CAS_CACHE: {
        get: vi.fn(),
        put: vi.fn(),
      },
    };

    mockRequest = {
      params: {
        id: "0~abc123",
      },
      query: {
        account_handle: "acme",
        project_handle: "myapp",
      },
      headers: {
        get: vi.fn(),
      },
      body: null,
      arrayBuffer: vi.fn(),
    };
  });

  describe("handleGetValue", () => {
    it("should return 400 when query parameters are missing", async () => {
      mockRequest.query = {};
      mockRequest.headers.get.mockReturnValue("Bearer token123");

      const response = await handleGetValue(mockRequest, env, {});

      expect(response.status).toBe(400);
      const data = await response.json();
      expect(data.message).toContain(
        "Missing account_handle or project_handle",
      );
    });

    it("should return 401 when Authorization header is missing", async () => {
      mockRequest.headers.get.mockReturnValue(null);

      const response = await handleGetValue(mockRequest, env, {});

      expect(response.status).toBe(401);
      const data = await response.json();
      expect(data.message).toContain("Missing Authorization header");
    });

    it("should fetch prefix from server when not cached", async () => {
      mockRequest.headers.get.mockReturnValue("Bearer token123");
      env.CAS_CACHE.get.mockResolvedValue(null);
      serverFetch
        .mockResolvedValueOnce(
          new Response(JSON.stringify(["acme/myapp"]), {
            status: 200,
            headers: { "Content-Type": "application/json" },
          }),
        )
        .mockResolvedValueOnce(
          new Response(JSON.stringify({ prefix: "server-prefix/" }), {
            status: 200,
            headers: { "Content-Type": "application/json" },
          }),
        );
      checkS3ObjectExists.mockResolvedValue(true);
      getS3Url.mockReturnValue(
        "https://s3.amazonaws.com/test-bucket/server-prefix/0/abc123",
      );

      mockS3Client.fetch.mockResolvedValue(
        new Response("file content", { status: 200 }),
      );

      const response = await handleGetValue(mockRequest, env, {});

      expect(response.status).toBe(200);
      expect(serverFetch).toHaveBeenNthCalledWith(
        1,
        env,
        "/api/accessible-projects",
        expect.objectContaining({
          method: "GET",
          headers: expect.objectContaining({
            Authorization: "Bearer token123",
          }),
        }),
      );
      expect(serverFetch).toHaveBeenNthCalledWith(
        2,
        env,
        "/api/cache/prefix?account_handle=acme&project_handle=myapp",
        expect.objectContaining({
          method: "GET",
          headers: expect.objectContaining({
            Authorization: "Bearer token123",
          }),
        }),
      );
      expect(env.CAS_CACHE.put).toHaveBeenNthCalledWith(
        1,
        expect.any(String),
        JSON.stringify({ projects: ["acme/myapp"] }),
        { expirationTtl: 600 },
      );
      expect(env.CAS_CACHE.put).toHaveBeenNthCalledWith(
        2,
        expect.any(String),
        JSON.stringify({ prefix: "server-prefix/" }),
        { expirationTtl: 3600 },
      );
    });

    it("should use cached authorization success", async () => {
      mockRequest.headers.get.mockImplementation((header) => {
        if (header === "Authorization") return "Bearer token123";
        return null;
      });
      env.CAS_CACHE.get
        .mockResolvedValueOnce(JSON.stringify({ projects: ["acme/myapp"] }))
        .mockResolvedValueOnce(JSON.stringify({ prefix: "cached-prefix/" }));
      checkS3ObjectExists.mockResolvedValue(true);
      getS3Url.mockReturnValue(
        "https://s3.amazonaws.com/test-bucket/cached-prefix/0/abc123",
      );

      mockS3Client.fetch.mockResolvedValue(
        new Response("content", { status: 200 }),
      );

      const response = await handleGetValue(mockRequest, env, {});

      expect(response.status).toBe(200);
      expect(serverFetch).not.toHaveBeenCalled();
      expect(mockS3Client.fetch).toHaveBeenCalledWith(
        "https://s3.amazonaws.com/test-bucket/cached-prefix/0/abc123",
        { method: "GET" },
      );
    });

    it("should cache authorization failures with shorter TTL", async () => {
      mockRequest.headers.get.mockImplementation((header) => {
        if (header === "Authorization") return "Bearer invalid-token";
        return null;
      });
      env.CAS_CACHE.get.mockResolvedValue(null);
      serverFetch.mockResolvedValue(
        new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 }),
      );

      const response = await handleGetValue(mockRequest, env, {});

      expect(response.status).toBe(404);
      expect(env.CAS_CACHE.put).toHaveBeenCalledWith(
        expect.any(String),
        expect.any(String),
        { expirationTtl: 300 },
      );
      const [, cachedValue] = env.CAS_CACHE.put.mock.calls[0];
      expect(JSON.parse(cachedValue)).toEqual({
        error: "Unauthorized or not found",
        status: 404,
        shouldReturnJson: true,
      });
    });

    it("should use cached authorization failure", async () => {
      mockRequest.headers.get.mockImplementation((header) => {
        if (header === "Authorization") return "Bearer invalid-token";
        return null;
      });
      env.CAS_CACHE.get
        .mockResolvedValueOnce(
          JSON.stringify({
            error: "Unauthorized or not found",
            status: 404,
            shouldReturnJson: true,
          }),
        )
        .mockResolvedValue(null);

      const response = await handleGetValue(mockRequest, env, {});

      expect(response.status).toBe(404);
      expect(serverFetch).not.toHaveBeenCalled();
      const data = await response.json();
      expect(data.message).toBe("Unauthorized or not found");
    });

    it("should forward x-request-id header to server", async () => {
      mockRequest.headers.get.mockImplementation((header) => {
        if (header === "Authorization") return "Bearer token123";
        if (header === "x-request-id") return "req-123";
        return null;
      });
      env.CAS_CACHE.get.mockResolvedValue(null);
      serverFetch
        .mockResolvedValueOnce(
          new Response(JSON.stringify(["acme/myapp"]), {
            status: 200,
            headers: { "Content-Type": "application/json" },
          }),
        )
        .mockResolvedValueOnce(
          new Response(JSON.stringify({ prefix: "server-prefix/" }), {
            status: 200,
            headers: { "Content-Type": "application/json" },
          }),
        );
      checkS3ObjectExists.mockResolvedValue(true);
      getS3Url.mockReturnValue(
        "https://s3.amazonaws.com/test-bucket/server-prefix/0/abc123",
      );

      mockS3Client.fetch.mockResolvedValue(
        new Response("content", { status: 200 }),
      );

      await handleGetValue(mockRequest, env, {});

      expect(serverFetch).toHaveBeenNthCalledWith(
        1,
        env,
        "/api/accessible-projects",
        expect.objectContaining({
          headers: expect.objectContaining({
            Authorization: "Bearer token123",
            "x-request-id": "req-123",
          }),
        }),
      );
      expect(serverFetch).toHaveBeenNthCalledWith(
        2,
        env,
        "/api/cache/prefix?account_handle=acme&project_handle=myapp",
        expect.objectContaining({
          headers: expect.objectContaining({
            Authorization: "Bearer token123",
            "x-request-id": "req-123",
          }),
        }),
      );
    });

    it("should return 404 with JSON when artifact does not exist", async () => {
      mockRequest.headers.get.mockImplementation((header) => {
        if (header === "Authorization") return "Bearer token123";
        return null;
      });
      env.CAS_CACHE.get
        .mockResolvedValueOnce(JSON.stringify({ projects: ["acme/myapp"] }))
        .mockResolvedValueOnce(JSON.stringify({ prefix: "prefix/" }));

      // Mock S3 client to return 404
      mockS3Client.fetch.mockResolvedValue(new Response(null, { status: 404 }));

      const response = await handleGetValue(mockRequest, env, {});

      expect(response.status).toBe(404);
      const data = await response.json();
      expect(data.message).toBe("Artifact does not exist");
    });

    it("should return 404 with JSON when server returns forbidden", async () => {
      mockRequest.headers.get.mockImplementation((header) => {
        if (header === "Authorization") return "Bearer token123";
        return null;
      });
      env.CAS_CACHE.get.mockResolvedValue(null);
      serverFetch
        .mockResolvedValueOnce(
          new Response(JSON.stringify(["acme/myapp"]), {
            status: 200,
            headers: { "Content-Type": "application/json" },
          }),
        )
        .mockResolvedValueOnce(
          new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 }),
        );

      const response = await handleGetValue(mockRequest, env, {});

      expect(response.status).toBe(404);
      const data = await response.json();
      expect(data.message).toBe("Unauthorized or not found");
    });

    it("should return 404 with empty body when server returns not found", async () => {
      mockRequest.headers.get.mockImplementation((header) => {
        if (header === "Authorization") return "Bearer token123";
        return null;
      });
      env.CAS_CACHE.get.mockResolvedValue(null);
      serverFetch
        .mockResolvedValueOnce(
          new Response(JSON.stringify(["acme/myapp"]), {
            status: 200,
            headers: { "Content-Type": "application/json" },
          }),
        )
        .mockResolvedValueOnce(
          new Response(JSON.stringify({ error: "Not found" }), { status: 404 }),
        );

      const response = await handleGetValue(mockRequest, env, {});

      expect(response.status).toBe(404);
      const body = await response.text();
      expect(body).toBe("");
    });

    it("should return 500 when S3 bucket is not configured", async () => {
      mockRequest.headers.get.mockImplementation((header) => {
        if (header === "Authorization") return "Bearer token123";
        return null;
      });
      env.CAS_CACHE.get
        .mockResolvedValueOnce(JSON.stringify({ projects: ["acme/myapp"] }))
        .mockResolvedValueOnce(JSON.stringify({ prefix: "prefix/" }));
      env.TUIST_S3_BUCKET_NAME = undefined;

      const response = await handleGetValue(mockRequest, env, {});

      expect(response.status).toBe(500);
      const data = await response.json();
      expect(data.message).toContain("Missing TUIST_S3_BUCKET_NAME");
    });
  });

  describe("handleSave", () => {
    it("should return 400 when query parameters are missing", async () => {
      mockRequest.query = {};
      mockRequest.headers.get.mockReturnValue("Bearer token123");

      const response = await handleSave(mockRequest, env, {});

      expect(response.status).toBe(400);
      const data = await response.json();
      expect(data.message).toContain(
        "Missing account_handle or project_handle",
      );
    });

    it("should return 401 when Authorization header is missing", async () => {
      mockRequest.headers.get.mockReturnValue(null);

      const response = await handleSave(mockRequest, env, {});

      expect(response.status).toBe(401);
      const data = await response.json();
      expect(data.message).toContain("Missing Authorization header");
    });

    it("should return 404 with JSON when server returns forbidden", async () => {
      mockRequest.headers.get.mockReturnValue("Bearer token123");
      env.CAS_CACHE.get.mockResolvedValue(null);
      serverFetch
        .mockResolvedValueOnce(
          new Response(JSON.stringify(["acme/myapp"]), {
            status: 200,
            headers: { "Content-Type": "application/json" },
          }),
        )
        .mockResolvedValueOnce(
          new Response(JSON.stringify({ error: "Forbidden" }), { status: 403 }),
        );

      const response = await handleSave(mockRequest, env, {});

      expect(response.status).toBe(404);
      const data = await response.json();
      expect(data.message).toBe("Unauthorized or not found");
    });

    it("should cache 401 authorization failures", async () => {
      mockRequest.headers.get.mockReturnValue("Bearer bad-token");
      env.CAS_CACHE.get.mockResolvedValue(null);
      serverFetch.mockResolvedValue(
        new Response(JSON.stringify({ error: "Unauthorized" }), {
          status: 401,
        }),
      );

      const response = await handleSave(mockRequest, env, {});

      expect(response.status).toBe(401);
      expect(env.CAS_CACHE.put).toHaveBeenCalledWith(
        expect.any(String),
        expect.any(String),
        { expirationTtl: 300 },
      );
      const [, cachedValue] = env.CAS_CACHE.put.mock.calls[0];
      expect(JSON.parse(cachedValue)).toEqual({
        error: "Unauthorized or not found",
        status: 401,
        shouldReturnJson: true,
      });
    });

    it("should return 204 when artifact already exists", async () => {
      mockRequest.headers.get.mockReturnValue("Bearer token123");
      env.CAS_CACHE.get.mockResolvedValue(null);
      serverFetch
        .mockResolvedValueOnce(
          new Response(JSON.stringify(["acme/myapp"]), {
            status: 200,
            headers: { "Content-Type": "application/json" },
          }),
        )
        .mockResolvedValueOnce(
          new Response(
            JSON.stringify({ prefix: "test-account/test-project/cas/" }),
            { status: 200 },
          ),
        );
      checkS3ObjectExists.mockResolvedValue(true);
      getS3Url.mockReturnValue("https://s3.amazonaws.com/test-bucket/test-key");

      const response = await handleSave(mockRequest, env, {});

      expect(response.status).toBe(204);
      expect(response.body).toBeNull();
      expect(mockS3Client.fetch).not.toHaveBeenCalled(); // Should not upload if exists
    });

    it("should upload file to S3 and return 204 on success", async () => {
      mockRequest.headers.get.mockImplementation((header) => {
        if (header === "Authorization") return "Bearer token123";
        if (header === "Content-Type") return "application/octet-stream";
        return null;
      });
      mockRequest.arrayBuffer.mockResolvedValue(new ArrayBuffer(100));
      env.CAS_CACHE.get.mockResolvedValue(null);
      serverFetch
        .mockResolvedValueOnce(
          new Response(JSON.stringify(["acme/myapp"]), {
            status: 200,
            headers: { "Content-Type": "application/json" },
          }),
        )
        .mockResolvedValueOnce(
          new Response(
            JSON.stringify({ prefix: "test-account/test-project/cas/" }),
            { status: 200 },
          ),
        );
      checkS3ObjectExists.mockResolvedValue(false);
      getS3Url.mockReturnValue("https://s3.amazonaws.com/test-bucket/test-key");
      mockS3Client.fetch.mockResolvedValue(new Response(null, { status: 200 }));

      const response = await handleSave(mockRequest, env, {});

      expect(response.status).toBe(204);
      expect(response.body).toBeNull();
      expect(mockS3Client.fetch).toHaveBeenCalledWith(
        "https://s3.amazonaws.com/test-bucket/test-key",
        expect.objectContaining({
          method: "PUT",
          body: expect.any(ArrayBuffer),
          headers: expect.objectContaining({
            "Content-Type": "application/octet-stream",
          }),
        }),
      );
    });
  });
});
