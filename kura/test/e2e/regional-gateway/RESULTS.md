# Staging regional gateway experiment — 2026-09-10

Follow-up: [longer, warmed paired comparisons](SUSTAINED_RESULTS.md) investigate
whether the short-burst throughput difference below persists. Do not use the
6–12% figure as a fixed gateway capacity penalty.

The basic routing model worked: two TLS gateways routed two account hostnames
to separate standalone Kura backends. Moving the gateway off the backend node
added approximately 0.4 ms to small-request median latency in this experiment.
Large downloads reached approximately 900 Mbps on both paths. Concurrent
256 KiB transfers lost approximately 6–12% throughput with the extra hop.

These results support trying a single regional gateway. They do not establish
the required gateway machine size or validate a 10/25 Gbps private network.

## Placement and controls

- Staging Kubernetes v1.34.6, Cilium VXLAN tunnel routing.
- Nodes A and B: the two 4-vCPU staging general-purpose workers in Hetzner
  `fsn1-dc14`. Both already carry staging workloads; neither was dedicated to
  the experiment.
- Node C: the staging Hetzner bare-metal ClickHouse node, running only the
  isolated load-generator pod for this experiment. The ClickHouse deployment
  and data were untouched. This was a third host in the same region, not a
  proven identical-rack or private-network connection.
- Kura image `ghcr.io/tuist/kura:sha-4fbea0289708`, resolved digest recorded in
  [metadata.json](results/2026-09-10/metadata.json).
- Gateways used `nginx:1.27.3-alpine` with the same TLS certificate, HTTP/2
  settings and routing config. The client explicitly trusted the test CA.
- Node A held gateway A and backend A; node B held gateway B and backend B.
  Run A targeted backend A; run B targeted backend B. Each run tested the local
  and remote gateway paths in alternating order across three rounds.
- Client traffic used the pod network directly. Kubectl carried commands and
  results, not benchmark payloads.
- Every container had a 2-core CPU limit. Backend memory was capped at 2 GiB,
  gateway memory at 256 MiB, and client memory at 1 GiB. Backend data was in
  temporary emptyDirs on the workers' root disks, not the production NVMe layout.

## Completed measurements

The table reports medians of the six case results (three rounds on each
backend placement). Mbps means decimal megabits of successful payload per
second. Latency is the median of the per-case p50 values, not a pooled request
percentile. Read payload integrity was checked against both length and SHA-256.
Writes used unique, incompressible data prepared outside the timing window.

| Protocol | Operation | Size / concurrency | Local gateway | Remote gateway | Change |
| --- | --- | --- | ---: | ---: | ---: |
| gRPC | Read latency | 4 KiB / 1 | 1.078 ms | 1.484 ms | +0.406 ms |
| HTTP/2 | Read latency | 4 KiB / 1 | 1.079 ms | 1.525 ms | +0.446 ms |
| gRPC | Read throughput | 256 KiB / 8 | 842.6 Mbps | 792.3 Mbps | −6.0% |
| HTTP/2 | Read throughput | 256 KiB / 8 | 850.3 Mbps | 789.0 Mbps | −7.2% |
| gRPC | Write throughput | 256 KiB / 8 | 745.9 Mbps | 698.4 Mbps | −6.4% |
| HTTP/2 | Write throughput | 256 KiB / 8 | 826.3 Mbps | 724.1 Mbps | −12.4% |
| gRPC | Read throughput | 8 MiB / 4 | 899.9 Mbps | 898.0 Mbps | −0.2% |
| HTTP/2 | Read throughput | 8 MiB / 4 | 899.0 Mbps | 898.3 Mbps | −0.1% |
| gRPC | Write throughput | 8 MiB / 4 | 602.0 Mbps | 573.0 Mbps | −4.8% |
| HTTP/2 | Write throughput | 8 MiB / 4 | 841.4 Mbps | 862.4 Mbps | +2.5% |

The small-request latency penalty was positive in both placements: gRPC
approximately +0.59 ms / +0.17 ms; HTTP/2 +0.59 ms / +0.30 ms. The difference
between placements shows why a single topology should not be treated as an
exact physical-hop latency measurement. The HTTP/2 large-write improvement is
measurement variability or resource/path interaction, not evidence that a
network hop improves performance.

There were **120 timed cases and 8,640 timed requests, with zero request errors**.
Run B also wrote different bytes under the same key in the two accounts and
verified both values through both gateways. This passed, demonstrating that
the routing configuration kept their backends separate. Both runs completed
gRPC smoke checks of the second hostname through both gateways. This is not a
test of production authorization; only the isolated backends had auth disabled.

## Proxy resource use

- Gateway container peak cgroup memory: approximately **26–28 MiB**.
- Highest metrics-server sampled gateway CPU: approximately **0.20 cores**.
- No CPU quota throttling was recorded for any benchmark container in either
  completed run (`nr_throttled` and `throttled_usec` remained zero).

CPU samples cover windows containing idle time as well as transfers. They do
not establish peak packet-processing capacity, and Cilium's host CPU is not
included in gateway container CPU. Memory was measured with at most eight
concurrent requests and two account routes; connection-heavy fleet traffic
would need a separate test. These measurements support modest proxy memory
requirements at this tested load, not a production RAM sizing guarantee.

## Limits and next deployment decision

The approximately 900 Mbps download plateau is consistent with a roughly
1 Gbps path ceiling, but this experiment does not independently identify the
limiting link. It cannot reveal throughput differences beyond that ceiling.
The short transfer batches measure build-cache bursts rather than sustained
multi-minute saturation; large-object tail percentiles have only 16 samples
per case and are not statistically stable.

This validates the static account-routing data path and its measured overhead
on staging's overlay. Before purchasing hardware, repeat on a same-provider
private-network pair with a faster load generator, representative connection
counts, and simultaneous replication/recovery traffic. Validate the actual
gateway implementation, account-to-primary updates, peer mTLS, public wildcard
DNS/certificates, bandwidth admission/shaping, and single-gateway recovery
separately. No production configuration or endpoint was changed here.

## Preliminary run and cleanup

An earlier attempt placed the client in France and found a roughly 5 ms WAN
route difference between the gateway nodes. It also caught a prototype
configuration error: sharing an upstream keepalive pool between HTTP/1 and
h2c caused an invalid HTTP response. The harness now uses separate pools.
That incomplete attempt was cleaned up and is excluded from the results above.

Both completed runs removed their five pods, two Services, ConfigMap, disposable
TLS Secret and NetworkPolicy. A subsequent query found no benchmark resources,
and every staging node remained Ready. No existing persistent cache data was
modified.

The [runner and reproduction instructions](README.md),
[raw run A](results/2026-09-10/a-results.jsonl),
[raw run B](results/2026-09-10/b-results.jsonl), and
[machine-readable summary](results/2026-09-10/summary.json) are retained with
the cgroup counters and CPU/memory samples. Private keys are not retained in
the repository. Validation included Linux client compilation, Go vet, Python
syntax/render checks, and the completed staging experiments.
