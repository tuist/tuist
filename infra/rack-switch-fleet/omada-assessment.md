# Should the Omada Controller manage these switches?

This directory exists because the switches were put in standalone mode and
driven over SSH. That decision was recorded as "controller mode limits the
feature set and wants to own the configuration, which fights a git-rendered
desired state". The first half of that is checkable and the second half is not
an argument. This is the check.

**Short version: the capability objection does not survive contact with the
vendor's own feature list.** Everything this repository renders is configurable
in controller mode. What is not settled is whether it can be driven from git
through a supported API, and that is now the question worth answering rather
than the one that was assumed.

## What we actually render, against what controller mode supports

Sourced from TP-Link's own [list of switch functions available under the Omada
SDN Controller](https://support.omadanetworks.com/us/document/13032/). Not
verified on an SX3832: this is a documentation review, and the prototype below
is what would make it evidence.

| What `configs/ber1/*.cfg` sets | Controller mode | Note |
|---|---|---|
| Management address, `interface vlan 1` | **Yes** | "System IP (Static/DHCP)" |
| Management VLAN | **Yes** | listed explicitly |
| Hostname | **Yes** | "Device Description" |
| `spanning-tree mode rstp` | **Yes** | STP, RSTP and MSTP all listed |
| Per-port `spanning-tree` | **Yes** | port configuration is covered |
| `lldp` | **Yes** | LLDP-MED |
| VLANs (when the rack has a plan) | **Yes** | 4K VLANs |
| Port roles, LAG, isolation | **Yes** | |
| `telnet disable`, `no ip http server` | **Not listed** | neither is offered in controller mode, which is the same outcome by a different route |
| `no snmp-server` | **Not listed** | worth confirming |
| `no controller cloud-based` | n/a | meaningless once adopted |
| `serial_port baud_rate` | **Not listed** | console only, and console bring-up stays either way |

So the config this repository renders is almost entirely expressible. The one
material change is that **SSH becomes read-only**: "Switch supports SSH access
in controller mode, but it only supports using the showing commands." That
deletes `apply` and `replace` and leaves the driver doing what it is best at,
reading. It also removes the write path whose every bug this PR has been fixing.

## The blockers that are real

Capability is not the problem. These are.

**There is no fully supported write API.** The Open API is documented and
authenticated with client credentials, but its published guide covers site
creation, not switch configuration. The community
[Terraform provider](https://github.com/wncservices/terraform-provider-omada)
is explicit that "the web API is the only surface with full configuration
coverage", and the web API is the undocumented one behind the UI. It reads
switch ports from the web API and writes them through the Open API, and it does
not implement spanning tree, PoE, per-port QoS or storm control. It is v0.6.x
and reserves breaking changes for v1.0.0.

**So the choice is between two unsupported things**, and that is the honest
framing: a bespoke SSH driver we maintain, or a community provider on an
undocumented API that the vendor can change. The second is smaller code and
larger blast radius when it breaks.

**Adoption behaviour is unknown.** What happens to the configuration already on
`ber1-tor-a` and `ber1-tor-b` when the controller adopts them, whether it is
preserved, replaced or merged, and whether the management address survives, has
not been established. That is the first thing the prototype answers.

**The controller is another thing to run.** A
[Helm chart exists](https://github.com/mbentley/docker-omada-controller/blob/master/helm/omada-controller-helm/README.md),
so its lifecycle is solvable with what we already do. But it puts the switches'
management plane inside the cluster whose network those switches carry, which is
the same failure-domain question as a switch operator, and it wants a database
and persistent state.

## The prototype, ready to run when the rack is reachable

Smallest path that answers the real questions. `ber1-mgmt` is the target: it is
an SG3452 sitting in storage, it is not carrying traffic, and nothing depends on
it. Not the ToRs.

1. **Stand the controller up** from the Helm chart, in staging, reachable from
   the management network. No switches adopted yet.
2. **Back up `ber1-mgmt` first** with `mise run rack:fleet backup ber1-mgmt`, so
   there is a known-good standalone configuration to return to.
3. **Adopt it** and record what changed: does the management address survive,
   is the prior configuration preserved or replaced, what does
   `show running-config` look like afterwards, and does SSH go read-only as
   documented.
4. **Make one change from committed data.** The smallest representative one is
   the management VLAN or a port description, applied through the Open API with
   client credentials, from a value in `sites/ber1.json`.
5. **Read it back** through the API and over SSH, and diff against the rendered
   desired state. That is the same verification loop this tool already does, so
   the comparison is like for like.
6. **Answer the coverage question with evidence**: which of the table's rows can
   be written through the Open API rather than only the UI or the web API.

If that works, the switch half of this directory becomes a renderer plus a
verifier, and the SSH driver keeps only what the controller cannot do: console
bring-up, backups, and recovery when the controller is unavailable.

If it does not, the finding is worth as much: it is the evidence the original
decision was missing.

## Rollback on this hardware, which is also unverified

Separately from Omada, a confirmed-commit shape may already be available. The
switch has `reboot-schedule`, and the controller feature list confirms "Reboot
Schedule". The sequence to test is:

1. Save a known-good startup configuration.
2. Arm a scheduled reboot far enough out to cover the change and its check.
3. Apply to the running configuration only, never saving.
4. Verify.
5. On success, cancel the timer and save. On failure or on losing the session,
   the timer fires and the switch returns to the known-good configuration.

That is automatic recovery from a change that cuts off the path used to make it,
which is the failure this tool currently has no answer to. **The PR does not
implement it**: `apply` saves before verifying, and `replace` overwrites the
startup configuration outright. Worth testing on `ber1-tor-b` before it is
relied on, and worth having before any change is made to `ber1-tor-a` again.

## Coordination, if this becomes a controller

The per-rack lock is a directory under `TMPDIR`. It serialises runs on one
machine that share a `TMPDIR` and nothing else: two operators on two laptops, or
a laptop and a CI job, do not see each other's lock. That is honest for what it
is, and it is not a distributed lock.

A `Lease` is the right shape once there is something in the cluster to hold one,
and it costs no switch connections. Two properties matter more than the
mechanism. Every writer has to participate, including a human running the CLI,
which argues for a single executor rather than a lock everyone is trusted to
take. And a lease expiring must not start a second change: a change whose
outcome is unknown needs a human, because neither a Lease nor a Job gives
exactly-once, and the thing being changed reboots.
