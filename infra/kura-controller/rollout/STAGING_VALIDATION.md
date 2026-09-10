# Regional routing staging validation — 2026-09-10

This validates the controller/DNS migration on the managed staging ingress,
separately from the [transport benchmark](../../../kura/test/e2e/regional-gateway/SUSTAINED_RESULTS.md).
Server/controller image: `sha-df547b9af8ed`. Kura runtime was held at
`sha-4fbea0289708` (0.8.0) throughout. The final deployment uses chart/workflow
commit `bbe8532078` with those prebuilt images.

[The final staging deployment](https://github.com/tuist/tuist/actions/runs/34523092067)
passed: preparation revision 694, eight serving-path probes across four public
accounts, then publication revision 695. The server publication map contains
EU West, and both server-managed public accounts converged to canonical
HTTP/gRPC hosts with all replicas Ready at the current revision. The gate also
confirmed that canonical names had no individual DNSEndpoint records, including
the fresh fixture.

Subsequent gate-only hardening made the TLS 1.2 minimum explicit and limited
plan parsing to validated Kubernetes resource names and routing metadata.
Both remaining staging accounts passed public and peer TLS probes again with
that minimum; the gate suite now has 13 passing tests.

## Fixtures and method

Two disposable, authenticated accounts were used. One began with legacy public
and peer hostnames and had two replicas on different machines. The second was
created with canonical regional names and never had a legacy hostname. It had
one replica. Their control-plane registration was disabled; JWT authorization
and account-scoped peer mutual TLS remained enabled.

A temporary second ingress process on an existing general worker exercised
multiple public addresses without buying machines. The original ingress was
kept running. Every HTTP/2/gRPC matrix case used 16 operations, four concurrent
requests and 256 KiB payloads; reads verified their size and SHA-256 content.
The benchmark client's untimed seeding is outside the request counts below.

These are functional checks from a workstation, including a deliberately
remote backend. Their WAN timings do not measure the cost of a regional hop.

## Results

| Scenario | Counted operations | Errors |
| --- | ---: | ---: |
| Legacy HTTP/2/gRPC reads and writes through two ingress addresses | 128 | 0 |
| Legacy traffic after the primary moved to another machine, with DNS unchanged | 64 | 0 |
| Regional aliases before canonical migration, including the fresh account | 192 | 0 |
| Legacy and regional traffic after canonical migration | 192 | 0 |
| Final legacy/regional/fresh-account matrix through both ingress addresses | 384 | 0 |
| gRPC writes with normal ingress connection recycling | 4,096 | 0 |
| gRPC reads with normal ingress connection recycling | 4,096 | 0 |
| HTTP/2 reads with normal ingress connection recycling | 4,096 | 0 |
| Deliberate primary restart during gRPC reads, without retries | 10,000 | 259 |

The matrices total **960 operations with no errors**. The steady connection
recycling checks total **12,288 operations with no errors**. Counts extracted
from the client output are in [staging-results.json](staging-results.json).

The deliberate restart returned `UNAVAILABLE: server is draining` for 259
requests; 9,741 succeeded. The primary changed machines and DNS stayed stable.
This exercises the existing runtime drain behavior: stable DNS does not make
a primary restart error-free, and callers need retries for interrupted work.
An earlier uncounted read attempt coincided with a CPU autosizing roll; its
output was not retained, so no failure count is claimed for that attempt.

Additional checks:

- Both legacy and regional peer SNI names served the expanded certificate,
  authenticated the intended account, and transferred a 256 KiB artifact.
  A missing client certificate and another account's client certificate were
  rejected. Fresh-account peer routing passed independently.
- Missing/invalid JWTs, account-scope mismatches, and valid tokens directed at
  another account's backend were rejected. Four cross-account gRPC writes
  were rejected through both ingress addresses. Internal peer routes were
  unavailable on the public HTTP endpoint, and unknown SNI was rejected.
- The migrated account retained its old public and peer alias arrays after
  switching its canonical specification. The fresh account's arrays stayed
  empty. Removing the temporary ingress withdrew its public address from DNS.
- One HTTP/1.1 diagnostic probe received an unexpected HTTP/2 frame. It did
  not recur in 128 follow-up checks, split equally between no ALPN and explicit
  HTTP/1.1 negotiation. The final authorization checks with explicit HTTP/1.1
  negotiation also passed. The cause was not isolated; this is not counted as
  a successful initial probe. The deployment probe now advertises its HTTP/1.1
  protocol explicitly and reports hostname/address context on network errors.

## Fixes and gate behavior established during deployment

1. Updating a Kubernetes-mounted peer Secret did not update the certificate
   served by Kura. Hashing the leaf in the StatefulSet template triggered a
   normal roll; the actually served old/new SANs were then verified. Enrollment
   certificate reload does not watch the Kubernetes-mounted files.
2. An issuer rate limit blocked the expanded public wildcard certificate. The
   gate retained legacy URL publication until renewal succeeded after the
   permitted retry time. TLS verification was never disabled.
3. The upstream EU-region rename migration collided with an existing canonical
   daily storage rollup. The corrected sweep retained canonical aggregates,
   renamed non-conflicting rows, passed temporary PostgreSQL regression checks,
   and then completed on staging.
4. CI runner egress allows public HTTP(S), but excludes peer port 7443. Peer
   checks therefore run in one bounded, unprivileged Job in the target cluster,
   against public peer addresses and SNI. The Job passed both fixture checks
   and was deleted. It receives only leaf credentials through exec stdin and a
   memory volume; it has no service-account token. Public checks remain in CI.
5. Preparation for a later region preserves the already-published subset.
   Unit and rendered-manifest checks cover empty, partial and full publication,
   and reject unknown region names. Adding a region must not recreate legacy
   records for accounts already using canonical endpoints.

## Cleanup

Both disposable KuraInstances, their three pods and PVCs, underlying volumes,
JWT signing Secret, peer leaves and account CA Secrets were removed. Temporary
ingress and placement labels were removed, and the original ingress selector
and update strategy were restored. No validation Job remained. The two
server-managed staging accounts were rechecked after cleanup: both retained
canonical URLs, complete workload revisions, verified public TLS and working
peer mutual TLS. Local copies of test credentials were removed.
