# gRPC upload throughput e2e (gateway HTTP/2 window)

This harness validates, end to end, the fix in the kura gateway nginx config
that raises the HTTP/2 request-body flow-control window
(`http2_body_preread_size` / `client_body_buffer_size`, with
`http2_max_concurrent_streams` to bound memory).

## What it proves

Under WAN latency, nginx's default 64KB HTTP/2 request-body window caps every
gRPC upload stream at roughly `window / RTT`. Bazel REAPI `ByteStream.Write`
uploads of large blobs (e.g. the ~784MB `librocksdb-sys` artifacts) therefore
crawl and time out. Raising the window removes the cap and the upload becomes
uplink-bound.

The test runs the **same** kura backend behind two nginx configs that differ
only in those window directives, plus a direct-to-kura control, all behind
toxiproxy injecting identical symmetric latency:

```
client ─► toxiproxy ─► nginx-baseline (64KB window, today)  ─► kura
       (latency)    ─► nginx-patched  (4MB window, the fix) ─► kura
                    ─► kura (direct, tonic default ~1MB window)
```

`nginx/baseline.conf` and `nginx/patched.conf` are identical except for the
three directives the `kura-controller` ConfigMap and the platform chart now
render — so the measured difference is attributable to that change alone.

## Measured results

At the production round-trip time (192ms — the latency measured from the
Bazel client to `grpc.tuist-us-west-1`), 16MB payload:

| path | HTTP/2 upload window | throughput | notes |
|------|----------------------|-----------|-------|
| baseline    | 64KB (nginx default) | **0.32 MB/s** (≈335 KB/s) | reproduces the production ~310 KB/s |
| patched     | 4MB                  | **12.24 MB/s** | **38.7x faster** |
| direct_kura | ~1MB (tonic default) | 3.76 MB/s | nginx-free control; bounded by kura's own window |

The baseline figure matches both the first-principles prediction
(64KB ÷ 0.192s = 0.33 MB/s) and the throughput observed in the production
Bazel gRPC logs, so the harness is reproducing the real bug, not an artifact.
`patched` exceeds `direct_kura` because nginx's 4MB window is larger than
kura's own ~1MB tonic stream window — which is why the kura-side
`max_connection_age` / window work is tracked as a separate follow-up.

## Run it

Standalone (uses the pinned released image `ghcr.io/tuist/kura:0.10.1`):

```bash
./run.sh
# tune:
SIZE_MB=16 LATENCY_MS=96 MIN_SPEEDUP=4 ./run.sh    # 192ms RTT, production-faithful
```

| env | default | meaning |
|-----|---------|---------|
| `SIZE_MB`    | 16  | payload uploaded per path |
| `LATENCY_MS` | 50  | one-way latency; injected on both streams, so RTT ≈ 2x |
| `CHUNK_KB`   | 256 | ByteStream chunk size |
| `MIN_SPEEDUP`| 4   | required patched/baseline ratio (test fails below it) |
| `KURA_IMAGE` | `ghcr.io/tuist/kura:0.10.1` | kura image under test |

Via the shellspec suite (builds + tests the local kura source as `kura:e2e`):

```bash
KURA_E2E_THROUGHPUT=1 mise run test-e2e -- spec/e2e/grpc_upload_throughput_spec.sh
```

The spec is skipped unless `KURA_E2E_THROUGHPUT=1` because it builds a small Go
client image and takes ~30-60s.

## Notes / scope

- toxiproxy is an L4 TCP proxy, so it transparently shapes the cleartext
  HTTP/2 (h2c) the client and nginx speak. Flow control is independent of TLS,
  so h2c reproduces the TLS production path faithfully while keeping the harness
  certificate-free.
- The test targets the **nginx window** variable specifically. The ~600s
  connection-age force-close (kura `max_connection_age` + grace) seen in
  production is a separate failure mode addressed on the kura runtime side; it
  is not exercised here.
- kura runs as a bare standalone node with the auth extension disabled
  (`KURA_EXTENSION_ENABLED=false`), so no Tuist control plane is required.
