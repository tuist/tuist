# Spec 95 staging validation — 2026-09-22

Status: inert staging rollout and regional regression checks passed; stable DNS
validation is blocked on AWS access.
This is not evidence that Route53 steering or the stable hostname works yet.

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
  Stable DNS, advertising, and hand-out remain disabled.
- The earlier run 35764868105 failed at checkout because its commit input was
  abbreviated. It performed no deployment.
- No canary or production deployment was dispatched.

## Fixture and evidence

The dedicated staging organization is `kura-spec95-e2e` (account 49), with project
`probe` (46). A project-restricted account token with cache write scopes expires
24 hours after creation. It is held only in a local file with mode `0600`; the
probe passes it to curl through stdin and to grpcurl through the subprocess
environment, never through command arguments or evidence logs.

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
[`staging_probe.py`](staging_probe.py), using [`reapi-smoke.proto`](reapi-smoke.proto).

## Completed baseline checks

Controller validation was repeated on the newer staging integration revision:
`go test -race ./...` passed in `infra/kura-controller`, including the Helm
rendering tests with `TUIST_TEST_HELM` set. The probe's Python syntax and protobuf
schema also validated, and its staging-only hostname guard rejected a production
hostname before making a request.

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

## Blocker and remaining work

`cache.tuist.dev` has no delegated nameservers. The local AWS CLI has no configured
credentials, and the two existing AWS access-key items in 1Password both failed
STS identity checks. Working access to the dedicated DNS account is required to
create the zone and three scoped runtime identities, following [bootstrap](README.md#bootstrap-operator-step-not-performed-by-local-validation).
Secret values must stay in the CLI credential store or 1Password.

After access is available:

1. Provision/delegate the zone, synchronize separate writer/solver/controller
   credentials, and issue the wildcard certificate. Arrange read access to the
   test fixture's DNSEndpoint sources for inspection.
2. Enable advertising only for `kura-spec95-e2e`; keep hand-out disabled. Verify
   direct stable SNI, both regional latency records, ownership, health checks,
   readiness observations, and authenticated HTTP/gRPC traffic on both boxes.
3. Compare DNS steering from both regions with client probe choices. Prove that
   primary demotion leaves records unchanged while traffic continues.
4. Exercise withdrawal, stalled writer, failed provider reads, controller restart,
   and deletion. Keep the full 3720-second post-observed-withdrawal drain. Verify
   surviving DNS/routing continuously and teardown only after the barrier.
5. Exercise health-check failover with an isolated test target or a coordinated
   shared-gateway drill; the existing gateways serve other staging accounts.
6. Enable hand-out for the test account, then validate real client configuration,
   persisted Bazel endpoints, CAS proxy recovery, and staging CI soak.

The fixture remains available for continuation. When validation ends, revoke the
token, clear keep-warm, and remove only this account's test placements through the
normal lifecycle. If stable advertising has been enabled, complete withdrawal and
the drain before removing provider credentials or DNS resources. Do not strip
finalizers to force cleanup.
