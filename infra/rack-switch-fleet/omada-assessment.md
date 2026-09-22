# Should the Omada Controller manage these switches?

This directory exists because the switches were put in standalone mode and
driven over SSH. That decision was recorded as "controller mode limits the
feature set and wants to own the configuration, which fights a git-rendered
desired state". The first half of that is checkable and the second half is not
an argument. This is the check.

**Short version: on controller 6.3, the Open API can write everything this
repository renders.** On 5.15 it could not: spanning-tree mode and LAGs were
writable only for switch stacks. So the controller path is a documented vendor
API, not a community provider on an undocumented one. What is still open is
what adoption does to a switch that already has a configuration, and that needs
a switch nobody depends on.

Measured 2026-09-22 by running both controllers locally
(`mbentley/omada-controller:5.15`, which reports 5.15.24.19, and `:6.3`, which
reports 6.3.0.45) and reading the OpenAPI document each one serves at
`/v3/api-docs`, which is what `/doc.html` renders. No switch has been adopted,
so this is what the vendor documents, not yet what an SX3832 accepts.

## What we render, against what the Open API can write

Paths are under `/openapi/v1/{omadacId}/sites/{siteId}`. `{mac}` is the
switch's MAC address.

| What `configs/ber1/*.cfg` sets | 6.3 write endpoint | Read back through the API | 5.15 |
|---|---|---|---|
| `hostname` | `PATCH switches/{mac}/general-config`, `name` | yes | same |
| Management address, `interface vlan 1` | `POST switches/{mac}/networks/{networkId}`, `ip` | yes, `GET switches/{mac}/networks` | same |
| Management VLAN | same path, `mvlan` | yes | same |
| `spanning-tree`, `spanning-tree mode rstp` | `PUT switches/{mac}/config/loopback`, `stp: 2`, plus priority and timers | **no** | stacks only |
| Per-port `spanning-tree` | `spanningTreeEnable` on a `lan-profiles` entry, or per port through `PATCH switches/{mac}/ports/{port}` | through the profile; per-port settings **no** | profile only |
| `lldp` | `PATCH lldp`, site-wide | yes | same |
| `no snmp-server` | `PATCH setting/service/snmp`, site-wide | yes | same |
| VLANs, when the rack has a plan | `lan-networks`, with membership on the profile or the port | yes | profile only |
| LAG | `PATCH switches/{mac}/ports/{port}`, `operation: aggregating` with `lagSetting` | membership, as `lagPort` in `GET switches/{mac}` | stacks only |
| Port isolation | `portIsolationEnable` on the profile or the port | through the profile | profile only |
| `telnet disable`, `no ip http server` | none | | neither is offered in controller mode, which is the same outcome by a different route |
| `no controller cloud-based` | n/a | | meaningless once adopted |
| `serial_port baud_rate`, `no system-time dst`, `no service reset-disable` | none | | device-local; what adoption does to them is part of the adoption question |

Three things follow.

**The controller version is part of the answer.** 5.15 could not set RSTP or a
LAG on a standalone switch; 6.3 can. The wrapped chart deploys 6.3.0.45 by
default, and `infra/helm/omada/values.yaml` pins that tag so the controller
that runs is the one that was measured. An upgrade means measuring again.

**Verification does not come with it.** Spanning-tree mode and per-port
spanning-tree settings can be written for a standalone switch but not read
back: only stacks return them. Everything else reads back. So the verify half
of a controller-driven loop still needs `show running-config`, which controller
mode leaves available over SSH, read-only, and which is what `fleet.sh` already
does. The split this points to is the controller writing and the existing
driver reading and diffing.

**The community evidence was about the community.** The Terraform provider not
implementing spanning tree, and calling the web API the only surface with full
coverage, described that provider's scope. The vendor's Open API has spanning
tree on 6.3.

The one material change to how the switches are driven is that **SSH becomes
read-only**: "Switch supports SSH access in controller mode, but it only
supports using the showing commands." That deletes `apply` and `replace`, and
it removes the write path whose every bug this PR has been fixing.

## The blockers that are real

The API is no longer one of them. These are.

**Adoption behaviour is unknown.** What happens to the configuration already on
`ber1-tor-a` and `ber1-tor-b` when the controller adopts them, whether it is
preserved, replaced or merged, and whether the management address survives, has
not been established. That is the first thing the prototype answers.

**Model support is likely, not tried.** The firmware carries controller
settings, since `no controller cloud-based` is in the running configuration, and
the 6.3.0.45 web bundle's device table lists both `SX3832` and `TL-SG3452`,
hardware version 1.0. Nothing has been adopted.

**The controller is another thing to run.** A
[Helm chart exists](https://github.com/mbentley/docker-omada-controller/blob/master/helm/omada-controller-helm/README.md),
so its lifecycle is solvable with what we already do. But it puts the switches'
management plane inside the cluster whose network those switches carry, which is
the same failure-domain question as a switch operator, and it wants a database
and persistent state.

## The prototype, against the staging controller

Smallest path that answers the real questions. `ber1-mgmt` is the target: an
SG3452 on `ber1-edge`'s port, carrying no traffic, that nothing depends on. Not
the ToRs.

1. **The controller** is deployed to staging by `omada-deployment.yml` and
   exposed on the tailnet as `omada`; `ber1-mgmt` reaches it through
   `ber1-edge` (`rack:edge-path`, and the route in its render). Its wizard and
   Open API client are the one-time manual step; record its tailnet IP as
   `management.controller.address`.
2. **The standalone configuration to return to** is committed:
   `backups/ber1/ber1-mgmt.cfg`, taken after zero touch provisioned and sealed it.
3. **Adopt it** with `mise run rack:omada inform ber1-mgmt` then
   `mise run rack:omada adopt ber1-mgmt`, and record what changed: does the management address survive,
   is the prior configuration preserved or replaced, what does
   `show running-config` look like afterwards, and does SSH go read-only as
   documented.
4. **Make two changes from committed data**, through the Open API with client
   credentials, from values in `sites/ber1.json`: a port description, which the
   API can read back, and spanning-tree mode, which it cannot.
5. **Read them back**, through the API where it can and over SSH where it
   cannot, and diff against the rendered desired state. That is the same
   verification loop this tool already does, so the comparison is like for like.
6. **Mark the table with what the switch accepted.** An endpoint existing is not
   the same as an SG3452 or an SX3832 honouring it.

If that works, the switch half of this directory becomes a renderer plus a
verifier, and the SSH driver keeps only what the controller cannot do: console
bring-up, backups, and recovery when the controller is unavailable.

If it does not, the finding is worth as much: it is the evidence the original
decision was missing.

## Rollback on this hardware, now measured and built

Separately from Omada, the switch has a confirmed-commit shape of its own in
`reboot-schedule`. The sequence:

1. Save a known-good startup configuration.
2. Arm a scheduled reboot far enough out to cover the change and its check.
3. Apply to the running configuration only, never saving.
4. Verify.
5. On success, cancel the timer and save. On failure or on losing the session,
   the timer fires and the switch returns to the known-good configuration.

That is automatic recovery from a change that cuts off the path used to make it.
Measured on `ber1-tor-b` on 2026-09-22: an unsaved change was discarded when the
timer fired, and a cancelled timer did not fire. `apply` now works this way; see
"Apply is a confirmed commit" in [AGENTS.md](AGENTS.md). `replace` still
overwrites the startup configuration outright.

Under the controller the same shape would need a different timer. The Open API's
`reboot-schedules` are daily, weekly or monthly, with no one-shot form, so the
nearest equivalent is a daily schedule a few minutes out, deleted on success.
What a controller-managed switch reloads when that fires is part of the adoption
question.

## Coordination, if this becomes a controller

The per-rack lock is a directory under `/tmp`. It serialises runs on one machine
and nothing else: two operators on two laptops, or a laptop and a CI job, do not
see each other's lock. That is honest for what it is, and it is not a
distributed lock.

A `Lease` is the right shape once there is something in the cluster to hold one,
and it costs no switch connections. Two properties matter more than the
mechanism. Every writer has to participate, including a human running the CLI,
which argues for a single executor rather than a lock everyone is trusted to
take. And a lease expiring must not start a second change: a change whose
outcome is unknown needs a human, because neither a Lease nor a Job gives
exactly-once, and the thing being changed reboots.
