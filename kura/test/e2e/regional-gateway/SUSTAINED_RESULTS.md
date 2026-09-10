# Longer staging gateway comparison — 2026-09-10

The extra node hop added **0.50–0.55 ms** to small-request median latency, but
the earlier **6–12% medium-transfer throughput penalty did not persist** in
longer, warmed transfers. Both paths delivered approximately 900 Mbps. Across
eight paired repetitions per workload, medium-read throughput changed by
−0.33% for gRPC and −0.02% for HTTP/2; upload differences were small and changed
sign between placements. This supports budgeting for extra latency, without
assuming a fixed 6–12% reduction in sustained bandwidth.

This follow-up tests whether the 6–12% medium-transfer throughput difference
in [the original short-burst experiment](RESULTS.md) persists with longer,
warmed batches. It compares a proxy sharing the backend's node with an
identically configured proxy on another node. Both paths already include a
proxy and TLS termination; this is not a direct-to-Kura versus proxy comparison.

## Completed results

**128 timed cases, 328,192 requests, 80.244 GiB of timed payload, zero request
errors**, plus warm-up traffic. Each workload has eight local/remote pairs:
four rounds on each backend placement. All read responses passed size and hash
verification. Both initial account-routing checks and final gRPC smoke checks
passed. The failed connection-recycling attempt described below is excluded.

Throughput is successful payload in decimal Mbps. Local and remote columns are
medians across cases. Change and interval columns use paired percentage changes.

| Protocol | Workload | Local Mbps | Remote Mbps | Paired median change | Exploratory 95% interval |
| --- | --- | ---: | ---: | ---: | ---: |
| gRPC | 256 KiB read, concurrency 8 | 900.98 | 897.94 | −0.33% | −1.04% to −0.01% |
| HTTP/2 | 256 KiB read, concurrency 8 | 899.44 | 898.68 | −0.02% | −0.10% to +0.00% |
| gRPC | 256 KiB write, concurrency 8 | 893.91 | 892.86 | +0.51% | −1.93% to +1.82% |
| HTTP/2 | 256 KiB write, concurrency 8 | 893.20 | 899.72 | +0.73% | −0.68% to +2.61% |
| gRPC | 8 MiB read, concurrency 4 | 867.56 | 875.52 | +1.09% | −2.93% to +3.72% |
| HTTP/2 | 8 MiB read, concurrency 4 | 867.75 | 866.87 | −0.17% | −3.52% to +3.74% |

Individual medium-transfer paired differences ranged from −2.20% to +2.74%,
across both protocols and directions. Positive changes do not imply that the
extra hop improves networking. For example, median gRPC upload change was
positive in placement A and negative in placement B. Gateway/client paths and
shared-host resource interactions remain part of this experiment.

| 4 KiB reads, concurrency 1 | Local p50 | Remote p50 | Median paired increase | Paired increase range |
| --- | ---: | ---: | ---: | ---: |
| gRPC | 0.892 ms | 1.443 ms | +0.546 ms | +0.419 to +0.602 ms |
| HTTP/2 | 0.970 ms | 1.420 ms | +0.498 ms | +0.338 to +0.690 ms |

These are medians of per-case p50 values, not pooled request percentiles.
The latency increase was positive in every small-read pair. Serial small
requests consequently lost approximately 34–36% throughput in this low-latency
test: a roughly half-millisecond delay matters considerably when the original
request takes about one millisecond. Throughput cost depends on object size,
concurrency and traffic pattern; it is not one percentage for every workload.

Interior-second throughput agrees with the whole-batch measurements. For
256 KiB gRPC reads it was 901.25 versus 899.28 Mbps; for HTTP/2 reads, 899.55
versus 899.28 Mbps. Excluding the start and end of the timed batch does not
reveal the earlier 6–12% gap.

## Resource and transport observations

- Gateway cgroup peak memory ranged from **18.2 to 30.7 MiB**.
- Highest metrics-server sampled gateway CPU was **0.73 cores**. The longer
  batches provide a more useful CPU observation than short bursts diluted by
  idle time in a sampling window; this still does not measure peak capacity.
- The client used at most **0.49 CPU cores** during a timed batch.
- No client, gateway or backend CPU quota throttling was recorded in any
  measured case. Both metrics collection runs completed without errors.
- TCP retransmissions occurred on both paths. The largest per-case
  retransmitted/outgoing segment ratio was 0.022% for a gateway and 0.411% for a
  backend. These are transport counters, not independently measured packet-loss
  rates, and do not establish the cause of the original burst gap.

There is no evidence of client CPU saturation or container CPU quota throttling
at this tested rate. This does not exclude host networking costs or establish
headroom at higher link speeds. Memory was tested with only two routes and at
most eight concurrent requests, not a fleet-sized connection population.

## Method

The same two Hetzner general-purpose staging workers host the two gateways and
temporary Kura backends. The load generator remains on the third, bare-metal
staging node. Each placement has four rounds, with the backend moved from A to
B between runs. Workload order is shuffled deterministically, and each local
versus remote pair alternates which path runs first. Placements run sequentially.

Compared with the original experiment:

- 256 KiB batches grow from 64 to 4,096 requests: 16 MiB to 1 GiB each.
- Small 4 KiB reads grow from 200 to 2,000 requests.
- Large 8 MiB reads grow from 16 to 64 requests: 128 MiB to 512 MiB each.
- Each case has 128 warm-up requests at its measured concurrency.
- Client and server TCP/CPU counters accompany individual cases, and the client
  records completed requests per second.

Read data is seeded and warm, with length and SHA-256 checked on every request.
Writes use one incompressible random buffer per worker, with a newly randomized
prefix and SHA-256 per request. This keeps memory bounded and hashes unique.
Fixture preparation is included in batch elapsed time but excluded from
individual RPC latency. The temporary backend is recreated before every write
case; its data is in an emptyDir. This experiment does not measure cold disk
performance or sustained disk flush capacity.

Each client invocation uses one warmed HTTP/2 connection. Both gateways use
`keepalive_requests 10000` for this profile, above the largest case including
warm-up. TLS, routing, upstream pools, window settings and resource limits are
otherwise the same between paths. gRPC uses h2c upstream; HTTP/2 requests use
HTTP/1.1 upstream, matching the prototype's separate protocol pools.

## Interpretation and limits

Compare paths within the same backend placement, round, protocol and workload.
The summary reports the median of those paired percentage changes. This can
differ from dividing the independently computed local and remote medians.
Bootstrap intervals resample the eight whole pairs, not individual requests.
They are exploratory: shared staging load, machine differences and topology
bias are not fully represented by a small-sample statistical interval.

Client counter windows enclose only the timed batch. Gateway/backend counter
windows also include warm-up and kubectl command overhead. CPU counters exclude
the host's networking work. Retransmission counts cover each pod's TCP traffic;
gateway counters do not distinguish its client-facing and upstream legs.
Interior-second throughput excludes the first second and final partial second.

The approximately 900 Mbps ceiling of this staging path can hide differences
in maximum gateway capacity above that rate. These longer batches are still
seconds-long experiments, not multi-minute saturation or a production soak.
The comparison does not validate a dedicated 10/25 Gbps private network,
thousands of connections, cold NVMe reads, replication/recovery traffic,
production host-network ingress or gateway failover.

The original short-burst results may still be relevant to bursty build traffic.
This rerun changed both warm-up and batch duration and ran at a different time;
it does not identify the exact share of the earlier difference attributable to
TCP startup, HTTP/2 flow control, scheduling or staging variation. A controlled
warm-up/batch-size sweep would separate those effects. Before sizing hardware,
repeat on the intended private network with a load generator capable of
exceeding the target gateway rate and representative build traffic.

## Connection recycling found during setup

The initial extended attempt used the prototype's default client-facing nginx
keepalive limit. Its first 4,096-request gRPC upload case had 15 failures, with
the first reported error `Unavailable: the connection is draining`. That
attempt is excluded from successful throughput comparisons.

Nginx defaults to closing a keepalive connection after 1,000 requests; see the
[nginx keepalive documentation](https://nginx.org/en/docs/http/ngx_http_core_module.html#keepalive_requests).
The revised experiment raises this limit identically on both paths so each
case measures a stable, warmed connection. This is an experiment control, not
a production fix. Graceful connection recycling, GOAWAY handling and retries
for interrupted streaming writes require a separate reliability test before
shipping the gateway design.

## Reproduction and cleanup

See [the runner instructions](README.md), [paired analyzer](analyze.py),
[raw A measurements](results/2026-09-10-sustained/a-results.jsonl.gz),
[raw B measurements](results/2026-09-10-sustained/b-results.jsonl.gz), and
[summary](results/2026-09-10-sustained/summary.json). Raw files retain per-case
TCP/cgroup snapshots and completion buckets. Compressed case details, resource
samples, resolved image digests, parameters, and the excluded-attempt record
are retained alongside them. Gateway configurations matched after normalizing
the unique run IDs. TLS private keys and Secret manifests are excluded.

Both successful runs and the initial failed attempt removed their temporary
resources. The final cluster query found **zero benchmark resources**, and all
**15 staging nodes were Ready**. Existing persistent Kura data, production
configuration, DNS, and account endpoints were untouched.

Validation included Linux/amd64 client compilation, Go vet, Python syntax and
counter-parser checks, runner context/workload guards, compressed-archive
analysis, complete-pair/request-count checks, both staging matrices, and final
resource cleanup verification.
