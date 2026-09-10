# Regional gateway staging benchmark

See [the longer paired comparison](SUSTAINED_RESULTS.md) and
[the original short-burst results](RESULTS.md).

Compare a TLS gateway on the Kura backend's node with an identical gateway on
another node. Both paths terminate TLS once and use the same production HTTP/2
window settings. The load generator runs on a third node; `kubectl exec` starts
the client, but payload traffic never passes through kubectl or port-forwarding.

```text
                  gateway A on node A ──► Kura A on node A  (local)
client on node C ──┤
                  gateway B on node B ──► Kura A on node A  (remote)
```

Both gateways also route `b.benchmark.test` to a separate Kura B on node B.
Repeat with `--backend b` to reverse the placement and check for host/path bias.
These internal test names do not create public DNS records. The certificate is
generated for the benchmark and explicitly trusted by the client; TLS
verification is enabled. HTTP and gRPC have separate upstream keepalive pools,
because an HTTP/1 request must never reuse a pooled h2c connection.

## Run

Requires Python 3.9+, OpenSSL, Go, kubectl, and staging write access. The runner
rejects contexts without `staging` in their name and requires three distinct
nodes. Verify the selected context actually points at staging before running.
Select worker nodes with spare CPU, memory and disk; never select control-plane
nodes. The client supports the staging Dedibox and ClickHouse node taints.

Build the client with the existing throughput harness's pinned dependency set:

```sh
# From the repository root; use absolute paths when running outside it.
repo_dir="$PWD"
build_dir="$(mktemp -d)"
cp kura/test/e2e/grpc-upload-throughput/client/go.{mod,sum} "$build_dir/"
CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go -C "$build_dir" build \
  -mod=readonly -trimpath -o "$build_dir/benchmark" \
  "$repo_dir/kura/test/e2e/regional-gateway/client.go"

python3 kura/test/e2e/regional-gateway/run.py render \
  --context STAGING_CONTEXT \
  --node-a BACKEND_NODE --node-b GATEWAY_NODE --client-node CLIENT_NODE \
  --image ghcr.io/tuist/kura:PINNED_STAGING_TAG \
  --binary "$build_dir/benchmark" --output /tmp/kura-hop-run

# Inspect /tmp/kura-hop-run/nginx.conf and resources.json, then use the same
# arguments with `run` instead of `render`. Choose a new output directory for
# a reciprocal run with --backend b.
```

The runner creates only uniquely labelled benchmark Pods, ClusterIP Services,
a ConfigMap, a disposable TLS Secret, and a NetworkPolicy in `kura`. Kura auth
is disabled only on these standalone instances. The policy admits only the
benchmark pods and DNS egress. No existing KuraInstance, DNS record, Ingress,
account, node label, or persistent volume is changed. Data lives in bounded
emptyDirs and disappears with the pods. Pods have a one-hour active deadline.

CPU limits are two cores per container; backend memory is capped at 2 GiB,
gateway memory at 256 MiB, client memory at 1 GiB. These are experiment bounds,
not recommended production hardware sizes. Default runs write under 2 GiB to
the measured backend; each backend has a 4 GiB emptyDir limit.

Resources are removed in the runner's `finally` block. If the process is killed
or loses access, use its exact run ID from `run-id.txt` to clean up:

```sh
kubectl --context STAGING_CONTEXT -n kura delete \
  pods,services,configmaps,secrets,networkpolicies \
  -l tuist.dev/gateway-benchmark=RUN_ID
```

## Measurements and interpretation

The default `--profile burst` alternates local/remote order in each round for:

- 4 KiB reads, concurrency 1, 200 requests (latency).
- 256 KiB reads and writes, concurrency 8, 64 requests each.
- 8 MiB reads and writes, concurrency 4, 16 requests each.

Both gRPC ByteStream and HTTP/2 are exercised. Requests use warmed connections.
Payloads are random and incompressible; writes have unique hashes generated
outside the timing window in the burst profile. Reads use warm seeded objects and verify both size
and SHA-256. Write completion sizes are verified for gRPC; HTTP writes require
a successful response. Any failed request aborts the run. Before the matrix,
the routing check writes different bytes under the same key in the two accounts
and verifies both values through both gateways. The second hostname is also
smoke-tested over gRPC through both gateways after the matrix.

Outputs include per-case JSON with errors, p50/p95/p99 in fractional
milliseconds, successful payload Mbps (decimal megabits), and timestamps;
metrics-server CPU/memory samples; container cgroup counters before/after;
resolved pod placement and image digests; and container logs. Metrics-server
samples span windows and are not exact per-case CPU measurements. With only 16
large-blob samples per case, p95/p99 are effectively the maximum; use repeated
throughput results rather than claiming stable tail percentiles for that case.

Report medians and ranges across rounds and check the reciprocal run. A faster
remote path can mean client-to-gateway route differences, shared-host noise,
or reduced CPU contention; it does not demonstrate negative network latency.

This measures the extra node hop through staging's current Kubernetes network.
It does not benchmark a dedicated 10/25 Gbps private network, cold NVMe reads,
production host-network ingress, WAN loss, long-duration saturation, large
connection populations, peer mTLS, certificate/DNS migration, automated routing
updates, or failover. The routing check validates backend separation, not the
production authorization layer. Hardware purchase sizing requires those
separate checks.

## Longer paired comparison

Use `--profile sustained --rounds 4` and repeat with `--backend b` in a fresh
output directory. Run placements sequentially so their traffic does not compete.
This profile uses 128 warm-up requests at the measured concurrency, then:

| Operation | Object size | Requests | Concurrency | Timed payload |
| --- | ---: | ---: | ---: | ---: |
| Read | 4 KiB | 2,000 | 1 | 7.8 MiB |
| Read | 256 KiB | 4,096 | 8 | 1 GiB |
| Write | 256 KiB | 4,096 | 8 | 1 GiB |
| Read | 8 MiB | 64 | 4 | 512 MiB |

Workload order is deterministically shuffled; local/remote order is balanced
within each placement. This is a longer batch experiment, not a soak test.
The standalone target backend is recreated before every upload case so its
emptyDir stays bounded. No persistent backend is reset. A readiness write may
retry while endpoints settle; measured requests are not retried by the harness.

Sustained writes reuse one random buffer per worker, change a random prefix and
recompute SHA-256 per request, producing unique incompressible objects with
bounded client memory. This preparation is included in batch wall time, while
per-request latency starts after preparation. Inspect client CPU before treating
the resulting throughput as a network limit.

The sustained profile sets client-facing nginx `keepalive_requests 10000` on
both gateways, above the largest case including warm-up. The default limit of
1,000 triggered gRPC connection-draining errors in the first long attempt.
Keeping connections alive isolates the warmed data path; it does not validate
connection recycling or prescribe a production keepalive setting.

Each case captures client TCP and cgroup counters immediately around its timed
batch, and gateway/backend counters around the full client invocation. Server
counter windows include warm-up and command overhead. Completed-request counts
per second allow an interior-window throughput check; exclude the first second
and final partial second. Container counters do not include host networking CPU.

```sh
python3 kura/test/e2e/regional-gateway/analyze.py \
  /tmp/kura-hop-a/results.jsonl /tmp/kura-hop-b/results.jsonl \
  --output /tmp/kura-hop-summary.json
```

The analyzer pairs paths within the same placement, round, protocol and
workload. It reports median paired percentage changes, ranges, placement
breakdowns, and an exploratory bootstrap interval resampling whole pairs.
Requests within a case are not independent experimental repetitions. With only
eight pairs and shared staging nodes, intervals do not capture all systematic
uncertainty. The analyzer also accepts gzip-compressed raw result files.
