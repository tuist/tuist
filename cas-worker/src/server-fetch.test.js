import { describe, it, expect, vi } from "vitest";
import { serverFetch } from "./server-fetch.js";

describe("serverFetch", () => {
  it("should use SERVER_URL from env if provided", async () => {
    const env = { SERVER_URL: "https://custom.example.com" };
    const mockFetch = vi
      .fn()
      .mockResolvedValue(new Response("OK", { status: 200 }));

    await serverFetch(env, "/api/test", { method: "GET" }, mockFetch);

    expect(mockFetch).toHaveBeenCalledWith(
      "https://custom.example.com/api/test",
      { method: "GET" },
    );
  });

  it("should default to https://tuist.dev if SERVER_URL not provided", async () => {
    const env = {};
    const mockFetch = vi
      .fn()
      .mockResolvedValue(new Response("OK", { status: 200 }));

    await serverFetch(env, "/api/test", { method: "GET" }, mockFetch);

    expect(mockFetch).toHaveBeenCalledWith("https://tuist.dev/api/test", {
      method: "GET",
    });
  });

  it("should return the response", async () => {
    const env = {};
    const mockResponse = new Response("test data", { status: 200 });
    const mockFetch = vi.fn().mockResolvedValue(mockResponse);

    const response = await serverFetch(env, "/api/test", {}, mockFetch);

    expect(response).toBe(mockResponse);
  });

  it("should pass through fetch options", async () => {
    const env = { SERVER_URL: "https://example.com" };
    const mockFetch = vi
      .fn()
      .mockResolvedValue(new Response("OK", { status: 200 }));

    await serverFetch(
      env,
      "/api/test",
      {
        method: "POST",
        headers: { "Content-Type": "application/json" },
        body: JSON.stringify({ test: "data" }),
      },
      mockFetch,
    );

    expect(mockFetch).toHaveBeenCalledWith("https://example.com/api/test", {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({ test: "data" }),
    });
  });
});
