# Design: declarative Vultr bare-metal nodes via the in-house provider

Status: design. The Santiago box behind the `sa-west` Kura region
(`kura-sa-west-1`) is prepared but hand-joined; nothing adopts, heals or
releases it yet.

## Scope

`sa-west` is the first Kura region on Vultr. South America is the reason:
neither OVH nor Scaleway nor Hetzner sells there, which is what put a fourth
provider in the fleet at all. OVH's own datacenter availability API returns
`bhs, ca-east-tor-a, eu-west-par-{a,b,c}, fra, gra, hil, lon, rbx, sbg, sgp,
syd, waw, ynm`.

The box is a worker in the same cluster as every other region's node pool, so
this is the Elastic Metal pattern with a different provisioning call. See
[scaleway-elastic-metal-support.md](scaleway-elastic-metal-support.md) for the
shared parts: the stub `TuistCluster`, the identity-mint self-join, the orphan
reclaimer, and why upstream per-provider CAPI providers do not fit clusters
whose infrastructure provider is caph.

## The contract Vultr cannot honour

Every existing Linux kind implements the same lifecycle: adopt a pre-prepped
box, self-join it, and **reinstall it back to the pool on release**. The
reinstall is what makes a released box safe to re-adopt, and on OVH and Dedibox
it is also what lays down the disk layout, because both APIs take a
partitioning plan (`internal/ovh` `PlanStorage`, `internal/dedibox`
`planPartitions`): a mirrored root plus a separate XFS `/data`.

**Vultr's API has no partitioning control.** Its installer offers RAID 1 across
both disks, which is one filesystem spanning the pair, or no RAID.
`POST /v2/bare-metals/{id}/reinstall` takes an optional hostname and nothing
else. So the layout the cluster requires cannot be produced by the install, and
`mise run baremetal:prep-vultr` exists to convert the box afterwards: split the
mirror, hand the freed disk to XFS `/data`, leave the root running on the
remaining leg.

That layout is not cosmetic. `tuist.kuraVolumeQuotaProgram` leaves every cache
volume unbounded unless `/data` is a separate XFS filesystem mounted with
project quotas, and the self-join refuses a box that cannot enforce. An
unbounded `/data` is what caused the 2026-07-16 eu-central outage.

**Consequence for this kind:** release-then-reinstall returns a box in a state
the cluster will refuse to re-adopt. A `VultrMachine` therefore needs a
conversion stage the other kinds do not have, run over SSH after the reinstall
reports done and before the box is marked adoptable. The alternative, leaving
released boxes unconverted, turns every release into manual work and silently
breaks the "scale a MachineDeployment" contract that makes the other fleets
declarative.

Two ways to place that stage, to be decided when this is built:

1. **In the controller**, as a `Converting` stage between `Installing` and
   `Adopting`. Keeps the lifecycle closed, at the cost of the controller owning
   a disk-surgery step and needing the fleet key to reach a box it has just
   reinstalled.
2. **In `prep-vultr`**, with release leaving the box out of the pool until an
   operator re-preps it. Simpler controller, but release stops being automatic,
   which is most of what the kind is for.

(1) is the better fit for a fleet that scales by `kubectl scale`, and the
conversion is already scripted and idempotent, so the controller is re-running
a known-good procedure rather than inventing one.

## CRDs

| Kind | Purpose |
|---|---|
| `VultrMachine` (+ `…Template`) | One Vultr bare-metal server: region, plan, OS, `fleetName`, `nodeTaints`, and the adoption selector. Reinstall-on-release, with the conversion stage above. |

Everything else is shared: the stub `TuistCluster`, the `controllers/linux`
package (`linux_cloudinit.go`, `node_storage.go`, the kubelet and containerd
drift checks), and the operator-minted kubelet identity.

## Adoption

The other kinds adopt by a provider-side marker set as the last step of prep:
an OVH `displayName` prefix, a Dedibox tag. Vultr bare metal carries both a
`label` and a `tags` list (the singular `tag` field is deprecated), so either
can serve. The label is already in use here (`tuist-kura-vultr-production-sa-west`,
set at order time and following the `adoptDisplayNamePrefix` convention), which
argues for prefix-matching the label and keeping `tags` free.

Whichever is chosen, the marker has to be settable independently of the install,
because prep names a box into the pool only after it is converted.

## Provider client (`internal/vultr`)

The surface the reconciler needs, mirroring `internal/ovh`:

| Operation | Endpoint |
|---|---|
| `FindAdoptableServer` | `GET /v2/bare-metals` filtered by region, plan and label prefix, minus already-claimed |
| `GetServer` | `GET /v2/bare-metals/{id}` for IP and status |
| `RegisterSSHKey` | `POST /v2/ssh-keys` |
| `StartInstall` | `POST /v2/bare-metals/{id}/reinstall` |
| `InstallState` | poll `GET /v2/bare-metals/{id}` status |
| `SetLabel` | `PATCH /v2/bare-metals/{id}` for the mark step |

Unverified and worth confirming against a live key before building: whether the
list endpoint supports server-side filtering by label or tag, or whether the
client filters client-side; and what the status field reads during and after a
reinstall.

## Credential

`VULTR_API` in `tuist-k8s-<env>`, an API Credential item with an `api-key`
field, mirroring `OVH_API` and `DEDIBOX_SCW_API`. It does not exist yet;
`VULTR_FLEET_SSH` is currently the only Vultr item.

Vultr gates API keys on a **source IP allowlist**, which the other providers do
not. A key that works from a laptop will fail from the controller unless the
cluster's egress address is allowlisted, and that address is the one the
`stable-egress-controller` keeps pinned. This is the first thing to check when
the controller gets 401s that a local `curl` does not reproduce.

## Out of scope

- Ordering. As with every other kind, boxes are pre-ordered in the console; the
  controllers never buy hardware.
- Private networking. `sa-west` is a single-box region whose gateway binds the
  box's public IP, and Kura's peer plane is a public host. A VPC would be an
  unused interface, and unused private networks on bare metal have caused
  problems before.
- Multi-box regions. `replicas` stays 1 until South American volume argues
  otherwise.
