# CAS and Atlas verifier qualification, 2026-10-22

This is source and local candidate evidence, not release, deployment or complete
fleet remediation. No production client was published and no existing proxy was
restarted. The working baseline was `0a862f25b669685815841ed5f3b28e3f78a98864`.

## Implementation

CAS and Atlas auth embed byte-identical twelve-key SPKI policies independently.
Rustls 0.23.45 / WebPKI 0.103.16 preserve ordinary certificate, hostname and
handshake-signature verification. The patched path builder rejects the eight
intermediate keys; candidate-anchor filtering covers all twelve keys, including
the four roots. The additive peer-chain check also rejects accepted test keys.
Typed TLS causes are inspected without formatting credential-bearing errors.

- CAS `reapi::secure_endpoint` uses tonic's custom verifier with native roots,
  without combining it with incompatible tonic root-setting APIs. TLS failures
  are not retryable transport failures. Only the proxy performs remote TLS; the
  compiler plugin communicates over a local socket.
- Atlas auth preserves its original bundled WebPKI root semantics for both the
  single reqwest client and the explicit WSS connector. Presence reports a fixed
  `secure_connection_failed` category and stops that TLS reconnect loop.
- Atlas favicons retain OS trust, not Rust's bundled roots. Apple SecTrust and
  Android's original contextual trust manager validate normally before denying
  keys over the constructed path, including anchors. Requests are credential-free,
  bounded, cancellable and HTTPS-only on every redirect. Apple byte streaming and
  ImageIO decoding use a nonisolated helper; Android retains its bounded executor.
  Both preview targets include the new policy dependencies.
- The earlier Rust image/FFI experiment was removed because it changed native
  enterprise/OS trust semantics. Its historical image logs are superseded.

## Executed checks

Commands use explicit installed toolchains, not global toolchain/trust changes.
Local logs are under `/tmp/tuist-emudhra-audit/`.

| Check | Result and limit |
| --- | --- |
| CAS policy tests, Rust 1.94.1, `TUIST_TRUST_LIVE=1 cargo test --offline --locked --manifest-path cas-plugin/Cargo.toml --lib certificate_trust_tests -- --nocapture` | Four pass. Real twelve-key DER/anchor filtering, accepted private CA, accepted leaf/root denies, hostname/unknown-CA/expiry/signature controls. Actual tonic Capabilities loopback accepts the private CA and rejects added leaf/root denies. The twelve public negatives run through Rustls with incident roots deliberately restored and require typed policy-specific denial; unrelated HTTPS succeeds. Log: `cas-policy-formatted-final-tests.log`. |
| Atlas auth, Rust 1.96.0, `TUIST_TRUST_LIVE=1 cargo test --offline --locked --manifest-path atlas-native/auth/Cargo.toml -- --nocapture` | 38 pass. Actual production HTTP/WSS builders have accepted-key differentials. All 48 public checks (twelve hosts, two transports, default and incident-root-added roots) require policy-specific failure. Unrelated HTTPS 200. Log: `atlas-policy-formatted-final-tests.log`. |
| Native Apple policy/session host tests | Two Swift Testing tests pass on macOS using the actual new policy/session source, with `ATLAS_TRUST_LIVE=1`. Normal native validation accepts an unrelated chain; add-only leaf/root denies reject it through the actual session. Configuration and malformed DER are checked. Both native-reference and protected default sessions accept the positive. Log: `atlas-native-swift/tests-final.log`. Not iOS runtime evidence or a twelve-key native DER test. |
| Actual Atlas debug APK, native API 35 arm64 emulator | Separate Java instrumentation loads the target APK's policy, not a second compiled copy. Default NSC `android.security.net.config.RootTrustManager` accepts unrelated HTTPS; add-only accepted leaf/anchor denies fail with the application-specific cause. Twelve public controls fail for certificate reasons; redirect-factory flags are checked. `INSTRUMENTATION_CODE: -1`. Log: `atlas-native-android-final-tree-instrumentation.log`, including the installed APK hash. This does not exercise the UI redirect loop, older APIs, custom NSC/CT, R8 or a signed release. |
| Once targets | `AtlasAuthTests`, final `AtlasIOS` simulator app and corrected `AtlasSettingsAndroidPreview` build pass. Production `AtlasAndroid` debug APK builds with explicit Rust 1.96.0/Android toolchain settings. Current-source logs: `atlas-once-final-tree-auth-tests.log`, `atlas-reviewed-final-ios-build.log`, `atlas-reviewed-final-android-preview-build.log`, `atlas-android-final-tree-build.log`. The earlier auth-test/APK build logs predate the final policy-ID/graph edits and are superseded. No production-device qualification. |
| Shared Go policy/factory guards | Qualified Go 1.26.10 suite passes, including policy synchronization and native source-directory transport guards. Log: `rust-native-final-go-tests.log`. Static guards are not runtime evidence. |
| CAS release build | Local macOS plugin/proxy candidate builds with Rust 1.94.1. Log: `cas-policy-final-release-build.log`. Not published or a running-daemon test. |

The native Android harness initially completed its runtime assertions but lacked
raw instrumentation output needed by the shell's final status check. A subsequent
metadata-only attempt encountered an early-exiting grep/pipefail check. The final
script uses a metadata file and raw instrumentation output; its complete run
passes. Only the owned emulator was used and stopped; no device remains attached.
No certificate store, signed target resource or production identity was changed.

The CAS full run remains **243 passed, one failed, three ignored**, with later
integration targets not reached after the library failure. The unchanged test
`proxy::tests::a_store_past_its_limit_that_a_prune_would_not_change_is_left_alone`
also fails in isolation and from a clean `git archive` of the committed baseline,
compiled with the same Rust 1.94.1 SDK (`cas-prune-head-baseline.log`). This proves
the failure predates this diff in this environment, not its root cause or
flakiness. Do not call the full suite green or change cache/pruning behavior as a
TLS workaround. A subsequent run excluding that pruning test reached 242 passed,
one failed and three ignored, failing instead at the unchanged
`a_failed_publication_already_in_flight_ends_the_wait_as_a_failure` five-second
wait assertion (`cas-tests-known-baseline-prune-excluded.log`). That publication
test passes in isolation in both current and baseline trees; its suite failure's
cause is unestablished. Integration targets still were not reached. Both failures
remain visible rather than being called a complete suite pass.

### Recorded local candidates

These identify the specifically inspected/tested local files, not release inputs
or an assertion that every later rebuild has identical bytes:

- Native-tested Atlas debug APK SHA256:
  `f8073a4b3b1e500c0cf3a22dc9513a36550af4f1d69b43151f3b29415cce940a`, recorded by both the current-tree build and instrumentation harness before installation.
- Local CAS proxy build SHA256:
  `87ee2ce483797a747eb486cc553f0d8215750ef185bca1ef839119d8bded412b`, recorded in the build log.
- Local CAS plugin build SHA256:
  `34cd0d730fcd991f279abf1a526e97889ddfaf8940edc86ea2e3f2216f3bb3ac`, recorded in the build log.

## CAS owner replacement gate

Installing new files or a new compiler plugin does not upgrade an old daemon.
The new proxy emits its embedded policy revision and PID at startup, to stderr
and the configured diagnostic log. This is an observation, not cryptographic
attestation; establish that the corresponding process and qualified artifact
are still running. There was no live daemon replacement in this qualification.

1. Release and qualify the paired CLI/plugin/proxy artifacts independently.
   Record the actual fixed release/digest floor, not merely a newer-looking tag.
2. Enforce that floor across **every project, pinned CLI and override on the
   machine**. An older CLI's `tuist setup cache` can overwrite the plugin/plist
   and reinstall an unprotected proxy. A fence implemented only in new code
   cannot stop that old installer.
3. Stable-era proxies (4.213.0 and earlier) lack idle self-upgrade and need new-CLI
   setup at an owner-approved safe point. Managed idle upgrades first appeared
   in 4.214.0-canary.46. Their selected target must advance and all pools drain
   after 30 seconds without requests; a busy machine has **no replacement
   deadline**. Setup/override paths can boot out a process, so do not run them
   blindly during jobs.
4. Verify each running replacement's identity, policy, TLS controls and warm
   health before considering it remediated. Preserve local stores, publications,
   cache spools and active jobs; retain an independently qualified patched
   rollback. Never clear caches or force restarts just to obtain a policy marker.
5. Do not bump the socket protocol as a pretend trust fence: an old proxy can
   continue its own snapshot, publication and refresh traffic even when new
   plugin requests become misses.

Read-only Claude review confirmed the source TLS design and identified the
preview dependency, narrower static guards and evidence weaknesses addressed
above. Final read-only review found no source blockers; its stale-log/artifact
provenance findings were addressed with current-source reruns, logged artifact
hashes, and a policy-ID synchronization assertion. It also identified the old-CLI downgrade and indefinite-idle lifecycle
constraints. Review is not release or fleet clearance.

## Remaining gates

Exact released artifacts/platforms, real CAS proxy lifecycle, full origin/proxy
wire flows, iOS native execution and all twelve native Apple policy DER checks,
older Android APIs, custom NSC/CT and minification remain open. Native trust and
bundled WebPKI trust must stay independent. Atlas's navigation CLI has no auth
crate dependency; any browser it opens belongs to the separate external-runtime
floor in C15. Other inventory rows, including Linux Foundation, Go helpers,
Grafana, Kura and proprietary/delegated runtimes, are not closed by these builds.
