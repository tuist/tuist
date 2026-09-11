# Remote Asset fetching

- Implements Remote Asset v1 `FetchBlob` on Kura's existing gRPC listener; directory fetching and Push are unsupported.
- `request.rs` validates qualifiers and computes namespace-scoped opaque lookup keys. Include canonical IDs, integrity and effective origin headers in the identity. Never persist or log raw origin credentials or signed URLs.
- `http.rs` resolves, validates and pins public destinations on every redirect. Keep proxy discovery disabled, reject private/reserved addresses and HTTPS downgrades, and strip origin headers across origins. The loopback allowance exists only under `cfg(test)`.
- Stream through ordinary memory and temporary-storage budgets; verify checksum and size before publishing CAS. Preserve cancellation cleanup and replication backpressure.
- Store CAS blobs and lookup records through the existing Reapi artifact producer and replication machinery. A lookup is usable only while its CAS body remains available; there is no retention lease or permanent mirror guarantee.
- Coalesce same-key requests per node and namespace. Bound concurrency, request size, redirects, retries and total timeout.
- Keep tests in `tests.rs` and real Bazel coverage in `spec/e2e/bazel_remote_asset_spec.sh`. Do not add production fault-injection controls.
