# cache-gateway

Terminates the GitHub Actions cache **v2** protocol inside a runner fleet and
translates it to S3 against a co-located SeaweedFS cluster. One instance per
fleet, fronted by the host-side `runner-cache-proxy` (which intercepts the
runner's cache traffic and routes the Twirp `CacheService` calls here). The
customer's workflow is unchanged.

## Two surfaces (one mux, path-prefixed)

- **Coordination** — `POST /twirp/github.actions.results.api.v1.CacheService/<Method>`,
  JSON. `CreateCacheEntry`, `FinalizeCacheEntry`, `GetCacheEntryDownloadURL`.
  Authenticated by the tenant cache token (`Authorization: Bearer`), verified
  with a configured Ed25519 **public** key. The server holds the private key.
- **Blob transfer** — `PUT/HEAD/GET /blob/<opaque-object-key>`, the Azure Block
  Blob subset the action actually performs. Authenticated only by an
  **HMAC-signed URL** (the SAS-URL pattern), served on the gateway's own
  hostname with a real certificate.

## Security invariants (do not regress)

- **Opaque object ids only.** Storage keys are `acct/<account_id>/blob/<id>`
  where `id` is server-generated from `crypto/rand` (`internal/objid`). The
  workflow-controlled cache `key`/`restore_keys` NEVER become a path, URL, or
  signed string — they live only as parameterized values in the metadata index
  (`internal/index`). Traversal is structurally impossible because no request
  byte is ever concatenated into a storage key.
- **No key normalization.** Cache keys are opaque bytes; byte-distinct keys are
  distinct entries (NFC≠NFD, `a%2Fb`≠`a/b`). The index composite key
  length-prefixes the controlled fields and stores the user key as the trailing
  raw region (`internal/index/codec.go`), so a `restore_keys` prefix scan stays
  inside one `(account, version, scope)` partition.
- **Ref scoping** (`internal/claims/scope.go`) mirrors GitHub: a read tries own
  ref → PR base ref → default branch; an untrusted fork sees only its own ref.
- **Sign the path, not the query** (`internal/sign`). The HMAC covers
  `op \n objectKey \n exp` and ignores every other query param, so the Azure SDK
  appending `&comp=block&blockid=...` after signing does not break verification.
- **Token alg pinned to EdDSA** (`internal/claims/verifier.go`): `alg:none` and
  HMAC-with-public-key confusion attacks are rejected.

## Fail open

Any failure degrades to a cache **miss**, never a hard error: invalid token,
backend error, tripped breaker, or unknown method all return `{ok:false}` (or a
Twirp `bad_route`), which `actions/cache` treats as a miss/skip. The
`cache_gateway_passthrough_fallback_total` metric is the first-class SLI.

## Multipart translation

`internal/multipart` buffers staged Azure blocks and, on Put Block List,
coalesces them in list order into ≥5 MiB S3 parts (final part may be smaller),
or single-shots the whole object when it is below the multipart floor — so a
customer `uploadChunkSize` under 5 MiB degrades gracefully. State is in-memory,
keyed by the opaque blob path; a restart fails an in-flight upload, which the
client retries idempotently.

## Layout

- `cmd/cache-gateway/main.go` — flags/env, two listeners (data + metrics/health).
- `internal/objid` — the single canonical storage key.
- `internal/claims` — token verifier (Ed25519) + ref-scope rules.
- `internal/index` — bbolt metadata index + the security-critical codec.
- `internal/sign` — HMAC signed blob URLs.
- `internal/objstore` — S3 interface, SeaweedFS impl, in-memory fake (enforces
  the 5 MiB rule).
- `internal/multipart` — Azure-block → S3-multipart coalescing.
- `internal/breaker` — health-gated circuit breaker.
- `internal/metrics` — Prometheus instrumentation (pass-through SLI first).
- `internal/server` — the two HTTP surfaces.

## Build / test

```
cd infra/cache-gateway
GOWORK=off go build ./...
GOWORK=off go test ./...
GOWORK=off go test -run=xxx -fuzz=FuzzCodecRoundTrip -fuzztime=20s ./internal/index/
```

The security test matrices in `internal/index/codec_test.go`,
`internal/sign/sign_test.go`, `internal/claims/*_test.go`, and the
`signed == routed == S3 key` property test in `internal/server/server_test.go`
are the proof for the traversal/encoding/ref-scope guarantees above. Keep them
green.
