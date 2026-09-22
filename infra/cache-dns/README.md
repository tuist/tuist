# Proximity-steered managed cache hostnames

Implements [Atlas spec 95](https://atlas.tuist.dev/engineering/specs/95).
All rollout switches default off. Adding these files does not provision a zone,
change delegation, enable advertising, or change client endpoint responses.

## Bootstrap (operator step, not performed by local validation)

1. In the dedicated DNS AWS account, create a CloudFormation change set from
   `zone.yaml`, review it, and apply it. The stack retains the public zone even
   if the stack is deleted. Record `HostedZoneId`, `NameServers`, and policy ARNs.
2. Create **plain, DNS-only NS records** named `cache` in Cloudflare's `tuist.dev`
   zone, one per exact nameserver returned by that stack. Do not invent names,
   proxy the delegation, or remove the parent zone. Verify the delegation with
   `dig +trace cache.tuist.dev NS` and direct authoritative queries.
3. Provision separate AWS identities for the record writer, ACME solver, and
   controller. Attach only their corresponding policies. Health-check APIs have
   account-wide create/list scope; use the dedicated DNS account. The controller
   only deletes checks whose caller reference belongs to its zone/cluster.
4. Store each identity's `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` as fields
   in separate 1Password items. The platform and Tuist chart ExternalSecrets
   consume those fields through the existing `onepassword` ClusterSecretStore.
   Never place credentials in Helm values or git. The writer and solver Secrets
   live in the platform/ClusterIssuer resource namespace; the controller Secret
   lives in `kura`. All environments share the zone but use different owners.
5. Enable platform `cacheDNS.enabled`, supplying `hostedZoneId`, a unique
   `ownerId` (e.g. `tuist-staging-cache`), and the writer/solver item names under
   `cacheDNS.externalSecret`. Set `externalSecret.enabled: true` to sync them.
   The Cloudflare external-dns excludes `cache.tuist.dev`, while the AWS writer
   only reads CRDs, filters this zone by both name and ID, and uses a distinct
   TXT owner. Preserve the exclusion if overriding external-dns `extraArgs`.
6. Enable `kuraController.stableDNS` with the same zone, cluster-unique owner and
   controller item. Leave `drain: 3720s` (minimum 120 seconds). Keep credentials
   and the provider enabled through rollback until all stable status is gone.
7. Add `*.cache.tuist.dev` to the existing
   `kuraController.publicWildcardCertificate.dnsNames`, retaining
   `*.kura.tuist.dev`, and wait for issuance before enabling advertising.
   Environments share an ACME name set: issue serially, without deleting Secrets.
   Regional ingress TLS stays on its working wildcard while stable TLS is
   pending. Hosts not covered by the wildcard use the per-instance Certificate.
8. Enable server environment `TUIST_KURA_STABLE_HOSTNAME_ENABLED=true` through
   `server.extraEnv`. Keep `TUIST_KURA_STABLE_HOSTNAME_HANDOUT_ENABLED` unset.
   Set `TUIST_KURA_STABLE_HOSTNAME_ACCOUNTS` to a comma-separated list of exact
   test-account handles for the first rollout. Empty means all managed placement
   accounts. The same allowlist gates advertising and endpoint hand-out; removing
   an account safely withdraws its records through the normal drain barrier.
9. After staging routing/steering validation, independently set
   `TUIST_KURA_STABLE_HOSTNAME_HANDOUT_ENABLED=true`. A response collapses only
   when every desired region is active and every advertising managed region has
   fresh, generation-matched controller readiness. Self-hosted registrations and
   eligible custom endpoints remain alongside the managed stable name.

The current catalog calls the Paris region `eu-west` (the spec's `eu-central`
was renamed). Its AWS tag is `eu-west-3`; Northern Virginia is `us-east-1`, Oregon
`us-west-2`, Montreal `ca-central-1`, and Singapore `ap-southeast-1`.

## Lifetimes and failure behavior

The CR keeps the regional host, stable host, and advertising intent separate.
The controller probes `/ready` by connecting directly to the primary's box on
443 with the stable SNI and normal public certificate verification. Only then
can it create the latency A record (60-second TTL), per-region set identifier,
and shared TCP health check. Readiness also requires the provider's actual
record to match the target, AWS region, and check ID. A shared zone snapshot
bounds these AWS reads to one scan per ten seconds; failed refreshes never
reuse expired data.

Placement role changes do not enter this intent: demotion leaves records alone.
A retiring instance keeps advertising until the lifecycle can start its drain,
which waits for a surviving stable endpoint. Drain-pending instances withdraw
immediately on the next intent sync, while ingress and certificate rendering
continue. The CR finalizer covers deletion as well as ordinary retirement.

Withdrawal is confirmed by reading the exact Route53 name/type/set identifier,
not by assuming a deleted Kubernetes object implies deleted DNS. The full
3720-second drain starts **after** the provider first reports the record absent,
covering Route53 propagation and resolver TTL as well as existing connections.
This can extend the existing placement drain, intentionally. AWS errors or a
stalled external-dns retain routing indefinitely. Authoritative DNS and real
client behavior still require the staging validation below; a local fake API
cannot prove AWS's propagation or ingress-nginx reload behavior.

Health checks use standard 30-second TCP probes on port 443, three failures,
shared per box and cluster. They do not promise failover within a single second
or detect a broken account on a healthy box. Route53 skips unhealthy records
and fails open if every record is unhealthy. A five-minute, leader-only sweep
removes this cluster's unreferenced checks after both provider records and
persisted instance state release them, including orphans from interrupted creates.

Readiness is cached in the existing ephemeral key-value store for at most three
minutes and retains the controller's timestamp. Re-reading frozen status does
not renew it. A cache restart or a stale observation restores regional endpoint
responses. No account data or database columns are added; DNS and readiness
state are documented in `server/data-export.md`.

## Rollback

First turn off **hand-out**. Keep advertising and rendering for persisted clients
until they have refreshed configuration. If withdrawing the stable lane is then
appropriate, turn off **hostname enabled**, leaving the controller, AWS writer,
zone delegation, credentials and solver running. The controller retains the old
name from status until each regional record is observed absent and its drain
elapses. Confirm there are no stable DNSEndpoints, provider A records, retained
stable status, or owned health checks before disabling the writer/provider.
Do not remove finalizers, delete the zone, or remove AWS credentials to force a
rollback: those actions defeat the withdrawal barrier. Regional names remain
available throughout, but deliberately withdrawing the stable lane requires
persisted clients to refresh configuration first.

Existing account handles ending in `-staging` or `-canary` are not silently
renamed: they stay on regional endpoints. New names/renames with those suffixes
are rejected case-insensitively. Audit and resolve any existing collisions before
enabling their stable lane.

## Local validation (2026-09-22)

- `go test -race ./...` in `infra/kura-controller`: passed, including the owned
  Helm template tests with `TUIST_TEST_HELM` pointing to Helm. Covers readiness,
  regional record identity, persistent withdrawal/drain, finalizer enforcement,
  shared health checks, provider failures, and regional TLS during issuance.
- Focused server tests for stable endpoints, the Kubernetes provisioner, region
  catalog, account validation, placement rows, lifecycle, and both generations
  of account cache resolution: **323 passed, one baseline failure**. The failing
  `every registered region derives a budget Kura can honour` assertion reports
  that `us-east` exceeds its disk envelope. Re-running that test with the
  unchanged HEAD region catalog and provisioner reproduced the same failure.
  Disk sizing is unchanged by this implementation.
- `mix format --check-formatted` on changed Elixir files and
  `mix credo diff --from-git-ref HEAD --strict`: passed; no new Credo issues.
  The repository-wide Credo scan still reports existing findings.
- `git diff --check`: passed. Dependency resolution preserved `server/mix.lock`.

The server checks used isolated local PostgreSQL and ClickHouse test databases.
These checks do not establish real Route53 propagation, public resolver steering,
ACME issuance, ingress reloads, or client HTTP/gRPC behavior against the new name.

## Deferred staging validation

No step in this list is executed by the local checks.

- Verify delegation, credentials, solver selection, separate TXT ownership, and
  that Cloudflare does not create records under the delegated zone.
- With eu-west and ca-east serving a test account, resolve from both boxes and
  external resolvers, recording answers against historical client probe choices.
  Confirm actual AWS steering quality before hand-out; metro tagging is an
  approximation of client latency, especially with distant recursive resolvers.
- Exercise HTTP reads/writes and Bazel gRPC against the stable name in both
  regions, including TLS certificate rotation and nginx reloads.
- Run a 65/35 relocation with demotion. Assert zero changes to either DNS source
  and uninterrupted HTTP/gRPC serving; primary role is irrelevant to advertising.
- Expand, then retire a region. Watch the DNSEndpoint disappear, query Route53's
  regional record and authoritative servers, and confirm routing persists for
  the post-withdrawal drain. Stall external-dns and separately fail AWS reads;
  teardown must remain blocked while the survivor continues serving.
- Delete an instance and restart the controller during withdrawal. Verify the
  persisted status/finalizer retains the same ordering.
- Kill a gateway and measure health-check failover, including the all-unhealthy
  fail-open case. Confirm one check per shared box and cleanup only after its
  final account leaves.
- Enable hand-out. Test single-entry bypass in Xcode/module/Gradle, Bazel setup
  persistence and credential refresh, CAS proxy re-resolution, and mixed
  managed/self-hosted/custom endpoints. Soak staging CI before canary/production.
