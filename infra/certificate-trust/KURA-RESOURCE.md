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
one host to investigate phase/variation and observer cost. It is pending, not a
rerun-until-green or budget waiver. The job has contents-read permission only;
publishing is skipped and private keys/binaries/images are excluded from uploads.

This fixture measures local private-peer behavior, not native HTTP-client
construction cost, physical provider networks, fleet capacity or deployed
Sentry/OTLP/enrollment/Kubernetes integrations. Those and exact release/runtime
qualification remain independent gates. No production deployment, customer
publication or installed-process replacement occurred.
