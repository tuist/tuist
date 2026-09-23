# Proximity-steered managed cache hostnames

Implements [Atlas spec 95](https://atlas.tuist.dev/engineering/specs/95).
Chart defaults remain off. Managed overlays prepare DNS infrastructure in all
three environments. Canary enables eligible accounts on merge. Staging and
production use the `kura_stable_hostname` FunWithFlags account/global flag as
the sole rollout control; absent is off. No server environment toggle or
account-name allowlist is required.

## Managed rollout on merge

The shared zone and Cloudflare delegation already exist. Each environment has
separate `cache-dns-writer`, `cache-dns-solver`, and `cache-dns-controller` items
in its `tuist-k8s-<environment>` 1Password vault. ESO supplies the credentials;
no keys are committed. The canary and production IAM identities and vault items
were prepared on September 23; Kubernetes resources are applied by the normal
merge deployment, not by the credential bootstrap.

Certificate readiness is a one-time operator rollout check, not a gate on
routine server deployments. Before the initial merge rollout, use the bootstrap
steps below to prepare the wildcard certificate in canary and then production,
finishing issuance in each environment before starting the next because they
share the ACME name set. With the intended cluster selected in the current
kubeconfig, run:

```bash
# Canary; for production select its cluster and use NAMESPACE=tuist.
HELM_RELEASE_NAME=tuist NAMESPACE=tuist-canary \
  bash infra/cache-dns/wait-for-certificate.sh
```

The check requires both `*.kura.tuist.dev` and `*.cache.tuist.dev` and a Ready
condition at the current generation. If it fails, resolve issuance before
continuing the initial rollout. Repeat it when changing certificate hostnames;
cert-manager handles routine renewals. The normal deployment cascade applies
canary, runs acceptance tests, and then applies production without waiting for
this certificate. The controller independently verifies HTTPS with the stable
hostname before advertising any endpoint, so pending issuance keeps accounts
on their regional URLs.

Managed overlays enable the DNS infrastructure. Canary requires no account
flag. In staging and production, an absent or disabled `kura_stable_hostname`
flag keeps accounts on regional URLs and creates no stable DNS advertising
intent. Use the existing `/ops/flags` surface to create the flag
and enable it for actor `account:<id>`, or use an authorized release console:

```elixir
account = Tuist.Accounts.get_account_by_handle("example")
FunWithFlags.enable(:kura_stable_hostname, for_actor: account)
```

The normal reconciliation loop publishes DNS and observes gateway/provider
readiness before API responses change; enabling the flag is not an immediate
traffic cutover. Once the initial accounts are validated, enable the same flag
for everyone with `FunWithFlags.enable(:kura_stable_hostname)`. Explicit actor
disables still take precedence; clear those overrides separately if intended.
No deploy is required for either flag change. New eligible accounts then inherit
the global setting. For staging, enable only the validation accounts initially.
Before deploying this change to the existing staging setup, enable the flag for
`kura-spec95-e2e` and `kura-spec95-health` if those fixtures should remain active;
the old environment allowlist is no longer read. Without those actor gates,
reconciliation will safely withdraw their existing stable records.

Disabling an account flag stops hand-out and withdraws its advertising through
the existing provider-confirmed drain. Follow the rollback ordering below for
clients with persisted URLs. Disabling the global boolean alone does not revoke
explicit actor enables; remove all enabling actor/group/percentage gates as
well when rolling back every account. Canary activation is automatic and does
not consult the flag; reverting canary requires a code/configuration rollback.

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
8. In staging, enable `kura_stable_hostname` through `/ops/flags` for the selected
   validation account actors. Use the same account-level opt-in for the initial
   production cohort. Canary is automatically enabled. No separate advertising,
   hand-out, or account-list environment variables are needed.
9. Reconciliation publishes intent and waits for DNS/TLS readiness before
   returning the stable hostname. A response collapses only when every desired
   region is active and every advertising managed region has fresh,
   generation-matched controller readiness. Self-hosted registrations and
   eligible custom endpoints remain alongside the managed stable name. After
   validating the initial production cohort, enable the same flag globally.

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

An identity whose target was never persisted cannot have published a DNS source
and clears immediately. Once publication was possible, provider failures keep
the withdrawal barrier in place while normal public workload repairs continue.

Health checks use standard 30-second TCP probes on port 443, three failures,
shared per box and cluster. They do not promise failover within a single second
or detect a broken account on a healthy box. Route53 skips unhealthy records
and fails open if every record is unhealthy. A five-minute, leader-only sweep
removes this cluster's unreferenced checks after both provider records and
persisted instance state release them, including orphans from interrupted creates.

Readiness is projected into PostgreSQL `kura_servers.stable_endpoint`, shared
between the reconciler and all web replicas without requiring Redis. It retains
the controller's timestamp and expires after three minutes, with a 30-second
tolerance for an observation ahead of the server clock. Re-reading
frozen status does not renew it; absent or stale evidence restores regional
responses. Archival and cold return clear it. The additive nullable column needs
no backfill: the next reconciliation populates it. DNS and readiness state are
documented in `server/data-export.md`.

Stable intent synchronization uses eight concurrent workers with bounded reads,
and unchanged projections do not rewrite rows. Endpoint resolution reuses the
managed-server query's readiness fields and evaluates the account flag once.
Custom URLs join a stable response only after the stable hostname is actually
selected, preserving archived-account provisioning and legacy fallback.

## Client selection contract and follow-up cleanup

**Hold the client follow-up merge and all client releases until the parent
stable-hostname feature has rolled out globally in production and been
verified.** Canary success, a selected production cohort, or merely enabling
the global flag does not satisfy this hold. Record production DNS/TLS readiness,
native-client behavior across serving regions, mixed endpoints, and rollback
checks in the follow-up PR before lifting it. This is a release condition, not
a new client feature flag.

The endpoint API returns an **unranked** list. It replaces supported managed
regional URLs only after readiness converges; unsupported placements, enrolled
self-hosted nodes, and eligible custom URLs can still accompany the stable URL.
Stale/missing readiness restores regional URLs, and older/self-hosted servers
retain their existing response shape. No hostname suffix or first array element
establishes a preference among multiple URLs.

| Response/configuration | Client selection |
| --- | --- |
| `TUIST_CACHE_ENDPOINT` override | Use it directly; do not query or rank API endpoints. |
| One stable managed URL | Use it without a latency probe; DNS chooses the serving region. |
| One regional, custom, or self-hosted URL | Use it directly, preserving the existing single-endpoint behavior. |
| Several regional URLs, including readiness fallback/rollback | Keep client latency selection among reachable endpoints. |
| Stable URL plus unsupported/custom/self-hosted URLs | Keep all alternatives eligible and retain latency selection. |
| Empty response | Preserve provisioning waits and the existing local-cache/error behavior. |

Swift's shared `CacheURLStore` covers module caching, Xcode setup/proxy startup,
and Bazel setup/credential refresh. Gradle follows the same singleton versus
multiple-endpoint rule. These singleton fast paths predate the follow-up: there
is no remaining managed-region latency race to delete for a stable-only answer.
The follow-up keeps compatibility selection and makes `tuist cache config`
return its choice and endpoint list from **one fresh API response**. Previously
it selected a URL (possibly cached) and fetched the list independently; a
readiness change between requests could report a regional choice with only the
stable URL in its list, or vice versa. The proxy uses list membership to detect
withdrawal, so those fields must describe the same observation. This does not
make API reads atomic with subsequent DNS or control-plane changes.

No new server capability is required for this cleanup. Removing the remaining
multi-endpoint probe would require an explicit server-selected endpoint or an
ordered failover contract that defines custom/self-hosted preference and
reachability fallback. It would still need a compatibility path for servers
without that contract. Returning the stable URL first is insufficient, and
silently preferring it could bypass a faster or uniquely reachable private
cache. Global production activation alone cannot remove that prerequisite.

The CAS plugin delegates URL selection to the CLI via its proxy; it has no
separate latency selector to remove. Keep periodic endpoint refresh, the
reachability check and confirmation for competing choices, transport retries,
and reconnect-time DNS resolution. A sole stable URL replacing a regional URL
(or the reverse on rollback) moves immediately when the old URL disappears
from the returned list. An unchanged stable URL retains existing channels;
DNS steering affects new connections, not healthy established ones.

Bazel must persist the hostname in `.bazelrc.tuist`, including for its remote
downloader. Its REAPI capability check validates usability and is not a latency
ranking probe. Keep credential-helper refresh for rollback and regional
fallback; rewritten configuration takes effect on a later Bazel invocation.
Preserve user overrides, custom downloader settings and local fallback.

The follow-up changes no endpoint API schema, DNS configuration, flags, retry
policy or cache format. Client rollback needs no data migration. Server rollback
must still retain stable DNS while already-configured clients refresh, as below.
Local selection tests do not extend the parent PR's staging evidence: the
recorded gateway recovery, steering anomalies, and native SDK/large-transfer
limitations remain in the linked validation record.

## Rollback

Disable `kura_stable_hostname` for the affected account. This immediately stops
new stable URL hand-out once the flag change reaches each server and requests
DNS withdrawal on the next reconciliation. There is no separate hand-out-only
switch. Coordinate refresh of persisted client endpoint configuration before
withdrawing stable URLs: the drain protects existing connections and cached
answers for a bounded period, not indefinitely saved configuration.

For a full staging/production rollback, disable the global flag and remove any
enabling actor, group, or percentage gates; a false global gate alone does not
override explicit actor enables. Canary remains automatically enabled and needs
a code/configuration rollback instead. Leave the controller, AWS writer, zone
delegation, credentials and solver running. The controller retains the old name
from status until each regional record is observed absent and its drain elapses.
Confirm there are no stable DNSEndpoints, provider A records, retained stable
status, or owned health checks before disabling the writer/provider. Do not
remove finalizers, delete the zone, or remove AWS credentials to force a rollback.
Regional names remain available throughout.

Existing account handles ending in `-staging` or `-canary` are not silently
renamed: they stay on regional endpoints. New names/renames with those suffixes
are rejected case-insensitively. Audit and resolve any existing collisions before
enabling their stable lane.

Email-derived signup handles that would use a reserved suffix receive a numeric
suffix through the existing collision retry path; explicit handle requests
remain subject to validation.

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

## Staging validation tools and evidence

The initial rollout used purpose-built HTTP/REAPI round-trip and persistent-
connection probes restricted to the spec 95 staging fixture. They are not runtime
or CI dependencies and are not maintained in this tree. Their sources and usage
remain available at the [validation tooling revision](https://github.com/tuist/tuist/tree/9e8963e9a0052b925609838c3b5b9d4acceecfa9/infra/cache-dns/probes)
and its [runbook](https://github.com/tuist/tuist/blob/9e8963e9a0052b925609838c3b5b9d4acceecfa9/infra/cache-dns/README.md#repeatable-staging-probes).
If repeating those experiments, use a separate checkout of that revision, verify
that the fixture still exists, and supply a fresh project-scoped token; recorded
hosts and IPs describe the original setup. Keep TLS verification enabled and
credentials out of command arguments and logs. Protocol probes complement real
client builds rather than replacing them.

See [the staging validation record](https://github.com/tuist/tuist/blob/0e7cc8d2dcce18012377f3d6efa9656b1e23b17e/infra/cache-dns/staging-validation.md)
for completed checks, exact deployment revisions, and coverage limits.

## Staging validation checklist

These live checks are separate from local tests. See the
[validation record](https://github.com/tuist/tuist/blob/0e7cc8d2dcce18012377f3d6efa9656b1e23b17e/infra/cache-dns/staging-validation.md) for completed runs and remaining
coverage limits; the checklist is also the procedure for repeating them.

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

Health-check creation uses a fresh caller reference after collection. Route53
retains deleted references for several days, so a cold return cannot recreate
one using only its deterministic box identity. Existing legacy checks remain
adoptable; uncertain create retries retain their reference to avoid duplicates.

### Gateway outage and steering checks

For outage validation, keep authenticated HTTP/1.1 and HTTP/2 REAPI connections
alive across the failure, verify downloaded bytes, and record connection reuse,
remote addresses, and recovery time without restarting the clients. Use ordinary
DNS and verified TLS. For steering comparisons, pair system and authoritative DNS
answers with fresh TCP/TLS `/up` timings to each serving region. Distinguish these
measurements from historical native-client telemetry and bound the experiment's
duration. The archived tools above implement the original staging experiment.

Before a gateway drill, inventory every Ingress and KuraInstance on its ingress
class and every DNS record referencing its health check. A fixture-only gateway
can be temporarily unscheduled; leave shared gateways serving unrelated accounts
alone. Save its template, arrange a bounded restoration watchdog, shorten only
the affected pod's shutdown grace to break existing connections, and restore
only the injected selector. Require a Ready survivor and healthy DNS records
before starting. Record actual health/DNS transitions and unchanged-process
recovery, then verify gateway readiness and restored health. Never treat a
health-check configuration fault as proof of actual gateway recovery.

For latency comparisons, inspect probe CPU-throttling counters before interpreting
results. The initial 200m staging probe ceiling throttled fresh TLS handshakes;
independent probes with a one-core ceiling removed that confound. Retain the
original series when refining the sampling method, including mismatches.
