# runners-controller

Kubernetes controller for `RunnerPool` CRDs. Runs in the workload
cluster, reconciles Pods + per-Pod `ServiceAccount`s that the Tuist
server's dispatch endpoint authenticates via the TokenReview API.

Two reconcilers, both on the same `RunnerPool` resource but with
independent workqueues:

- **`RunnerPoolReconciler`** — converges Pods + SAs to match
  `spec.replicas`. Idle Pods (those without the
  `tuist.dev/runner-pool-owner` label) are the only ones eligible for
  scale-down deletion; runners mid-job are never killed.

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
