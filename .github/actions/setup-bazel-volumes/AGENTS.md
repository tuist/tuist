# Bazel cache volumes

This internal composite configures repository downloads and the content-addressed
Bazel disk cache beneath one Linux volume. Stable per-task keys keep concurrent
compile, test, Clippy and image jobs from replacing each other's snapshots.
Trusted and fork variants share keys; the volume service owns publication policy.
Do not cache the output base, execution tree, remote-cache tokens or Bazel server.
Keep remote cache configuration independent. The GC flags require Bazel 7.4+;
Kura pins Bazel 9.1.1. Idle GC is best effort, not a strict size bound.

Validate wiring with actionlint and the manual Linux Build Cache Benchmark.
Warm benchmarks must verify a mounted volume and retained source marker.
