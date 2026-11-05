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

## Runner Pods are not Guaranteed yet

Until every container of a runner Pod has CPU and memory requests equal to
limits, runner Pods stay Burstable. Burstable Pods run on the shared pool, so
the host config pins nothing for them.

The open question is the `dind` sidecar. The Kata agent applies each
container's CPU quota and memory limit inside the guest (`constrainGRPCSpec`
strips only cpusets). The guest runs cgroup v2 and gives every container its
own cgroup namespace. dockerd uses the `cgroupfs` driver, so every Docker
container a job starts nests under `dind`'s cgroup. A Guaranteed Pod therefore
caps `container:` jobs, `services:` and `docker build` at whatever `dind`
requests, and that request is also charged to the node. On Kubernetes 1.34
two containers cannot share one budget. The pod-level resource managers that
would allow it (`PodLevelResourceManagers`) are alpha in 1.36.
