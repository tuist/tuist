# Runner helper client qualification

## Scope: interactive shell agent only

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

Local logs: `/tmp/tuist-emudhra-audit/runner-shell-{macos,linux-source}-reviewed-live-race.log`, `runner-shell-reviewed-go-sync.log` and `runner-shell-reviewed-actionlint.log`. These are test receipts, not signed release attestations.

## Remaining owner gates

- Exact committed candidate binary hashes/build metadata and candidate execution, Linux runtime, older supported OS/native/corporate trust stores and HTTPS redirect-to-protected-target wire cases remain separate from the above source/host tests. Resumption is currently disabled; enabling it requires resumed wire qualification.
- Existing Linux/Packer build failures remain open. No new runner image, helper publication, installed process replacement or deployed default is claimed here.
- Independently qualify `tuist-cache-volume`, `tuist-runner-cache`, GitLab's upstream cache downloader/archiver, host bootstrap/sensors/log shipper, MDM and other Go/vendor/subprocess clients. Their compiler pin alone covers the eight intermediate keys, not an application twelve-key callback.
- Apply owner-authorized patched artifact floors and idle/warm replacement. Preserve active jobs, token isolation, warm capacity, APFS masters, cache volumes/PVCs, local stores and spools. Do not kill active shell/job processes merely to replace this binary, and retain a qualified patched rollback.

See [wrapper ownership](ACTION-CLIENTS.md), [client inventory](CLIENTS.md) and the [warm-rollout runbook](README.md).
