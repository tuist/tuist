# Kura private-peer resource evidence

## Identity and outcome

Build-only [run 40073713999](https://github.com/tuist/tuist/actions/runs/40073713999)
compared candidate `fe4c162fed7608edb373df0b49d2acbec659dad4` with main
merge-base `8611f6aa9d4f9b046de3389df74d9b306329ed2b` on one isolated Linux
amd64 host. It completed full Linux tests, both release assemblies and all four
ABBA workloads, including retained-object and recovery checks. The workflow
**failed** its final comparison because convergence retries were incorrectly
included in the successful-work equality gate. It is not a passing-workflow
receipt or resource-budget approval. Publishing was skipped.

The full Linux library passed 1,250 cases/52 ignored in 22.777 s, alongside the
independent 10/3 ignored, reporter 3 and main 1. Both explicit public/identity
opt-ins passed in 3.326 s. Both images ran `--version` and had identical
non-binary layers under the same pinned release Dockerfile/context.

| Identity | Baseline | Candidate |
| --- | --- | --- |
| Binary SHA-256 | `2e804d4c3a3b4d0d667f8217a9a1f65702b41b3285723936d2aaa5868d0c2131` | `94b8cf8f5701d761f1c20878e8ad17862bc4b5dcfef3b7db925921ff6e5b32e3` |
| Local image ID | `sha256:61af603437d215a75d8c98356e943bcfbca4a2b74828f8f92f7168622a839bcd` | `sha256:d286841da8f2059fc2d8eccf93d1212536810976aa48f313b38aa31332d720db` |

These are local build-only identities, not published images or installed versions.

## Work and derived analysis

Each run completed 320 PUTs, 1,728 GETs, 1,280 full nonresumed inbound peer-mTLS
handshakes and 960 retained-object checks with no recorded workload failures.
Client writes were 320 MiB, peer applied bytes 640 MiB, recorded read bodies
1,728 MiB and server artifact egress 1,920 MiB. The last includes exactly 192 MiB
of successful seed probes. All successful work and artifact egress match.

Convergence probes were 196/197/196/197 attempts in ABBA order, with 192 MiB plus
128/160/128/160 bytes read. The historical receipt did not record response-code
detail. Retrying convergence is measured setup cost, not a valid outcome filter:
the candidate may change it. Requiring equality would selectively refuse slow
runs rather than report their cost.

Original downloaded CI receipts remain unchanged at
`/tmp/tuist-emudhra-audit/kura-resource-fifth-40073713999/`. A separate, explicitly
labelled copy at `kura-fifth-derived-observer-analysis/` was processed with the
corrected comparison. This is derived analysis of a failed workflow, not a
retroactive green result. It preserves raw transmit/CPU costs and additionally
reports transmit minus stored metrics **body** bytes within the interface-counter
window. Sample zero precedes that window and is excluded. HTTP/TCP/IP overhead
and scrape CPU remain included; this is not complete observer-cost removal.

| Measurement | Baseline mean | Candidate mean | Delta | Baseline spread |
| --- | ---: | ---: | ---: | ---: |
| Peak anonymous memory, MiB | 227.854 | 235.430 | **+7.576 (+3.325%)** | 2.551 |
| Cooldown anonymous memory, MiB | 139.350 | 142.400 | +3.051 | 5.949 |
| Peak jemalloc allocated, MiB | 52.378 | 53.319 | +0.940 | 1.120 |
| Peak jemalloc resident, MiB | 145.061 | 144.166 | -0.895 | 0.059 |
| Peak transient reservation, MiB | 10.500 | 16.750 | +6.250 | 17.000 |
| CPU seconds/client GiB | 9.894857 | 9.888000 | -0.006857 | 0.187429 |
| Allocated disk bytes/write GiB | 3,226,101,350.4 | 3,226,094,796.8 | -6,553.6 | 26,214.4 |
| Raw transmit bytes/client GiB | 1,244,590,378.1 | 1,244,581,855.8 | -8,522.3 | 294,360.7 |

Pressure tier, transitions and sheds stayed zero; segment refresh stayed zero.
Transient peaks were at most 4.557% of a node's measured capacity. All 320 objects
remained readable on every node, followed by the second cooldown.

## Investigation and gates

**Peak anonymous memory increases beyond the observed two-baseline spread. Its
cause remains unestablished, so this is not budget clearance.** Three peaks fall
at sample 3 and one candidate peak at sample 33. Historical exact phase boundaries
were not recorded. Allocator cooldown does not increase, but asynchronous RSS and
jemalloc readings do not establish allocation attribution or rule out a regression.

The corrected fixture records probe successes/statuses, image/source identity,
phase boundaries and per-node peaks. It reports every block's delta/spread/signs
as well as pooled results; widening a pooled range cannot erase an individual
block's flag. Unknown legacy/unsampled measurements remain explicitly unavailable.

[Run 40078717301](https://github.com/tuist/tuist/actions/runs/40078717301), source
`d99f37fe3925712d85bed6a05ae5d3ed6387e8ca`, requests three complete ABBA blocks on
one host to investigate phase/variation and observer cost. It **succeeded** at
09:24:12 UTC on 2026-10-24, including full Linux tests, both assemblies and all
12 resource workloads. This was not a rerun-until-green or budget waiver. The job
had contents-read permission only; publishing was skipped and private
keys/binaries/images were excluded from uploads.

This fixture measures local private-peer behavior, not native HTTP-client
construction cost, physical provider networks, fleet capacity or deployed
Sentry/OTLP/enrollment/Kubernetes integrations. Those and exact release/runtime
qualification remain independent gates. No production deployment, customer
publication or installed-process replacement occurred.

## Completed three-block investigation

Run `40078717301` passed 14 measurement contracts, 1,250 library cases/52 ignored
(22.179 s), independent 10/3 ignored, reporter 3, main 1 and both public/identity
opt-ins (6.065 s). The exact binary hashes match the previous table; only the
local image identities changed:

- Baseline: `sha256:94777b1582d88005d2a02389174236c8d7e9d89ec76c9691787045a4be2504e6`.
- Candidate: `sha256:49be3a8c2075a14786af0a91128b7acd1bb6358c555072ba54e7ef4ea145783c`.

All 12 workloads completed identical successful work and application egress,
including 192 successful seed probes/192 MiB, 1,280 nonresumed handshakes and
960 retention checks each. Failed probes were four or five 404s per run, evenly
spread across variants. Pressure tier/transitions/sheds and segment refresh
remained zero; maximum sampled transient fraction was 8.333%.

| Pooled measurement | Observed candidate change | Per-block evidence |
| --- | ---: | --- |
| Peak anonymous memory | -6.825 MiB (-2.767%) | Negative in all three blocks |
| Cooldown anonymous memory | -0.854% | Block 1 **+3.223 MiB**, beyond its 0.922 MiB spread |
| Peak jemalloc allocated | -7.263% | No positive increase beyond spread |
| Cooldown jemalloc resident | -1.983% | Block 1 **+1.475 MiB**, beyond its 0.852 MiB spread |
| Peak transient reservation | -59.574% | Block 3 **+13.500 MiB**, beyond its 1.000 MiB spread |
| CPU/client GiB | -0.313% | No positive increase beyond spread |
| Allocated disk/write GiB | -0.000068% | No positive increase beyond spread |
| Logical disk/write GiB | Approximately flat | Block 3 **+683.2 B/GiB**, beyond 643.2 B/GiB spread |
| Raw transmit/client GiB | -0.000628% | No positive increase beyond spread |
| Transmit minus metrics bodies/client GiB | +0.001110% | Within spread in every block |
| Receive/client GiB | **+0.012503%** | Positive in all three blocks; block 3 beyond spread |

These percentages are observations, not confidence intervals or evidence of
improvement. The earlier peak-anonymous increase did not reproduce, but the
host differed; do not pool absolute values across hosts or call its cause fixed.
Every per-block flag remains visible and open despite negative pooled means.

Read-only source/evidence review found plausible explanations, not attribution:

- RX increases by 128,425 B and 1,726.5 packets per run on average. About 74 B per
  extra packet is header-sized. A **hypothetical** 66-byte header model explains
  about 89% of the difference, but no capture establishes ACK versus segmentation
  versus candidate scheduling or host noise. No assumed headers are subtracted
  from the authoritative comparison.
- Large transient observations are isolated seed-phase samples near a 32 MiB
  reservation. Baselines hit those samples more often overall. Sparse gauges
  cannot determine reservation duration or prove the block-3 cause.
- Cooldown values use one final sample. Block 1's live jemalloc allocations are
  lower for the candidate, and the other two cooldown deltas are negative, but
  this does not prove absence of retention.
- The logical disk flag is roughly 213.5 B total; allocated storage has no
  block-3 increase and all retention reads pass. Small metadata files are a
  plausible source, not a file-by-file demonstrated cause.
- Baseline `before-6` had one extra metrics scrape. Body-only accounting exposes
  that observation cost, not all TCP/IP overhead or scrape CPU. Phase edges and
  cached gauges remain too coarse for allocation attribution.

Original receipts are immutable under
`/tmp/tuist-emudhra-audit/kura-resource-sixth-40078717301/`; the workflow's own
`comparison.json` includes all blocks, raw phase/per-node peaks, identities and
flags. The read-only review is `claude-kura-three-block-resource-final.json`.

**Workflow completion is now established. Resource-budget clearance is not.**
The remaining flags, native-client construction cost and exact deployed/runtime
integrations still require qualification. No further repetitions are being used
to erase flags, and no publication, deployment or replacement follows from this
successful build-only run.
