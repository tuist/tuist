# Grafana backend verifier qualification, 2026-10-22

This records source and local candidate checks, not execution inside Grafana,
catalog publication or a running-plugin/fleet replacement. The initial source
baseline was `7d3a09a175b2f6adf29aeedaddad61efcdee178c`.

## Implementation and reasoning

Go 1.26.10's qualified built-in deny covers the eight incident intermediate keys,
not all twelve application-policy keys. The independent backend now embeds all
twelve SHA256 SPKI hashes in `pkg/plugin/certificate_trust.go`.

The API factory clones the existing default transport and TLS configuration,
preserving native system/private roots, environment proxies, HTTP/2, timeouts,
ordinary certificate/hostname validation and original verification callbacks.
Custom TLS dialers or disabled verification fail closed rather than bypassing the
policy. The additional callback inspects every complete verified chain, including
anchors, and the supplied peers. It runs on resumed TLS sessions too. It neither
installs host certificates nor needs this checkout at customer runtime.

This deliberately rejects a supplied blocked certificate even when it is unused
by a clean selected path, matching the Rust clients. Apple/Android native image
loaders check only their evaluated paths. A self-hosted server sending a redundant
blocked AAA cross-sign/root can therefore lose availability and must repair its
served chain; do not add an unprotected fallback.

Redirects retain the normal ten-hop limit and credential behavior, but refuse an
HTTPS-to-HTTP downgrade. Explicitly configured HTTP endpoints retain their prior
semantics; they are not TLS-failure fallbacks. Both HTTPS proxy and tunneled target
TLS use the protected configuration. API errors expose fixed certificate-policy,
native-certificate, timeout/cancellation categories or HTTP status, never URLs,
headers or response bodies. Health checks no longer blame TLS rejection on the
token. Datasource disposal closes only its owned idle connections.

## Executed validation

All Go commands used the explicit genuine Go 1.26.10 toolchain with `GOROOT`
unset and `GOTOOLCHAIN=local`, not a global SDK/trust change. Logs are under
`/tmp/tuist-emudhra-audit/`.

- On exact committed Grafana source `12cd81f6a98b1c328ae2c5007f49532aaf8a511b`,
  `TUIST_TRUST_LIVE=1 go -C grafana-datasource test -race ./... -count=1
  -timeout 5m -v` passes, including all live and wire controls (plugin package
  20.781s). `grafana-committed-live-race-tests.log` records the commit and genuine
  Go version. Earlier offline race runs also pass (`grafana-final-race-tests.log`).
- Focused offline policy tests pass (`grafana-final-offline-policy-tests.log`):
  real twelve-key DER/hash rejection; empty/nil material; actual API-client
  acceptance of a private chain and add-only leaf/intermediate/root denial;
  hostname, unknown CA, expiry, signature, usage and unknown-critical-extension
  rejection; original callback preservation; refusal of unsafe configurations;
  factory defaults and diagnostic/health/disposal checks.
- Actual wire controls accept unrelated private HTTPS and then reject an
  additionally denied destination after HTTPS redirect, a denied HTTPS proxy
  before CONNECT, and a separately denied target inside a clean CONNECT tunnel.
  Proxy and target use different PKIs. TLS 1.2 and TLS 1.3 session resumption are explicitly
  observed and its cached accepted anchor is then denied. No denied connection
  reaches the protected API handler.
- `TUIST_TRUST_LIVE=1 go -C grafana-datasource test ./pkg/plugin -run
  '^TestCertificateTrustLiveProductionFactory$' -count=1 -timeout 5m -v` passes
  in 16.11s on the final recorded run (`grafana-final-live-tests.log`). The log records SDK `go1.26.10`,
  all twelve certificate-specific negatives and an unrelated HTTPS positive.
  All twelve show `native_verifier=true, application_key_deny=false`: these
  qualify the combined SDK/native roots, **not application-callback execution**.
  Only the accepted-chain differential/wire checks prove the new layer executes.
- An earlier combined live full-package run exceeded the tool harness's 180s
  deadline during the long native probe. It is incomplete, not a pass. The first
  live run completed in 190.03s; final offline/race and focused live runs above
  supersede it for current-source qualification.
- Shared Go tests synchronize the twelve hashes and protected factory wiring.
  Scoped workflow actionlint and whitespace checks pass. No Python, real account
  credentials, host trust installation or signed-resource alteration was used.

## Built candidates and remaining gates

Actual backend executables build with `go build -trimpath ... ./pkg`:

| Candidate | SHA256 |
| --- | --- |
| Darwin arm64 | `a53b3be9ea4fb4cee127b0e2635a46779d95388da0a786c24d728630352fad6b` |
| Linux amd64, CGO disabled | `dd8d1a393e332599a732644c1c4440e2f6acc0a0182fd8c2d61e34b99ec9b747` |

Build logs, `artifact-sha256.txt` and `artifact-build-info.txt` are in the `grafana/`
log subdirectory. `go version -m` records Go 1.26.10 but no VCS identity; release inputs must
be rebuilt and qualified from their committed release source. These are local build-only
artifacts, not signed release bundles, Linux runtime evidence or an assertion
that a published/running plugin already contains the policy.

Read-only Claude review found no source blocker, and requested explicit native
versus application attribution, separate tunnel-target denial, sanitized useful
TLS health categories and documentation of strict peer-certificate refusal.
Those findings are addressed above. Other OS/root stores, corporate proxy/custom
CA environments, Grafana plugin RPC/query/alert integration and exact signed
catalog artifacts remain gates. An owner must qualify a fixed release and safely
replace plugin processes while preserving active queries, alerting availability,
HA capacity and a qualified patched rollback. No plugin publication, Grafana
restart or production promotion was performed.
