# Linux cache volumes

Opt-in persistent dependency caches with private Ceph RBD snapshot clones. Every
job gets a writable filesystem, including parallel jobs and pull requests. A
successful trusted job publishes a snapshot for subsequent jobs. Attachment does
not download or extract an archive. Reads and writes depend on Ceph and the fleet
network; this is not a promise of local-NVMe latency.

The implementation is disabled by default. No Ceph cluster is provisioned by this
change. Enable it only after the storage and Kata integration gates below pass.

## Workflow

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

Pin the action to a reviewed commit for production workflows. The action is in
this repository; `tuist/cache-volume@v1` is not a published distribution. Use one
key/path pair per action, before any tool populates that directory. Absolute,
relative and `~/` paths work. Existing nonempty directories cause an error.
`cache-hit` is `true` when attached from a published snapshot, otherwise `false`.
Do not restore an archive into the same path. A missing agent or failed attachment
warns and creates ordinary job-local directories; errors after attachment may
fail the build. No workflow OIDC permission or privileged container is required.

Keys allow 1–200 ASCII letters, digits, dots, underscores, slashes and hyphens,
starting with a letter or digit. They are metadata, never filesystem paths.
Identity includes account, immutable GitHub repository ID, key, architecture and
execution UID. Native jobs and root containers therefore have separate caches.
Mount path is not part of the identity. At most eight allocations per pod and
100 active local clones per host are admitted by default.

## Trust and publication

The agent binds the TCP source IP to the named running pod's UID and local node.
It authenticates to Tuist using its own Kubernetes service account. The server
joins the live runner session to the workflow job GitHub actually assigned
(`executed_workflow_job_id`), then retrieves the run and repository through the
GitHub App. Dispatch predictions and workflow-provided repository/branch names
never determine scope or publication rights.

Successful default-branch `push`, `schedule` and
`workflow_dispatch` jobs can publish. PRs can read the same published snapshot
in private clones, but their changes are discarded. Publication rules are fixed;
other branches, forks, `pull_request_target` and other events cannot publish. Treat cached
contents as readable by workflows admitted to that repository, including forks.

Publication requires a successful completion record plus two local fences: the
pod is absent (or replaced with a different UID), AND its kubelet directory is
absent. A terminal phase, webhook or timeout alone is insufficient. API errors
retain clones. The agent unmounts and unmaps, flattens clone ancestry, creates and
protects a snapshot, then reports it. Publication is last-published-writer-wins;
changes from concurrent jobs are not merged. Flattening is off the attach path
and does not hold the lock for another lease's attachment.

The server locks the volume row for publication and deletion.
Deletion increments the generation and clears the head immediately; running
jobs retain private copies but cannot republish the old generation. A new job
can start a fresh empty generation while old storage is being reclaimed.

## Storage and recovery

The privileged agent owns Ceph credentials and host block devices. Images are
`<pool>/<namespace>/tuist-<use UUID>`; the only publication snapshot is `@cache`.
Images have a fixed 20 GB (decimal) logical capacity by default, rounded up to the next
MiB for RBD. This is fleet-controlled; workflow-level sizing is not yet exposed.
Existing images and their clones keep their original size. Filesystem capacity
reports exclude filesystem overhead. Clones read unchanged
blocks from their parent, and Ceph manages changed blocks. Snapshot protection
prevents removal while dependent clones exist. The server also retains parents
referenced by unfinished allocations. Sparse allocation and shared blocks mean
logical filesystem usage is not physical Ceph consumption.

A durable host journal, `state/<use UUID>.json`, is fsynced before remote resource
creation. `allocated → active → sealed → deleted` operations are restart-safe.
The format marker is written before exposing a cold filesystem, preventing a
retry from formatting data a job has used. A deletion remains journaled until
the server acknowledges it. The client verifies a per-use marker inside the
mounted filesystem before linking a path, so failed mount propagation falls
back cold instead of writing into an ordinary host directory. Mount operations reject symlinks, and cleanup uses
`os.Root`. Guests only see `pods/<their UID>` via SubPathExpr, with incoming mount
propagation; they never see another job's clone, credentials or the journal.

The journal/scratch root must itself be a separate bounded filesystem from host
root and kubelet. Jobs can write scratch files into their private subtree even
without acquiring a volume. Those files are removed only after the teardown
fences and after all block mounts have been detached. Make the filesystem mount
a kubelet service prerequisite, with shared mount propagation. Preload the host
`rbd` kernel module. The DaemonSet uses the dedicated `cache-volumes` Docker
build target with `ceph-common` and `e2fsprogs`, not the distroless controller.

Agent restarts retain kernel mounts and resume the local journal. Host reboot
loses running jobs; the journal allows later cleanup after kubelet teardown.
Permanent node/journal loss requires operator reconciliation: enumerate central
usage records and Ceph image names, prove the old host and its VMs can no longer
write, then reclaim or recover the affected images. Do not infer writer death
from Node NotReady or a timeout. The dashboard keeps unacknowledged deletion
pending; it does not claim that unreachable storage has been erased. This first
version does not automatically recover journals from permanently lost hosts.

There is no per-account physical-byte quota. Capacity planning must cover clone
counts, replication, retained parents and flattening. Provision Ceph pool quotas
and monitor free space, failed operations and pending deletion age. A full pool
or network outage can affect already attached jobs. Idle heads expire after
seven days without use; active clones remain fenced. Deleted use history is
pruned 90 days after acknowledged deletion; volume identities persist until
account deletion.

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
dependent clones and responding storage agents. History remains available.
Account deletion cascades metadata; agents receive a delete decision for their
orphaned images and still enforce teardown fences. See
[export and erasure](../../server/data-export.md#linux-runner-cache-volumes-opt-in).

## Rollout gates

1. Provision and validate Ceph separately: dedicated pool/namespace, appropriate
   replication and network bandwidth/latency. Create a least-privilege Ceph
   client restricted to that pool/namespace. The Kubernetes secret must contain
   `ceph.conf` and `ceph.client.<client>.keyring`, mounted read-only at `/etc/ceph`.
   Do not pass these credentials to workflows.
2. Build the dedicated agent image and updated Linux runner/controller images.
   Apply the database migration and release the server. Upgrade the RunnerPool
   CRD explicitly (Helm does not upgrade CRDs automatically).
3. Prepare bounded shared-propagation host journal filesystems and the RBD kernel
   module. Verify the agent can create/map/mount/unmount/clone/flatten/protect/
   delete images with its restricted credential.
4. In staging, set `runnersFleetLinux.cacheVolumes.enabled`, `hostPath`, `maxSlots`,
   `volumeGB`, `image.tag`, and `ceph.{pool,namespace,client,existingSecret}`. An
   explicit agent tag is required. Keep production disabled. Runner mount
   revisions use the bounded idle rollout; busy runners finish first.
5. Run `.github/workflows/linux-cache-volumes-smoke.yml` on the default branch,
   cold and then warm after publication. Test native and ordinary Docker jobs,
   on different hosts sharing Ceph. Check that mounted content actually reaches
   Kata/virtiofs and DinD; Kubernetes YAML rendering cannot establish this.
6. Overlap same-key jobs; verify private writes. Exercise a same-repo PR and a
   fork: both read warm, neither changes the protected head. Verify failure and
   cancellation discard, agent restart, delete during a running job, a new cold
   generation, and eventual physical deletion. Check dashboard attribution,
   counters, timestamps and reader/admin permissions.
7. Benchmark representative Gradle cold, warm and concurrent jobs. Measure attach,
   dependency resolution, end-to-end duration and Ceph/network load. The earlier
   1.34 GB / 39-second download / 5-second extraction is motivation, not a result
   of this implementation. Roll out only after the real integration gates pass.

Rollback: stop new volume-using jobs and let existing jobs complete. Keep agents
and their server report endpoint available until all clones have been fenced and
cleaned. Disabling the chart flag also removes the DaemonSet, so do not do that
while retaining mounts that require maintenance. Never unmount backing storage
under active jobs. Remove stale `tuist.dev/linux-cache-volumes` readiness labels
when retiring the feature. Schema rollback is destructive to history and should
follow storage cleanup, not precede it.

## Local validation (2026-09-17)

- 199 top-level Go tests passed with the race detector across cache storage (11),
  node agent (3), pod templates (33), CRD types (7), controller (139), and workflow
  client (6). Regression cases include clone isolation, blocked unmounts,
  interrupted snapshot protection, scratch symlinks, publication fencing,
  concurrent attachment during slow sealing, IP/UID/node binding and missing
  mount proofs. Ceph command tests use a scripted executor, not a live cluster.
- 14 lifecycle tests passed against an isolated PostgreSQL 16 instance with the
  actual new migration and production context. The account fixture and unrelated
  ClickHouse setup were replaced in memory with a minimal account table. Tests
  cover tenant boundaries, generation invalidation, PR/default-branch policy,
  success gating, idempotency, quotas, timestamps, analytics and history cleanup.
- Eight controller/LiveView tests passed, including actual HEEx rendering and
  mutation authorization. The changed server modules/router were compiled using
  local dependency BEAMs. This was an isolated harness, not a full `mix test` run;
  unrelated modules absent from those borrowed BEAMs produced compiler warnings.
- Linux/amd64 static builds of the storage agent and workflow client passed.
  Enabled/disabled Helm rendering, selected agent ingress, workflow/action YAML,
  four job-start-hook checks and `git diff --check` passed. The actual rendered
  dashboard was visually inspected with sample data and Noora styles.
- No Ceph resources or fleet changes were made, no image was published, and no
  performance claim was validated. Real Ceph/kernel/Kata/DinD integration,
  cross-host reuse, host-loss recovery and workload benchmarks remain rollout
  gates. The checked-in smoke workflow was not dispatched.
