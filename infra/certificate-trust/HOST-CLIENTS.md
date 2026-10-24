# Host helper transports

## macOS log shipper

The standalone `tuist-log-shipper` binary now embeds all twelve SPKI hashes. Its
owned client clones the original native Go transport/TLS configuration, runs
ordinary validation and existing callbacks, then restricts complete verified
paths (including absent anchors and resumed paths) and supplied certificates.
On Darwin with nil roots, native validation delegates to Security.framework;
private explicit-root tests alone do not exercise that production path.
Insecure verification/custom TLS dialers are refused rather than bypassed.
Additional hashes are copied and can only add restrictions.

`NewClient` retains the existing per-dial MagicDNS resolver, OS-resolver fallback,
30-second push deadline and direct/no-proxy topology. The lazy zero-value client
path is protected too. Both paths own their clones and idle connections; no
process-global transport, environment or root store is changed. Existing
callback, proxy, protocol and session-cache configuration is retained when the
internal factory is exercised with an explicit base client.

Push diagnostics retain typed causes but expose only fixed categories/status
codes, not endpoint userinfo/query, payloads, headers or receiver response bodies.
Startup does not print the URL and refuses malformed/non-HTTP(S) receivers
before tailing. Dual resolver errors retain typed causes and expose only
resolver identity, fixed DNS kind/timeout or dial errno categories. Native TLS,
policy and cancellation failures do
not become `ErrRejected`: retries remain protected, offsets stay put and log
batches are not silently dropped. Existing 4xx-versus-429/5xx handling, bounded
backoff, file tailing, rotation/truncation and position semantics remain intact.

### Qualification

On the Darwin arm64 host with genuine Go 1.26.10:

- All-package race/public-opt-in tests passed.
- The same complete suite/public opt-in passed with `CGO_ENABLED=0`, matching
  the owner build setting. The actual MagicDNS/native-default client accepts
  unrelated HTTPS, then additive leaf/intermediate/absent-anchor hashes from its
  evaluated chain produce `errDistrustedKey`. Roots stay nil and the root is
  verified absent from the supplied chain. This qualifies the Apple native path
  independently of the private explicit-root fixtures.
- Real DER tests cover all twelve keys. Actual Push accepts private chains then
  rejects leaf/intermediate/absent-root keys before log-body delivery.
- Native hostname, expiry, signature, usage, critical-extension and unknown-CA
  failures remain authoritative.
- Defensive configured-transport coverage: separate-PKI HTTPS CONNECT rejects keys on either leg before proxy credentials
  or log bodies reach the rejected endpoint; legitimate connections work again.
- Defensive configured-transport coverage: real TLS 1.2/1.3 resumed sessions
  reject a cached absent anchor before delivery. The production client retains
  its nil session cache and no-proxy behavior; neither path is enabled by this fix.
- Configuration/callback/redirect/cancellation/status/privacy tests and existing
  position/drop/backoff tests pass. Public negatives require certificate-specific
  errors, with unrelated HTTPS success; they do not prove application enforcement.
- Shared policy, bounded factory ownership and diagnostic AST guards passed.

These are host tests, not the exact operator-image/binary installation or a
fleet rollout. The managed receiver remains **plaintext HTTP over the tailnet**;
this implements configurable HTTPS without converting the deployed topology.
The CAPI image embeds this daemon and bootstrap re-pushes it on a host-config
hash change. Qualify that owner artifact and replace the installed daemon only
with separate rollout authorization, preserving positions and logs.

## Other C13 boundaries still open

GitLab's coordinator/API, object storage, upstream cache archiver/downloader,
GoCDK and job subprocesses are independently owned. The pinned upstream client
rebuilds TLS configuration on CA/certificate/key file changes and provides no
public additive verification hook. Patching its coordinator alone would not
protect the archiver or delegated tools. Any owned upstream source patch must
use a verified temporary module copy plus private modfile/replace, not a Go
`-overlay` beneath `GOMODCACHE` or mutation of the shared module cache.

Runner-cache transfers, host bootstrap/sensors, MDM and curl/Git/Bazel/SwiftPM
subprocesses retain separate audits and verifier/release gates. Shell HTTP/WSS
and cache-volume HTTPS evidence is in [RUNNER-CLIENTS.md](RUNNER-CLIENTS.md).
Neither a Go SDK pin nor root-store removal proves all-twelve application
restriction across these boundaries. No publication or deployment is implied.
