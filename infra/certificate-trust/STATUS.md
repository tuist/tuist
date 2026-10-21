# eMudhra remediation handoff

Recorded **2026-10-21**. This is source work, not fleet remediation. See the
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

**No images were published or deployed by this work. No active jobs were killed,
Kubernetes Secrets read, Pods executed, elevation approved, admin kubeconfig
retrieved or developer-host trust settings changed.**

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
