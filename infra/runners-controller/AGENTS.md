# runners-controller

Kubernetes controller for `RunnerPool` CRDs. Runs in the workload
cluster, reconciles Pods + per-Pod `ServiceAccount`s that the Tuist
server's dispatch endpoint authenticates via the TokenReview API.

Two reconcilers, both on the same `RunnerPool` resource but with
independent workqueues:

- **`RunnerPoolReconciler`** — converges Pods + SAs to match
  `spec.replicas`. Idle Pods (those without the
  `tuist.dev/runner-pool-owner` label) are the only ones eligible for
  scale-down deletion; runners mid-job are never killed. It also owns
  a `tuist.dev/runner-pool-drain` finalizer: deleting or renaming a
  RunnerPool (e.g. a helm pool-topology change) would otherwise let
  GC cascade-delete the owned Pods — busy ones included — so the
  finalizer holds the CR Terminating, reaps only idle Pods, and waits
  for mid-job Pods to finish their single-shot job before releasing.
  When it reaps a terminal Pod it logs the `runner` container's
  `exitCode`/`reason` first — the durable, image-independent post-mortem
  fingerprint for a runner that "lost communication" (0 = clean,
  137+OOMKilled = host OOM, 137+Error = guest OOM / in-VM kill, signal
  15 = SIGTERM, other = crash), captured before the Pod is gone.

- **`AutoscalerReconciler`** — on a 5-second cadence, calls the
  server's `/api/internal/runners/desired_replicas` endpoint and
  patches `RunnerPool.spec.replicas`. The per-pool policy math lives in
  `internal/scaling/desired.go`; tuning knobs (`minWarmPoolFloor`,
  `maxReplicas`, `scaleDownCooldownSeconds`) live in the
  `RunnerPool` spec, so a tuning change is helm-only.

  **Fleet-capacity awareness.** Both Linux shape pools and macOS Xcode
  pools share a capacity budget across siblings, so their warm capacity
  competes. The reconciler runs the per-pool target through
  `internal/scaling/allocate.go`'s `AllocateFleet`, a three-tier priority
  allocation over the pools sharing `(OS, FleetSelector)`:
  (1) real load (`claimed + queued`), (2) each pool's `minWarmPoolFloor`
  above its load, then (3) the speculative p95 buffer above that. Only
  tier 1 (real load) is inviolable — granted in full even past capacity,
  with the excess going Pending (the "add a host" signal). Tiers 2+3 are
  idle warm capacity and yield under contention — headroom first, then
  floor — to admit another pool's real queued work. So when a starved
  pool has queued jobs that don't fit, an idle pool's warm Pods are
  reaped (its desired drops *below* its floor) to free capacity, rather
  than leaving the queued jobs Pending while idle Pods hold reservations.
  The tradeoff: under sustained load on one pool, other pools' warm
  fleets shrink toward their real load, so a returning spike pays
  cold-start — a job queued now beats a warm Pod for a job that might
  arrive, and the scale-down cooldown damps the reap.

  The capacity unit and per-Pod cost depend on OS:

  - Linux: budget = sum of allocatable memory across nodes labeled
    `node.cluster.x-k8s.io/pool=<FleetSelector>` (scaled by
    `MemReserveFraction`, default 0.9); cost = `spec.podMemoryMB`.
    Memory is the only dimension — kata pins it per microVM and CPU
    is oversubscribed.
  - macOS: budget = count of nodes labeled `tuist.dev/fleet=<FleetSelector>`
    + `kubernetes.io/os=darwin`; cost = 1 per Pod (one VM per Mac
    mini under the Virtualization.framework SLA). The allocator
    apportions the host budget across competing Xcode pools.

  Only nodes that report `Ready=True`, remain schedulable, and have no
  memory, disk, or process identifier pressure contribute to either
  budget. A fleet filtered to zero capacity still takes the existing
  per-pool fallback, so a transient node roll never triggers a mass
  scale-down of warm Pods. Pod creation has a separate fail-closed
  healthy-node gate described below.

  The reconciler reads nodes via the cluster-scoped `nodes` verb in
  the ClusterRole. Any failure gathering the fleet view falls back to
  the per-pool target — a node-read blip must never trigger a mass
  scale-down. A pool with an unrecognised `OS` (or without autoscaling
  enabled) skips the allocator entirely.

  **Linux Kata provisioning admission.** Capacity and creation velocity
  are separate safety boundaries. A queue spike can fit within the
  fleet's memory budget while still asking kubelet and Kata to start too
  many sandboxes together. Before filling a Linux Kata pool's replica
  gap, `RunnerPoolReconciler` counts every alive, unclaimed Pod whose
  dispatch poller has not started across sibling pools sharing
  the same operating system and `FleetSelector`. It creates only up to
  `spec.provisioning.maxConcurrentPerFleetSelector` (default 4), using
  the lowest sibling value so one mismatched pool cannot weaken the
  fleet boundary. Excess demand remains a replica gap and is retried
  every five seconds. macOS pools skip this gate.

  Pod creates are visible to the cached client asynchronously. The
  reconciler therefore keeps a 30-second in-process reservation for each
  successful create and counts it until the cache observes the Pod. This
  prevents an immediate reconcile from admitting a second full batch in
  the cache-lag window. The controller keeps its default single reconcile
  worker; raising that concurrency requires revisiting the admission
  invariant.

  A Linux Pod that is bound to a node but whose poller has not started
  within `spec.provisioning.startTimeoutSeconds` (default 300, 0 disables)
  is reaped with a warning event and node-condition log. Unscheduled Pods
  are not recycled because recreation cannot solve a scheduler capacity
  wait. Claimed Pods and Pods whose poller has terminated are protected.
  Terminal cleanup and idle scale-down run before admission and are never
  blocked by the provisioning ceiling.

  **Allocation observability (`internal/metrics`).** Each tick the
  reconciler publishes the squeeze on the controller's existing
  `--metrics-bind-address` endpoint, per `pool`:
  `tuist_runners_autoscaler_target_replicas` (the pool's full ask, pre-
  allocation), `..._allocated_replicas` (what it got = `spec.replicas`),
  `..._min_warm_floor_replicas` (configured `minWarmPoolFloor`), and
  `..._warm_deficit_replicas` — the warm floor the allocator wanted to
  fund but couldn't under contention (`max(0, min(load+floor, target) −
  allocated)`, clamped so load starvation isn't counted). The deficit is
  the leading indicator for cold boots: alive-vs-desired only shows the
  pool converging to the *already-squeezed* target, never the squeeze
  itself. Series are dropped (`metrics.Clear`) when a pool is deleted or
  opts out of autoscaling.

  `RunnerPoolReconciler` also publishes
  `tuist_runners_pool_phase_replicas{pool,phase}` for alive Pods by
  Kubernetes phase (`Pending`, `Running`, `Unknown`). This preserves the
  runner dashboard's macOS ready vs cold-booting split without relying
  on pod-scoped kube-state-metrics series.

  Provisioning safety publishes
  `tuist_runners_pool_pending_provisioning_pods{pool}`,
  `tuist_runners_pool_admission_blocked_total{pool,reason}`,
  `tuist_runners_fleet_ready_nodes{fleet_selector,operating_system}`,
  `tuist_runners_fleet_filtered_nodes{fleet_selector,operating_system,reason}`,
  and `tuist_runners_pool_pod_start_timeouts_total{pool,reason}`.

  Alongside it, `tuist_runners_pool_oldest_pending_pod_age_seconds{pool}`
  is how long the pool's oldest un-`Running` Pod has been waiting (0 when
  none). **darwin pools only.** On a Tart pool a Pod is `Pending` from
  creation until tart-kubelet has its VM up, so this is the boot path's
  queue age. On a Linux pool `Pending` is the *healthy steady state* —
  the dispatch poller is an init container and kubelet holds a Pod in
  `Pending` for as long as any init container runs — so publishing it
  there would peg every idle pool at its warm-pool age. A Linux
  equivalent has to read the poller's own lifecycle, not the Pod phase.

  The phase count above can't stand in: a pool steadily replacing
  single-shot runners and a pool with one Pod wedged for hours both read
  `Pending=1`. Neither can tart-kubelet's
  `tart_kubelet_pod_provision_delay_seconds`, which is observed when a VM
  finally starts and so omits Pods that never boot entirely — the failure
  this gauge exists to catch, and one that leaves the Node `Ready` and
  `kube_pod_status_unschedulable` at 0 throughout.

  **Starvation vs saturation.** `..._autoscaler_claimed_jobs{pool}` and
  `..._autoscaler_queued_jobs{pool}` publish the server's two demand
  signals unsummed, and `tuist_runners_pool_idle_replicas{pool}` counts
  alive current-image Pods with no `tuist.dev/runner-pool-owner` that can
  actually accept a job right now. "Can accept" is OS-dependent, for the
  same reason the un-booted age above is darwin-only: on a Tart pool only
  `Running` counts, because a Pod still waiting on a Mac mini has no VM
  and is not capacity however long it has been alive; on Linux `Pending`
  counts, because that is where a warm dispatch poller spends its whole
  idle life. Getting this wrong inverts the reading — a fleet starved of
  hosts would report idle Pods sitting on queued work, which is the
  fingerprint of the opposite failure. Together they separate two failures
  that every other series conflates:

  - **Saturated**: `queued > 0`, `idle == 0`. Real work exceeds hosts.
    The fix is capacity.
  - **Starved**: `queued > 0` *and* `idle > 0`, sustained. Warm Pods are
    polling dispatch and getting nothing while jobs wait. The fix is
    server-side; adding hosts changes nothing.

  The second state should be impossible — an idle Pod polls continuously,
  so queued work reaches it within a poll interval — which is what makes
  the overlap a reliable fingerprint, **provided `queued` counts only
  dispatchable work**. Raw queue depth includes jobs held back because
  their account is at its platform concurrency limit; dispatch will never
  hand those out, so with a raw count the overlap is a valid steady state
  rather than a fault. The server caps each account's contribution at its
  remaining concurrency headroom before exporting the count (tuist/tuist#11981),
  which is what makes `..._queued_jobs` trustworthy here. Nothing else shows it: the phase
  count reads a warm idle Pod and a Pod running a customer job
  identically (both `Running`), `claimed+queued` stays flat while work
  drains normally (`queued` → `claimed`), and the oldest-un-booted-Pod
  age above only sees Pods that never booted, not booted Pods that never
  received work. The `Runner queue age` alert fires on either state, so
  it says something is wrong without saying which lever to pull.

  Pod-level autoscaling only — bare-metal Host count is operator-
  managed via the CAPI cluster topology, since Hetzner Robot hosts
  are monthly-billed and can't be auto-ordered. To grow capacity,
  the operator orders another `tuist-bm-<env>-*` host in the Robot
  panel and bumps the cluster topology's `runners-linux` MD
  replicas; the `hetzner-robot-controller` reflects the new server
  into a `HetznerBareMetalHost` CR automatically.

## Machine-metrics sampling (in-VM, not in the controller)

Runner-job machine metrics (CPU/memory/network/disk for the Metrics
tab) are sampled **inside the runner VM**, not by this controller. An
earlier design had the controller scrape each node's kubelet
`/stats/summary` through the apiserver node proxy, but that source is
unavailable in this cluster — the macOS Tart fleet's custom kubelet
doesn't serve the cAdvisor Summary API, and the Linux kata nodes reject
the proxied request — so it produced nothing. Sampling now lives in the
runner images (`infra/linux-runner-image`, `infra/runner-image`): a
loop reads the VM's own `/proc`+cgroup (Linux) or `vm_stat`/`netstat`
(macOS) and POSTs to `POST /api/internal/runners/pods/:pod_name/metrics`
with the runner's own per-pod SA token (audience
`tuist-runners-dispatch`). On Linux the token is isolated from the
customer container, so the sampler runs as a dedicated native sidecar
that mounts the token and shares the pod's cgroup/network namespace.

## Linux runner substrate: Hetzner Robot bare-metal hosts (caph)

Linux runner Pods run as Firecracker microVMs (via Kata Containers)
on Hetzner Robot dedicated servers (AX42-U class for staging,
AX162-R for production). Two cooperating mgmt-cluster components
drive adoption end-to-end:

* **caph** (upstream CAPI provider) claims `HetznerBareMetalHost`
  CRs, drives Robot rescue, runs `installimage`, and waits for
  kubeadm-join.
* **`hetzner-robot-controller`** (Tuist-built, see
  [infra/hetzner-robot-controller/](../hetzner-robot-controller/AGENTS.md))
  fills the gap caph leaves: reflects Robot's server inventory
  into `HetznerBareMetalHost` CRs (so caph has something to claim)
  and auto-fills disk WWNs once caph populates `hardwareDetails`.

Operator workflow becomes Scaleway-shaped:

```
operator orders AX42-U via Robot panel, sets name `tuist-bm-<env>-<n>`
        │
        ▼
hetzner-robot-controller polls Robot, sees the new server, creates
a HetznerBareMetalHost CR labeled
`app.kubernetes.io/managed-by=hetzner-robot-controller`
        │
        ▼
HetznerBareMetalMachineTemplate's `hostSelector` matches that
label; caph claims the new CR
        │
        │ (caph reads Robot credentials from `org-tuist/hetzner`
        │  Secret, contacts Robot API to reboot into rescue mode)
        ▼
Box boots Hetzner rescue; caph SSHes in via `hetzner-bare-metal-ssh-key`,
reads hardware details, writes them to `spec.status.hardwareDetails`
        │
        ▼
hetzner-robot-controller watches the CR, sees populated
hardwareDetails + empty rootDeviceHints, patches RAID 1 WWNs from
the first two disks into `spec.rootDeviceHints.raid.wwn`
        │
        ▼
caph runs `installimage` (Ubuntu 24.04 LTS on RAID 1 across both NVMes)
        │
        ▼
Box reboots into the installed OS; cloud-init runs the bare-metal
worker `KubeadmConfigTemplate` (containerd + kubeadm + `kubeadm join`)
        │
        ▼
Node registers in workload cluster, labeled
`node.cluster.x-k8s.io/pool=runners-linux` and
`tuist.dev/kata-runtime=true`
        │
        │ (kata-deploy DaemonSet sees the kata-runtime label, installs
        │  Kata Containers + Firecracker binaries, configures
        │  containerd, restarts containerd)
        ▼
Node ready to schedule runner Pods (which carry
`runtimeClassName: kata-fc`, so each Pod becomes a microVM)
```

No hand-authored `HetznerBareMetalHost` CR, no manual WWN copy.

### Fleet credentials

Robot user/pass and the shared SSH key are fleet-level — one
Hetzner Robot account spans every AX-class host across staging /
canary / production — so both 1P items live in the mgmt
cluster's own vault (`tuist-k8s-mgmt`).

The mgmt cluster doesn't yet have external-secrets-operator
installed (that's part of the workload-side platform chart), so
the operator creates the two Secrets manually once per mgmt
cluster bring-up:

```bash
# Robot webservice credentials — caph drives the Robot API with these
op read "op://tuist-k8s-mgmt/HETZNER_WEBSERVICE/username" > /tmp/robot-user
op read "op://tuist-k8s-mgmt/HETZNER_WEBSERVICE/password" > /tmp/robot-pass
kubectl --kubeconfig "$MGMT_KUBECONFIG" -n org-tuist create secret generic \
  hetzner-robot-credentials \
  --from-file=hetznerRobotUser=/tmp/robot-user \
  --from-file=hetznerRobotPassword=/tmp/robot-pass
# caph reads Robot keys from the SAME Secret as the hcloud token
# (the one named in HetznerClusterTemplate.hetznerSecretRef, today
# `hetzner`). Merge the keys in:
ROBOT_USER_B64=$(base64 -w0 < /tmp/robot-user)
ROBOT_PASS_B64=$(base64 -w0 < /tmp/robot-pass)
kubectl --kubeconfig "$MGMT_KUBECONFIG" -n org-tuist patch secret hetzner \
  --type=merge -p "{\"data\":{\"hetznerRobotUser\":\"${ROBOT_USER_B64}\",\"hetznerRobotPassword\":\"${ROBOT_PASS_B64}\"}}"
shred -u /tmp/robot-user /tmp/robot-pass

# SSH key — caph SSHes into rescue mode with this
op read "op://tuist-k8s-mgmt/HETZNER_BARE_METAL_SSH_KEY/public-key-name" > /tmp/sshname
op read "op://tuist-k8s-mgmt/HETZNER_BARE_METAL_SSH_KEY/public-key"      > /tmp/sshpub
op read "op://tuist-k8s-mgmt/HETZNER_BARE_METAL_SSH_KEY/private-key"     > /tmp/sshpriv
kubectl --kubeconfig "$MGMT_KUBECONFIG" -n org-tuist create secret generic \
  hetzner-bare-metal-ssh-key \
  --from-file=sshkey-name=/tmp/sshname \
  --from-file=ssh-publickey=/tmp/sshpub \
  --from-file=ssh-privatekey=/tmp/sshpriv
shred -u /tmp/sshname /tmp/sshpub /tmp/sshpriv
```

Once ESO lands on the mgmt cluster, both Secrets can move to
`ExternalSecret` resources in `bare-metal-staging.yaml` and this
manual step goes away.

### Bringing up a new bare-metal host (operator workflow)

1. **Order an AX-class server from [robot.hetzner.com](https://robot.hetzner.com)**.
   FSN1 for staging (matches the Cloud cluster region). Paste the
   shared SSH public key from `tuist-k8s-mgmt/HETZNER_BARE_METAL_SSH_KEY`
   into the order form. **Important**: set the server **Name** in
   the Robot panel to `tuist-bm-<env>-<n>` (e.g.
   `tuist-bm-staging-3`) — that's what `hetzner-robot-controller`
   matches on. Wait for the fulfillment email.

2. **Bump `runnersFleetLinux.pools[].autoscaling.maxReplicas`** (and
   `minWarmPoolFloor` if you want it always-hot) in
   `values-managed-staging.yaml` to match the new total host count
   × per-host microVM density. The runners-controller autoscaler on
   the workload cluster patches the `runners-linux` MD's replicas
   on the mgmt cluster to match. Push.

That's it. From the operator's point of view the only manual gate
is the Robot order itself; everything from "controller spots the
new server" through "Node is Ready with kata-deploy installed"
runs unattended.

To **watch** progress on the mgmt cluster while it happens:

```bash
kubectl --kubeconfig "$MGMT_KUBECONFIG" -n org-tuist \
  get hetznerbaremetalhost -w
```

Status goes through `(empty)` → `preparing` → `registering` →
`image-installing` → `ensure-provisioned` → `provisioned` →
`kubeadm-joined`. ~8-15 min total for an AX42-U.

To **verify the Node** registered in the workload cluster:

```bash
kubectl --kubeconfig "$STAGING_KUBECONFIG" get nodes \
  -l node.cluster.x-k8s.io/pool=runners-linux
```

The kata-deploy DaemonSet auto-installs (it watches for
`tuist.dev/kata-runtime=true`). Wait for it to mark the node
`katacontainers.io/kata-runtime=true` before runner Pods will
schedule:

```bash
kubectl --kubeconfig "$STAGING_KUBECONFIG" -n tuist-staging \
  get pods -l app.kubernetes.io/name=kata-deploy
```

### Emergency SSH access

If a bare-metal host misbehaves and caph isn't responding, the
operator can SSH in directly using the shared key from
`tuist-k8s-mgmt/HETZNER_BARE_METAL_SSH_KEY`:

```bash
op read "op://tuist-k8s-mgmt/HETZNER_BARE_METAL_SSH_KEY/private-key" \
  --account=tuist.1password.com > /tmp/hbm
chmod 600 /tmp/hbm
ssh -i /tmp/hbm root@<host-ip>
# remember to: shred -u /tmp/hbm afterwards
```

The key remains valid through reinstalls because caph configures it
into `/root/.ssh/authorized_keys` as part of the cloud-init
bootstrap.

## Token isolation (credential split, Linux pools)

Linux runner Pods run untrusted workflow code (incl. fork PRs), so
`podtemplate.Build` splits a Linux Pod into two containers running
the same runner image so the dispatch token never shares a
container with customer code:

- **`poller` init container** — the only container that mounts the
  audience-scoped projected token (`tuist-runner-token`). Runs
  `dispatch-poll.sh` with `TUIST_RUNNER_JIT_OUTPUT_PATH` set: it
  polls the dispatch endpoint, and on a claim writes the minted,
  job-scoped JIT to the shared `tuist-runner-jit` emptyDir, then
  exits 0. Runs as `runAsUser: 0` purely so it can write that
  root-owned emptyDir — it executes only our poll script, never
  customer code. Declared **after** the dind sidecar so it inherits
  the same `docker info` startupProbe gate the runner container had
  before the split.
- **`runner` main container** — holds no token. kubelet starts it
  only after the poller init container exits, so the JIT (if any)
  is already staged. Runs `run-job.sh`, which reads
  `TUIST_RUNNER_JIT_PATH` and execs the runner, or exits 0 when no
  JIT was staged (the 410 stale-image drain, or a poller abort).

Why this is enough: the token is pool-scoped and can claim a
pending `workflow_job` for the pool, so a Pod that leaks it could
race the warm pool for other tenants' jobs. The JIT is job-scoped
— it binds the runner to exactly one workflow run — so the runner
already operating under it loses nothing by holding it.

**Lifecycle consequence:** a warm-standby Linux Pod sits in
`Pending` (poller polling in Init) rather than `Running` until it
claims a job. `RunnerPoolReconciler`'s stale-Pending reap therefore
carries an `isIdle` guard so an image roll that races a claim
doesn't reap a just-claimed Pod that's momentarily Pending. The
`pod-lifecycle` billing reconciler keys on the `runner` container's
`terminated.finishedAt` (the poller/dind are init containers, absent
from `containerStatuses`), so billing still anchors on exactly the
customer job's runtime. macOS keeps the single-container shape (the
Tart VM is the isolation boundary; tart-kubelet projects the token
into it).

**Death-cause backstop:** the same reconciler also re-emits a
runner's final log on an abnormal end — a non-zero/SIGKILLed exit, or
a Pod reaped while still `Running` (the "lost communication" /
torn-down-microVM shape). It reads the `runner` container's tail via
`pods/log` and logs it to the controller's own (durable, long-lived)
stdout before the reap. Without this the trail (the `RUNNER_VITALS`
samples from `vitals.sh` + the streamed `_diag`) lives only in the
kubelet container log, which is GC'd the instant the Pod is deleted —
and `alloy` doesn't reliably win that race on a churning node, so
mid-job deaths otherwise leave nothing in Loki. A clean exit 0 (job
done, or no JIT claimed — and note a workflow that fails its own tests
still exits the runner 0) is skipped, so this fires only for runner
*infrastructure* deaths, not job outcomes.

**Rollout ordering:** ship the runner image carrying `run-job.sh`
+ the poller-mode `dispatch-poll.sh` (and pin
`runnersFleetLinux.pools[].runnerImage` to it) **before** the
controller that creates the split Pod shape. A new controller on an
old image would set `TUIST_RUNNER_JIT_OUTPUT_PATH` against a
dispatch-poll that ignores it and execs the job inside the poller
(token still mounted). The reverse (old controller, new image) is
safe: with the env unset the new script execs the runner in place —
a rollout bridge that can be dropped once every env runs the split
controller.

## dockerd sidecar (Linux pools)

Every Linux runner Pod gets a `dind` native sidecar (k8s ≥ 1.29:
initContainer with `restartPolicy: Always`) running the upstream
`docker:dind` image. The runner container stays unprivileged;
only the sidecar is `privileged: true`, bounded by the Pod's
`kata-qemu` microVM. **Linux pools must set `spec.runtimeClass:
kata-qemu`** — `podtemplate.Build` fails closed (returns an
error, controller logs it and creates no Pod) for a Linux pool
that would get the dind sidecar without it, so the privileged
container can't fall back to the host runc runtime and escape
the microVM boundary. The sidecar image (`runnersController.
dindImage`) is digest-pinned for the same reason: a privileged
container's exact bytes shouldn't move outside review.

Mirrors the ARC `gha-runner-scale-set` sidecar pattern. The
sidecar's `startupProbe` (`exec: docker info`) blocks the runner
container from starting until dockerd is reachable, replacing
what would otherwise be a polling loop on the runner side.
kubelet supervises dockerd — if it crashes, k8s restarts it.

Shape:

- `dind-sock` emptyDir at `/var/run` (both containers) exposes
  `/var/run/docker.sock`.
- `work` emptyDir at `/home/runner/actions-runner/_work` (both
  containers) so `docker run -v $PWD:/x` paths resolve the same
  on either side.
- `dind-storage` emptyDir at `/mnt/dind-disk` (sidecar only).
  Plain node-disk emptyDir — holds a sparse `disk.img` the
  sidecar entrypoint loop-mounts as ext4 onto `/var/lib/docker`
  before exec'ing dockerd. See "Why loop-mount" below.
- `DOCKER_HOST=unix:///var/run/docker.sock` injected into the
  runner so the docker CLI hits the sidecar.
- `--group=123` passed to dockerd so the socket GID matches the
  `docker` group baked into the runner image at build time.
- `--default-ulimit nofile=1048576:1048576` passed to dockerd
  so containers it spawns (incl. the buildkit container the
  `docker-container` buildx driver creates) inherit the high
  rlimit. Pair it with `ulimit -n 1048576` in the shell that
  starts dockerd to cover dockerd's own fd budget. Kata's
  microVM kernel defaults nofile=1024; without both, a docker
  build that walks a non-trivial `node_modules` tree EMFILEs.

### Why loop-mount? (the virtio-fs / overlay2 gotcha)

Per upstream kata docs (`docs/how-to/how-to-run-docker-with-
kata.md`), **virtio-fs cannot serve as an overlayfs upper
layer**. overlayfs requires `trusted.overlay.*` xattrs on the
upper, and the host kernel CAP-gates `trusted.*` writes on
virtiofsd's effective uid no matter how virtiofsd is
configured (`--xattr` alone enables the xattr methods but
still hits EPERM on the trusted.* probe; `--xattrmap` is a C-
virtiofsd flag that Rust virtiofsd-rs doesn't accept and
breaks kata sandbox creation if passed). Dockerd silently
detects the failure and falls back to vfs; on vfs, BuildKit's
docker-container driver refuses overlayfs snapshotter and
uses runc-native, which fd-bombs heavy npm trees past any
sane rlimit.

Kata's two recommended workarounds are tmpfs `medium: Memory`
(eats pod RAM proportional to the image cache, and inode-
capped) or a loop-mounted disk image. We pick the loop-mount:
the sidecar entrypoint `truncate`s a sparse 100 GiB file on
the virtio-fs-backed `dind-storage` volume, `mkfs.ext4`s it,
mounts it `-o loop` onto `/var/lib/docker`. Dockerd then sees
a real kernel-native ext4 filesystem inside the kata VM, with
full `trusted.*` xattr support — overlay2 initializes
normally and BuildKit picks the overlayfs snapshotter. The
sparse file only consumes node-disk bytes as written (no pod-
memory tax), and the loop mount is bounded by the
`truncate -s` cap.

The entrypoint installs `e2fsprogs` via apk on each boot
because `docker:*-dind` doesn't ship `mkfs.ext4` by default;
worth baking into a custom dind image once the shape settles.
StartupProbe failureThreshold bumped from 30 → 60 to absorb
the ~8 s of pre-dockerd setup time.

The sidecar image is pinned via the chart's
`runnersController.dindImage` value and threaded into the
controller as `--dind-image`. Renovate keeps the pin bumped.

## Pool variants

Linux per-tenant slot sizes are now shape-keyed via Runner
Profiles. `runnersFleetLinux.shapes` in the chart values lists
the `(vcpus, memoryGb)` tuples the fleet exposes; the server
resolves a customer's `runs-on: tuist-<name>` to the matching
shape-keyed `RunnerPool` CR. Keep that list in sync with
`:runner_linux_shapes` in `server/config/config.exs` — same
catalog from two sides.

Follow-up: bake `e2fsprogs` into a custom `tuist-dind` image so
the `apk add` on every Pod startup goes away.
