# Browser telemetry receipts

`Receipts` coordinates LCP replay classification through PostgreSQL. Never use
node-local caches as the authority: concurrent deliveries can hit any replica.

- Claim sorted fingerprints in a short transaction; do not hold it across HTTP.
- A 30-second lease permits recovery after a killed gateway. Only the matching
  lease can complete or release a receipt. A busy batch returns a retryable error
  and rolls back all new claims from that batch.
- Remember confirmed deliveries for 48 hours, and prune expired rows in bounded
  batches through the existing idempotent-request pruning worker.
- Preserve raw reports. These receipts classify replays; they do not promise
  exactly-once Alloy ingestion after an ambiguous timeout or lost acknowledgment.
- Store hashes and lease/expiry timestamps only. Keep `server/data-export.md`
  and `infra/helm/k8s-monitoring/browser-rum.md` aligned with this contract.
- The independent-connection tests use an unsandboxed owner and clean only their
  own randomly generated keys. Never point those tests at a shared deployment.

Parent: [business logic](../AGENTS.md).
