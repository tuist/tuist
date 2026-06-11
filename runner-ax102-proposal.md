# Proposal: add an AX102 (Ryzen 9 7950X3D) host fleet for single-core-bound CI

## TL;DR

I want to pilot a second Linux runner fleet on Hetzner **AX102 (Ryzen 9
7950X3D)** boxes alongside our current AX162-R fleet, and route the
performance-sensitive runner shapes to it. It's roughly cost-neutral for the
same capacity and meaningfully faster on the part of CI that actually dominates
wall-clock. Asking for buy-in to order **2× AX102** to benchmark in production.

## The problem

Our Linux runners run as microVMs on Hetzner AX162-R bare metal (EPYC 9454P,
48c/96t, ~3.8 GHz boost). Two things cap real-world build speed:

1. **Single-core performance.** A lot of CI wall-clock is the *serial* part of a
   build (dependency resolution, linking, codegen, the one slow module). vCPU
   count doesn't help those — only faster cores do. The 9454P boosts to
   ~3.8 GHz, which is mid-field. Competing CI vendors' x64 runners (Namespace,
   Blacksmith) benchmark ~15% higher single-thread.
2. **CPU oversubscription.** We schedule microVMs by memory and intentionally
   oversubscribe CPU (256 GB → ~64 microVMs over 96 threads ≈ 1.5×). Great for
   density/cost, but it means a runner's effective single-core throughput is
   below the bare-metal boost under load.

## The proposal: AX102 (Ryzen 9 7950X3D)

This is the box the fast Hetzner-based CI vendors (Blacksmith, Warpbuild,
Ubicloud) standardize on. Versus our AX162-R:

|        | AX162-R (today)     | AX102 (proposed)            |
| ------ | ------------------- | --------------------------- |
| CPU    | EPYC 9454P, 48c/96t | Ryzen 9 7950X3D, 16c/32t    |
| Boost  | ~3.8 GHz            | **~5.7 GHz**                |
| Cache  | 256 MB L3           | **96 MB 3D V-Cache** CCD    |
| RAM    | 256 GB              | 128 GB DDR5 ECC             |
| Price  | ~€199/mo            | **€109/mo** + €39 setup     |

Why it helps:

- **~5.7 vs ~3.8 GHz** directly speeds up the serial, single-core-bound parts of
  every build.
- **3D V-Cache** is a big win for compile/link (very cache-sensitive) — it's why
  the 7950X3D outperforms its clock on build workloads.
- **Oversubscription improves for free:** 128 GB → ~32 microVMs over 32 threads
  ≈ 1:1, vs ~1.5× today. Faster cores *and* less contention, no scheduling-model
  changes.

## Cost & tradeoff (honest version)

Half the RAM per box = half the microVM slots, so we need ~2× the boxes for the
same fleet capacity. The math nets out:

- **2× AX102 = €218/mo** → 256 GB, 32c/64t, 5.7 GHz + V-cache
- **1× AX162-R = €199/mo** → 256 GB, 48c/96t, 3.8 GHz

≈ cost-parity for equal RAM/density. We trade raw thread count (64 vs 96) for far
faster, cache-rich threads — the right trade for single-core-bound CI. Minor
downsides: a few more nodes to manage (already automated by our robot-controller)
and the 7950X3D's asymmetric CCDs (a non-issue for our microVMs).

## Plan — low-risk, reversible

1. Stand up a separate fleet (`runners-linux-fast`) on **2× AX102**.
2. Route the larger / latency-sensitive shapes (≥4vcpu-16gb) there; keep AX162-R
   for tiny high-density shapes (1vcpu-2gb, 2vcpu-4gb) where density wins.
3. Benchmark a representative build on both, compare wall-clock + €/build, then
   decide how far to shift.

## Ask

Approval to order **2× AX102** (~€218/mo + €78 setup) for a production benchmark.
If the numbers don't hold up, we release the boxes — nothing structural changes.

## Note

Hetzner doesn't offer a Zen 5 9950X3D box yet; when they do it's a strict
upgrade, so worth re-checking before any larger order.

## Sources

- [Hetzner AX102 (Ryzen 9 7950X3D)](https://www.hetzner.com/dedicated-rootserver/ax102/)
- [Hetzner AX server matrix](https://www.hetzner.com/dedicated-rootserver/matrix-ax/)
- [RunsOn — GitHub Actions runner CPU benchmark](https://runs-on.com/benchmarks/github-actions-cpu-performance/)
