# Local shared-disk end-to-end test

Run `run.mjs` as root in a disposable Linux VM with XFS project quota support,
`xfsprogs`, `util-linux`, Node.js 18 or newer, and the two Linux binaries:

```sh
KURA_BINARY=/path/to/kura KURA_DISK_AGENT_BINARY=/path/to/disk-agent node run.mjs
```

The test uses its own sparse 16 GiB loopback image, 12 GiB tenant budget,
two 4 GiB floors and two 8 GiB ceilings. It creates bounded memory cgroups and
private mount/cgroup namespaces for the runtime processes. No real block device,
cluster, external endpoint or account is used. Ports 4301/4302 and 7441/7442 must
be free. The host must have room for approximately 12 GiB of allocated test data.
Docker Desktop's Linux kernel did not enable XFS quotas on the validation host;
a local Ubuntu VM provided real accounting and enforcement instead.

The workload writes 900 8 MiB objects to A and 650 to B, verifies recent objects,
keeps unlinked file descriptors open across contention and allocator restart,
and expires then renews the allocation lease. Holding files deliberately makes
growth wait: the test releases those files before completing B's write workload.
HTTP write retries are bounded because a refusal can close a streaming body.

The script prints each successful assertion and the evidence directory. It
retains allocator/runtime logs and JSON quota observations, and removes its
loop image, mounts, child processes and cgroups. Failed runs retain logs too.
`finally` cleanup requires the process to remain alive; a killed VM may need
manual cleanup of this test's temporary mount and cgroups.

The harness exercises runtime → allocator → kernel behavior. Kubernetes
placement, admission and manifest generation have separate server/controller
tests; this harness does not deploy Kubernetes or claim to validate a live
DaemonSet rollout. The implementation and opt-in rollout boundary are described
in [shared disk capacity](../../../../infra/kura-controller/shared-disk-capacity.md).

The compact fixture uses a 128 MiB staging budget with 4 GiB floors. Managed
controller instances require at least an 8 GiB floor and retain the full 2 GiB
maximum staged-request allowance; the fixture does not qualify smaller managed
floors or exercise maximum-size module uploads.

For the runtime resource comparison, run `../quota-pressure/resources.mjs`
sequentially against baseline and changed images on the same idle host. Set
`KURA_RESOURCE_SHARED_DISK=1` only for the changed image. It publishes synthetic
leases while keeping the effective ring at 3 GiB, so workload and cache size
match. This measures runtime memory, disk, CPU and egress overhead; it does not
measure the host agent or establish physical quota safety. Use the XFS test
above for the latter.

## Staging qualification and benchmark

The [validation record](validation.md) separates the local fixture from the
isolated staging Kubernetes run. Staging uses real local-path PVCs and the actual
node allocator; it does not enable a region or replace existing workloads.

`benchmark.go` is a dependency-free HTTP cache client for explicitly authorized
fixtures. Build it for the client host, mount a fixture-scoped bearer-token file,
and supply the fixture URL and tenant:

```sh
GOOS=linux GOARCH=amd64 go build -o /tmp/cache-bench benchmark.go
/tmp/cache-bench -base http://FIXTURE:4000 -account default \
  -token-file /run/fixture-token -out /tmp/result.json
```

It uses namespace `shared`, eight workers, 400 16 KiB PUTs/GETs, 64 4 MiB
PUTs/GETs, 24 batches of 64 unique 4 MiB eviction writes, then 64 verified reads.
Every GET verifies the returned bytes. A non-2xx response or checksum mismatch
fails the run; evictions of older churn objects are expected. The object prefix
`thin-bench-` is retained from the earlier benchmark so workload construction
stays comparable; this client does not require thin storage or encryption.

Compare identical CPU/memory limits, cache sizes, XFS quotas and placement using
baseline/candidate/candidate/baseline order. Scrape `/metrics` throughout load
and at least 20 seconds afterward, and capture cgroup CPU, anonymous memory,
pressure/OOM counters, physical data-directory bytes and network counters. Keep
allocator costs separate from runtime costs. The harness reports per-phase
percentiles; an average of batch p95s is not a whole-run p95. Use at least a
working set larger than memory for read-throughput qualification; the default
256 MiB immediate-read phases can be warm-cache measurements.
