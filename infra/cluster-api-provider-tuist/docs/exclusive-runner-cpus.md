# Exclusive CPU cores on Linux runner hosts

Kata runner hosts (OVH `kataRuntime: true` fleets, and the Hetzner
`bare-metal-worker` template) run the kubelet's static CPU manager with
`full-pcpus-only`. A container of a Guaranteed Pod whose CPU request is a whole,
even number gets whole physical cores to itself. Every other container, sandboxd
and the Firecracker guests it runs included, shares the cores left over.

## What the host config does

- `cpuManagerPolicy: static` with `full-pcpus-only: "true"`. A request that is
  not a multiple of the SMT level (2 on these boxes) is rejected at admission
  with `SMTAlignmentError`.
- `reservedSystemCPUs` is cpu0 and its hyperthread sibling, read from
  `/sys/devices/system/cpu/cpu0/topology/thread_siblings_list` on the host
  (`0,16` on a Ryzen 9950X). It replaces the 500m + 500m CPU reservation, so
  allocatable CPU goes from 31 to 30 on a 32-thread box. The runners-controller
  reads live allocatable for its shape caps, so nothing there changes.
- `system.slice` is pinned to the reserved core (`systemctl set-property
  system.slice AllowedCPUs=...`), so kubelet, containerd and sshd stay off the
  cores Pods get. The reserved core stays in the shared pool.
- This depends on Kata's `sandbox_cgroup_only = true`
  (`config.d/50-tuist-sandbox-cgroup.toml`, from #15250). Without it, QEMU,
  virtiofsd and the shim run in cgroups outside `kubepods.slice`, and the
  cpuset the CPU manager writes never reaches the VM. Check a node's placement
  (first check under "Validation on staging") before reading into its pinning.

## Rollout

The controller re-pushes the kubelet config to every Ready Kata node when it
rolls (`kubelet_config_drift.go`). A kubelet whose checkpoint
(`/var/lib/kubelet/cpu_manager_state`) names another policy refuses to start,
so the re-push keeps such a node on its old shared-CPU config, with the old
reservation and `system.slice` unpinned. The node keeps running exactly as before. The
Kata drop-in reaches existing nodes through the Kata host config repair and
applies to Pods created after it.

Moving a node onto the static policy is a human step, one box at a time. Each
box is about 10% of production Linux CI capacity. Canary and production writes
need `/elevate` (see `infra/AGENTS.md`, "Cluster access for agents").

1. Cordon the node and wait until no runner Pod runs on it. The
   runners-controller retires idle Pods on a cordoned node; running jobs finish.
2. On the host: `sudo rm /var/lib/kubelet/cpu_manager_state`. Leave kubelet
   running; under the `none` policy it does not rewrite the file.
3. `kubectl annotate node <node> tuist.dev/kubelet-config-hash-`. Within 10
   minutes the controller re-pushes, finds no checkpoint, writes the static
   config, pins `system.slice` and restarts kubelet.
4. Check `sudo cat /var/lib/kubelet/cpu_manager_state` shows
   `"policyName":"static"` and the node reports 30 allocatable CPUs, then
   uncordon it.

Reprovisioning a box does the same, since a fresh join has no checkpoint.

## Validation on staging

Do this on one staging box before canary:

- `cat /proc/<qemu-pid>/cgroup` shows a `cri-containerd-<id>.scope` under
  `kubepods.slice`, not a `kubepods-…slice:cri-containerd:<id>` directory at
  the cgroup root.
- `systemctl show system.slice -p AllowedCPUs` shows the reserved core.
- With a Guaranteed runner Pod running, find its QEMU process and check its
  vCPU threads: `grep Cpus_allowed_list /proc/<qemu-pid>/task/*/status`. They
  include the cores in the Pod's `cpu_manager_state` entry, and virtiofsd and
  the shim show the same list.
- For a Firecracker guest under sandboxd, the same check shows only the shared
  pool, which excludes every runner's exclusive cores.
- Run a CI job next to a busy Orb and compare job time with the Orb idle.

## Pod-level resource managers (kubelet v1.36)

**Exclusive-CPU Pods must not get KVM from the device plugin on current kubelets.**
[Kubernetes #143490](https://github.com/kubernetes/kubernetes/issues/143490)
identifies a missing device allocation in pod-level admission. Containers then
allocate devices concurrently at startup, racing in the device manager and
panicking kubelet. The proposed [upstream fix](https://github.com/kubernetes/kubernetes/pull/143494)
is not yet merged. Pools with both `exclusiveCPUs: true` and
`nestedVirtualization: true` therefore get `/dev/kvm` from the `kvm-nri-plugin`
DaemonSet (`runnersFleetLinux.nestedVirtualization.nri.enabled`), a containerd
NRI plugin that adds the device to the containers a kata-qemu Pod names in its
`tuist.dev/kvm-containers` annotation; those Pods request no
`devices.tuist.dev/kvm`. Without NRI enabled, Helm still rejects the
combination. Never give a Pod with a Pod-level budget a
`devices.tuist.dev/kvm` request. See `infra/runners-controller/AGENTS.md`
("Exclusive CPUs").

This prevents new Pods from taking the broken admission path; it does not repair
an already-inconsistent CPU checkpoint. Recover a damaged host separately after
checking its live runtime workloads. Never reset allocation state automatically
under running jobs. Production's OnDelete fleets do not upgrade existing hosts
when `kubernetesVersion` changes, so check live kubelet versions rather than
assuming every host runs the chart's version.

**A kubelet restart with exclusive-CPU Pods running leaks their cores.** On
v1.36.6 (and upstream master), `staticPolicy.AllocatePod` does not check for an
existing Pod-level allocation, so the restarted kubelet re-admits each running
Pod onto new cores and never returns the old ones. The Pods keep running, but the
old cores are in neither `defaultCpuSet` nor any entry, and the next kubelet
start fails `validateState` ("current set of available CPUs ... doesn't match")
and stops. Staging reproduced it on 2026-11-12: two Pods on `1,13` and `2,14`
moved to `3,15` and `4,16`, and the checkpoint was left with
`defaultCpuSet: 0,3-12,15-23` and no entries. Once no exclusive-CPU Pod is left
on the host, recover by stopping the kubelet, moving
`/var/lib/kubelet/cpu_manager_state` aside and starting it again. Drain
exclusive-CPU Pods before a planned kubelet restart.

A runner Pod is the runner container plus `dind`, `dind-externals`, `metrics`
and the shell bridge. On v1.34 the static policy can only pin a container whose
own requests equal its limits, so the Pod stays Burstable on the shared pool
("Runner Pods with exclusive CPUs" below). Kubelet v1.36's pod-level resource managers (alpha)
pin a Pod's `.spec.resources` budget instead: with the Topology Manager in pod
scope, a Guaranteed Pod-level budget gets one exclusive set of whole cores, and
every container without its own Guaranteed resources shares that set. It is
isolated from the node's shared pool, and CFS quota still caps it at the
budget.

A Kata host whose kubelet is v1.36 or newer (`podLevelResourceManagers`) adds:

- the `PodLevelResourceManagers` feature gate, `topologyManagerPolicy:
  best-effort` and `topologyManagerScope: pod`. The Memory Manager stays at
  `None`: the RISE boxes have one NUMA node, so there is nothing to align, and
  the CPU manager allocates the Pod-level CPU set without it.
- Kata's `static_sandbox_resource_mgmt = true`
  (`config.d/50-tuist-static-sandbox.toml`), so the VM is sized once from the
  Pod-level budget: 1 vCPU and 2 GiB for Kata plus the budget. Without it Kata
  hotplugs every container's copy of the budget (a 4 CPU / 6Gi Pod booted a
  9 vCPU, ~14.5 GiB guest inside an 8.5 GiB Pod cgroup on staging).
- `memoryReservationPolicy: TieredReservation`, which every v1.36 node gets, so
  MemoryQoS keeps protecting memory.
- the node label `tuist.dev/pod-level-resource-managers=true`. Runner Pods with
  a Pod-level budget must only land on labelled nodes.

The CPU manager reads the budget from `.spec.resources` and ignores the
RuntimeClass overhead (250m, 2560Mi), so the overhead does not stop the Pod
from getting integer CPUs. A v1.34 kubelet panics on the unknown gate, so the
config is always rendered for the kubelet a node runs: the drift loop uses the
Node's reported kubelet version, and nodes below v1.36 render and hash exactly
as before.

### Moving a fleet to v1.36

The control plane must already be on v1.36 (a kubelet cannot be newer than its
API server). A fresh OVH join installs the kubelet minor of its CAPI Machine's
`spec.version`, which the fleet's `ovhFleets.<key>.kubernetesVersion` sets.

1. Set `ovhFleets.runners-linux.kubernetesVersion` to the control plane's
   version in the env's values. The MachineDeployment is `OnDelete`, so no box
   changes.
2. Per box: cordon it, wait until no runner Pod runs on it, then delete its
   Machine. The provider reinstalls the box, and the replacement Machine joins
   with the v1.36 kubelet, the static CPU manager and the pod-level managers.
   Canary and production need `/elevate`.
3. Check the Node reports the new kubelet version, 30 allocatable CPUs on a
   32-thread box, and the `tuist.dev/pod-level-resource-managers` label.

## Validation on a v1.36 runner node

- `sudo cat /var/lib/kubelet/cpu_manager_state` lists a Pod-level entry for a
  runner Pod with a Pod-level budget.
- The `Cpus_allowed_list` of its QEMU vCPU threads, virtiofsd and the shim
  matches that entry.
- A Firecracker guest under sandboxd and a Burstable runner Pod's VM only see
  the shared pool.
- The guest has 1 + the budget's vCPUs and memory, and a Burstable Pod's guest
  is still sized from its runner container's limit.
- A CI job next to a busy Orb takes as long as with the Orb idle.

## Runner Pods with exclusive CPUs

A runner Pod is Burstable unless its pool sets `exclusiveCPUs`; Burstable Pods
run on the shared pool, so the host config pins nothing for them.

On v1.34 the blocker was the `dind` sidecar. The Kata agent applies each
container's CPU quota and memory limit inside the guest (`constrainGRPCSpec`
strips only cpusets). The guest runs cgroup v2 and gives every container its
own cgroup namespace. dockerd uses the `cgroupfs` driver, so every Docker
container a job starts nests under `dind`'s cgroup. Making every container
Guaranteed would cap `container:` jobs, `services:` and `docker build` at
whatever `dind` requests, and charge that request to the node as well.

A pool with `spec.exclusiveCPUs: true` avoids that with one Pod-level budget.
The runners-controller moves the pool's CPU and memory from the runner
container to `.spec.resources` (requests equal to limits), leaves every
container without CPU or memory of its own, and adds the
`tuist.dev/pod-level-resource-managers=true` node selector. All containers,
and every Docker container `dind` starts, then share the Pod's exclusive cores
and its memory. The pool needs `kata-qemu` and an even number of CPUs: with
`full-pcpus-only` the CPU manager allocates whole two-thread cores, and an odd
count fails admission. Turning the flag on or off rolls idle Pods; claimed
jobs finish on the Pod they started on.

The chart switch is `runnersFleetLinux.exclusiveCPUs.defaultEnabled`, which
turns it on for every Linux pool and shape with an even vCPU count (odd
shapes such as 1 vCPU keep shared cores). A pool or shape can set
`exclusiveCPUs` itself. Turn it on only once every box in the fleet carries
the label, or the opted-in pools only fit on the boxes that do.
