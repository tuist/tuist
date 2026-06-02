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

- **`AutoscalerReconciler`** — on a 5-second cadence, calls the
  server's `/api/internal/runners/desired_replicas` endpoint and
  patches `RunnerPool.spec.replicas`. The per-pool policy math lives in
  `internal/scaling/desired.go`; tuning knobs (`minWarmPoolFloor`,
  `maxReplicas`, `scaleDownCooldownSeconds`) live in the
  `RunnerPool` spec, so a tuning change is helm-only.

  **Fleet-capacity awareness (Linux).** Linux shape pools share one
  bare-metal node pool, so their speculative warm headroom competes for
  the same memory. For `os: linux` pools the reconciler runs the
  per-pool target through `internal/scaling/allocate.go`'s
  `AllocateFleet`, a three-tier waterfall over the pools sharing a
  `FleetSelector`: (1) every pool's `minWarmPoolFloor`, (2) real load
  (`claimed + queued`), then (3) the speculative p95 buffer from
  whatever memory is left. Tiers 1+2 are always honored (excess goes
  Pending — the "add a host" signal); tier 3 is squeezed under
  contention, so an idle shape's warm Pods fall back toward its floor to
  admit another shape's real queued work. Memory is the only dimension
  (kata pins it per microVM; CPU is oversubscribed). Fleet allocatable
  is summed from nodes labeled `node.cluster.x-k8s.io/pool=<FleetSelector>`
  (cluster-scoped `nodes` read in the ClusterRole), scaled by
  `MemReserveFraction` (default 0.9). Any failure gathering the fleet
  view falls back to the per-pool target — a node-read blip must never
  trigger a mass scale-down. macOS pools (one VM per host, no
  bin-packing) keep the plain per-pool path.

  Pod-level autoscaling only — bare-metal Host count is operator-
  managed via the CAPI cluster topology, since Hetzner Robot hosts
  are monthly-billed and can't be auto-ordered. To grow capacity,
  the operator orders another `tuist-bm-<env>-*` host in the Robot
  panel and bumps the cluster topology's `runners-linux` MD
  replicas; the `hetzner-robot-controller` reflects the new server
  into a `HetznerBareMetalHost` CR automatically.

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
