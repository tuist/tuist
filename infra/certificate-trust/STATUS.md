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

- Gradle now applies a per-client `X509ExtendedTrustManager` to both OkHttp and
  HTTPS URL connections. It retains the original validator and socket/engine
  context, rejects the twelve keys, and performs additional validation against
  filtered anchors. It never changes JVM-global trust defaults. Twenty-two
  focused tests pass, including preserved private CAs and rejected hostname,
  expired-certificate and unknown-CA cases. Both actual transports in the shaded
  candidate JAR reject all twelve public controls and accept unrelated HTTPS
  on JDK 21.0.2. Candidate JAR SHA-256:
  `82415c7ac17ae7a53902eda23c6017a5103aad0d8d95f659d25d23d19b785ac2`.
  This is not a published plugin or qualification of every JVM/provider.

Candidate builds at `47d307fdde` successfully published SHA-only CAPI, egress
agent, runners-controller and cache-agent images. They were not deployed.
The fresh macOS 26.5 runner build failed closed when the guest refused the
`com.apple.trust-settings.admin` authorization database write (`-60005`); no
artifact was created. Linux image builds lost their self-hosted runner again
even on the larger shape; bind-mount tests passed but image qualification did
not. Do not treat the unexecuted native checks or lost builds as passed.
Remaining macOS/xcresult candidates and client/platform rows still require
separate qualification and release.

## Validation and limits

- The standalone Go policy/store/guard suite passes with actual **Go 1.26.10**.
  Java tests use temporary public stores and a synthetic identity; guard tests
  use a fake kubectl, not live API access. The suite includes JKS and passwordless
  PKCS12 anchor preservation, hardlink refusal, desired-image/no-ack and multi-
  container guard cases. SDK lint covers repository pins, modules/workspaces and
  workflow literals/version files and is tied to the actually probed SDK.
- Go 1.26.10 rejects all eight compromised intermediate keys and accepts the
  valid ISRG R11 control, including under go1.23/go1.25/go1.26 compatibility
  defaults. Genuine Go 1.25.10 and Go 1.27.1 accept a compromised intermediate.
  The 1.27.1 test was rerun with correct GOROOT, not inferred from a compile error.
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
