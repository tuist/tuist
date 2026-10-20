/**
 * Cloudflare Email Worker: Atlas inbox bridge.
 *
 * Cloudflare Email Routing calls email() for every message delivered to
 * inbox@atlas.tuist.dev. The worker is a thin, signed relay: it reads the raw
 * RFC 822 message, HMAC-signs it with the shared secret, and forwards it to
 * Atlas. It does NOT decide whether the sender is authorized.
 *
 * Why no sender authorization here: a Cloudflare Email Worker runs before
 * Cloudflare stamps its own Authentication-Results, so at this point the
 * message carries no trustworthy SPF/DKIM/DMARC verdict the worker could
 * evaluate (only upstream ARC, which is forwarder-controlled). Authorization
 * therefore lives in Atlas, where the full raw message is available and the
 * decision is testable. The HMAC signature is the trust boundary for this
 * worker→Atlas hop.
 *
 * Required secrets (set via Cloudflare dashboard or `wrangler secret put`):
 *   ATLAS_INBOX_WEBHOOK_SECRET: shared secret, also stored in 1Password as
 *                                 atlas-inbox-webhook-secret/password and
 *                                 injected into the Atlas pod via External Secrets.
 *
 * Signature scheme (must match Atlas.Inbox.verify_signature/4):
 *   HMAC-SHA256(key=secret, message="{timestamp}.{raw_body_bytes}")
 *   Header: x-atlas-inbox-signature: sha256=<lowercase hex>
 */

export default {
  async email(message, env, _ctx) {
    const rawBuffer = await new Response(message.raw).arrayBuffer();
    const timestamp = Math.floor(Date.now() / 1000).toString();
    const signature = await hmacSha256Hex(
      env.ATLAS_INBOX_WEBHOOK_SECRET,
      timestamp,
      rawBuffer
    );

    const response = await fetch(`${env.ATLAS_URL}/api/inbox/emails`, {
      method: "POST",
      headers: {
        "content-type": "message/rfc822",
        "x-atlas-inbox-timestamp": timestamp,
        "x-atlas-inbox-signature": `sha256=${signature}`,
        "x-atlas-inbox-envelope-from": message.from,
        "x-atlas-inbox-envelope-to": message.to,
      },
      body: rawBuffer,
    });

    if (!response.ok) {
      const body = await response.text().catch(() => "");
      throw new Error(`Atlas ${response.status}: ${body}`);
    }
  },
};

/**
 * Returns the lowercase hex HMAC-SHA256 of `"${timestamp}.${rawBody}"`.
 * Matches the Elixir expression:
 *   :crypto.mac(:hmac, :sha256, secret, [timestamp, ".", raw_body])
 */
async function hmacSha256Hex(secret, timestamp, rawBody) {
  const key = await crypto.subtle.importKey(
    "raw",
    new TextEncoder().encode(secret),
    { name: "HMAC", hash: "SHA-256" },
    false,
    ["sign"]
  );

  const prefix = new TextEncoder().encode(`${timestamp}.`);
  const message = new Uint8Array(prefix.byteLength + rawBody.byteLength);
  message.set(new Uint8Array(prefix), 0);
  message.set(new Uint8Array(rawBody), prefix.byteLength);

  const buf = await crypto.subtle.sign("HMAC", key, message);
  return Array.from(new Uint8Array(buf))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}
