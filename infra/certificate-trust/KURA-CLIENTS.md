# Kura native and explicit-anchor certificate trust

Implementation and local qualification, **2026-10-22**. Kura now independently embeds the twelve-key `emudhra-2026-10-19-v2` policy in its native and explicit-anchor verifiers. This is source, macOS-host and standalone Linux CI evidence, not a release-image qualification, resource-budget clearance or a rollout. Container PEM containment alone does not close this row.

## Locked verifier and production paths

Kura's locks resolve reqwest **0.13.2**, rustls **0.23.46**, rustls-webpki **0.103.16**, rustls-platform-verifier **0.6.2**, rustls-native-certs **0.8.3**, security-framework **3.7.0** and tonic **0.14.5**. Do not substitute the locally cached platform-verifier 0.7.x source when reviewing the locked backend. Kura installs AWS-LC; reqwest otherwise prefers the installed process provider before its own AWS-LC default.

Unlike Atlas's reqwest 0.12 setup, reqwest 0.13's normal `rustls` path uses the platform verifier, including when extra roots are added. `tls_certs_only` instead constructs WebPKI over explicit anchors. Reusing Atlas's bundled-root config would change Kura's native/enterprise trust semantics. Kura publishes macOS binaries as well as Linux artifacts, so macOS cannot be silently excluded.

Production constructors protected together:

- `auth/tuist.rs`: the separately constructed token introspection/cache-access client.
- `control_plane_http.rs`: control-plane, heartbeat, usage, analytics, analytics-forwarder and Bazel test-artifact clients.
- `enrollment.rs` and `registration.rs`: separately built enrollment/registration clients, including enrollment's client secret.
- `reapi/asset/http.rs`: Remote Asset origin downloader. Preserve the validating resolver, IP-literal and redirect checks, origin-header stripping, no-proxy policy, pool/read/time bounds, drain cancellation and publication rules in its leaf `AGENTS.md`.
- `telemetry.rs`: blocking OTLP HTTP client and Sentry's SDK-internal reqwest transport. Supplying a protected OTLP client does not protect Sentry's independently constructed client.
- `serving_authority.rs`: Kubernetes client with the service-account CA added to native roots. Preserve HTTPS-only, no-proxy, redirect rejection and short timeout.
- `peer_tls.rs`: explicit-anchor mTLS client, per-build identity snapshot, rotation, topology routing, resolving and download idle-time settings. Its inbound client-authentication verifier is a separate internal-plane owner boundary, also requiring the twelve-key audit.

Current OTLP gRPC does not enable the exporter's TLS features: an HTTPS endpoint fails construction, not a protected TLS handshake. Enabling TLS later requires an explicit protected channel and tests; do not add plaintext fallback or treat plaintext export as TLS qualification. Distinguish production constructors from `#[cfg(test)]` helpers.

## Native verifier implementation and retained contracts

A wrapper around `rustls_platform_verifier::Verifier` cannot inspect its private anchor store or the evaluated native chain: `verify_server_cert` returns only `ServerCertVerified`. Checking only supplied peers leaves absent anchors and native cached/AIA intermediates uncovered.

- **Linux:** reproduce the locked platform backend's native-store/extra-root behavior, including strict extra-root parsing, native-store warning behavior, empty-store failure and per-build root loading. Filter all twelve blocked candidate-anchor keys, preserve the provider and normal WebPKI validation, and restrict supplied peers. The pinned WebPKI path builder denies the eight intermediate keys. Do not switch to bundled roots or change `SSL_CERT_FILE`/`SSL_CERT_DIR` semantics.
- **macOS:** preserve native SSL/hostname policy, verify date, stapled OCSP and extra anchors alongside system roots, then check the complete successfully evaluated SecTrust chain. Retain native validation and provider signature verification. A second peer-only wrapper is not sufficient.
- **Explicit peer anchors:** a private-CA deployment assumption is not enforcement. A configured CA can contain a blocked root key, and a privately signed peer can reuse a blocked public key. Filter all twelve candidate-anchor keys and restrict peer keys while preserving the ordinary verifier. Do not exempt this branch merely because WebPKI blocks the eight intermediates.
- **Identity/rotation:** reqwest's preconfigured-TLS route skips its identity, roots, SNI, protocol-version and ALPN setup. Reproduce those settings deliberately. Preserve PEM parsing parity (certificate order, accepted PKCS#8/PKCS#1/SEC1 sections, last-key behavior and rejection of unsupported sections) and `with_client_auth_cert` validation. Keep per-build identity reload, overlap CA bundles and failure ordering. Do not inadvertently send the peer identity to public origin/control-plane clients.
- **Sentry:** a custom transport must use the protected client without enabling invalid-certificate options, dropping existing proxy behavior or printing DSN credentials. An SDK-owned default client is not covered by another factory.
- **Origin construction/availability:** Remote Asset currently constructs its client through `Default` with `.expect(...)`; preserve or deliberately change and test its build-failure behavior. Customer-chosen origins are especially sensitive to a conservative supplied-peer deny: a redundant blocked cross-sign can cause rejection even when another valid path exists. Document that availability distinction and repair served chains, never disable verification or select weaker fallbacks.

`src/certificate_trust.rs` implements Unix native-store/explicit-anchor filtering, ordinary verification plus restrictive peer checks, independent client-authentication verification, immutable policies, provider/config/PEM parity and bounded typed failure classification. `certificate_trust_apple.rs` reproduces the locked native SSL/hostname/date/OCSP/extra-plus-system contract and inspects the complete successfully evaluated chain. Its count/index APIs preserve macOS 11 compatibility; no macOS 12-only chain symbol is introduced. `ApplicationVerificationFailure` identifies the additive key policy. Filtered-anchor failures can instead surface as ordinary certificate-validation errors and must not be mislabelled as callback evidence.

Auth diagnostics use fixed transport categories, not formatted credential-bearing error URLs; tracing records the hostname rather than the complete base URL. Typed TLS failures are terminal, including typed protocol corruption, while the pre-existing single retry for untyped handshake EOF/reset remains. Overdeep cause chains conservatively stop retries but retain an unknown classification. The retry guard is named `terminal_transport_failure`, explicitly distinguishing that conservative bound from identified TLS errors. Remote Asset keeps its existing typed certificate-failure mapping after private-address checks and does not alter SSRF, redirects, budgets, cancellation or publication.

## Local qualification

The exact commands and raw output are retained under `/tmp/tuist-emudhra-audit/kura-trust-*`. Bazel 9.1.1 uses the repository Rust 1.94.1 toolchain on an Apple-silicon **macOS 27.0** host. The native Apple tests execute SecTrust; they are not a Linux or macOS 11 runtime receipt.

```sh
cd kura
bazel test //... --define=kura_deny_warnings=true --jobs=6 \
  --nocache_test_results --test_output=all
bazel build //... --aspects=@rules_rust//rust:defs.bzl%rust_clippy_aspect \
  --output_groups=clippy_checks --jobs=6
bazel build //... --aspects=@rules_rust//rust:defs.bzl%rustfmt_aspect \
  --output_groups=rustfmt_checks --jobs=6
bazel test //:certificate_trust_test --define=kura_deny_warnings=true \
  --nocache_test_results --test_arg=--ignored \
  --test_env=TUIST_TRUST_LIVE=1 \
  --test_env=KURA_TRUST_OPENSSL=/opt/homebrew/opt/openssl@3/bin/openssl \
  --test_output=all
```

The clean committed-source rerun at **`d6096523f2e900dba9ce57ca7d2e49b526e001d6`** passes **1,246 library cases with 51 ignored**, **10 independent trust cases with 2 ignored**, and **3 Rust reporter cases**; the main-binary unit target has zero cases. All four public Bazel test targets pass. The library takes **10.639s**. Both ignored independent cases then execute separately and pass in **3.353s**, with ten ordinary cases filtered out. The receipt includes the source SHA and empty worktree status: `/tmp/tuist-emudhra-audit/kura-trust-committed-tests.log`.

After the internal retry-guard naming clarification, the clean committed **`b94bb9bd2fe504834533f086ad36f20d687581ab`** repeats all four targets with identical case/ignore counts (library **10.210s**) and both opt-ins (**3.094s**), then passes full Clippy and rustfmt aspects. Receipt: `/tmp/tuist-emudhra-audit/kura-trust-clarified-committed-tests.log`.

Clippy over `//...`, the full Bazel rustfmt aspect, the shared Go policy suite (**45.700s**) and scoped certificate-workflow actionlint also pass locally. The PR remains open and its last inspected current-head check rollup is empty; these receipts are not current-head CI.

The independent target avoids RocksDB. Default cases cover real twelve-key DER and malformed input; otherwise accepted native/explicit private leaf, intermediate and absent-root denial; direct Apple evaluated-chain enforcement with an intentionally unfiltered test anchor; ordinary hostname/expiry/signature/usage/critical-extension/unknown-CA checks; mandatory inbound client authentication; identity parsing/config parity; typed private diagnostics; actual HTTPS denial before request delivery; h2 over TLS 1.2 and 1.3; and HTTPS CONNECT with separate proxy/target PKIs and per-leg credential isolation.

Library integration additionally exercises actual peer identity rotation with an overlap CA bundle and immutable old-client snapshots; Sentry's post-default proxy settings and refusal to honor the invalid-certificate option; and real auth certificate rejection before credentials, without retries or URL leakage, while transient handshake EOF still retries once. These are local fixture tests, not enrollment/production CA rotation or a real Sentry/OTLP collector deployment.

The two **explicitly ignored** opt-in cases were separately executed: twelve public certificate-specific failures plus unrelated HTTPS 200, and valid PKCS#1/SEC1 identity validation against original reqwest using an **existing OpenSSL 3** solely to create isolated synthetic fixture keys. No host trust change, package installation or compromised private key is involved. Public negatives can be rejected by the native verifier before the additive callback; the accepted private-key differentials establish application enforcement instead.

The existing Kura JUnit adapter used Python. Commit `66df472e87` replaces its report writer with Rust, preserving public case identity/counts/durations/ignored/failure output and nonzero exits. Three reporter unit cases and an exit-7 shell contract pass. Trust tests were rerun through the Rust reporter; earlier Python-wrapper runs are not the no-Python qualification receipt. `--test_filter` is not translated by this wrapper; use `--test_arg` for libtest filters. Earlier apparent filtered runs actually ran the complete library target.

The shared Go suite checks all twelve hashes, the policy marker, real fixture equality, locked verifier versions and a bounded constructor/backend/alternative-stack inventory, including code after named test modules. It is not an arbitrary Rust alias/macro/data-flow proof. The normal Kura Bazel pipeline includes these targets; a source guard or a local pass is not current-head Linux CI evidence.

## Standalone Linux CI qualification

Read-only [workflow 39911817495](https://github.com/tuist/tuist/actions/runs/39911817495) succeeded at `2a5d5062fb3acb6c341a0d15dbe6ab2709c0429e` on GitHub-hosted Linux amd64 (Ubuntu kernel 6.17.0-1022-azure), Bazel 9.1.1/Rust 1.94.1. The independent target passed **10 cases, 3 ignored** in **0.174 s**. Both explicit public/PKCS#1/SEC1 opt-ins separately passed; the public case took **6.455 s**. Twelve public negatives required typed certificate failures, and unrelated HTTPS succeeded. Accepted synthetic leaf/intermediate/absent-root controls establish the additive deny separately.

The Linux-only parent test launches an owned child with isolated `SSL_CERT_FILE`/`SSL_CERT_DIR`. It exercises native-file override, all-blocked anchors, malformed/missing stores, strict extra roots, valid extra roots despite native-store errors and fresh-file reload. No shared environment or host trust is mutated. Raw source/platform/JUnit/log receipts are in `/tmp/tuist-emudhra-audit/kura-linux-native-39911817495/`.

The runtime workflow's explicit `qualification_only=true` branch now builds the main merge-base and candidate with identical release assembly, runs the complete Linux suite, and collects ABBA private-peer resource evidence. It has no registry login, publication or deployment. Its source path and measurements are not yet a passing resource/release receipt. The improved fixture uses distinct incompressible objects, full mTLS churn and post-load retention/recovery; it does not measure native-client construction cost or deployed telemetry/auth integrations.

## Full Linux build-only phase

[Workflow 39918861598](https://github.com/tuist/tuist/actions/runs/39918861598)
at `8cad1fb4a1` passed the complete warnings-denied Linux suite: **1,250 library
cases, 52 ignored (31.194 s)**, **10 independent cases, 3 ignored**, **3 reporter
cases** and **1 main-binary case**. Both explicit opt-ins passed (4.605 s).
The improved child-store test checks old-client snapshots and exactly one child
case. Both baseline/candidate binaries and pinned-runtime release images built,
ran `--version`, and had equal non-binary layers. These were build-only inputs,
not published artifacts. Public metadata/JUnit receipts were downloaded to
`/tmp/tuist-emudhra-audit/kura-resource-second-39918861598/`.

The overall workflow **failed** after the first baseline workload because the
summarizer did not recognize a legitimately empty lazy pressure counter.
The next run (`39922891645`, source `406514e1c2`) similarly stopped on initial
artifact egress, not a completed comparison. The source-qualified lazy schema
now includes pressure transitions, artifact egress and segment refresh only;
unknown metrics still refuse. Successful work/actual egress must match across
runs. Convergence retries are now measured cost, not an outcome equality filter.
Fourteen contracts pass, and the captured real baseline samples were
used for a separate derived parser regression, without editing raw receipts or
claiming resource clearance. Retry `40071266208` at `a9d2a42980` stopped before
resource measurement on `utils::tests::read_request_to_temp_cleans_up_when_cancelled`
(1,249 passed, one failed, 52 ignored): the file was unlinked but its five-byte
reservation had not yet been dropped. Production deliberately unlinks before
releasing admission. The test now signals that staging reached its pending read,
checks a real file/five-byte reservation, drops the future and waits through the
budget notification path for a full-capacity reservation before asserting unlink
and final zero. No production cleanup or admission limit changed. Fifty repeated
cases, all four macOS Bazel targets (1,246 library cases/51 ignored, 11.762 s),
Clippy and rustfmt passed. Build-only retry `40073713999` at `fe4c162fed` then
passed the complete Linux suite (1,250 library/52 ignored, 22.777 s), both release
assemblies and all four workloads/retention/recovery checks. Its final comparison
failed because expected convergence retries were incorrectly treated as unequal
successful work. Corrected derived analysis preserves the original failed receipt
and finds **+7.576 MiB/+3.325% peak anonymous memory**, beyond the 2.551 MiB
baseline spread. Its cause remains unestablished; no budget approval follows.
See the [resource receipt](KURA-RESOURCE.md) for exact identities, all four axes,
observer-cost limits and run `40078717301` (three complete blocks, pending).

## Remaining gates

- Supported distro/runtime variants and fresh final-source evidence remain distinct from the full Linux result above.
- Sustained before/after stress against the main merge base on **memory/headroom, disk/retention, CPU/work and egress/work**, including post-load recovery. The private-peer measurements above are not budget clearance: the anonymous-memory delta needs investigation, native-client construction cost remains unmeasured, and exact/deployed paths remain separate. This behavior change remains incomplete under Kura's four-axis policy.
- Exact Linux release images, macOS release binaries and minimum-supported-runtime qualification, plus deployed Sentry/OTLP/enrollment/Kubernetes integration where applicable. OTLP gRPC TLS remains unavailable, not silently protected or downgraded.
- Owner-authorized publication, installed runtime floors, version-skew/backport qualification and health-gated replacement preserving instance pins, warm caches, pauses, access and patched rollback. No release, deployment or replacement is authorized by this receipt.

Read-only adversarial review checked the locked native backend, all production factories, explicit peer roots, config/PEM/rotation parity, alternatives to the factory, auth retries and privacy. Receipts are under `/tmp/tuist-emudhra-audit/claude-kura-*`; the reviewer did not edit, build, test or call live services. Review is not release or rollout clearance.
