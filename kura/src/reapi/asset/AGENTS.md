# Remote Asset fetching

- Implements Remote Asset v1 `FetchBlob` on Kura's existing gRPC listener; directory fetching and Push are unsupported.
- `request.rs` validates qualifiers and computes namespace-scoped opaque lookup keys. Include canonical IDs, integrity and effective origin headers in the identity. Never persist or log raw origin credentials or signed URLs.
- `http.rs` shares a pooled client with a validating DNS resolver and separately validates IP literals on every redirect. Keep proxy discovery disabled, reject private/reserved addresses and HTTPS downgrades, and strip origin headers across origins. The loopback allowance exists only under `cfg(test)`.
- Cancel active fetches on the runtime drain notification so their gRPC guards cannot consume the shutdown budget.
- Stream through ordinary memory and temporary-storage budgets; verify checksum and size before publishing CAS. Preserve cancellation cleanup and publish through the store’s durable arrival feed for peer pull replication.
- Store CAS blobs and lookup records through the existing Reapi artifact producer and replication machinery. A lookup is usable only while its CAS body remains available; there is no retention lease or permanent mirror guarantee.
- Probe the cache before download admission; coalesce same-key misses per node and namespace, then probe again and acquire origin admission only for a caller that still needs to fetch. Same-key waiters must not consume download slots. Bound origin concurrency, request size, redirects, retries and total timeout.
- Keep tests in `tests.rs` and real Bazel coverage in `spec/e2e/bazel_remote_asset_spec.sh`. Do not add production fault-injection controls.

- Mirror permutations share admission using the smallest opaque URI identity, including effective headers. Coalesced results remain only while flight callers exist; validate the waiter's identity, freshness and CAS presence before reuse. Lookup publication failure must not discard an already-committed CAS result. Log invalid lookup records and publication failures without raw URLs or credentials.
- Hash SHA-256 for CAS plus only the requested additional integrity algorithm. Set exactly one identity encoding header. Keep incomplete framing non-retryable and cap all retries per mirror at 60 seconds within the three-minute request deadline.
- Keep the reqwest/rustls type-compatibility test and live untrusted-TLS regression together; avoid parsing TLS error messages.
