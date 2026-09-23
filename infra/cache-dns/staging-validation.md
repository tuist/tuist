# Spec 95 staging validation — 2026-09-22–23

Status: staging DNS, TLS, cache protocols, demotion, failure ordering, and real
client checks have passed. Both full withdrawal drains completed. Testing
found two hand-out races; both fixes are deployed, and the final local client
soak passed. GitHub CI awaits permission to store
the temporary fixture token as an Actions secret.

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
`probe` (46). A project-restricted account token with cache write scopes expires
24 hours after creation. It is held only in a local file with mode `0600`; the
current Go probe sends it in the HTTP Authorization header and to grpcurl through
the subprocess environment, never through command arguments or evidence logs.

Public placements were created through the server's normal admission APIs, with
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

The staging Kubernetes identity can read Kura instances and ingresses but cannot
`get` or `list` `dnsendpoints.externaldns.k8s.io` in namespace `kura`. Direct
inspection of DNSEndpoint source records was therefore not completed. The
remaining DNS source assertions need that read permission through the normal
cluster access path; no workload identity or admin kubeconfig was used to bypass
the denial.

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
pre-existing custom runner label excluded from actionlint. Automatic approval
blocked transferring the scoped token to an Actions secret; explicit permission
is pending, and no secret has been uploaded.

## Remaining work

1. Run the prepared GitHub CI soak if credential transfer is approved. The same
   harness passed locally; this does not substitute for a GitHub runner origin.
2. Direct DNSEndpoint source inspection still needs namespace-scoped get/list
   access; the normal staging identity still reports `no` for that permission.
3. Before broader rollout, validate longer-term steering telemetry and an actual
   shared-gateway outage. These remain distinct from the regional spot comparisons
   and isolated health-check failure above.

The main fixture remains available for the pending CI run, with Montreal and its
private runner cache active. Account 50 and the main fixture's Paris resources
are gone. All temporary fault settings are restored: the AWS writer is 1/1,
the controller's temporary inline IAM deny is absent, and the surviving health
check uses port 443. The wildcard certificate remains Ready. The isolated CAS
proxy, Bazel server, and completed local probes have been stopped. When validation
ends, revoke the token, clear keep-warm, and remove only this account's test placements through the
normal lifecycle. If stable advertising has been enabled, complete withdrawal and
the drain before removing provider credentials or DNS resources. Do not strip
finalizers to force cleanup.
