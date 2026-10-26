# Certificate trust and warm rollout

The October 2026 eMudhra incident requires both trust-store containment and
patched verification libraries. This directory deliberately contains **small
Go/shell checks**, not a third-party image manufacturing or publication system.
See [the dated handoff](STATUS.md) for scope and unresolved qualification.

## Checks

- `policy.json`: four root keys and eight compromised intermediate keys, with
  complete DER SPKI evidence and provenance. Match key identity, not names.
- `pem-store.sh check FILE...`: fail on blocked or unreadable certificates.
  `filter SOURCE DESTINATION` retains unrelated roots and refuses an empty
  result, private keys and blocked TRUSTED CERTIFICATE AUX records. It never
  installs system trust itself. `extract-blocked SOURCE DIRECTORY` exports
  matching public certificates for the Packer guest's native deny settings.
- `java-store.sh check|filter PUBLIC_CACERTS`: build-time checks for public SDK
  stores using the standard `changeit` password. It refuses private/unsupported
  entries, exports each candidate with keytool, deletes only blocked public CA
  aliases in a staged copy, and verifies the final PEM export. Keytool retains
  its store format. This is **not** a general private-keystore migration tool.
- `verify-go.go`: all eight cryptographically valid negative intermediate-key
  controls and an unrelated valid ISRG R11 chain, using explicit roots so OS
  containment cannot mask a missing verifier deny. The compiled runtime version
  must match `TRUST_EXPECTED_GO_SDK` when supplied. Go tests also validate the
  policy evidence, OTP deny-list equality, SDK pins and shell safeguards.
- `guard.sh`: read-only comparison of serving and proposed management Tailscale
  or HCCM images. Replacements need explicit human qualification; permission or
  parse failures stop the workflow. This never obtains access or approves JIT.

No Python is used by this tooling, its tests or its workflow. Python installed
for customer jobs in the final Linux runner remains a product toolchain.

## Local validation

Use the behaviorally qualified SDK, not merely a numerically greater version:

```bash
cd infra/certificate-trust
# Remove a stale GOROOT inherited from another SDK in these child processes.
env -u GOROOT GOWORK=off GOTOOLCHAIN=go1.26.10 \
  TRUST_EXPECTED_GO_SDK=go1.26.10 go test -count=1 ./...
env -u GOROOT GOWORK=off GOTOOLCHAIN=go1.26.10 \
  TRUST_EXPECTED_GO_SDK=go1.26.10 go run .
bash -n pem-store.sh
bash -n java-store.sh
bash -n guard.sh
```

Tests require OpenSSL, keytool, jq, bash and realpath. They use temporary public
stores and a fake kubectl, never live cluster access. The CI workflow has only
`contents: read`: no registry login, candidate matrix, publication or deployment.
It also runs the isolated ExUnit tests without booting the server or databases.
The explicit SDK allowlist fails on unqualified/floating pins; qualify new SDKs
and update CI and the allowlist together. Actual Go 1.27.1 accepts a compromised
intermediate despite its greater version number.

Native/OTP VM qualification and production application smoke tests remain
separate from these source checks. Never run Packer guest commands on the host.

## Build wiring

Root-context Dockerfiles have a scratch fallback containing the shared PEM
checker and policy. Narrow contexts use the named `certificate-trust` context:

```bash
docker build -f Dockerfile.release \
  --build-context certificate-trust=../infra/certificate-trust .
```

Keep CI, Compose, preview, E2E, local Helm and Once callers aligned. Android's
build-only JVM stage additionally copies `java-store.sh`; the final runner stays
JDK-free. Release detection watches actual policy/checker/control inputs, not
runbook-only changes.

## Do not merge this as one fleet rollout

The fresh adversarial review found that the aggregate changed paths can trigger
54 main-push workflows in the reviewed snapshot, including several production-only deploys and a
parallel staging/canary/production kubectl-gateway update. A source merge is an
operational event even when this directory's own workflow is test-only.

Prepare separate owner-scoped PRs and inspect each one's actual push triggers
before merging. This document does not create PRs or authorize live changes.

1. **Policy/checks only:** this directory and its test workflow. No deployment
   should be triggered; verify that from the complete proposed file set.
2. **Elixir services:** use the server canary, acceptance and production cascade.
   Slack, tuist-ops, Atlas, registry and other independent owners need their own
   sequencing and traffic smoke; do not assume the server gate covers them.
3. **Go controllers:** release separately from runners, access and rack changes.
   A runners-controller release also rolls the cache-volume agent. Its Local
   Service/DaemonSet currently has `maxUnavailable: 1`, `maxSurge: 0`, so active
   clients on that node can lose the agent during replacement. That step is not
   fully warm and needs an independently qualified low-traffic window.
4. **kubectl gateway alone:** staging first through its actual dispatch path,
   then explicitly canary and production. Confirm access through the gateway
   and an independent path. Its existing all-environment push matrix is not an
   ordered rollout. Check built `go version -m` metadata in isolated module mode;
   root-workspace and production compatibility defaults differ.
5. **Linux/macOS runner images:** let RunnerPool idle-only replacement work.
   Claimed/running Pods finish; preserve `minWarmPoolFloor` and
   `rollout.maxConcurrentPercent`. Never delete active Pods to accelerate it.
   Prefetch macOS goldens before repinning one pool at a time, preserve host
   cache masters and check disk headroom, including the 30% floor.
6. **Kura separately:** qualify the version jump first. The original audit found
   150/184 production instances pinned to 0.58.0-canary.13, not simply following
   defaults. Current compatibility promises only one release of skew. Inspect
   fleet version distribution and pauses; use a qualified backport or upgrade,
   then Tuist-account wave zero, paced production health gates and soak. Staging
   and canary expedited fan-out is not evidence for a paced production wave.
   Preserve PVCs/node-local PVs and regional availability; do not evacuate data.
7. **macOS/xcresult qualification:** build fresh guests, require native negative
   and positive controls and effective filtered OTP cache/boot. Qualify one
   staging Mac before prefetch/pool changes. CAPI host-binary drift pushes are a
   separate release: first establish what happens to running VMs, then one host
   at a time. Do not restart all host agents alongside guest image replacement.

### Access and cloud-controller exceptions

HCCM's Robot InternalIP target change and singleton management Tailscale's
Recreate update are **not warm replacements**. Keep them out of ordinary image
waves. Their source pins are not blindly reverted: doing so could downgrade an
already patched deployment. The shell guards block an unqualified difference. While the serving image differs
from the source pin, this blocks **every main-push run** of those workflows,
including unrelated configuration changes, until a qualified dispatch reconciles
it. Once the images match, ordinary pushes need no replacement acknowledgement.

Use a separate human-qualified window, a verified independent management route,
Robot load-balancer target checks, explicit single-environment dispatch and a
staged patched rollback. Acknowledgements do not supply or approve JIT elevation.
Never fetch an admin kubeconfig or approve an agent's own elevation.

## Third-party components

Use each owner's normal upstream release/value pins or a parity-reviewed source
rebuild. Never label a vendor verifier patched solely because its CA bundle
changed or a Go version string appears newer. Inspect immutable candidate bytes
read-only; do not execute the image or extract its rootfs to the host. Exporting
one explicitly known public bundle to stdout for `pem-store.sh check` is not an
exhaustive verifier audit. Go build metadata identifies a compiler, not actual
client behavior; run negative and unrelated positive controls for the client.

An owner-qualified ConfigMap bundle mount or client-specific CA setting can be
an interim containment path where the client actually uses it (for example,
Barman's `AWS_CA_BUNDLE`). Render the real bundle path, permission/mount behavior
and every sidecar, then roll through staging/canary. Such a mount does **not**
cover an embedded root set, NSS/browser database, bootstrap wheel, regenerated
bundle, private store or explicit client override. Do not add unqualified mounts
or assume all runtimes honor `SSL_CERT_FILE`.

Residuals include Alloy embedded material; UBI entitlement/p11-kit stores;
Omada's encrypted vendor keystore and NSS; Selenium/browser paths; hcloud-csi,
Reaper and scraper pip/certifi wheels; custom packing; mounted/private trust and
host/guest planes. Do not rewrite signed JARs or delete private identities or
protective distrust records to make a check pass. PostgreSQL/PgBouncer public
bundles are audit-only where unused: do not restart databases solely for them.

## Evidence and rollback

Record source change, completed build, published digest, deployed digest and
actual-verifier qualification separately. Ready status and retained bytes prove
neither verifier approval nor exploitation. Keep workflow URLs, binary SDK
metadata, native negative/positive results and Kura wave health per owner.

Keep warm old capacity until the patched replacement is healthy. Existing jobs
retain exposure until they finish; immediate termination needs separate human
agreement. Preserve a known-good **patched rollback floor** per component.
Rolling back below that floor reintroduces exposure and needs explicit human
acceptance. Re-inventory live image IDs, scheduled templates, Kura pins and
host/guest/private stores before declaring fleet remediation complete.
