# eMudhra remediation handoff

Recorded **2026-10-21**, updated after staging application qualification. This
is not complete fleet remediation. See the
[warm-rollout runbook](README.md). **Do not merge the aggregate change as one
fleet rollout.** Main path filters fan out to independent deployment owners.

## Current implementation

- No Python tooling or tests. The 2,053-line Python image-inspection/overlay/
  publication framework and its manifest/lock files were removed, not ported.
  There is no custom vendor-image publisher, registry login or package-write job.
- Retain the 12-key SPKI policy, portable PEM checks, a build-only public Java
  cacerts filter, native control fixtures, Go verifier/tests and isolated ExUnit.
- Go tests check policy DER evidence, OTP deny-list equality and qualified SDK
  pins across the repository, workflow literals and go-version-file inputs,
  including the generated Grafana harness's supported Compose override.
- Keep first-party build-context/caller/release-input fixes, prior Go runtime
  compatibility defaults, Darwin's explicit filtered OTP root cache, and Packer
  native negative/positive controls.
- Management Tailscale and HCCM replacement guards now use shell/kubectl/jq.
  Image pins are not blindly reverted, which could downgrade an already patched
  deployment. A differing serving image still requires explicit qualification.

**Staging application images were built, published and deployed.** No active
jobs were manually killed, Kubernetes Secrets read locally, elevation approved,
admin kubeconfig retrieved or developer-host trust settings changed. Bounded
checks ran inside the deployed staging server container.

## Verified staging application rollout

[Deployment run 39620482312](https://github.com/tuist/tuist/actions/runs/39620482312)
successfully deployed `1f29911425` as `sha-1f29911425d1`. Server, processor,
registry sync, Registry and Codebase Search reached full Ready replicas with
zero restarts; migrations and workflow smoke tests passed. Public readiness,
homepage and Registry checks, plus the allowed Codebase Search client check,
returned HTTP 200.

The running server container's OS bundle passed all 12 SPKI checks, rejected the
AAA-issued negative control and accepted the ISRG R11 positive control. A fresh
OTP process in that deployed image passed the same policy and verified HTTPS to
Let's Encrypt and GitHub. Distribution is intentionally disabled for this
single-replica server, so this was `eval`, not inspection of the running BEAM's
existing CA cache. Root removal is containment, not a compiled intermediate-key
verifier patch.

Platform, observability and Tailscale installs were skipped. Kura, CAPI,
runners-controller/cache agent, egress agent, Linux runner and xcresult versions
were explicitly pinned. Normal workflow resolution advanced macOS runner pins
to released `0.43.1`; warm floors were unchanged and observed 26.5/26.6 runners
were Ready and polling. Those guests are not fresh builds of this mitigation.
The independent `kura-spec98` experiments were not mutated by this session.

One registry-sync startup telemetry error was observed:
`Finch.get_pool_status(Tuist.Finch, nil)` raises `function_clause`. The worker
remains Ready with zero restarts; its metrics plugin and Finch dependencies
are unchanged from the previous staging deployment. Do not describe this as an
all-error-free run.

Follow-up CI fixes align Grafana's Go lock metadata with 1.26.10 and check that
alignment in the policy suite, apply the reported certifi/runtime formatting,
and use the larger runner for Linux image validation after a lost-runner failure.
The PR contains a scoped staging-test admonition. Canary/production and the
remaining host/guest/vendor paths are not qualified by that note.

## Cache-volume HTTPS follow-up

The independently shipped `tuist-cache-volume` helper now applies the twelve-key
policy to HTTPS acquire, checkout and export using its original default/proxy
transport semantics. Real DER, accepted leaf/intermediate/root denies across all
three request paths, both HTTPS CONNECT legs, configured TLS 1.2/1.3 wire
resumption, ordinary validation, no redirects and unchanged cold/grant behavior
pass in host race tests. Shared policy/factory/fixture guards and CI cover it.
The managed Helm endpoint remains in-cluster plaintext HTTP, so this is HTTPS
configuration coverage, not a TLS conversion or production handshake receipt.
macOS's local mailbox path is unchanged. See `RUNNER-CLIENTS.md`; image/runtime,
publication/replacement and the remaining GitLab/host/Kura clients stay separate.

## Client-verifier follow-up

The client-by-client scope and remaining gaps are tracked in `CLIENTS.md`.
Cloudflare's [incident response](https://blog.cloudflare.com/emudhra-certificate-compromise/)
and the linked upstream matrix reinforce that SDK, OS, browser, curl and actual
application verification paths must be assessed separately.

- `tuist_ex` now embeds the 12-key policy for both `:httpc` and gRPC/Mint. It
  filters anchors locally and rejects blocked intermediate/peer keys without
  modifying the host application's CA cache. On OTP 29.0.3 / Elixir 1.20.2,
  45 focused tests pass with the cold compile fixture explicitly excluded after
  timeout failures. Real local OTP/Mint HTTP/2 TLS preserves a private CA and
  rejects unknown CAs/wrong hostnames. All twelve public negative hosts reject
  through actual `HTTP.request` and Mint HTTP/1 TLS; sampled upload/download
  calls reject too, while unrelated HTTP and HTTP/2 positives pass. The public
  negative hosts do not negotiate HTTP/2, so those checks do not prove gRPC
  behavior by themselves. Compile, format, Hex build and docs passed; no Hex
  package was published.
- Current-host default Foundation rejects all twelve public controls. However,
  the actual custom-CA delegate source accepted some controls when their roots
  were supplied as additional anchors. `TLSValidator` now filters those anchors
  and checks the verified chain's DER SPKI hashes after normal evaluation.
  Ten focused Xcode tests pass, including all twelve policy certificates,
  malformed DER and preserved private-CA/hostname behavior. Repeating the live
  delegate test rejects all twelve controls and accepts unrelated HTTPS. The
  delegate reports rejected challenges as cancellation (`NSURLErrorCancelled`),
  not the default session's certificate-untrusted error. This is scoped source
  and current-macOS evidence, not a released client or Linux/iOS qualification.

- Android embeds the policy in authenticated/plain clients and the separate
  singleton image loader, with service-loader network fallback disabled. Original
  socket/engine checks precede the deny over the native complete path; reflective
  methods are kept by R8 and the API-28 method is guarded for minSdk 26. All 58
  unit tests pass, including 18 policy cases across Robolectric 26/28/35. Debug
  APK/native-test APK and release R8 compilation pass. Six real API 35 arm64
  emulator tests pass: constructed anchors, root/leaf denies through private
  `TrustManagerImpl` and default NSC `RootTrustManager`, hostname, unknown CA,
  expiry, bad signature, twelve public negatives and unrelated HTTPS.
  Native reference TLS already rejects all twelve public controls, so those
  negatives alone do not prove our deny; injected-key cases do. The API generator
  empty-enum build failure was fixed without wire-value changes. API26/28 devices,
  physical devices, per-domain NSC, CT-enabled/target changes and signed release
  artifacts remain open; browser OAuth and installed clients are separate gates.
- Gradle now applies a per-client `X509ExtendedTrustManager` to both OkHttp and
  HTTPS URL connections. It retains the original validator and socket/engine
  context, rejects the twelve keys, and performs additional validation against
  filtered anchors. It never changes JVM-global trust defaults. An additional PKIX checker covers built/AIA/cached intermediates, not only
  certificates supplied by the peer. Twenty-three focused tests pass, including
  all eight real intermediate paths, preserved private CAs and rejected hostname,
  expired-certificate and unknown-CA cases. Both actual transports in the shaded
  candidate JAR reject all twelve public controls and accept unrelated HTTPS
  on JDK 21.0.2. Candidate JAR SHA-256:
  `75d86bb3106f9f054954e700c5c64a0a775a20c8a5ba721b9cd7c660df1a1b66`.
  This is not a published plugin or qualification of every JVM/provider.

- The subsequent Swift sweep routes default/shared/configured Apple sessions and
  direct CLI/app authentication, OIDC, artifact, shard and image calls through
  the policy. Native-default cache/cookie/timeout behavior is retained for direct
  callers. Review caught that NIOSSL's Darwin default-root verifier bypasses
  legacy callbacks, so the original public-negative tests did not prove our deny
  was running. Corrected Darwin origin/proxy handling explicitly reproduces
  normal asynchronous Security.framework SSL/hostname verification and checks
  the full evaluated chain. Explicit roots on Darwin and other platforms retain
  BoringSSL verification plus the per-certificate deny. Normalized anchors come
  from the context, avoiding mismatched configuration; disabled/hostname-less
  verification is refused. Thirty-nine focused Xcode tests pass after correction,
  including production-config generated root/leaf deny regressions independent
  of platform revocation, effective-system-anchor DER compatibility, actual
  Foundation controls with affected anchors, twelve public NIOSSL controls and
  unrelated/private-CA positives and refresh/OIDC. The full CLI build passed
  after an earlier timeout. macOS and iOS Simulator app builds both passed again
  after the corrected shared helper; simulator compilation is not iOS runtime
  qualification. Subsequent actual production h2 GetCapabilities and separate-PKI
  HTTPS CONNECT fixtures pass otherwise-accepted leaf/intermediate/absent-root
  denies before metadata delivery on both legs, credential separation and restored
  positives. Six Xcode certificate tests pass including the public opt-in; see
  [Swift evidence](SWIFT-CLIENTS.md). Linux FoundationNetworking, broader streaming,
  NO_PROXY/plaintext-proxy/device flows and independent releases remain open.

- Standalone SwifterPM now embeds the twelve-key policy independently of the CLI.
  Its Apple session preserves native validation and rejects keys over the full
  constructed chain. Archive/metadata optimizations propagate TLS/cancellation
  rather than retrying, falling back to Git or silently ignoring registry seeding
  failures after native resolution. Ordinary unavailable metadata stays best effort,
  and failed seeding preserves the native download without publishing a cache entry.
  All 287 generated-core tests pass on Xcode 26.6 with public probes enabled,
  including actual HTTP data/download rejection of twelve hosts and unrelated
  positives. No native reference was recorded; application enforcement is proved
  only by offline accepted-root/leaf differentials through data/download/redirect
  factories. Production delegate wiring, private-CA/hostname/unknown-CA TLS checks,
  direct SecTrust expiry/signature checks and registry metadata/seeding failure
  propagation are checked too. The registry archive-download catch and full
  provider archive-to-Git failure flow retain helper-only coverage.
  Bazel builds the independent macOS candidate. Its broader current test target
  now passes 355 tests in 28 suites on Xcode 27.2 with live controls enabled.
  The same diagnostic binary crashes with the globally selected 26.6 Testing
  framework and discovers tests with matching 27.2 frameworks. Per-process
  framework/compiler selection and a test-private HOME qualify the full run;
  no global switch or source workaround was used. See [standalone qualification](SWIFTERPM-CLIENT.md).
  Linux, native SwiftPM/Git, signed CLI runtime, full archive-failure integration
  and exact published artifacts remain open. No SwifterPM release.

Candidate builds at `47d307fdde` successfully published SHA-only CAPI, egress
agent, runners-controller and cache-agent images. They were not deployed.
Both macOS runner builds (26.5/26.6) and xcresult failed closed when the guest refused the
`com.apple.trust-settings.admin` authorization database write (`-60005`); no
artifact was created. Linux image builds lost their self-hosted runner again
even on the larger shape; bind-mount tests passed but image qualification did
not. Do not treat the unexecuted native checks or lost builds as passed.
No successful macOS/xcresult candidate was produced. Those images and the
remaining client/platform rows still require separate qualification and release.

## CAS and Atlas client follow-up, 2026-10-22

CAS and Atlas Rust transports now independently embed the twelve-key policy,
filter anchors and preserve ordinary verification with the patched WebPKI path
builder. Four focused CAS tests and 38 Atlas tests pass, including real DER,
accepted-key production-builder differentials and policy-specific public controls.
Native Atlas favicon transports retain their original OS trust semantics and add
constructed-chain/anchor denial. The actual API 35 debug APK passes default-NSC
leaf/root differentials and twelve certificate-specific public negatives; two
native Apple host tests pass. Final simulator/preview builds pass. No signed
client release, iOS runtime or fleet replacement is claimed.

The CAS pruning failure was an invalid fixture: a zero-block primary made the
upstream itself exceed `total - 1`, so pruning was correct. Allocated
non-generation metadata and explicit preconditions repair the test without
changing production pruning. Full default-parallel and serial Rust 1.94.1 test
commands now complete all normal targets, each with 318 passed and 10 ignored.
The earlier publication-wait failure is not reproduced; its cause remains
unestablished, so timing stability is not proven. Only the proxy performs remote
TLS; installing a new plugin does not patch an old process. Read-only review identified indefinite
idle upgrades and old pinned CLIs that can downgrade shared machines. A qualified
paired release, machine-wide fixed CLI/artifact floor and safe per-process warm
replacement remain owner gates. The new proxy self-reports policy/PID at startup,
which is observability, not attestation. See [detailed evidence and limits](RUST-CLIENTS.md).

## Grafana client follow-up, 2026-10-22

The independent Grafana backend now embeds all twelve keys, beyond the qualified
Go SDK's eight intermediate denies. It preserves native roots and normal TLS,
then checks complete verified chains/anchors and supplied peers, including
resumption. API redirects and both legs of HTTPS CONNECT use the protected
transport; no downgrade/fallback is permitted. TLS/health errors retain useful
fixed categories without exposing URLs or response bodies. All-package race
tests, real DER, accepted-chain and redirect/proxy/resumption controls pass.
Twelve live negatives are explicitly attributed to Go's native verifier, not the
new callback; unrelated HTTPS succeeds. Local host/Linux backend builds pass,
not execution inside Grafana or publication. Signed artifacts, corporate/other
OS stores and safe owner process replacement remain open. See [evidence and
availability distinctions](GRAFANA-CLIENT.md).

## Wrappers, runner shell and Kura follow-up, 2026-10-22

The bounded install/cache action and Buildkite/GitLab wrapper audit traces their
networking to preinstalled CLI/helpers or external provider actions/executors.
Fifteen install tests and shell contracts pass with local stubs. They are not TLS
probes or qualification of separately published action tags. See
[wrapper ownership](ACTION-CLIENTS.md).

Both runner-shell-agent copies now embed the twelve-key deny for discovery HTTP
and WSS after ordinary native validation. Darwin-host race tests pass with real
DER, actual private accepted leaf/intermediate/root denies, normal trust
failures, downgrade restrictions and privacy-safe typed diagnostics. All twelve
public HTTP failures are natively attributed, not callback evidence. The Linux
source was tested on Darwin, not in a Linux image. Resumption remains disabled
by the original nil session cache. The shared guard/CI watches both copies;
no image, helper release or installed process replacement is claimed. Other
cache-volume/GitLab/host/poller/vendor transports remain open. See
[runner scope and qualification](RUNNER-CLIENTS.md).

Kura now implements the distinct reqwest 0.13 native-verifier boundary rather
than inheriting Atlas's bundled-root semantics. The independent twelve-key
policy covers Apple evaluated chains, Unix native/extra/explicit anchors,
ordinary peer validation and inbound mTLS. All audited outbound factories,
including separate auth, Sentry and blocking OTLP, use it; provider/PEM/SNI/ALPN
and rotating identity snapshots are preserved. Local macOS Bazel tests include
accepted-key differentials, actual HTTPS, h2/TLS1.2+1.3, separate-PKI HTTPS
CONNECT, peer rotation/overlap, Sentry controls and private terminal auth errors
with retained transient-EOF retry. Explicit public/PKCS1/SEC1 opt-ins pass.
The standard JUnit Python report adapter was replaced with Rust and tests rerun.
Standalone Linux CI at `2a5d5062fb` now passes 10 ordinary cases (3 ignored)
and both explicit public/PEM opt-ins, including isolated native-store failure,
override and reload controls (workflow `39911817495`). The full Linux phase at
`8cad1fb4a1` subsequently passed 1,250 library cases/52 ignored plus all other
Bazel targets and opt-ins, and assembled both build-only release images. Its
overall workflow failed in resource reporting after the first baseline run;
retry `40071266208` stopped on a cancellation-test synchronization race before
measurement. The test-only fix preserves unlink-before-release and passes fifty
repeats/full macOS suites; build-only retry `40073713999` remains pending.
Main-relative four-axis stress, final-source
runtime variants and
exact release/deployed integration remain required: this behavior change is
not complete under Kura's resource policy. No publication or rollout is claimed.
See [Kura implementation and qualification limits](KURA-CLIENTS.md).

The standalone macOS log shipper now embeds twelve-key enforcement with its
original MagicDNS/system fallback, no-proxy/timeout behavior and protected
once-owned default path. Private typed diagnostics preserve resolver kind and
dial errno without URLs or bodies; invalid receivers fail before tailing. TLS
and cancellation failures retain offsets and never become dropped-batch
`ErrRejected`. Host race and CGO-disabled live suites include native-default
Apple leaf/intermediate/absent-anchor differentials, actual private Push and
defensive configured CONNECT/resumption. The managed receiver remains plaintext
HTTP over the tailnet. Exact owner artifact/installed daemon and other C13
boundaries remain open. See [host helper evidence](HOST-CLIENTS.md).

## Validation and limits

- The standalone Go policy/store/guard suite passes with actual **Go 1.26.10**.
  Java tests use temporary public stores and a synthetic identity; guard tests
  use a fake kubectl, not live API access. The suite includes JKS and passwordless
  PKCS12 anchor preservation, hardlink refusal, desired-image/no-ack and multi-
  container guard cases. SDK lint covers repository pins, modules/workspaces and
  workflow literals/version files and is tied to the actually probed SDK.
- Go 1.26.10's qualified explicit-root verifier rejects all eight compromised
  intermediate keys and accepts the valid ISRG R11 control, including under go1.23/go1.25/go1.26 compatibility
  defaults. Genuine Go 1.25.10 and Go 1.27.1 accept a compromised intermediate.
  The 1.27.1 test was rerun with correct GOROOT, not inferred from a compile error.
  Darwin nil-root verification delegates to Security.framework and is a separate
  path; the log shipper's native-default accepted-chain differentials qualify its
  additive deny there rather than assuming the Go SDK's explicit-root behavior.
- Four isolated OTP/ExUnit tests passed on OTP 29.0.3 / Elixir 1.20.2. This is not
  fresh-VM native or effective application TLS qualification.
- Isolated kube-impersonator compilation and Linux/amd64 build passed; its
  DefaultGODEBUG matched the pre-incident module under the same patched compiler.
- Both Packer templates passed formatting and syntax-only validation. Full
  first-party Docker images and Packer VMs have not all been built here.
- The earlier Python test totals and 18/24 overlay dry-run receipts are
  historical investigation evidence only. That path has been withdrawn: those
  archives are **not supported release/deployment inputs**.

## Adversarial findings and rollout requirements

Claude's fresh no-Python review rejected the bulk rollout and the bespoke
publication framework. The no-Python findings are addressed by deletion and the
small shell/Go replacements. The publisher's missing independent appended-layer
semantic proof is no longer relevant because that publisher no longer exists.

The follow-up Claude review found no blocking code bug for commit/push. Its
requested PKCS12, SDK-lint, guard and hardlink regressions are now implemented
and passing. The review's 54-main-workflow fan-out and push-blocking access-guard
behavior are documented. Commit/push clearance is not merge/rollout clearance.

Availability findings remain **deployment constraints**, not green source-test
results:

1. Split owner releases, not merely commits in one PR. Several paths deploy to
   production directly, and the gateway's existing matrix updates environments
   in parallel. Inspect the actual trigger set before each owner merge.
2. RunnerPool idle-only replacement can remain warm: preserve active jobs, warm
   floors and caches, prefetch macOS goldens and repin one pool at a time.
3. The cache-volume agent's Local Service/DaemonSet can interrupt active clients
   during replacement. Host-binary drift pushes also need one-host qualification.
4. Kura needs version-skew/backport qualification before health-gated waves.
   Existing old pins do not follow a changed default. Preserve PVCs, pauses,
   regional health and patched rollback floors.
5. HCCM's Robot target change and singleton Recreate management Tailscale need
   separate human-qualified windows and independent access. They are not warm
   replacements, and a qualification flag does not grant JIT authorization.
6. Qualify fresh Apple/OTP VMs, actual effective verifiers, unrelated positive
   traffic, and owner-specific staged/canary behavior before production.

## Vendor and coverage residuals

Use qualified upstream releases or normal owner source rebuilds. An explicit,
owner-qualified CA mount/client setting can contain a known trust path, but is
not a bundled-verifier patch or universal SSL_CERT_FILE fix.

Outstanding classes include hcloud-csi/Reaper/scraper bootstrap and cached
pip/certifi wheels; Alloy embedded material; UBI entitlement/p11-kit stores;
Omada's encrypted vendor keystore and NSS; Selenium/browser verifiers; arbitrary
packing; mounted/private/custom roots; host/guest, management and separate-cluster
coverage. An unreadable identity is not evidence of exploitation; do not delete
it or rewrite signed resources to obtain a passing check. Do not restart
PostgreSQL/PgBouncer solely for unused public CA bundles.

Re-inventory deployed image IDs, templates and effective runtime stores before
claiming completion. Keep source, built, published, deployed and actual-verifier
states separate. Existing jobs retain exposure until they finish; shortening
that window by terminating jobs requires separate human agreement.
