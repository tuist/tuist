# Model Context Protocol Events

- `Tuist.MCP.Events` is the protocol entry point. `Catalog` declares event contracts; `Subscriptions` persists them, `SubscriptionAuthorization` checks their targets and credentials, `Publisher` queues domain-supplied event data, and `Payload` builds delivery links. Project-filtered build/test subscriptions and account-filtered runner job subscriptions are supported. Subscribe only for a real user and a scoped account or OAuth credential; check both against the relevant project or account without Atlas operator-read elevation.
- Store callback URLs and Standard Webhooks secrets encrypted. Verify callbacks before saving them, and pin public addresses again for every delivery. Do not follow redirects.
- Domain writers enqueue fan-out jobs on the isolated `:mcp_events` queue. Batch producers and fan-out workers insert jobs in bounded groups. Delivery jobs recheck owner access, the exact OAuth grant lineage or claimed account token, and expiry. Event IDs remain stable across retries.
- Fan-out and delivery jobs live in PostgreSQL so any server instance can run them. `Queue` inserts a deduplication key and job in one short transaction, including for bulk jobs. The hourly pruning job removes those keys in bounded batches after 31 days. Keep event IDs stable so clients can discard later duplicates.
- The daily pruning job removes subscriptions one day after expiry; the subscription cap counts only active rows.
- Keep event payloads limited to resource identifiers and links. Agents obtain failure details through authorized read tools.
- Add an event to `events/list` only when its domain hook and delivery path are ready.
