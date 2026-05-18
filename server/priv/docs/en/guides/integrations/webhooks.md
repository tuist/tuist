---
{
  "title": "Webhooks",
  "titleTemplate": ":title | Integrations | Guides | Tuist",
  "description": "Subscribe HTTPS endpoints to Tuist events, verify deliveries with a signed payload, and inspect every attempt from the dashboard."
}
---
# Webhooks {#webhooks}

Webhooks let your systems react to changes inside Tuist the moment they happen. Whenever a relevant event occurs — a new test case is observed, a preview finishes uploading, a flaky test gets remediated — Tuist makes an HTTP POST to every endpoint you have subscribed to that event type. The request body is a JSON envelope, and each delivery carries a signature header you can verify with the endpoint's signing secret.

You register a destination URL, pick the events you want, and Tuist takes care of signing, retries, and the delivery audit log.

## Steps to receive webhooks {#steps}

You can start receiving event notifications in your app with these steps:

1. [Identify the events](#event-types) your application wants to receive.
2. [Create a webhook endpoint](#create-an-endpoint) as an HTTP endpoint (URL) on your local server.
3. Handle requests from Tuist by [parsing the payload](#payload) and returning [a 2xx status](#responding) so Tuist marks the delivery as successful.
4. [Verify the signature](#verify-signature) on every request to prove it came from Tuist.
5. Use the [event log](#inspect-deliveries) in the Tuist dashboard to debug while you build.

## Event types {#event-types}

Tuist groups events by the resource they describe. The `type` field in the envelope uses dotted notation (`{resource}.{action}`) — same as the value you'd subscribe to in the dashboard.

{{webhook_events_table}}

More event types will follow. If you need one we don't yet emit, let us know and we'll add it to the catalog.

## Create an endpoint {#create-an-endpoint}

Endpoints are configured per account. Open **Webhooks** from your account settings, click **Add endpoint**, and provide:

- **Name** — how the endpoint appears in the listing.
- **Endpoint URL** — must use `https://`.
- **Events to listen for** — pick the specific events, or use **Select all** at the group level. Tuist only POSTs to the endpoint when one of the subscribed events fires.

![The Endpoints listing with two webhook endpoints subscribed to two events each](/images/guides/integrations/webhooks/endpoints.png)

When you save, Tuist generates a fresh signing secret and displays it once. Copy it into your application's configuration immediately — you won't be able to retrieve it again from the dashboard. If you lose it, use **Rotate secret** on the endpoint's actions menu to issue a new one.

<img src="/images/guides/integrations/webhooks/create-endpoint.png" alt="The Webhook endpoint creation modal with name, URL, and grouped event-type checkboxes" style="max-width: 500px;" />

## The payload {#payload}

Every delivery is a single JSON object. The envelope wraps an event-specific resource snapshot in metadata you can use to deduplicate, route, and audit deliveries:

| Field     | Description                                                              |
| --------- | ------------------------------------------------------------------------ |
| `id`      | A UUID unique to this delivery. Use it to deduplicate when retries fire. |
| `type`    | The dotted event type, e.g. `test_case.updated`.                         |
| `created` | Unix timestamp (seconds) at which Tuist enqueued the delivery.           |
| `object`  | The resource snapshot. The shape depends on the event type.              |

The exact payload schema for each event type is documented in the [Tuist API reference](https://tuist.dev/api/docs#section/Webhook-events) under **Webhook events** — every event has a matching `WebhookXxxEvent` schema under `components.schemas` you can `$ref` from a code generator.

A `test_case.updated` payload, for example, also carries an `events` array listing the canonical transitions that caused the write (`marked_flaky`, `muted`, `unskipped`, …), plus `actor_id` and `alert_id` so receivers can distinguish manual edits from automation-driven changes.

Each request also carries these HTTP headers:

| Header              | Description                                                                                   |
| ------------------- | --------------------------------------------------------------------------------------------- |
| `Content-Type`      | Always `application/json`.                                                                    |
| `User-Agent`        | `Tuist-Webhooks/1.0`.                                                                         |
| `Tuist-Event-Id`    | Same UUID as `id` in the body — convenient if you log headers before parsing the payload.     |
| `Tuist-Event-Type`  | Same string as `type` in the body.                                                            |
| `Tuist-Signature`   | The HMAC-SHA256 signature, formatted as `t={timestamp},v1={hex_digest}` — see below.          |

## Responding to a webhook {#responding}

To acknowledge a delivery, your endpoint should return any `2xx` status code. Anything outside the `2xx` range — along with connection failures and timeouts — is treated as a delivery failure and retried. Tuist doesn't follow `3xx` responses, so respond at the canonical URL directly rather than redirecting.

Keep your handler **fast**: Tuist waits up to **10 seconds** for the response. If you have heavy work to do (calling another API, updating a database, sending notifications), accept the request and process it asynchronously. Returning early also makes you resilient to transient slowness in your downstream services.

## Verify the signature {#verify-signature}

Anyone who learns your endpoint URL can POST to it. The signing secret lets your server reject anything that doesn't come from Tuist.

For every request, Tuist computes:

```
signed_payload = "{timestamp}.{raw_request_body}"
signature      = HMAC-SHA256(signing_secret, signed_payload)
header         = "t={timestamp},v1={hex(signature)}"
```

To verify on your side:

1. Read the `Tuist-Signature` header and split it into the `t=` (timestamp) and `v1=` (hex digest) parts.
2. Reject the request if the timestamp is more than **5 minutes** away from your server's current time. This *bounds* the replay window but doesn't close it — pair it with idempotency below.
3. Recompute `HMAC-SHA256(signing_secret, "{timestamp}.{raw_body}")` and compare it to the digest in **constant time**.
4. Dedupe deliveries on the payload `id` (also surfaced as the `Tuist-Event-Id` header). It's stable across retries, so persisting the IDs you've already processed prevents a captured request from being replayed within the tolerance window and shields you from double-processing on a retry.

> [!IMPORTANT] USE THE RAW BODY
> The signature is computed over the bytes Tuist sent. If your web framework reparses and re-serializes the JSON before you verify, the digest won't match. Capture the raw body (e.g. `request.body.read` in Rack, the raw `Buffer` in Express) and pass that to your verifier.

A reference verifier in Node.js — translate the same four steps (parse the header, check the timestamp drift, recompute the HMAC, compare in constant time) to whatever language your receiver is written in:

```javascript
import crypto from "node:crypto";

function verifyTuistSignature(rawBody, header, secret, toleranceSeconds = 300) {
  const parts = Object.fromEntries(
    header.split(",").map((kv) => kv.split("=", 2))
  );
  const timestamp = Number(parts.t);
  const signature = parts.v1;
  if (!timestamp || !signature) return false;

  const drift = Math.abs(Math.floor(Date.now() / 1000) - timestamp);
  if (drift > toleranceSeconds) return false;

  const expected = crypto
    .createHmac("sha256", secret)
    .update(`${timestamp}.${rawBody}`)
    .digest("hex");

  const a = Buffer.from(expected, "hex");
  const b = Buffer.from(signature, "hex");
  return a.length === b.length && crypto.timingSafeEqual(a, b);
}
```

## Retries {#retries}

Tuist retries any delivery that returns a non-`2xx` status, times out, or fails to connect. The schedule is fixed:

| Attempt | Wait before sending |
| ------- | ------------------- |
| 1       | (immediate)         |
| 2       | 1 minute            |
| 3       | 5 minutes           |
| 4       | 30 minutes          |
| 5       | 2 hours             |
| 6       | 8 hours             |
| 7       | 24 hours            |

After the seventh attempt fails, the delivery is permanently marked as failed. Because every attempt is signed with the timestamp at which it was sent, your replay-protection window still applies on retries — you don't have to widen it.

## Inspect deliveries {#inspect-deliveries}

Open an endpoint from the **Webhooks** page to see its delivery history. The detail page surfaces:

- A **summary card** with the destination URL, the masked signing secret, the subscribed events, and the creation date.
- A **delivery chart** with running totals and the failure count, scoped to the selected time window.
- An **events table** you can filter by status, event type, or event ID.

![A webhook endpoint detail page showing the summary card and the event deliveries chart](/images/guides/integrations/webhooks/endpoint-detail.png)

Click an event to see the full request and response from that attempt — the exact payload Tuist sent, the headers, the upstream status code, and the response body. This is the same data your server saw, which makes it the fastest way to debug a signature-verification mismatch or a 5xx upstream.

![A webhook event detail page showing the summary, the request headers and body, and the upstream response](/images/guides/integrations/webhooks/event-detail.png)

Delivery records are retained indefinitely so you can look back when debugging an integration. If your downstream system needs durable copies (e.g. for compliance), capture the deliveries on your own infrastructure as they arrive.

## Rotate or delete an endpoint {#rotate-or-delete}

Both actions live in the kebab menu on the endpoint row and on the endpoint's detail page:

- **Rotate secret** — generates a new signing secret and shows it once. Existing consumers fail verification until you update them, so plan the rotation alongside a deploy.
- **Delete endpoint** — removes the endpoint and stops delivery. Already-recorded delivery attempts are kept until the standard retention window expires.

## Security notes {#security}

- Endpoint URLs must be HTTPS. Tuist refuses to deliver to plaintext destinations.
- Tuist resolves the destination hostname before each delivery and rejects loopback, RFC1918, link-local, ULA, and cloud-metadata addresses (`169.254.169.254`, `fd00::/8`, …). This prevents a misconfigured webhook from being used to scan or attack the host that runs your Tuist server.
- The endpoint URL and signing secret are encrypted at rest. They are excluded from GDPR/CCPA data exports as bearer credentials.
- The signing secret is shown exactly once. Treat it like a password: store it in your secret manager, not in the repo.
