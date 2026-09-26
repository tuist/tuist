# Quota pressure and resource comparison

Run from `kura/` with Node.js and Docker on PATH. Build the images before measuring, then run them sequentially on an otherwise idle host. The scripts create and remove only their own disposable containers. The quota reproducer needs an 8 GiB Docker VM; the resource harness reserves loopback ports 4191 and 4192 and container names `kura-resource-a` / `kura-resource-b`.

```sh
KURA_IMAGE=kura:baseline KURA_QUOTA_EXPECT_BLOCKED=1 KURA_QUOTA_OUTPUT=/tmp/quota-before node test/e2e/quota-pressure/run.mjs
KURA_IMAGE=kura:after KURA_QUOTA_OUTPUT=/tmp/quota-after node test/e2e/quota-pressure/run.mjs
node test/e2e/quota-pressure/resources.mjs before kura:baseline
node test/e2e/quota-pressure/resources.mjs after kura:after
```

Set `KURA_QUOTA_SOURCE_IMAGE=kura:baseline` with the changed target image to exercise a mixed-version pair during rollout.

`run.mjs` replicates 512 × 8 MiB writes from an unrestricted source to a target with a real 5 GiB tmpfs limit and 1.25 GiB of non-CAS occupancy. The latter represents metadata competing for the same filesystem; it is not a simulated free-space callback. The fixed target must serve the latest object byte-for-byte after reclaiming old segments. The baseline must fail specifically with `disk_full` and fail to replicate that object. Both targets can report Ready: readiness is deliberately not the success criterion. The test uses a filesystem size limit, not a production XFS project quota. tmpfs is charged as memory, so the target has an explicit memory budget that keeps this a disk-pressure test.

`resources.mjs` uses ordinary disk-backed container stores. It seeds 64 × 8 MiB objects, waits for the last to replicate, then offers 256 more writes and 256 verified reads to each replica at four operations per second per stream. It samples both `/metrics` endpoints every two seconds through a 30-second cooldown and records work completed, bytes, container CPU, disk footprint and network counters. Captures go to `/tmp/kura-resource-<label>/` (override with `KURA_RESOURCE_OUTPUT`). Compare anonymous resident/allocator memory, pressure and shedding, retained disk and segment refresh bytes, CPU per completed work, client egress and peer applied bytes. The runtime currently exports no process CPU-seconds counter, so the harness supplements Prometheus with cgroup `cpu.stat`; network counters include TCP/probe overhead and should be reported separately from payload counters.

These short local runs test bounded regression and replication recovery. They do not prove a production metadata compaction profile, sustained production throughput or long-term retention.
