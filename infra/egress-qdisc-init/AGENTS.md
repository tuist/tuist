# egress-qdisc-init

Init container image that enforces the per-tenant Kura egress ceiling
(`egress_burst_mbps`) with a root qdisc on the pod's own `eth0`, inside the pod
network namespace.

## Why it exists

On the bare-metal Kura regions the customer read path is
`kura pod → co-located hostNetwork ingress-nginx → client`. Cilium's bandwidth
manager (the enforcer behind the `kubernetes.io/egress-bandwidth` pod
annotation) paces at the `fq` qdisc on the physical NIC only, so the node-local
hop to nginx never crosses a paced device and the nginx→client leg has no pod
identity. The annotation is therefore bypassed on the read path
(tuist/tuist#12363). A root qdisc installed inside the pod netns shapes all pod
egress — node-local hops included — before packets cross the veth into the
host.

## Design invariants (do not weaken)

- **Fail-closed.** Any failure in `entrypoint.sh` fails the init container and
  the pod never starts unshaped. No `|| true`, no ignored exit codes.
- **Init container, not a sidecar.** The qdisc survives the init container's
  exit because it lives in the pod netns, which all containers share. Regions
  pack many instances per box; a resident per-pod process multiplies.
- **No ownership conflict.** Cilium programs the host side (`lxc*` hooks, the
  NIC). Nothing else installs qdiscs inside pod namespaces.
- **htb + fq_codel leaf**, not bare tbf: same behavior, but leaves room for a
  small high-priority class (health probes) without changing the mechanism.

## Wiring

The kura-controller renders this image as an init container into KuraInstance
pods whenever the instance spec carries the `kubernetes.io/egress-bandwidth`
pod annotation (see `infra/kura-controller/controllers/kurainstance_controller.go`).
The rate arrives as `EGRESS_BURST_MBPS` (integer Mbit/s), parsed from that
annotation's `<n>M` value. The image reference reaches the controller via the
`KURA_EGRESS_QDISC_INIT_IMAGE` env var (`kuraController.egressQdiscInitImage`
Helm value); the controller fails the reconcile loudly if an instance needs the
init container but no image is configured.

The image is built by `.github/workflows/egress-qdisc-init-image.yml` and
published to `ghcr.io/tuist/egress-qdisc-init`. Pin deployments by digest.

## What it does not solve

Box-level aggregate caps (per-pod ceilings oversubscribe the NIC by design),
wire-truth accounting of the nginx→client leg, and bandwidth floors
(`tuist.dev/egress-mbps` bin-packing) are separate concerns. See the design
handover in tuist/tuist#12363 before extending this.
