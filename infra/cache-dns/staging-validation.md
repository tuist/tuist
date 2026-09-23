# Spec 95 staging validation — 2026-09-22–23

Status: staging DNS, TLS, cache protocols, demotion, withdrawal/draining, native
client builds, external CI and the actual gateway-outage drill are complete.
Established HTTP/1.1 and HTTP/2 clients recovered after about 126 seconds.
The one-hour latency comparison and supplemental forty-minute paired run are
complete: one measured steering mismatch and four DNS timeouts are retained
below; all 1,830 pinned TLS requests succeeded. This is bounded staging evidence,
not multi-day or all-region validation. Two hand-out races and a health-check
recreation defect were fixed and deployed to staging. The self-hosted runner's
public-endpoint attempt remains denied by its existing network policy.
The fixture token was revoked, its GitHub secret and local file were removed,
and temporary probe pods were deleted. The fixture placements remain available
for reproduction. Canary and production preparation is committed but undeployed.

## Revisions and rollout boundaries

- Implementation: `e33db996e674f22e3fa2720afcc1c8e4f4577004` on
  `codex/cache-dns-spec95`, with the local validation recorded in [README](README.md).
- Staging was already running `db5e8ea4c0ee0dbaa1f045de6c6b24c5c8c09e66`.
  The implementation was cherry-picked onto that revision to preserve the newer
  staging changes: `56966885e6aac2638713e1b270137bc6bdb7e2dc`, branch
  `codex/cache-dns-staging-e2e`.
- [Staging deployment run 35765192379](https://github.com/tuist/tuist/actions/runs/35765192379)
  was dispatched with that full commit SHA and the existing Kura runtime pinned
  to `sha-db5e8ea4c0ee`. The workflow completed successfully. The migration hook
  reported both databases already up to date. Server and controller each reached
  2/2 ready, updated replicas on image tag `sha-56966885e6aa`.
  Stable DNS, advertising, and hand-out were disabled for that September 22 run.
- The earlier run 35764868105 failed at checkout because its commit input was
  abbreviated. It performed no deployment.
- No canary or production deployment was dispatched.

## Fixture and evidence

The dedicated staging organization is `kura-spec95-e2e` (account 49), with project
`probe` (46). A project-restricted account token with cache write scopes was
created with a 24-hour expiry. It was held in a local file with mode `0600` and was
temporarily supplied to GitHub Actions with the user's explicit approval. The
current Go probe sends it in the HTTP Authorization header and to grpcurl through
the subprocess environment, never through command arguments or evidence logs.
The token was explicitly revoked after the final authenticated run, before expiry.

Public placements were initially created through the server's normal admission APIs, with
`eu-west` primary and `ca-east` secondary. Both have keep-warm enabled while the
validation is in progress. Project creation also provisioned its normal private
runner cache. All three instances reached Kubernetes phase `Ready`.

| Region | Public box | Kura instance |
| --- | --- | --- |
| Paris / `eu-west` | `195.154.155.12` | `kura-kura-spec95-e2e-eu-west-1` |
| Montreal / `ca-east` | `144.217.252.35` | `kura-kura-spec95-e2e-ca-east-1` |

Local JSONL evidence is in `/tmp/spec95-staging-e2e/`. Do not copy the `token`
file into a report or artifact. The reproducible harness is
[`cmd/staging-probe`](../kura-controller/cmd/staging-probe/main.go), using its
embedded [`reapi-smoke.proto`](../kura-controller/cmd/staging-probe/reapi-smoke.proto).

## Completed baseline checks

Controller validation was repeated on the newer staging integration revision:
`go test -race ./...` passed in `infra/kura-controller`, including the Helm
rendering tests with `TUIST_TEST_HELM` set. The original probe's syntax and protobuf
schema also validated, and its staging-only hostname guard rejected a production
hostname before making a request. That probe was subsequently replaced with Go
to use the repository's existing infrastructure toolchain.

Each round trip uploads a random 64 KiB artifact through the HTTP Gradle cache
route and through REAPI `BatchUpdateBlobs`, then verifies the exact returned
bytes and digest. TLS verification remains enabled, including when pinning an
IP while preserving the regional hostname/SNI.

| UTC | Check | Result | Local evidence |
| --- | --- | --- | --- |
| 18:18:16–18:18:18 | Paris, writes and reads pinned to its box | HTTP 201/200, gRPC status 0; bytes verified | `eu-west-regional-before.jsonl` |
| 18:18:16–18:18:19 | Montreal, writes and reads pinned to its box | HTTP 201/200, gRPC status 0; bytes verified | `ca-east-regional-before.jsonl` |
| 18:19:34–18:19:43 | Paris writes, Montreal reads | Both protocols replicated; initial misses converged within about five seconds | `cross-region-before.jsonl` |
| 18:20:24 | Authenticated endpoints API, current CLI header | Exactly the two regional URLs; `provisioning: false` | `endpoints-before.json` |
| 18:20:44–18:20:51 | Montreal writes, Paris reads, normal DNS | Correct public box addresses; both protocols replicated and verified | `cross-region-dns-before.jsonl` |

Expected replication misses are retained in the evidence: HTTP 404 and REAPI
NOT_FOUND (5), followed by success within the bounded retry window. These are
regional baseline checks; no request in this table used `cache.tuist.dev`.

## Completed rollout regression checks

- Repeated probes through normal regional DNS completed **60 round trips per
  region**, 120 total, spanning the rollout. All 240 HTTP requests and 240 gRPC
  requests passed with matching artifact bytes. Evidence:
  `eu-west-during-rollout.jsonl` and `ca-east-during-rollout.jsonl`.
- At 18:31 UTC, release RPC assertions verified the new implementation was
  loaded, derived `kura-spec95-e2e-staging.cache.tuist.dev`, and had both hostname
  enablement and hand-out disabled. The RPC emitted only a fixed confirmation.
- The authenticated endpoints API still returned exactly the two regional URLs,
  with `provisioning: false` (`endpoints-after.json`).
- All three fixture instances remained `Ready` without stable intent or status.
  Their HTTP/gRPC ingresses retained only regional hosts and now declare
  `external-dns.alpha.kubernetes.io/ingress-hostname-source: annotation-only`.
- At 18:32 UTC, both new deployments had 2/2 ready, updated replicas. The existing
  Cloudflare writer had `--exclude-domains=cache.tuist.dev` (`rollout-after.json`).

During this baseline, the staging Kubernetes identity could read Kura instances
and ingresses but could not `get` or `list` `dnsendpoints.externaldns.k8s.io` in
namespace `kura`. Direct source inspection was deferred until the separate
read-access PR deployed on September 23, as recorded below. No workload identity
or admin kubeconfig was used to bypass the denial.

## AWS bootstrap and Go probe — September 23

The initial AWS access blocker was resolved through a temporary CLI login to
account `881372579491`, profile `tuist-dns`. The reviewed `tuist-cache-dns`
CloudFormation change set created exactly one zone and three managed policies;
the stack reached `CREATE_COMPLETE` at 09:13 UTC.

- Hosted zone: `Z046862130S1WUMPV7Z3P` (`cache.tuist.dev`).
- Cloudflare delegation: four unproxied NS records, TTL 300, using AWS's exact
  nameservers. Public resolution through 1.1.1.1 and a direct authoritative SOA
  query both succeeded.
- Separate IAM users: `tuist-staging-cache-dns-{writer,solver,controller}`. Each
  has only its corresponding stack policy; keys were written directly to the
  `cache-dns-{writer,solver,controller}` items in the `tuist-k8s-staging` vault.
  Bootstrap credentials are not delivered to Kubernetes.
- Plumbing rollout: [35842020182](https://github.com/tuist/tuist/actions/runs/35842020182),
  chart revision `f2ce45200f3`, preserving the validated images. Both hostname
  flags were off for this plumbing deployment, with only `kura-spec95-e2e` allowed.
- At 09:20 UTC, writer and solver ExternalSecrets were `SecretSynced`, and the
  Route53 external-dns deployment was 1/1 ready with successful provider reads.
- The replacement Go probe passed authenticated Paris-to-Montreal HTTP and gRPC
  replication through normal DNS at 09:19 UTC (`go-cross-region-baseline.jsonl`).

The plumbing deployment succeeded. All three ExternalSecrets synchronized and
the shared wildcard certificate became Ready at approximately 09:23 UTC, covering
both `*.kura.tuist.dev` and `*.cache.tuist.dev`. Advertising was then enabled for
the fixture while hand-out remained disabled.

## Stable routing, demotion, and withdrawal — September 23

- Authenticated HTTP and REAPI round trips passed through stable SNI pinned to
  both public boxes. Both controller stable endpoint observations became ready.
- Queries to the Route53 authoritative nameserver from the actual Paris and
  Montreal gateway pods selected their respective local box. Local `/ready`
  requests over verified TLS took approximately 14 ms and 11 ms respectively.
  These are spot comparisons, not a long-term client probe telemetry study.
- At 09:27 UTC, primary placement moved to Montreal with Paris retained as a
  secondary. The normal placement API received a 65/35 evidence payload; this
  test consumes that decision and does not exercise the upstream traffic
  classifier. Provider A/TXT records were byte-identical before and after the
  demotion, and 24 concurrent authenticated round trips passed.
- With the AWS writer scaled to zero, Paris retirement removed its advertising
  intent while its provider record remained. The withdrawal clock stayed unset,
  phase remained Ready, and authenticated HTTP/REAPI traffic passed.
- A temporary explicit deny of `ListResourceRecordSets` on the controller's
  test-zone policy was verified using its own credential and controller logs.
  After the writer resumed and removed Paris's record, failed provider reads
  still left the clock unset and Paris serving both protocols. The deny was
  removed; IAM propagation and controller retry backoff delayed recovery.
- Successful provider observation started the drain at **09:48:22 UTC**. A
  rolling controller restart preserved that exact timestamp. Deleting only the
  retiring fixture CR at **09:49:42 UTC** left its finalizer and routing intact.
Its teardown deadline is **10:50:22 UTC**, with the full 3720 seconds unchanged.

The first two fault-script attempts had inconclusive checkpoints: one checked
logs before a denial appeared; another allowed too little recovery time after
removing the deny. Their cleanup restored permissions and the writer. The
successful state observations above were recorded independently afterward.

An earlier laptop-origin soak recorded TCP connect timeouts to Paris at 09:41:53
and 09:42:03 UTC. The gateway served the controller's readiness request at
09:41:51 and subsequent authenticated requests at 09:42:37; routing remained
configured. The cause is not established, so this is not counted as an
uninterrupted soak. A new evidence series began around 09:46 UTC and retains
failures rather than silently retrying them away.

Evidence: `records-{before,after}-demotion.json`, `demotion-*.jsonl`,
`writer-stalled-*`, `provider-denied-*`, `controller-read.stderr`,
`provider-read-failure.log`, `withdrawal-observed-instance.json`,
`after-controller-restart.json`, `deletion-during-drain.json`,
`drain-survivor-soak.jsonl`, and `drain-paris-rendering.jsonl`.

The full drain completed without shortening its timer. Both authenticated
protocols passed on Paris at 10:49:23 UTC, and the pinned HTTP probe still passed
at **10:50:16 UTC**. A Kubernetes watch recorded CR deletion at exactly
**10:50:22 UTC**. The first subsequent pinned probe, at 10:50:49 UTC, received
the expected TLS `unrecognized name` rejection. The Ingresses, Services, and
StatefulSet were gone; pods entered their normal termination grace period.
Montreal's authenticated round trips continued without interruption. Evidence:
`paris-final-drain-roundtrip.jsonl` and `paris-teardown-watch.jsonl`.

After teardown, Bazel again reported a remote cache hit with the originally
generated `.bazelrc.tuist` checksum unchanged. The same long-running CAS proxy
served another clean Xcode rebuild using a new empty local CAS directory,
again yielding **138/138 hits**. Its latest endpoint transition was still the
automatic recovery to the stable hostname; it was not restarted for this test.
Evidence: `bazel-after-paris-hit.log`, `xcode-after-paris-build.log`, and
`cas-endpoint-evidence.json`.

## Shared health checks and failover

A second fixture, `kura-spec95-health` (account 50), advertised from both boxes
and reused the existing two health-check IDs. Before injection, an account-wide
inventory confirmed exactly one hosted zone, two TCP checks, no calculated
check dependencies, and only these two test accounts referencing either check.
Automatic approval initially rejected the drill over possible shared impact;
the complete reference inventory and runtime scope guards established that no
other account would be affected, and the guarded drill was then approved.

Temporarily changing the Paris check's probe port from 443 to closed port 1
caused real TCP failures and switched authoritative queries from Paris to
Montreal by **10:00:42 UTC**. The surviving stable endpoint returned HTTP 200.
With both checks probing the closed port, authoritative DNS still returned an
address at **10:02:40 UTC** instead of NXDOMAIN. Both checks were restored to
port 443; subsequent reads confirmed all 16 observers for each check reported
successful connections. The gateways themselves stayed running: this tests failed TCP probes
and DNS steering, not a shared-gateway process outage or recovery of existing
client connections to a dead gateway.

Normal destruction of account 50's test instances began after the drill. Both
public finalizers observed withdrawal at **10:05:20 UTC** and must retain
rendering until **11:07:20 UTC**. Their shared checks must remain referenced
until every remaining provider record and retained instance releases them.

Both routes still returned HTTP 200 at 11:07:02 UTC. The controller deleted both
CRs at **11:07:29 UTC**, nine seconds after the full drain deadline. Account 50
was then deleted through `Accounts.delete_account!`, after confirming both public
CRs were gone and their server rows had left the live lifecycle. This also
removed its automatically provisioned private runner cache. Its empty,
ownerless account-level peer Service was then removed explicitly after verifying
its account selector and absence of live pods or endpoints. The final resource
inventory contained no resources for account 50 or the retired main Paris
instance. Release RPC also confirmed Paris was archived with its PostgreSQL
readiness projection cleared. The main fixture and its Montreal advertisement
remain available for the pending GitHub CI run.

At 11:00 UTC both TCP checks still existed even though only the main fixture's
Montreal A/TXT records remained: the draining CRs protected the shared checks.
After final release, the Paris check was collected; the 11:13 UTC inventory
contained only Montreal's original check, still on port 443 and referenced by
the surviving account. Evidence: `records-after-paris-retirement.json`,
`health-before-final-release.json`, `health-after-final-release.json`,
`health-final-release-watch.jsonl`, and `health-fixture-cleanup.log`.

Evidence: `health-*.json`, `health-*.txt`, and `health-survivor-ready.jsonl`.

## Real clients and the cross-replica defect

Using the existing CLI `4.211.0-canary.7`, isolated temporary fixtures, and the
project-restricted token:

- Bazel 9.2.0 built an artifact, then restored it from the remote cache after
  clearing local outputs. After hand-out enablement, `tuist bazel setup` wrote
  `grpcs://kura-spec95-e2e-staging.cache.tuist.dev`; the same clean rebuild
  reported **one remote cache hit** through that name.
- The current Gradle plugin source with the repository's Gradle 9.2.1 wrapper
  compiled a Java fixture, then reported `compileJava FROM-CACHE` with the local
  build cache disabled. An initial Gradle 8.12.1 attempt failed to compile the
  plugin's test sources; using the pinned wrapper resolved that tool mismatch.
- Xcode 27.0 generated and built the existing compilation-cache acceptance
  fixture against a separate CAS proxy socket. The cold build reported 0/138
  hits. After draining uploads, cleaning products, and selecting a new empty
  local CAS directory, the rebuild reported **138/138 hits (100%)**. Build/run
  report uploads were refused because the token grants cache access only; this
  does not validate the analytics upload path. The isolated proxy's launch
  endpoint was the stable hostname; its endpoint log showed no change before
  these builds completed at 09:55 UTC. At 10:23:29 UTC it switched to the regional
  Montreal hostname during an endpoint refresh, another consequence of the
  inconsistent hand-out described below (`cas-endpoint-evidence.json`).

The local preflight for the prepared CI soak then exposed inconsistent API
hand-out. Eight requests alternated between the stable and regional URL.
Reading the two web replicas showed a ready projection on one and `nil` on the
other. `KeyValueStore` uses local Cachex by default, and staging has no Redis;
the singleton reconciliation job therefore could not publish readiness to every
web replica. This was a real implementation defect despite working cache traffic.

The fix adds a nullable `kura_servers.stable_endpoint` JSONB projection, read
alongside the existing server query. It preserves the controller timestamp,
three-minute freshness, and generation check at observation; lifecycle resets
clear it. No request reads Kubernetes or AWS. The additive migration requires
no backfill and is compatible with the old server image during rolling deploys.
The regression failed before the fix, then the focused regression/provisioner
run passed **11 tests**. The complete affected suites subsequently passed
**206 tests**, excluding only the existing, separately reproduced `us-east`
disk-budget assertion. Credo reported no issues. The migration safety check
reported no warning for the new migration (existing historical migration
warnings remain).

The fix deployed successfully in
[run 35848047301](https://github.com/tuist/tuist/actions/runs/35848047301), using
server revision `4a256a44063636429871b3119df412bd85a948c6` while preserving the
previously validated controller and Kura runtime images. By 10:40 UTC both web
replicas read the same fresh PostgreSQL projection. After replacing exactly one
of the two healthy web pods, the replacement and survivor again read the same
projection; the migration version was also present in `schema_migrations`.
All **90 API requests**, thirty before, during, and after the restart, returned
only the stable hostname with `provisioning: false`.

Bazel then restored its artifact from the remote cache with the saved
`.bazelrc.tuist` checksum unchanged. At 10:43:31 UTC the existing CAS proxy
automatically returned to the stable hostname during its normal refresh,
without being restarted. Evidence: `shared-readiness-*.jsonl`,
`before-single-web-restart.json`, `bazel-fixed-hit.log`, and `cas-proxy.log`.

The longer local Gradle soak then stopped at 10:45:23 UTC after five successful
fresh-process restores because the API again returned a regional name. This was
a second race: every controller pass persisted `ready: false` before probing,
then `true` after completing its checks. A staging watch captured that exact
false/true transition at 10:49:37 UTC. The server could sample the intermediate
state and retain it until its next reconciliation even while cache traffic was
healthy. The first soak is therefore a failure, not a completed twelve-hit run.

The controller fix persists initial identity before publication as before, but
steady passes publish only completed observations. Failed probes and provider
reads still persist false readiness; a separate five-second status-write
context allows recording a provider deadline failure. The regression failed
before the fix. The full controller suite, including Helm rendering, then passed
with `go test -race ./...`; `go vet ./...` also passed.
Evidence: `readiness-watch-before-fix.jsonl`, `gradle-fixed-soak.log`, and the
local `spec95-controller-readiness-{red,green}.log` files.

Controller revision `2857be3434e27ee306087a3baf16fd9bcc94ad10` then deployed in
[run 35851387377](https://github.com/tuist/tuist/actions/runs/35851387377).
The first attempt stopped before application rollout because the observability
job received a 1Password 502. Retrying failed jobs reused the built images and
succeeded. Both controller and web deployments reached 2/2 updated ready
replicas by 11:12 UTC. Both web replicas read shared ready state, and thirty
consecutive API requests returned only the stable hostname. The final local run
of the CI harness passed: a unique remote upload followed by all **twelve
fresh-process remote hits**, with local caching disabled and output bytes
verified. All thirteen API checks returned exactly the stable hostname. The
eleven-minute controller watch recorded **43 ready observations and zero false
observations**, from 11:12:38 to 11:23:27 UTC.
Evidence: `gradle-final-soak.log`, `gradle-final-ci/`, and
`readiness-watch-after-fix.jsonl`.

The main drain/rollout soak completed **150 authenticated round trips** from
09:46 to 11:09 UTC with no failures: 300 HTTP requests and 300 REAPI calls, with
the exact uploaded bytes verified. A separate survivor soak passed another
**30 round trips** from 11:08 to 11:24 UTC through the final controller deployment,
also without failures. Expected TLS rejections from the retired Paris
IP after its deadline are recorded separately and are not survivor failures.

The prepared CI mode is `linux-runners-staging-smoke.yml` with both
`gradle_cache` and `stable_cache_dns` enabled, project `kura-spec95-e2e/probe`,
and staging URL. It unsets the private runner endpoint, requires the exact public
stable API answer, and checks a unique remote upload followed by twelve remote
hits in fresh Gradle processes. ShellCheck and actionlint passed, with only the
pre-existing custom runner label excluded from actionlint. The user explicitly
approved transferring the scoped token to a temporary Actions secret on
September 23.

The first GitHub attempt,
[run 35855223163](https://github.com/tuist/tuist/actions/runs/35855223163), used
`tuist-staging-linux`. The API returned the exact stable hostname, but the first
Gradle cache request timed out connecting to Montreal. Hubble on the runner's
node recorded repeated `EGRESS DENIED` / `Policy denied DROPPED` SYN packets to
`144.217.252.35:443` at 11:35:38–11:35:58 UTC. Cilium classifies that public IP
as `remote-node`, so the runner's public-internet egress rule does not admit it.
The harness deliberately removes the normal private runner endpoint override;
this failure therefore does not establish a failure of the normal private
runner-cache path. The temporary secret was deleted after this run.
Evidence: `github-ci-first/`, `github-ci-first-failed.log`, and
`github-ci-self-hosted-policy-denials.log`.

The same public-endpoint soak was then dispatched on `ubuntu-latest` in
[run 35855668647](https://github.com/tuist/tuist/actions/runs/35855668647), to
validate the external CI client path without changing runner network policy.
It **passed**: the initial unique remote upload and all twelve fresh-process
remote hits succeeded, with local caching disabled and output bytes verified.
All thirteen API observations, from 11:39:19 through 11:47:00 UTC, returned only
the stable hostname with `provisioning: false`. Downloaded artifacts independently
confirmed the upload, all twelve `FROM-CACHE` / loaded-entry results, absence of
cache errors, and the thirteen exact API answers. The fixture token was absent
from the artifacts. Cleanup deleted `SPEC95_STAGING_CACHE_TOKEN`; a subsequent
repository-secret listing confirmed zero entries with that name.
Evidence: `github-ci-external/` and `github-ci-external-watch.log`.

## DNS source access and final provider comparison

The independent read-only access change,
[PR #13524](https://github.com/tuist/tuist/pull/13524), was merged at 11:37:22 UTC.
Its existing automatic Pomerium workflow completed successfully in
[run 35855609870](https://github.com/tuist/tuist/actions/runs/35855609870), applying
the access chart to staging, canary, and production. This was an access-chart
rollout; the spec95 application changes remain staging-only.

Through the normal staging tailnet identity, get/list/watch on DNSEndpoints now
return `yes`; create/update/patch/delete still return `no`. At 11:41 UTC, direct
source inspection found exactly one surviving fixture stable DNSEndpoint,
`kura-kura-spec95-e2e-ca-east-1-stable-dns`. Its A target, TTL 60, `ca-east` set
identifier, `ca-central-1` AWS region and health-check ID all matched Route53.
The provider's TXT ownership named `tuist-staging-cache` and that exact CRD
source. No retired Paris or health-fixture DNSEndpoints remained. The private
runner DNS source still targeted its private address separately.
Evidence: `dns-source-after-access-pr.json` and
`dns-provider-after-access-pr.json`.

## Follow-up scope and fixture state

1. The self-hosted runner's public endpoint override remains blocked by its
   network policy, as recorded above. Use the external runner for this public
   client validation; the ordinary runner-cache path keeps its private override.
2. The actual gateway outage and persistent-connection recovery are recorded
   below. The bounded client-latency comparison supplements the earlier spot
   checks; multi-day historical telemetry and the other production regions
   remain outside this staging exercise.

The main fixture remains available for reproduction, with Montreal primary,
Paris restored as secondary for the final outage drill, and its private runner
cache active. Both public placements retain keep-warm. Account 50 is gone.
All temporary fault settings are restored: the AWS writer is 1/1, the controller's
temporary inline IAM deny is absent, and both health checks use port 443. The
wildcard certificate remains Ready. The isolated CAS proxy and Bazel server
have been stopped. The cache-only token was revoked after authenticated probes
finished, and its local file was removed; the GitHub secret was already absent.
Final fixture teardown is separate from temporary probe cleanup: clear keep-warm
and retire only this account's placements through the normal lifecycle, completing
withdrawal and the full drain before removing provider credentials or DNS resources.
Do not strip finalizers to force cleanup.

## Canary and production preparation — September 23

The draft now enables the DNS infrastructure and server environment switches in
both managed overlays. Canary enables eligible accounts automatically after
readiness converges. Production additionally requires the `kura_stable_hostname`
FunWithFlags account/global gate for both DNS intent and endpoint hand-out;
the absent flag is off. No production account or global gate was enabled here.

Six separate IAM users were created:
`tuist-{canary,production}-cache-dns-{writer,solver,controller}`. Each has one
active key and only its intended writer, solver, or controller managed policy.
Credentials were written directly into the three `cache-dns-*` items in each
matching `tuist-k8s-{canary,production}` vault. The creation responses confirmed
the destination items, and IAM inventory verified the policy/key state. A
separate secret-value read-back attempt awaited 1Password authorization and was
cancelled; new-identity authentication and live ESO synchronization are not
claimed as validated. No canary or production Kubernetes deployment was
dispatched. The existing zone and delegation were reused.

The merge deployment now waits for the wildcard Certificate to contain both
DNS zones and report Ready at its current generation. Canary must pass before
the cascade can proceed to production, preventing overlapping initial issuance
of the shared ACME name set. A post-Helm gate failure stops promotion; it does
not automatically undo the completed Helm upgrade. The predicate accepts the
actual current staging certificate.

Validation of this preparation:

- Full controller race suite passed, including the actual canary/production
  overlay renders and six certificate-gate cases (disabled, current, old names,
  stale generation, pending issuance, and pending-to-ready). `go vet` passed.
- Affected feature-flag, stable-endpoint, provisioner and lifecycle tests:
  **221 of 222 passed**, with only the previously reproduced `us-east`
  disk-envelope assertion failing. After adding the global-rollout/actor-opt-out
  case, the final focused feature-flag and stable-endpoint run passed **24 tests**.
- Changed Elixir formatting passed; focused Credo reported no added issues.
  ShellCheck, deployment-workflow actionlint (existing custom-label exception),
  and `git diff --check` passed.

Evidence: `/tmp/spec95-rollout-{identities,iam-inventory,elixir-tests,flags-final,go-tests,credo}.log`.
The earlier staging results refer to the deployed integration revision. The new
production gate and canary/production overlays have been tested locally and
remain pending the draft PR's merge deployment.

## Actual gateway outage and persistent connections — September 23

The final drill first restored the fixture's Paris instance through
`Kura.return_from_archive/3`, with Montreal primary and Paris secondary. This
exposed a third defect: Route53 returned HTTP 409 `HealthCheckAlreadyExists`
because it retains caller references for deleted checks for several days.
The previous deterministic box reference prevented a normal cold return from
advertising again after the earlier successful collection.

The controller now adds an incarnation nonce while preserving the zone/owner/box
prefix used for adoption and collection. Legacy checks remain adoptable.
Ambiguous create retries retain their pending reference; a definite conflict
clears it for the next reconciliation. The new regression failed with the same
error before the fix. The full Go race suite and vet pass, including tests for
restart adoption, uncertain requests, and collection/recreation.

[Controller image build 35865029302](https://github.com/tuist/tuist/actions/runs/35865029302)
and [staging deployment 35865967008](https://github.com/tuist/tuist/actions/runs/35865967008)
passed. Staging now runs controller `sha-e1af68dc5af9`; server
`sha-2857be3434e2`, runtime `sha-db5e8ea4c0ee`, registry and search
`sha-56966885e6aa` remained pinned. Both stable observations were Ready by
13:21:59 UTC. Paris received replacement health check
`db199e07-3775-4b3d-9e77-37ff461f8b43`, and both checks had all 16 observers
reporting success before the fault. No canary or production deployment ran.

The live impact inventory found exactly two Montreal Ingresses, both belonging
to account 49, and only this fixture's DNS records referencing its box check.
Paris serves other accounts and was left running. The private runner gateway
also remained running. Temporary measurement pods on the two regional nodes
used no service-account token, no elevated capabilities, and a 90-minute deadline.

At **13:22:52 UTC** the fixture-only Montreal gateway DaemonSet was unscheduled
with a temporary node selector. Its existing pod was deleted with one second
of shutdown grace at **13:22:53**, breaking real TCP connections. An exit trap
and an independent 330-second watchdog restore only the injected selector.
This did not change the AWS check configuration, DNS records, backend caches,
or any network policy.

The probe processes began at 13:00 (Paris and laptop) and 13:02 (Montreal).
Each held one HTTP/1.1 transport and one HTTP/2 REAPI transport, reading and
byte-checking the same fixture every two seconds. Connection addresses prove
the original sockets remained in use for over twenty minutes, then changed
to Paris without restarting a process, refreshing configuration, or forcing a
failover IP. TLS validation remained enabled. This is transport-level recovery
with a Go harness; it does not claim every native SDK's retry budget is identical.

| Observation | UTC / result |
| --- | --- |
| Montreal first failed reads, both protocols | 13:22:54.368, TCP connection refused |
| All AWS observers reported Montreal failure | 13:24:43, 16/16 |
| Last Montreal authoritative answer targeting Montreal | 13:24:39 |
| First Montreal authoritative answer targeting Paris | 13:24:50 |
| Montreal HTTP recovered to Paris | 13:24:58.706 |
| Montreal HTTP/2 REAPI recovered to Paris | 13:24:58.706 |
| Montreal failed attempts | 62 per protocol, two-second cadence |
| Paris clients recovered to Paris | 13:22:55; zero failed probe results |
| Laptop clients recovered to Paris | 13:22:56; zero failed probe results |

The measured outage recovery is **about 126 seconds**, including health
convergence, DNS caching, and client reconnection. It must not be described as
instant failover. The gateway was still down when every client recovered.
Existing healthy connections can remain on the survivor after restoration;
DNS proximity is reconsidered on the next resolution, not on every request.

Restoration and the final steering-window results are recorded below.
Raw evidence remains under `/tmp/spec95-staging-e2e/`
(`gateway-outage-timeline.log`, `outage-health-*.json`, `outage-dns-watch.log`,
`outage-soak-{paris,montreal,laptop}.jsonl`, and `steering-up-*.jsonl`).

Restoration completed at **13:28:18 UTC**, and the gateway was Ready at
**13:28:31**. Its pod template compares exactly equal to the snapshot taken
immediately before the fault; the extra node selector is absent. Direct
Montreal TLS `/ready` passed, and all 16 AWS health observers were healthy again
by **13:29:54**. Both controller stable observations returned Ready.
The full Route53 record-set snapshot compares byte-for-byte equal before and
after the outage. Thirty consecutive endpoint API requests after recovery
returned exactly the stable URL with `provisioning: false`.

The persistent runs completed with **1,801 requests per origin and protocol**:
10,806 reads in total, including 124 failed attempts during the induced outage
(62 Montreal attempts per protocol) and 10,682 successful byte-verified reads.
There were no failed results from Paris or the laptop. Montreal's recovered
connections remained on Paris for 1,000 requests, then naturally reconnected
to Montreal at **13:58:19.250 UTC** with no further failures. The gateway's
`keepalive_requests 1000` setting agrees with that observed renewal. Restoring
DNS proximity did not migrate an already healthy socket.

All three persistent processes completed by **14:02:13 UTC**. The fixture-only
cache token was revoked through the normal account-token API at **14:03:02**,
its absence was verified, and its local file was deleted. Both authenticated
measurement pods were deleted after saving their final logs. Subsequent `/up`
latency measurements require no credentials.

## Bounded DNS and client-latency comparison — September 23

The initial 200m CPU ceiling on the persistent probe pods throttled fresh TLS
handshakes, as demonstrated by their cgroup counters. Those timings are retained
as diagnostic evidence but excluded from the performance comparison. The outage
connection and byte-verification observations above remain valid. Independent
unauthenticated measurement pods used a one-core ceiling on the same regional
nodes; their throttling counters were checked throughout the clean runs.

The primary series samples once per minute for one hour from Paris, Montreal,
and an external laptop. Each sample resolves the stable hostname using ordinary
system DNS and a direct authoritative query, then makes three fresh TLS `/up`
requests to each regional IP with the same stable SNI and certificate validation.
The per-region median selects the measured faster destination. Timings include
TCP, TLS and response headers, but exclude regional hostname lookup. The `/up`
path matches the CLI's latency probe; this is controlled measurement, not
historical native-client telemetry.

The first clean series measured the two regions sequentially. At
**13:46:41.227 UTC**, the laptop measured Paris at **881.830 ms** and Montreal
at **757.989 ms**, while both DNS paths selected Paris: a **123.841 ms**
measured penalty. Both regional timings were unusually high; the cause is
unconfirmed. Sequential order can confound a short client-side slowdown with a
regional difference, so an additional forty-minute series starts both regions
together in each of three paired rounds, matching the CLI's concurrent selection.
The original mismatch is retained; the paired run supplements the original
series and does not replace it.

The paired series also retained two DNS lookup failures: the laptop's system
resolver timed out in the sample recorded at **14:29:43.386 UTC**, and Paris's
direct authoritative query timed out at **14:30:38.384 UTC**. The alternate DNS
path succeeded in each sample, and all six pinned TLS requests succeeded.
Their cause is unconfirmed; these are failed DNS lookups, not evidence that DNS
selected the slower region. No retry or replacement sample hides either error.
The serial series recorded the same classes of timeout nearby: Paris's
authoritative lookup at **14:29:37.621 UTC** and the laptop's system lookup at
**14:29:42.505 UTC**. Across both series there were four failed lookups out of
610 queries. Their proximity in time is recorded without assigning a cause.

### Completed steering results

Successful DNS answers are compared with the faster measured region; timed-out lookups are counted separately:

| Series / origin | Successful latency samples | System matches / answers | Authoritative matches / answers | DNS timeouts (system / authoritative) | Paris median (ms) | Montreal median (ms) |
| --- | ---: | ---: | ---: | ---: | ---: | ---: |
| One-hour serial / paris | 61/61 | 61/61 | 60/60 | 0 / 1 | 9.7 | 272.4 |
| One-hour serial / montreal | 61/61 | 61/61 | 61/61 | 0 / 0 | 278.3 | 26.9 |
| One-hour serial / laptop | 61/61 | 59/60 | 60/61 | 1 / 0 | 117.9 | 401.8 |
| 40-minute paired / paris | 41/41 | 41/41 | 40/40 | 0 / 1 | 9.7 | 272.2 |
| 40-minute paired / montreal | 41/41 | 41/41 | 41/41 | 0 / 0 | 279.0 | 30.1 |
| 40-minute paired / laptop | 40/40 | 39/39 | 40/40 | 1 / 0 | 118.2 | 394.5 |

Each latency in the table is the median of per-minute regional medians. The
one-hour serial series began at 13:35 UTC and ended at 14:35 UTC; the paired
series ran 13:50–14:30 UTC. Full timestamps, counts and retained mismatches
are in [the machine-readable summary](staging-validation-summary.json).

All 305 latency samples completed their six TLS requests successfully (1,830
requests). Both regional pods finished with zero throttled periods and zero
throttled microseconds. System-DNS latency penalty had a zero p95 for each
origin/series; the one serial laptop mismatch produced the maximum 123.841 ms
penalty. A timed-out lookup has no chosen destination and is excluded from that
penalty calculation, but remains in the error counts above.

All six runs reached their full requested duration. Logs and CPU counters were
saved before deleting the remaining latency pods. The final restoration check
at **14:32:14 UTC** verified the original gateway template, unchanged provider
records, generation-matched Ready endpoint observations and 16/16 healthy AWS
observers for each box. This exercise does not measure large in-flight transfer
recovery, every native SDK's retry budget, historical native-client choices,
multi-day behavior, or the other three production regions. Observe those during
the gated rollout before enabling the flag globally.
