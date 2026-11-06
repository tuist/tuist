# Provider topology resource comparison

Build the merge-base and changed images first, then run these sequentially on
the same otherwise idle host with Node.js, OpenSSL and Docker on PATH:

```sh
KURA_RESOURCE_METRICS_SOURCE=/path/to/baseline/kura/src/metrics.rs KURA_RESOURCE_OUTPUT=/tmp/topology-before node test/e2e/provider-topology/resources.mjs before kura:baseline
KURA_RESOURCE_METRICS_SOURCE=/path/to/candidate/kura/src/metrics.rs KURA_RESOURCE_OUTPUT=/tmp/topology-after node test/e2e/provider-topology/resources.mjs after kura:after
node test/e2e/provider-topology/summarize.mjs /tmp/topology-before /tmp/topology-after
```

The harness creates three disposable containers with distinct origin regions,
two providers, real peer mTLS, and separate private DNS aliases. The baseline
receives the same environment and ignores the new optional topology field.
Each container has one CPU, a 1.5 GiB cgroup limit and a 3 GiB cache capacity.
It reserves loopback ports 4291–4293 and 5291–5293, uses a disposable Docker bridge
and removes only its own randomly named containers/network. Keep the
output directories distinct and empty: each contains synthetic private keys
as well as resource traces. Never upload an entire output directory.
Keep these generated files out of the repository. Record measured results and
limitations in the associated PR, then remove the temporary output directories
when they are no longer needed.

The corpus is 64 seeded and 256 subsequent distinct, incompressible 1 MiB objects, written
round-robin across all three origins. Every seed must replicate byte-for-byte
to all nodes before load begins. The load offers four writes/second and four
verified reads/second per node for roughly 64 seconds, extending when writes
cannot keep pace. It also performs 1,280 full inbound peer-mTLS connections at
20/second, refusing resumed sessions. After a 30-second cooldown all 320
objects must still read byte-for-byte on all three nodes. Another 30-second
cooldown measures recovery after those final reads.
`result.json` records completed work, failures, process CPU ticks, disk size,
anonymous memory and network counters. Every node's `/metrics` is scraped at
two-second intervals throughout seeding, load and cooldown.

The summary writes `summary.json` and aggregates simultaneous memory samples across all three nodes,
reports peak and cooldown values, uses the doubled `_total_total` counters,
and normalizes CPU to completed client bytes. New runs record phase boundaries,
per-node memory peaks, 192 successful seed probes/192 MiB and failed probes by
status. Legacy/unsampled phase measurements stay null with distinct status reasons;
legacy probe statuses stay null. Phase edges are approximate to one two-second
scrape and the anonymous-memory gauge can additionally be about one second stale.
Do not attribute a cost from these asynchronous readings alone. Prometheus omits unused labeled
counter families entirely, including their TYPE lines. Only pressure transitions, artifact egress
and segment refresh may start empty, after verifying their `Family<..., Counter>`
declarations and unconditional registrations in the exact built `metrics.rs`.
The result records that source hash/schema. Arbitrary missing metrics still
fail; never substitute zero for an unknown gauge or renamed counter. The runtime has no CPU-seconds
metric, so `/proc/<kura-pid>/stat` supplies that measurement. Interface transmit
bytes include mTLS, ACKs, probes, metrics scrapes and metadata. The summary
counts stored exposition body bytes within the interface-counter window
(samples 1 onward, excluding sample 0 before the baseline); comparison shows both raw transmit
and transmit minus those bodies. This is body-only accounting: HTTP/TCP/IP
overhead and scrape CPU remain included. It is not full observer-cost removal;
 client egress and peer applied
payload counters are reported separately. Disk reports both apparent and allocated bytes, including metadata and segments;
refresh bytes show write amplification beyond the client and replicated corpus.

`compare.mjs before-1 after-1 after-2 before-2` compares summaries in ABBA
order, accepting one to three complete blocks. The workflow's bounded
`resource_repetitions` choice defaults to one; use three for additional
variation/phase investigation without rebuilding between blocks. All runs are
included, never selected by outcome. Unequal successful work/application egress
or missing/nonfinite measurements refuse. Convergence retries are measured axes,
not equality filters: the candidate may itself change convergence time. Report
all attempt/byte pairs and available status details, including every failed
probe's CPU and traffic cost. Comparison reports every delta and the complete
baseline range, plus every block's delta/range and sign agreement. Wider pooled
ranges are not stronger statistical evidence; a pooled **or any per-block**
increase beyond its spread remains flagged. Summary labels, image IDs and metrics
source hashes must identify stable variants in exact ABBA order. Raw phase/per-node
peaks are included without a verdict. Positive flags require investigation,
not an automatic budget waiver. See the
build-only [`certificate-trust` workflow entry point](../certificate-trust/AGENTS.md).

This is a bounded local resource regression check. It covers private-peer TLS,
not the cost of rebuilding native-root HTTP clients or deployed telemetry/auth. It does not verify provider
billing, production compaction/retention, N-1 capacity, or a physical private
underlay. Run the host capture and fault sequence in
[`private-replication.md`](../../../../infra/kura-controller/private-replication.md)
before enabling a managed routing domain. The normal ShellSpec mTLS suite also
exercises all three origins with the topology override.

The regional ShellSpec fixtures use `private-proxy.mjs` on an ORD-only Docker
network to record successful mTLS body requests. Canonical discovery remains on
the shared network; SCL private aliases are unreachable from ORD. The approved
and unapproved scenarios have independent setup and teardown. The latter leaves
SCL approval empty, verifies replication to a healthy SCL sibling, and
observes missing cross-domain replication for 30 seconds after all four peers
have joined. These are protocol/path tests, not physical VPC tests.
