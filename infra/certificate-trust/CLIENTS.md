# Client verifier coverage

This inventory tracks client-facing exposure separately from server image/root-store
containment. A configured dependency or passing source check is not a released or
runtime-qualified client. In particular, successful staging server probes do not
qualify the client software running on customers' devices.

Guidance: [Cloudflare's incident response](https://blog.cloudflare.com/emudhra-certificate-compromise/)
and [the upstream verifier/package matrix](https://emudhra.we-have-a-problem.com/),
reviewed 2026-10-21. Cloudflare explicitly distinguishes SDK, HTTP library,
runtime, OS and custom trust configurations, and requires actual-path testing.
Its published table also calls out customer-configured mTLS/uploaded CA stores:
those server-side client-authentication stores remain a separate owner audit.
The package matrix is a discovery source, not permission to skip behavioral tests
or assume a newer major SDK is patched.

Work through each row independently. Do not close a row until every listed
transport has signed negative controls, unrelated positive controls and preserved
hostname/ordinary trust validation, with the exact runtime and artifact recorded.
Tests with synthetic keys exercise the plumbing, not the compromised keys' actual
rejection. Test real policy certificates as well. Never generate or request the
compromised private keys.

| ID | Client / connection surfaces | Trust implementation | Current evidence / remaining work |
| --- | --- | --- | --- |
| C01 | `tuist_ex`: API/auth/OIDC, reporting, presigned uploads and streaming downloads | OTP `:httpc` | Implemented: embedded 12-key anchor filter and verification callback. All real policy keys rejected in DER/OTP callback tests; OTP 29 real handshake accepts private CA, rejects wrong hostname/untrusted CA. HTTP/pruned-path tests pass. Live HTTP rejects all twelve public negative hosts, plus sampled upload/download TLS failures; unrelated HTTPS returns 200. Hex build/compile/docs pass. Not published; other supported runtimes remain open. |
| C02 | `tuist_ex`: dependency-cache REAPI, capability negotiation and ByteStream | gRPC/Mint/OTP | Implemented: same embedded policy as HTTP, retaining endpoint hostname/SNI. Real local Mint HTTP/2 TLS accepts a private CA and rejects hostname mismatch/untrusted CA; public negative hosts reject through Mint HTTP/1 TLS (the hosts do not negotiate h2). 45 focused policy/HTTP/REAPI tests pass with one cold compilation fixture explicitly excluded after timeout failures. Complete gRPC runtime/version coverage remains open. |
| C03 | Swift CLI: API, OAuth refresh, CI OIDC, file transfers and cache HTTP | Foundation, custom additional-CA delegate; Linux FoundationNetworking separately | Current macOS Foundation rejects all twelve public hosts and accepts unrelated HTTPS. Found and fixed additional-CA bypass in `TLSValidator`: affected custom anchors previously produced successful HTTP responses. Filters blocked anchors and checks every verified-chain SPKI; 10 Xcode tests pass, including all twelve real keys, malformed DER and private CAs. Fixed delegate rejects all twelve live controls, positive HTTPS 200. Direct `URLSession.shared` paths depend on platform updates; Linux remains open. |
| C04 | Swift CLI: REAPI gRPC, HTTPS proxy CONNECT | SwiftNIO/NIOSSL | Pending. Separate verifier from Foundation; verify both origin and TLS proxy paths. |
| C05 | Apple app: API, authentication/refresh/dynamic registration, previews/images | Shared CLI modules plus direct Foundation sessions | Current-host native Foundation and shared custom-CA fix provide scoped evidence only. iOS, older supported macOS versions, direct sessions, background/image transfers and system-browser authentication still need independent qualification. |
| C06 | Android app: API, authentication/refresh, images and browser login | OkHttp/platform plus external browser | Pending. Both plain and authenticated OkHttp clients need coverage; browser trust remains OS/browser-owned. |
| C07 | Gradle plugin: cache, reports, shard/quarantine planning, discovery/latency | OkHttp and Java URL connections | Pending. Both transports and derived clients must use policy; retain private CA/enterprise proxy support. |
| C08 | Xcode CAS plugin and per-machine CAS proxy | Rust tonic/rustls with native roots | Locked webpki is 0.103.16, matching the upstream patched matrix. Native root loading alone is not an intermediate-key deny; verify the actual built proxy/gRPC binary and lifecycle. |
| C09 | Atlas native CLI, iOS, Android, authentication and WebSocket clients | Shared Rust reqwest/rustls and tokio-tungstenite/webpki | Patched lock versions selected, not runtime-qualified. HTTP and WebSocket verifiers both need controls. |
| C10 | SwifterPM: registry/manifests/artifact downloads and authentication | Foundation plus delegated SwiftPM/Git | Pending. Standalone package does not automatically inherit CLI networking changes. |
| C11 | Grafana datasource backend | Go HTTP client | Qualified compiler pinned, not rebuilt/released runtime proof. Verify proxy/custom transport settings and actual backend binary. |
| C12 | GitHub Actions: install, cache volume, Xcode/module/Gradle cache; Buildkite/GitLab equivalents | CLI/runner helpers, shell curl, actions runtime and downloaded executables | Pending. Trace each entrypoint to its actual downloader/credential transport; Node/curl trust and SDK helper releases are independent. |
| C13 | Runner pollers, cache-volume helpers, host bootstrap/sensors/log shipper, MDM enroller | Go plus subprocesses/vendor SDKs | Compiler minimum enforced in source; see owner rollout runbook. Inspect custom TLS overrides, subprocess stores and exact published/running artifacts. |
| C14 | Kura and other Rust services acting as outbound clients | Rust HTTP/gRPC/object-store TLS | Keep under service-owner qualification as well as server-side checks. Host bundle removal alone does not qualify embedded/native verifier behavior. |
| C15 | Browser/web clients, OAuth system browsers, third-party Bazel/SwiftPM/Git/Xcode/CI executors | External OS/browser/tool trust | Cannot patch through application JavaScript or assume SDK coverage. Record supported patched runtime/tool floors and test real executors. Signed artifact verification is a separate defense; attacker-replaceable checksums are not authentication. |
| C16 | Private `cli/TuistCacheEE` submodule and separately distributed code outside this checkout | Not available in the active worktree | Pinned-source review through GitHub is available at `1812b3e39fedf43813884bfd54f1a9f48fb0113b`; local submodule intentionally remains uninitialized. Modern binary storage imports `TuistREAPI`; legacy remote storage has its own session injection. Artifact-signing middleware is not TLS protection. Legacy downloader defaults to `.tuistShared`; modern binary storage imports `TuistREAPI`. Remaining pinned-source tracing/build qualification is open. |

## Completion and release rules

- Restrict a valid chain further; never replace normal verification with an
  accept-all/custom callback. Keep hostname, expiry, signature, key usage and
  unknown-critical-extension rejection. Preserve unrelated enterprise/private CAs.
- Deny keys, not certificate subjects or only one certificate fingerprint. Apply
  the 12-key SPKI policy to intermediates as well as trust anchors. Avoid globally
  modifying a customer's trust store or requiring a local repository policy file.
- Exercise auth/refresh, redirects, proxy connections, downloads and separately
  constructed clients. No TLS-failure fallback to plaintext or weaker transport.
- Blocked connections must not disclose tokens, bodies or credentials in errors.
  A blocked-key alert is useful evidence; an arbitrary TLS failure is not proof of
  MITM, and a successful connection is not historical proof of no compromise.
- Keep independent package release boundaries. A source commit is not protection
  for already installed clients, long-lived CAS proxies, or customer JVMs/devices.
- Avoid certificate pinning without a separately reviewed rotation/recovery plan.
  Known-compromised-key rejection is not equivalent to leaf-certificate pinning.
