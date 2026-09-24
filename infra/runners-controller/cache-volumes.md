# Linux cache volumes

Linux custom volumes use the same storage model as the automatic macOS cache:
persistent local masters, private copy-on-write branches, immutable object-storage
images, and generation-checked publication. No Ceph cluster, credentials, RBD
images or network block devices are required. Custom key/path volumes remain
Linux-only; the existing automatic macOS repository cache is unchanged.

The feature is disabled by default for self-hosted installs. Staging is enabled
for the validation below. The managed production overlay enables it through the
normal merge-and-deploy pipeline, including host filesystem provisioning.

## Workflow

The release interface is the dedicated `tuist/cache-volume@v1` action. Its
[distribution and CI-provider integrations](cache-volume-integrations.md)
covers the release workflow and the implemented Buildkite/GitLab wrappers. Until the first
release passes the live storage gates, test with a reviewed monorepo commit:

```yaml
permissions:
  contents: read
jobs:
  test:
    runs-on: tuist-linux
    container: eclipse-temurin:21-jdk
    env:
      GRADLE_USER_HOME: ${{ github.workspace }}/.gradle
    steps:
      - uses: actions/checkout@v4
      - uses: tuist/tuist/.github/actions/cache-volume@main
        with:
          key: gradle-dependencies-v1
          path: .gradle
      - run: ./gradlew test
```

The standalone action release is part of the launch, with immutable version
tags and an advancing `v1` tag. Pin its release commit for production. Use one
key/path pair per action, before any tool populates that directory. Absolute,
relative and `~/` paths work. Existing nonempty directories cause an error.
`cache-hit` is `true` when attached from a published snapshot, otherwise `false`.
Do not restore an archive into the same path. A missing agent or failed attachment
warns and creates ordinary job-local directories; errors after attachment may
fail the build. No workflow OIDC permission or privileged container is required.

Keys allow 1–200 ASCII letters, digits, dots, underscores, slashes and hyphens,
starting with a letter or digit. They are metadata, never filesystem paths.
Identity includes account, provider, provider instance, immutable repository/project
or pipeline scope, key, architecture and
execution UID. Native jobs and root containers therefore have separate caches.
Mount path is not part of the identity. At most eight allocations per pod and
100 active local clones per host are admitted by default.

## Shared machinery and Linux substrate

Both platforms use `Tuist.Runners.VolumeHeads` for fast-forward compare-and-swap,
`Tuist.Runners.volume_master_upload_url` for checksum-signed immutable uploads,
`report_volume_head` for publication and supersession, and the existing master
and orphan cleanup workers. Objects use the same account-owned
`runner-volume-masters/<account>/<volume>/<digest>-<sha256>.image` infrastructure.
Linux storage names are `linux-<hash of volume UUID and clear generation>`;
macOS dispatch names still accept only `tuist-cache` and repository names. A Linux
custom volume cannot be selected as a macOS cache by widening storage validation.

The filesystem-specific implementation lives in `../runner-cache/local.go`:

- A dedicated XFS filesystem with reflinks (or another validated reflink-capable
  filesystem) holds immutable masters and sparse, 20 decimal GB ext4 images.
  Host-local branches use `cp --reflink=always`, the Linux equivalent of APFS
  `clonefile`. Unsupported or cross-filesystem clones fail; no full-copy fallback.
- A warm master is cloned locally. A host without the assigned version downloads
  it through a presigned URL, checks its SHA-256, restores it sparsely, and clones
  it. A failed restoration falls back to ordinary job-local directories through
  the existing client. It never advertises a hit from corrupt data.
- Raw ext4 images are gzip-compressed for object storage so unwritten space does
  not require transferring 20 GB. The SHA-1 artifact identifier and SHA-256 checksum
  describe the compressed object; unlike macOS's inventory digest, the Linux
  identifier is not a cache-file inventory. Downloads are bounded in compressed
  and expanded size and verified before installation.
- The host agent owns loop devices and mounts. Only `pods/<pod UID>` is exposed
  to that job's runner and DinD containers. Masters, images, journals, tokens and
  signed URLs stay outside workflow mounts. Mount operations reject symlinks.

Current runner root filesystems are ext4, which cannot provide these reflinks.
`scripts/provision-cache-filesystem.sh` prepares a bounded, **fully preallocated**
XFS backing file and a persistent systemd mount on an existing host. It reserves
all backing bytes before use and leaves 40 GB free for the host, so filling the
inner cache filesystem cannot grow its outer file into kubelet's free space.
The default backing file is 200 GB; an operator can choose a different size.
Formatting disables discard and the persistent mount opts out of periodic
[fstrim](https://www.man7.org/linux/man-pages/man8/fstrim.8.html), preserving the
outer file reservation. Do not manually trim or hole-punch that backing file.
It never reformats or resizes an existing image. A dedicated block device with
XFS is also supported with automatic provisioning disabled.

Managed production sets `cacheVolumes.provisioning.enabled=true`. A privileged
init container runs this same script in the host mount namespace before the
agent starts, covering both current and replacement hosts. It requires the XFS
tools already installed by fleet bootstrap, checks free space, and installs the
persistent systemd mount without restarting kubelet or repartitioning disks.
Retries retain existing contents and reject size mismatches, foreign mounts,
symlinks, and nonempty unprovisioned paths. Failure leaves the agent unready;
the host cannot advertise volume readiness. Disabling provisioning never deletes
the backing file or unmounts existing storage. Runner scheduling prefers ready
hosts but does not require them; jobs on other hosts fall back to ordinary
directories. If unprovisioned hosts have accumulated pod directories, drain those
pods and remove only their confirmed-unused directories before retrying setup.

## Trust, publication and recovery

The agent binds source IP, pod UID and node before allocation. The server resolves
the actual executed job through its runner session and verified GitHub,
Buildkite or GitLab metadata. Workflow-supplied branch names never grant writes.
GitHub default-branch push/schedule/workflow_dispatch jobs may publish after
success; PRs and forks read private branches but cannot update the master.
See [provider policies](cache-volume-integrations.md).

Publication remains synchronous in the existing node-agent reconciliation path;
there is no background-upload service or detached publication queue. Linux must
first prove the pod is absent and the host CRI reports no ready sandbox or
non-exited container for that pod UID, then unmount and detach
its private image. Before unmounting, it checks `syncfs` and ext4 error counters
for delayed write-back failures (including host ENOSPC). A durable `.checking`
guard precedes that check; a failed or interrupted check disqualifies the branch
and deletion is acknowledged normally. A `.verified` marker permits upload
retries only after clean write-back and full loop detachment. It compresses the settled image, preflights the base generation,
uploads it and asks the shared macOS HEAD code to fast-forward. Only an accepted
image becomes a local master. A slow job cannot overwrite a newer generation;
concurrent changes are not merged. A lost publication response is idempotent.

The OS lifecycle boundary differs: the macOS guest uploads before halting its VM;
Linux's host agent publishes after teardown to prove that all writers are gone.
Consequently this implementation does **not** promise that the runner slot stays
reserved during upload. The upload-before-publication protocol and shared storage
machinery are the same; moving the Linux writer fence or slot-release boundary
requires validation against Kata, rather than trusting a job's completion signal.

The privileged agent alone receives the host containerd socket and uses CRI list
operations for that writer fence. Runtime errors fail closed. Waiting for the
whole kubelet directory before unmounting deadlocks: propagated child mounts
keep kubelet's SubPath mounts busy. After the runtime fence, unmounting releases
those children so kubelet can complete cleanup. Directory removal still waits
for kubelet's directory to disappear. No runtime socket enters a workflow pod.

GitHub's execution webhook can arrive after the first workflow step. An open
Linux session without that verified binding returns an explicit pending response;
the agent waits up to 30 seconds, retrying once per second. A denied identity is
not retried, and no volume is allocated before verified attribution arrives.

The journal is persisted and fsynced before creating a branch. Cold images are
formatted in a private temporary file and atomically renamed before exposure;
a restart never reformats an image a job could have written. Attachment checks
a per-use marker. Teardown errors retain the image for retry. Private branches
are released after durable sealing and publication acknowledgement. Local master
replicas are validated against the central HEAD and evicted when superseded,
cleared, or idle for seven days. Physical free-space watermarks drive admission
and LRU eviction because reflinks share blocks; summed logical sizes cannot
measure host disk consumption. Defaults are eight allocations per pod, 100 active
branches per host, 20 GB logical volume capacity, and a 40 GB free-space reserve.

A cold machine can restore accepted images from the existing object storage.
Losing a host loses unpublished changes, not the last accepted remote master.
This version restores on demand; it does not yet prewarm arbitrary custom keys
or steer by a particular cached key, because keys are first declared inside jobs.
Host/journal loss still requires operator reconciliation of usage records. Never
infer successful erasure from Node NotReady or a timeout. Clearing increments a
separate invalidation generation, removes the shared HEAD and schedules remote
object cleanup through the existing URL-TTL grace. Running branches cannot
resurrect it. Account deletion uses the existing master-prefix cleanup.

## User-visible management

Account **Runners → Volumes** shows volume count, retained logical used space
and cache hit rate with date ranges and period comparisons. Its searchable,
sortable, paginated table lists keys, repositories, platforms, used space,
capacity and last use. Volume details sit above the Overview and Jobs tabs;
the overview adds storage, hit-rate and job-run charts plus recent jobs.
Job history includes job and workflow names, cache lifecycle status ("Saved"
for published changes), hit/miss, sizes and a single mount timestamp.
Job details link back to their volumes. Unknown capacity is "Not reported".
Readers need `runners_read`; clearing requires `account_update`
and a confirmation. Every browser query and mutation is account-scoped.

Clearing invalidates immediately. Physical removal waits for running jobs,
responding storage agents and eviction of local master replicas. History remains available.
Account deletion cascades metadata; agents receive a delete decision for their
orphaned images and still enforce teardown fences. See
[export and erasure](../../server/data-export.md#linux-runner-cache-volumes-opt-in).

## Rollout and validation

1. Apply the additive publication-metadata migration and deploy the server.
   Build the controller, node-agent and Linux runner images. Upgrade the RunnerPool
   CRD explicitly when needed; Helm does not update CRDs automatically.
2. Managed production provisions the bounded filesystem through the opt-in init
   container. For manual/self-hosted setup, install XFS/e2fsprogs/util-linux and
   run `sudo scripts/provision-cache-filesystem.sh`. The agent probes reflinks and
   refuses the host root or kubelet filesystem. A failed host stays unready.
3. Enable `runnersFleetLinux.cacheVolumes` with an explicit agent image tag,
   `hostPath`, `maxSlots`, `volumeGB`, and `minFreeGB`. There is no storage secret.
   Existing object-storage configuration is reused through server-issued URLs.
4. Run `.github/workflows/linux-cache-volumes-smoke.yml` cold and warm on native
   and ordinary Docker jobs, including jobs on different nodes. Verify that host
   mounts propagate through Kata/virtiofs/DinD. Exercise all three CI providers,
   concurrent writes, untrusted and failed jobs, clearing during a job, agent
   restart, host loss, upload outage and filesystem exhaustion.
5. Track representative cold/warm workload duration and attach/upload cost.
   Local filesystem tests establish semantics, not deployed fleet performance.

The normal controller release publishes its cache-volume agent with the same
semantic version and checks both registry images before creating the release tag.
Production inherits that version from `runnersController.image.tag`; an explicit
`cacheVolumes.image.tag` remains available for staging and self-hosted deployments.
No separate production kubectl elevation is part of the merge/deploy path.

`scripts/test-cache-filesystem.sh` runs the real Linux storage test in an isolated
privileged Docker container with its own disposable XFS image. It covers creating
and mounting ext4, local reflinks, private-write isolation, synchronous publication,
and verified restore on a second host directory. The controller image workflow
runs it alongside the Go suites. It does not substitute for the deployed Kata,
provider authorization and actual object-store gates above.

Rollback: disable new volume-using jobs, allow teardown/publication to settle,
then remove the agents and readiness labels. Never unmount the backing filesystem
under live jobs. Do not roll back to the RBD agent against local-image journals.
The new schema columns are additive; rollback after cleanup can drop them, but
would lose publication metadata.

### Staging evidence (September 23, 2026)

The [staging deployment](https://github.com/tuist/tuist/actions/runs/35888943138)
uses a separately provisioned 200 GB preallocated XFS filesystem on the staging
OVH Linux host. Its systemd mount and provisioning idempotency were checked; a host
reboot has not been tested. Production is unchanged.

The automated provisioning path was subsequently exercised in the same host
mount namespace used by the chart's init container, with a separate disposable
64 GB backing file. Cold creation, XFS reflink copies, the persistent systemd
mount, and an idempotent rerun preserving sentinel contents all passed. The
temporary mount, backing file, unit, and helper resources were removed; the
existing runner cache remained mounted. The
[filesystem CI run](https://github.com/tuist/tuist/actions/runs/35895316941)
also passed provisioning refusal/retry regressions and the real image lifecycle
suite. This tests setup and repeat execution, not a physical reboot.

Real GitHub native and ordinary Docker jobs passed
[cold attachment](https://github.com/tuist/runners-benchmark/actions/runs/35882826464),
[warm restoration](https://github.com/tuist/runners-benchmark/actions/runs/35883138500),
and [remote restoration after agent restart](https://github.com/tuist/runners-benchmark/actions/runs/35884140819).
The last test moved aside only the two disposable local smoke masters after all
active uses settled, forcing downloads from the real object store. It does not
simulate losing a physical host.

[Failed jobs](https://github.com/tuist/runners-benchmark/actions/runs/35883293984)
wrote different contents and intentionally failed; their uses were discarded.
[Active jobs](https://github.com/tuist/runners-benchmark/actions/runs/35883427020)
retained private contents after clearing, while
[new jobs](https://github.com/tuist/runners-benchmark/actions/runs/35883588085)
started empty. Old-generation writes were discarded. The clear test invoked the
shared account-scoped service for two allowlisted smoke volumes, not the public
authenticated HTTP endpoint.

[Cancellation](https://github.com/tuist/runners-benchmark/actions/runs/35884472438)
discarded both jobs' private writes, and
[subsequent jobs](https://github.com/tuist/runners-benchmark/actions/runs/35884844710)
verified the last successful contents were unchanged.

GitLab’s actual remote template passed
[cold attachment and save](https://gitlab.com/tuist2/gitlab-runner-staging-e2e/-/jobs/16687684514),
[warm restoration](https://gitlab.com/tuist2/gitlab-runner-staging-e2e/-/pipelines/2875884783),
and [post-failure content verification](https://gitlab.com/tuist2/gitlab-runner-staging-e2e/-/pipelines/2875891183).
The [intentional failure](https://gitlab.com/tuist2/gitlab-runner-staging-e2e/-/pipelines/2875887310)
wrote a different sentinel; its eligible-but-failed use was discarded. The original
pipeline configuration was restored exactly after these tests. The live job-token
API exposed `pipeline.source`, which required correcting the top-level-only lookup.

Buildkite’s [scheduled seed](https://buildkite.com/tuist/tuist-staging-smoke/builds/9)
passed with a real cold mount and accepted generation-1 publication. The
[API-triggered warm run](https://buildkite.com/tuist/tuist-staging-smoke/builds/13)
restored its contents and changed a private sentinel; its successful use was
discarded with save permission disabled. The self-contained warm smoke skipped
the unrelated example-repository checkout and used Git protocol v1 for the actual
plugin clone after anonymous GitHub v2 checkout failures.
The [fresh verification run](https://buildkite.com/tuist/tuist-staging-smoke/builds/14)
then recovered the original sentinel, nested file, and symlink, confirming that
the read-only run's private writes did not replace the saved contents. The original
Buildkite pipeline command and queue were restored, and all temporary schedules
were removed.

Buildkite’s first real plugin invocation exposed a missing explicit plugin
checkout directory in the standalone agent. The corrected image reached the hook,
then exposed a second issue: Stacks reports a running job’s state but returns 404
for its full scheduling payload after acquisition. The server now captures only
verified scope and save permission before returning the acquisition token. Missing
identity snapshots decline attachment, and a failed refresh clears earlier authority.

The first live run exposed the verified-job webhook race and the Kata SubPath
teardown deadlock described above. Both were fixed and rerun. Public distribution releases, host reboot/loss,
capacity exhaustion, upload outage injection, and representative workload
benchmarks remain outstanding operational validation. Production enablement was
explicitly requested after these provider smokes; it does not imply those
additional checks have passed.

Review regression validation: a privileged Linux container with a 4 GB XFS
filesystem successfully reproduced buffered writes succeeding after backing
storage was exhausted. Sealing rejected that branch, freeing space and restarting
the backend could not publish it, and an independent restore retained the previous
good contents. This covers isolated filesystem exhaustion, not fleet-wide capacity
planning, physical host loss or reboot.
