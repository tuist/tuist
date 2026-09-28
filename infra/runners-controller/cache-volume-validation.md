# Linux cache-volume reliability checks — September 28, 2026

## Repeated production CI

All runs used the same merged source commit, `39d0e6905ad9667246aec27f983df3521eb3c8f7`.
The first run created empty volumes; attempts 2 and 3 reran only the named job.
The production runtime was controller/agent 0.26.2 and runner 0.13.2. These runs
precede the prefetch change; they are its baseline, not evidence of its benefit.
All twelve jobs passed.

| Job | First job | Repeat 1 | Repeat 2 | Volume result on repeats |
| --- | ---: | ---: | ---: | --- |
| [Registry tests](https://github.com/tuist/tuist/actions/runs/36408223611) | 334 s | 57 s | 61 s | Both volumes warm |
| [Cache tests](https://github.com/tuist/tuist/actions/runs/36408223480) | 358 s | 58 s | 54 s | Both volumes warm |
| [Server Credo](https://github.com/tuist/tuist/actions/runs/36408223576) | 347 s | 76 s | 84 s | Both volumes warm |
| [Kura Bazel compile](https://github.com/tuist/tuist/actions/runs/36408223675) | 148 s | 167 s | 118 s | Both timed out; continued cold |

Job duration includes checkout and tool installation, but excludes queueing and
post-job agent publication. It is not a controlled estimate of volume-only gains:
for example, Registry's mise step fell from 238 s to 19–26 s independently.

Comparing the cache-dependent steps gives a narrower result:

- Registry: both attachments + dependencies + tests fell from 73 s to 17 s and
  16 s. The warm attachments cost 10 s combined.
- Cache: the same steps fell from 105 s to 23 s on both repeats. The attachments
  cost 11 s combined.
- Server: setup (including tools, volumes and dependencies) + Credo fell from
  301 s to 58 s and 65 s. This still includes tool setup effects.
- Kura: all three builds reported 1,062 remote action-cache hits. Bazel itself
  took 75.021 s, 45.568 s and 47.069 s. Both repeated volume attachments reached
  the 25-second host deadline, so neither demonstrates a local-volume speedup.
  The remote action cache allowed both jobs to finish successfully. Checkout
  varied from 13 s to 56 s, explaining much of the total-job variance.

This supports retaining the Elixir adoption and addressing Kura's cold-host
restoration overhead. It does not establish fleet-wide hit rates or percentiles.
Two repeats per workload are a small operational sample.

## Staging deployment and recovery

The initial [provider smoke](https://github.com/tuist/tuist/actions/runs/36413529344)
failed before mounting: staging's old controller did not put the mount broker
socket into runner pods. Upgrading the staging controller to the already-released
0.26.2 replaced idle pods with the required wiring. The runner image was already
0.13.2. This was deployment drift, not an application dependency-cache failure.

A concurrent Helm deployment then restored the old staging-only agent pin
`sha-a1c278970fe8`. Remove that pin so normal staging deployments resolve the same
agent release as their controller. Candidate agents were applied only to staging;
production was observed and exercised through ordinary CI, not patched.

- [Native and Docker seed](https://github.com/tuist/tuist/actions/runs/36414552898):
  passed with fresh keys, real mountpoint assertions, `npm ci` in the mounted
  `node_modules`, and sentinel/nested-file/symlink writes.
- [Live agent restart](https://github.com/tuist/tuist/actions/runs/36414751664):
  both warm jobs held their mounts for 180 seconds while the DaemonSet pod was
  replaced. Both verified their contents afterward and passed.
- Isolated filesystem tests on the actual staging host passed: real loop-mounted
  ext4 images on a disposable 4 GB XFS backing filesystem; local and remote
  restoration; ENOSPC/writeback-error rejection; cancelled restore journals
  surviving store reopen; immutable-master prefetch; and three concurrently
  writable, isolated clones. The test container had no service-account token or
  host cache path. Its transfer-delay injection was synthetic; its disk and
  mount operations were real.

The new phase logs measured four initial smoke publications at 9.24–9.57 s each:
8.57–8.69 s compression and 0.49–0.80 s upload/metadata. These are tiny payloads
inside 20 GB sparse images, not representative large Bazel images. Publication
runs after job teardown and is recorded separately from GitHub job duration.

## Automated validation

[Candidate CI](https://github.com/tuist/tuist/actions/runs/36414905315) passed Go
tests, vet, formatting, real Linux filesystem tests and both image builds.
Focused `go test -race ./internal/cachevolumes ./cmd/cache-volumes` also passed
locally with `GOWORK=off`. Production and staging Helm renders passed; annotations,
port 9091 and the observability-only ingress rule were checked in the output.

Live scraping caught a zero capacity gauge: the volume-specific `MeasureFS`
helper correctly refuses XFS, but the agent had used it for the host filesystem.
The corrected gauge uses filesystem-wide `statfs`; the Linux test now checks
available and total bytes on the actual XFS fixture.

## Limits and rollout

The prefetch change keeps the existing 25-second host / 30-second client budget.
A timed-out warm request can start one two-minute immutable-master restore per
node, with no queue and the existing disk reserve. It cannot mount a late image
into the cold job or publish that job's fallback directory. It can repeat download
work and contend with later requests for the same master; the new metrics should
show whether later local hits justify that bandwidth. Scheduler affinity and
fleet-wide replication are deliberately deferred pending those measurements.

Merge/release deploys the matching controller and agent through the existing
pipeline. Keep the host filesystem and journals when rolling back the agent.
The additions do not change the journal format or image format. Reverting the
prefetch implementation restores cancellation-only behavior without migrating
stored data. Metrics and network-policy additions can be reverted separately.

These checks do not validate physical host replacement, a prolonged object-store
outage, Buildkite/GitLab recovery, or a production improvement from prefetch. Do
not infer those outcomes from the native/Docker smoke or isolated filesystem test.

### Physical reboot result

The idle staging OVH Linux node was cordoned, its unassigned runner pods were
removed, and the host was rebooted with `systemctl reboot`. It returned in roughly
seven minutes with a changed boot ID and the cache agent ready. The persistent
XFS mount returned automatically with nine saved master images: total filesystem
capacity 199,902,347,264 bytes, available 195,992,653,824 bytes at the check.
The corrected metric matched `df` exactly. The node was then uncordoned.

[Post-reboot verification](https://github.com/tuist/tuist/actions/runs/36416446210)
passed for both native and Docker jobs: warm attachment, real mount, npm package
and sentinel/nested-file/symlink contents. The observed local storage attach phases
were around 29–30 ms; authorization made the complete acquisitions 0.79–0.90 s.
The temporary filesystem-test and host-check pods were removed. This establishes
persistence across this clean reboot, not power-loss durability or replacement of
the physical machine.

### Cold local master and telemetry result

After publication completed, the native sentinel smoke's local master directory
was moved into a temporary backup; the shared remote HEAD and other volumes were
left intact. [Remote restoration smoke](https://github.com/tuist/tuist/actions/runs/36416756537)
passed for native and Docker jobs. The native sentinel image downloaded, expanded
and verified in 3.721 s; storage attachment took 3.777 s and complete acquisition
4.705 s. The backup was removed after content verification. This uses the actual
object store and simulates loss of this local master, not physical machine replacement.

Grafana queries confirmed ingestion of the agent's counters, timing sums/counts,
and filesystem gauges after the observability-only ingress rule was restored
following the concurrent Helm deployment. The staging node is Ready and schedulable,
with the tested `sha-37cf4806efef` agent and released 0.26.2 controller. A subsequent
staging deployment can restore the old agent until the pin removal in this PR lands.
