# Reproducing retained-corpus handover failures

The 2026-10-16 production attempts failed after 300 seconds despite passing the
smaller handover fixtures. The candidate repeatedly revisited its retained index
following repair-triggered eviction; the source repeatedly abandoned preparation
requests at about 30 seconds. No complete matching receipt was obtained. Whether
request cancellation, repeated repair, fragmented capacity, or a combination is
responsible must be established by reproduction before another runtime change.

This fixture makes that loop independent of a production account, a runtime
release, or production elevation. It runs published source/warm/candidate images
on synthetic data in staging. A candidate image built from a branch can use the
same command. The source stays running while only the warm standby container is
replaced; its PVC is reused.

For same-repository PRs, Kura CI publishes its already built E2E runtime as
`ghcr.io/tuist/kura:qualification-<full merge commit SHA>`. Find the exact tag in
the **Publish Qualification Image** job summary and pass it as `--candidate-image`.
This requires neither a merge nor a release nor a server deployment. Forks do
not publish. Publication alone does not mean the other CI checks passed; inspect
those results before qualifying the candidate. Production does not consume these
tags. Evidence records the running image IDs as well as the requested tags.

## Run

Requires Node 22 or newer, kubectl with staging access, and OpenSSL. Select a
staging host with sufficient free disk, memory, and CPU first. The production
profile reserves two 64 GiB PVCs; each runtime has the same 57,804,891,095-byte
ring, 4 CPU ceiling, 4 GiB memory ceiling, and 1 GiB memory floor. Including the
fixture client and proxy, the pods request 4.45 CPUs and about 3.4 GiB of memory, plus 8 GiB of the node’s advertised memory-ceiling budget.
Do not run concurrent qualification jobs on the same host.

```sh
node --test kura/test/e2e/serving-authority/production/profile.test.mjs

node kura/test/e2e/serving-authority/production/staging.mjs \
  --context tuist-k8s-staging.taild6d7bb.ts.net \
  --namespace kura-spec98 \
  --node YOUR_STAGING_NODE \
  --output /tmp/kura-handover-baseline-UNIQUE \
  --profile production \
  --scenario fragmented \
  --source-image ghcr.io/tuist/kura:0.59.0-canary.2 \
  --warm-image ghcr.io/tuist/kura:0.59.0-canary.8 \
  --candidate-image ghcr.io/tuist/kura:0.59.0-canary.9 \
  --expect repair-timeout
```

Use `--profile smoke --scenario fresh --expect pass` first to check the harness
lifecycle with a small corpus. Smoke does not qualify a runtime for production.
Use `--profile records --scenario fresh --expect pass` to isolate record-count
overhead: it keeps all 151,943 blobs and 77,017 ActionResults, the same runtime
budgets and deadline, but gives every segmented blob a 16-byte body. It requires
the complete corpus on both replicas before measurement. This diagnostic removes
large-body I/O and is never a substitute for the production qualification matrix.
For a proposed fix, use `--expect pass` and repeat both `fresh` and `fragmented`
production scenarios on the same host and budgets. Keep the baseline output;
each run requires a new output directory.

The production corpus contains 151,943 segmented blobs totalling 44,885,777,151
bytes, plus 77,017 inline ActionResults referencing those blobs. Sizes follow the
observed histogram, including three approximately 814 MB objects. Bodies and
keys are deterministic synthetic data generated in bounded chunks, not copies
of actual artifacts. The fragmented scenario first writes and tombstones 20 GiB
of historical data and then writes up to 9 GiB of old destination-only data. It
measures the missing retained bodies after each GiB and stops once the deficit
reaches at least 2.4 GB, includes a largest body, and remains within the 5 GB
ceiling. `calibration.jsonl` records every measurement and the actual filler
amount is included in the result. This is
a reproducible fragmentation recipe, not a copy of the production disk layout.
The largest bodies are seeded first so they can fall into the oldest retained segments. Before measurement, the fragmented case requires 1–5 GB of missing bodies, including at least one approximately 814 MB body. A larger initial deficit could exhaust the deadline on transfer alone and is rejected as an invalid baseline. The fresh scenario omits that history and divergence.

## Evidence and gates

The command captures the workload, images and container identities, retained
index shapes, request timings, both runtime logs, authority transitions, metrics,
and cgroup CPU/memory, disk, and network samples. Raw pod network counters include
proxy traffic and must not be mistaken for per-runtime application egress;
use the runtime metrics and proxy byte counts to distinguish work.

A baseline run only counts as `repair-timeout` when it verifies the full corpus
shape, exhausts the unchanged 300-second handover deadline, observes repeated
approximately 30-second failed preparation requests and eviction-triggered repair
revisits, and proves that the same source resumes HTTP/gRPC writes after an
explicit abort. Startup failures, missing corpus, OOMs, unexpected restarts and
generic timeouts fail the run.

The calibrated `.canary.9` baseline on 2026-10-16 started with exactly three
missing 814,310,767-byte bodies, failed after 300.999 seconds, and safely resumed
the source after abort. It transferred 13.76 GB of peer-body responses and applied
9.70 GB during repair. Its nine timed-out preparation requests never completed a
repair walk, so the strict classifier returned `not-reproduced`: it exposed a
cancellation/restart variant, not the earlier production signature of completed
walks followed by eviction revisits. Preserve this distinction when interpreting
subsequent results; a valid failed workload is not automatically the same failure.

The request-lifetime candidate completed seven repair revisits but still failed
the fragmented case at 300.807 seconds. A full-size fresh-volume control then
failed at 301.705 seconds with zero missing bodies and zero request timeouts:
its reconciliation took 1.88 seconds, but full verification did not produce a
receipt. Both runs safely resumed source writes after abort. These separate
repair convergence from verification throughput; neither result qualifies the
candidate for rollout. On that same host, the record-count diagnostic passed:
228,962-record receipts in 30.295 seconds, complete handover in 32.930 seconds,
and original-session HTTP/gRPC fencing checks passed. All 12 resources and both
PVs were reclaimed. The much larger full-body cost remains to be separated from
hardware hashing throughput; the reduced-body pass is diagnostic evidence only.

A passing run requires matching full retained-corpus receipts, positive source
revocation, destination activation, rejection of writes on the original source
HTTP/2 and gRPC sessions, and successful destination writes. The runtime barrier
verifies the complete corpus. The external client additionally hashes selected
retained bodies, including the largest ones, while both holds are active.
Review deadline headroom and resource/repair amplification across repeated runs;
one late success is not sufficient qualification.

`cleanup.json` records removal of each uniquely labelled resource. The harness
checks UIDs before mutations, removes runtime pods before their PVCs, and leaves
unrelated workloads alone. If interrupted or a Kubernetes operation fails, check
that file and `owned.json` before cleanup. Never delete resources by a broad
namespace selector. PVCs use the existing `scw-local-nvme` Delete-reclaim class.

## Scope

Both runtimes run on one selected host with separate volumes. During measurement,
a proxy caps aggregate retained-body responses at 500 Mbit/s. It avoids adding
the transatlantic RTT between the available staging hosts, but does not reproduce
production network topology, disk contention or exact physical fragmentation.
The recorded achieved transfer rate matters, not just its configured ceiling.
`cpu.json` records the processor model and instruction flags as well as logical
CPU count. Equal CPU ceilings do not imply equal hashing throughput: the initial
staging host was an Intel Xeon E-2236 without SHA-NI. The fresh-volume failure
there does not by itself establish the same verification time on another CPU.

Authority is supplied by the existing TLS ConfigMap simulator, reachable only
inside these labelled fixture pods. The runtimes' Kubernetes hostname resolves
to that simulator; they have no Kubernetes service-account credential. No real
serving ConfigMap is modified. A NetworkPolicy confines communication to the
fixture and cluster DNS. This does not qualify the real controller, authentication,
separate-host failure, or physical power loss. After runtime qualification, run
the existing isolated real-controller tests in the parent directory before a
narrow production handover. No production account or account-wide flag is changed
by this command.

`qualify.mjs` accepts the same context, namespace, node, output and three image
arguments, and runs `fresh` and `fragmented` twice each, sequentially, requiring
success in every case. It writes `matrix.json` and stops at the first failed run.
The ShellSpec entry `serving_authority_production_spec.sh` is explicitly opt-in
with `KURA_E2E_AUTHORITY_PRODUCTION=1`; its named `KURA_E2E_PRODUCTION_*`
parameters map to the staging CLI arguments. It always requires a pass.

Each finished run writes `summary.json` with corpus shape, timing, memory peaks,
repair bytes, proxy traffic and cleanup results. `node summarize.mjs OUTPUT_DIR`
regenerates that report from preserved evidence. Missing samples are marked
unavailable, never interpreted as zero. Preparation groups at most 32 blobs and 128 MiB per batch with four workers; an
oversized blob runs alone. Only idempotent seed uploads may retry a connection
reset, at most twice, with each retry recorded. Qualification requests never
inherit those retries. CPU/memory/disk samples include preparation as well as
before, during and after handover.
Disk samples retain `du`'s valid total when a concurrently deleted descendant
disappears during its walk, and record the warning and count. Other disk command
failures still stop the run. This avoids turning normal temporary-file cleanup
into a spurious runtime failure without suppressing inaccessible storage.

The shaping proxy currently uses HTTP/1.1 on the internal peer plane. It does not
reproduce mTLS negotiation or HTTP/2 stream cancellation. Treat a reproduced
repair loop as evidence for that runtime path; confirm transport-dependent fixes
with the real-controller deployment's peer TLS configuration as well. The
`repair` section of `summary.json` reports repair amplification and the lower
bound on transferring the initially missing bytes at the configured rate. That
lower bound excludes metadata traversal, hashing, disk I/O and repair eviction.
