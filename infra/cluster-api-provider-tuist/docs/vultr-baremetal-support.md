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

## Adoption: tags, not a label prefix

Verified against the live API 2026-09-07.

The other kinds adopt by a provider-side marker set as the last step of prep: an
OVH `displayName` **prefix**, a Dedibox **tag**. `GET /v2/bare-metals` does
filter server-side, on `label`, `tag` and `region`, but **`label` matches
exactly**, not by prefix:

| query | matches |
|---|---|
| `label=tuist-kura-vultr-production-sa-west` | 1 |
| `label=tuist-kura-vultr-production` (prefix) | 0 |
| `label=TUIST-KURA-VULTR-PRODUCTION-SA-WEST` | 1 (case-insensitive) |

So the OVH `adoptDisplayNamePrefix` pattern has no server-side equivalent here.
Adoption follows **Dedibox instead**: an `adoptTag` on the `tags` list, narrowed
by `region` and `plan`, which is one query rather than listing the fleet and
filtering client-side. The `label` stays what it is now, the human-readable
per-box name.

The mark step is `PATCH /v2/bare-metals/{id}` with a `tags` array, which returns
202 and is immediately visible to `?tag=`. Both halves are confirmed working on
`kura-sa-west-1`, which now carries `tags: ["tuist-kura-vultr-production"]`.

The marker is settable independently of the install, which the conversion stage
requires: prep tags a box into the pool only once it has been converted.

## Provider client (`internal/vultr`)

The surface the reconciler needs, mirroring `internal/ovh`:

| Operation | Endpoint | Status |
|---|---|---|
| `FindAdoptableServer` | `GET /v2/bare-metals?tag=&region=`, minus already-claimed | verified |
| `GetServer` | `GET /v2/bare-metals/{id}` | verified |
| `SetTags` (mark) | `PATCH /v2/bare-metals/{id}` with `tags` | verified, 202 |
| `RegisterSSHKey` | `POST /v2/ssh-keys` | unverified |
| `StartInstall` | `POST /v2/bare-metals/{id}/reinstall` | unverified |
| `InstallState` | poll `GET /v2/bare-metals/{id}` `status` | unverified |

A bare-metal object carries `app_id, cpu_count, date_created, disk, features,
gateway_v4, id, image_id, internal_ip, label, mac_address, main_ip, netmask_v4,
os, os_id, plan, power_status, preemptible, region, snapshot_id, status, tag,
tags, user_scheme, v6_main_ip, v6_network, v6_network_size, vpcs`. `status` reads
`active` on a healthy box; `power_status` is separate.

### Reinstall, measured

Observed end to end on `kura-sa-west-1`, 2026-09-07:

| t after POST | `status` / `power_status` | reachable |
|---|---|---|
| 0s (the 202 body) | `active` / `running` | yes, the OLD system |
| ~54s | `pending` / `running` | no |
| ~313s | `active` / `running` | **no** |
| ~399s | `active` / `running` | yes, uptime 34s |

Three traps for `InstallState`, all of which would produce a controller that
self-joins a box that is not ready:

1. **The 202 body echoes the pre-transition state.** `StartInstall` learns
   nothing from its own response; only polling tells you anything.
2. **SSH stays up for roughly a minute after the 202**, because the old system
   is still running. Reachability is not a start signal, and a naive poller
   that waits for SSH returns instantly against a system about to be wiped.
3. **`status` returns to `active` about 86s before the box answers.** `active`
   alone is not ready. The condition that works is a *fresh* system: SSH
   answers and uptime is small.

Reinstall **preserves** the hostname passed in the request, the registered fleet
SSH key, the label, the tags, and the RAID 1 disk configuration chosen at order
time. It **wipes** `/data` and its fstab entry, which is the conversion stage
argued for above, now demonstrated rather than predicted.

It also triggers a **fresh array resync of roughly 75 minutes**, during which the
conversion must not run: splitting a rebuilding mirror leaves the root on a leg
that was never fully populated, and `prep-vultr` refuses (verified against a
real resyncing array). So the release-to-adoptable cycle is about 6.5 minutes of
install plus over an hour of resync before the box can be converted and marked
back into the pool. A `VultrMachine` reconciler has to treat that as a normal
duration rather than a stall, and it is worth knowing before anyone sizes a
`MachineHealthCheck` timeout against it.

## Credential

`VULTR_API` in `tuist-k8s-<env>`, an API Credential item with an `api-key`
field, mirroring `OVH_API` and `DEDIBOX_SCW_API`. Created 2026-09-07 in
`tuist-k8s-production`.

Vultr gates API keys on a **source IP allowlist**, which the other providers do
not, and the allowlist starts empty: a fresh key authenticates from nowhere and
returns `401 Unauthorized IP address: <caller>`. The error names the address it
rejected, which is the fastest way to see whether the caller was reached over
IPv4 or IPv6.

The production key currently allows any IPv4 and any IPv6, which is what
unblocked bring-up. That should narrow to the cluster's stable egress address
once the controller is the only consumer, since the key does not expire and can
destroy servers, and a wide-open ACL is not a control. That address is the
Hetzner Floating IP the `stable-egress-controller` pins to the `md-egress` pool
rather than a literal in this repo.

## Out of scope

- Ordering. As with every other kind, boxes are pre-ordered in the console; the
  controllers never buy hardware.
- Private networking. `sa-west` is a single-box region whose gateway binds the
  box's public IP, and Kura's peer plane is a public host. A VPC would be an
  unused interface, and unused private networks on bare metal have caused
  problems before.
- Multi-box regions. `replicas` stays 1 until South American volume argues
  otherwise.
