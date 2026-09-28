# Provider topology resource comparison

Build the merge-base and changed images first, then run these sequentially on
the same otherwise idle host with Node.js, OpenSSL and Docker on PATH:

```sh
KURA_RESOURCE_OUTPUT=/tmp/topology-before node test/e2e/provider-topology/resources.mjs before kura:baseline
KURA_RESOURCE_OUTPUT=/tmp/topology-after node test/e2e/provider-topology/resources.mjs after kura:after
node test/e2e/provider-topology/summarize.mjs /tmp/topology-before /tmp/topology-after
```

The harness creates three disposable containers with distinct origin regions,
two providers, real peer mTLS, and separate private DNS aliases. The baseline
receives the same environment and ignores the new optional topology field.
Each container has two CPUs, a 1.5 GiB cgroup limit and a 3 GiB cache capacity.
It reserves loopback ports 4291–4293 and removes only its own containers and
network. Keep the output directories distinct: each contains temporary test
certificates as well as the resource traces.

The corpus is 64 seeded and 256 subsequent 1 MiB objects, written round-robin
across all three origins. Every seed must replicate byte-for-byte to all nodes
before load begins. The load offers four writes/second and four verified
reads/second per node for roughly 64 seconds, extending when writes cannot
keep pace. A 30-second cooldown separates peak memory from settled memory.
`result.json` records completed work, failures, process CPU ticks, disk size,
anonymous memory and network counters. Every node's `/metrics` is scraped at
two-second intervals throughout seeding, load and cooldown.

The summary aggregates simultaneous memory samples across all three nodes,
reports peak and cooldown values, uses the doubled `_total_total` counters,
and normalizes CPU to completed client bytes. The runtime has no CPU-seconds
metric, so `/proc/<kura-pid>/stat` supplies that measurement. Interface transmit
bytes include mTLS, ACKs, probes and metadata; client egress and peer applied
payload counters are reported separately. Disk includes metadata and segments;
refresh bytes show write amplification beyond the client and replicated corpus.

This is a bounded local resource regression check. It does not verify provider
billing, production compaction/retention, N-1 capacity, or a physical private
underlay. Run the host capture and fault sequence in
[`private-replication.md`](../../../../infra/kura-controller/private-replication.md)
before enabling a managed routing domain. The normal ShellSpec mTLS suite also
exercises all three origins with the topology override.
