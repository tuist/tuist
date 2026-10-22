# Kura outbound trust: open implementation boundary

Source/design audit, **2026-10-22**. No new Kura verifier implementation, artifact qualification or rollout is recorded by this document. Container PEM containment does not close this row.

## Locked verifier and production paths

Kura's locks resolve reqwest **0.13.2**, rustls **0.23.46**, rustls-webpki **0.103.16**, rustls-platform-verifier **0.6.2**, rustls-native-certs **0.8.3**, security-framework **3.7.0** and tonic **0.14.5**. Do not substitute the locally cached platform-verifier 0.7.x source when reviewing the locked backend. Kura installs AWS-LC; reqwest otherwise prefers the installed process provider before its own AWS-LC default.

Unlike Atlas's reqwest 0.12 setup, reqwest 0.13's normal `rustls` path uses the platform verifier, including when extra roots are added. `tls_certs_only` instead constructs WebPKI over explicit anchors. Reusing Atlas's bundled-root config would change Kura's native/enterprise trust semantics. Kura publishes macOS binaries as well as Linux artifacts, so macOS cannot be silently excluded.

Production constructors to cover together:

- `control_plane_http.rs`: control-plane, heartbeat, usage, analytics, analytics-forwarder and Bazel test-artifact clients.
- `enrollment.rs` and `registration.rs`: separately built enrollment/registration clients, including enrollment's client secret.
- `reapi/asset/http.rs`: Remote Asset origin downloader. Preserve the validating resolver, IP-literal and redirect checks, origin-header stripping, no-proxy policy, pool/read/time bounds, drain cancellation and publication rules in its leaf `AGENTS.md`.
- `telemetry.rs`: blocking OTLP HTTP client and Sentry's SDK-internal reqwest transport. Supplying a protected OTLP client does not protect Sentry's independently constructed client.
- `serving_authority.rs`: Kubernetes client with the service-account CA added to native roots. Preserve HTTPS-only, no-proxy, redirect rejection and short timeout.
- `peer_tls.rs`: explicit-anchor mTLS client, per-build identity snapshot, rotation, topology routing, resolving and download idle-time settings. Its inbound client-authentication verifier is a separate internal-plane owner boundary, also requiring the twelve-key audit.

Current OTLP gRPC does not enable the exporter's TLS features: an HTTPS endpoint fails construction, not a protected TLS handshake. Enabling TLS later requires an explicit protected channel and tests; do not add plaintext fallback or treat plaintext export as TLS qualification. Distinguish production constructors from `#[cfg(test)]` helpers.

## Required implementation properties

A wrapper around `rustls_platform_verifier::Verifier` cannot inspect its private anchor store or the evaluated native chain: `verify_server_cert` returns only `ServerCertVerified`. Checking only supplied peers leaves absent anchors and native cached/AIA intermediates uncovered.

- **Linux:** reproduce the locked platform backend's native-store/extra-root behavior, including strict extra-root parsing, native-store warning behavior, empty-store failure and per-build root loading. Filter all twelve blocked candidate-anchor keys, preserve the provider and normal WebPKI validation, and restrict supplied peers. The pinned WebPKI path builder denies the eight intermediate keys. Do not switch to bundled roots or change `SSL_CERT_FILE`/`SSL_CERT_DIR` semantics.
- **macOS:** preserve native SSL/hostname policy, verify date, stapled OCSP and extra anchors alongside system roots, then check the complete successfully evaluated SecTrust chain. Retain native validation and provider signature verification. A second peer-only wrapper is not sufficient.
- **Explicit peer anchors:** a private-CA deployment assumption is not enforcement. A configured CA can contain a blocked root key, and a privately signed peer can reuse a blocked public key. Filter all twelve candidate-anchor keys and restrict peer keys while preserving the ordinary verifier. Do not exempt this branch merely because WebPKI blocks the eight intermediates.
- **Identity/rotation:** reqwest's preconfigured-TLS route skips its identity, roots, SNI, protocol-version and ALPN setup. Reproduce those settings deliberately. Preserve PEM parsing parity (certificate order, accepted PKCS#8/PKCS#1/SEC1 sections, last-key behavior and rejection of unsupported sections) and `with_client_auth_cert` validation. Keep per-build identity reload, overlap CA bundles and failure ordering. Do not inadvertently send the peer identity to public origin/control-plane clients.
- **Sentry:** a custom transport must use the protected client without enabling invalid-certificate options, dropping existing proxy behavior or printing DSN credentials. An SDK-owned default client is not covered by another factory.
- **Origin construction/availability:** Remote Asset currently constructs its client through `Default` with `.expect(...)`; preserve or deliberately change and test its build-failure behavior. Customer-chosen origins are especially sensitive to a conservative supplied-peer deny: a redundant blocked cross-sign can cause rejection even when another valid path exists. Document that availability distinction and repair served chains, never disable verification or select weaker fallbacks.

The smallest design still needs normal-path, configured-anchor and accepted leaf/intermediate/root deny differentials; actual mTLS rotation; real twelve-key DER; native macOS chain tests; ALPN; HTTPS CONNECT; all production constructor wiring; typed privacy-safe failures; and Bazel source/dependency/release integration. Follow Kura's Bazel-first instructions, serving-authority safety, rollout pauses, instance pins and warm-cache constraints. Source/design review is not permission to replace serving processes or promote a release.

Read-only adversarial review corrected two initially unsafe assumptions: the locked platform verifier is 0.6.2, not 0.7.x, and explicit/private peer anchors are not automatically twelve-key protected. Review receipts are under `/tmp/tuist-emudhra-audit/claude-kura-{native-design,peer-challenge}*`; no reviewer builds, tests or live calls were used (read-only source/shell inspection was permitted).
