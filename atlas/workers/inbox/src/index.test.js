import { afterEach, describe, expect, test, vi } from "vitest";

import worker from "./index.js";

const env = {
  ATLAS_INBOX_WEBHOOK_SECRET: "inbox-secret",
  ATLAS_URL: "https://atlas.example.com",
};

afterEach(() => {
  vi.restoreAllMocks();
  vi.unstubAllGlobals();
});

describe("inbox email worker", () => {
  test("relays the raw message to Atlas, signed, with envelope headers", async () => {
    const fetchMock = vi.fn(async () => new Response("{}", { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);

    const rawEmail = "From: Buyer <buyer@acme.com>\r\nSubject: Renewal\r\n\r\nBody";
    const message = buildMessage({ from: "Buyer@Acme.COM", rawEmail });

    await worker.email(message, env, {});

    expect(message.setReject).not.toHaveBeenCalled();
    expect(fetchMock).toHaveBeenCalledOnce();

    const [url, request] = fetchMock.mock.calls[0];
    expect(url).toBe("https://atlas.example.com/api/inbox/emails");
    expect(request.method).toBe("POST");
    expect(request.headers["content-type"]).toBe("message/rfc822");
    expect(request.headers["x-atlas-inbox-envelope-from"]).toBe("Buyer@Acme.COM");
    expect(request.headers["x-atlas-inbox-envelope-to"]).toBe("inbox@atlas.tuist.dev");
    expect(request.headers["x-atlas-inbox-signature"]).toMatch(/^sha256=[a-f0-9]{64}$/);
    expect(request.headers).not.toHaveProperty("x-atlas-inbox-authenticated-sender");
    await expect(new Response(request.body).text()).resolves.toBe(rawEmail);
  });

  test("relays regardless of authentication results (Atlas authorizes)", async () => {
    const fetchMock = vi.fn(async () => new Response("{}", { status: 200 }));
    vi.stubGlobal("fetch", fetchMock);

    const message = buildMessage({
      from: "pedro@tuist.dev",
      authenticationResults: "i=1; mx.google.com; arc=none",
    });

    await worker.email(message, env, {});

    expect(message.setReject).not.toHaveBeenCalled();
    expect(fetchMock).toHaveBeenCalledOnce();
  });

  test("throws when Atlas rejects the relay so Cloudflare retries", async () => {
    const fetchMock = vi.fn(async () => new Response("nope", { status: 500 }));
    vi.stubGlobal("fetch", fetchMock);

    const message = buildMessage({ from: "buyer@acme.com" });

    await expect(worker.email(message, env, {})).rejects.toThrow("Atlas 500: nope");
    expect(message.setReject).not.toHaveBeenCalled();
  });
});

function buildMessage({
  from,
  fromHeader = from,
  to = "inbox@atlas.tuist.dev",
  rawEmail = "Subject: Hello\r\n\r\nBody",
  authenticationResults,
}) {
  const headers = new Headers({ from: fromHeader });

  for (const value of [].concat(authenticationResults || []).filter(Boolean)) {
    headers.append("authentication-results", value);
  }

  return {
    from,
    headers,
    raw: new Response(rawEmail).body,
    setReject: vi.fn(),
    to,
  };
}
