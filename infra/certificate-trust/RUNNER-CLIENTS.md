# Runner helper client qualification

## Interactive shell agent

The Linux and macOS `cmd/runner-shell-agent` copies now embed the twelve-key SPKI policy for **session-discovery HTTP and shell WSS**. This is one part of C13, not closure of the runner image, cache-volume/GitLab executors, shell/curl pollers, host agents or delegated job tools.

Both copies use the same independently compiled policy and keep their direct/no-proxy dialers, native roots, TLS 1.2 minimum, deadlines, headers and Unix-socket/PTY behavior. Ordinary Go validation and original callbacks run before the additional deny over every verified chain (including anchors) and supplied peer certificate. Caller-provided add-only test denies are copied before use. Disabled verification is refused. Production resumption is disabled by the existing nil `ClientSessionCache`; a test pins that setting. The callback's synthetic resumed-state test does not qualify a resumed wire connection. If session caching is enabled later, qualify it on the wire before release.

Discovery refuses HTTPS redirects to plaintext. The raw-WebSocket-origin opt-out cannot downgrade an HTTPS-discovered session to `ws`; explicitly configured original HTTP/WS use remains, not a TLS-failure fallback. WSS uses the protected configuration even through the configurable internal connection builder. Errors retain typed causes and useful fixed TLS categories without rendering credential-bearing URLs or server response bodies. Raw discovery/tunnel URLs are no longer logged; timeout, cancellation, DNS, connection-refusal, URL-parse and invalid-JSON responses have separate fixed categories. Native verification and handshake signature processing are not replaced by key-only acceptance.

The deny is conservative: Go checks every returned verified chain and supplied peer certificate, including unused supplied cross-signs. A server sending a redundant blocked certificate may need its served chain repaired even if another path is clean. Never respond by disabling verification or retrying through a weaker transport.

## Local validation, 2026-10-22

Genuine Go **1.26.10**, retaining each module's `godebug default=go1.25`:

```sh
TUIST_TRUST_LIVE=1 GOWORK=off go -C infra/runner-image test -race -count=1 -v ./cmd/runner-shell-agent
TUIST_TRUST_LIVE=1 GOWORK=off go -C infra/linux-runner-image test -race -count=1 -v ./cmd/runner-shell-agent
```

Both suites pass on the **Darwin arm64 host**. Running the Linux image's source on Darwin is not execution of a Linux image or binary. Seven new top-level tests per copy cover:

- All twelve real policy certificates and empty/malformed certificate material.
- Actual `discoverSession` and actual WSS builder: accept an unrelated private root/intermediate/leaf chain, then deny its otherwise accepted leaf, intermediate or absent-from-peer root through add-only policy. Denied connections never deliver the fixture bearer token or an HTTP request.
- Certificate-specific ordinary hostname, unknown-CA, expiry, signature, usage and critical-extension failures on both HTTP and WSS.
- Retained native/no-proxy settings, refused disabled validation, original callback refusal, immutable extra denies, synthetic resumed/missing chain states and sanitized typed errors.
- Actual HTTPS redirect downgrade rejection and the raw WSS-origin opt-out restriction.
- Explicitly enabled credential-free public HTTP controls: all twelve reject for certificate-specific causes, unrelated Let's Encrypt HTTPS returns 200. Every public negative logs **`native_verifier=true application_key_deny=false`**. Application execution is demonstrated by accepted-key differentials, not these native rejections. No public WSS-upgrade success or twelve-host WSS qualification is claimed.

The shared policy suite checks both policy arrays; byte-identical `main.go`, `certificate_trust.go`, `certificate_trust_test.go` and `certificate_trust_diagnostics_test.go` copies; protected HTTP/WSS factory wiring; log arguments; and fixture equality. Linux's separate pre-existing `main_test.go` is not mirrored. Read-only certificate CI is wired to watch and run both focused suites; no completed Linux CI run is claimed here. Existing owner Docker/Packer builds include these new files through their existing `cmd` build inputs; no new runtime policy file or host trust mutation is required.

Source implementation: `50cda9fed5`. Repeated from clean committed tree **`2819576aded5bf39a53e34211084379f5628f4f6`**: both host race/live suites pass (macOS-module package 23.474 s, Linux-module source package 5.212 s), and the complete shared policy suite including final AST guards passes in 59.635 s. Logs: `/tmp/tuist-emudhra-audit/runner-shell-committed-{runner-image,linux-runner-image}-live-race.log` and `runner-shell-committed-go-sync.log`. Workflow lint passes in `runner-shell-final-actionlint.log` with the explicitly installed shellcheck on PATH. Earlier actionlint attempts that failed to resolve the mise shellcheck shim are not passing receipts.

Local candidates were built from that same clean tree using `-trimpath -ldflags='-s -w'`:

| Candidate | SHA-256 | Build metadata |
| --- | --- | --- |
| Darwin arm64 | `b6a52796e44acab838e3ccf3329b85a9725ab0522414974a51c41d6127aa337f` | Go 1.26.10, CGO enabled as in the native owner build |
| Linux amd64 | `d9e1135a85904da5b57f50b70f8556db60f8fe2648bb3a4f7d6f2ff37c21625f` | Go 1.26.10, CGO disabled as in the image builder |

Both retain matching prior-compatibility `DefaultGODEBUG` metadata and contain all twelve policy strings. `/tmp/tuist-emudhra-audit/runner-shell/artifacts/` records hashes, architecture, SDK/build metadata, the manually captured source revision and an empty worktree-status receipt. The Go build metadata itself does not include a VCS revision. These binaries were built and inspected, **not executed as candidate artifacts**, signed, published or installed; their presence and strings are not runtime attestation.

## Cache-volume HTTPS clients

`infra/linux-runner-image/cmd/tuist-cache-volume` now independently embeds the twelve-key policy for `/acquire`, `/checkout` and streamed `/checkout-export` when configured with HTTPS. Unlike the shell agent's direct dialer, these clients previously used `http.DefaultTransport`: the protected factory clones that transport and retains environment proxies, native roots, HTTP/2, original callbacks and timeouts. It refuses disabled verification/custom TLS dialers, checks all normally verified paths/anchors and supplied peers, and preserves refusal of **every** redirect. Acquire, checkout and export retain their 30 s, 20 s and 3 min limits. The production `ClientSessionCache` remains nil; configured-session tests separately exercise real TLS 1.2/1.3 resumption.

**Managed topology is not HTTPS today.** Both Helm cache-volume URL paths render `http://<service>.<namespace>.svc.cluster.local:8090`, which the controller forwards unchanged. That traffic has no certificate verification to restrict. This implementation protects HTTPS-configured deployments; it neither converts the managed service to TLS nor claims a certificate-policy handshake occurred on its current plaintext route. macOS attach/checkout continue using their local filesystem/mailbox path.

Eleven focused trust tests plus the existing helper suite cover real twelve-key DER; actual acquire/checkout/export accepted private leaf/intermediate/absent-root denies before any request or body is delivered; ordinary unknown-CA, hostname, expiry, signature, usage and critical-extension failures; separate proxy and target PKIs with proxy credential isolation; configured TLS 1.2/1.3 wire resumption; all five common redirect statuses; timeout/cancellation and typed private URL/JSON/DNS/refusal diagnostics. TLS failure leaves the ordinary empty-directory fallback intact and cannot create checkout/export permission without a host grant. Injected-client attach helpers now exist only in test files. Shared tests pin factories, policy/fixture equality and bounded diagnostic guards; CI watches and race-tests this package.

The complete helper suite passes with opt-in public controls on the Darwin host under genuine Go 1.26.10. All twelve public HTTP negatives are certificate-specific and natively attributed (`native_verifier=true application_key_deny=false`); unrelated HTTPS returns 200. Accepted-key tests, not these native negatives, prove application enforcement. Logs are `/tmp/tuist-emudhra-audit/cache-volume-trust-live-race.log` and `cache-volume-policy-sync.log`. This is not Linux runtime/image qualification or a released/installed helper. Normal Docker and macOS binary builds already include the whole package; no separate policy download is required.

## Remaining owner gates

- Candidate-artifact execution, Linux runtime, older supported OS/native/corporate trust stores and HTTPS redirect-to-protected-target wire cases remain separate from the above source/host tests and local build/metadata receipts. Resumption is currently disabled; enabling it requires resumed wire qualification.
- Existing Linux/Packer build failures remain open. No new runner image, helper publication, installed process replacement or deployed default is claimed here.
- Qualify exact cache-volume artifacts and HTTPS deployments independently of these source/host tests. `tuist-runner-cache`, GitLab's upstream cache downloader/archiver, host bootstrap/sensors/log shipper, MDM and other Go/vendor/subprocess clients still need their own enforcement audit. Their compiler pin alone covers the eight intermediate keys, not an application twelve-key callback.
- Apply owner-authorized patched artifact floors and idle/warm replacement. Preserve active jobs, token isolation, warm capacity, APFS masters, cache volumes/PVCs, local stores and spools. Do not kill active shell/job processes merely to replace this binary, and retain a qualified patched rollback.

See [wrapper ownership](ACTION-CLIENTS.md), [client inventory](CLIENTS.md) and the [warm-rollout runbook](README.md).
