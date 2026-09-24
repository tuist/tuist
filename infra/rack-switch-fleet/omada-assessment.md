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
| `telnet disable`, `no ip http server` | none | | not offered in controller mode; adoption left telnet disabled and turned the web server on |
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

**Adoption takes over the switch's login and services.** Measured on
`ber1-mgmt`; see "Adoption, measured on ber1-mgmt" below. What it does to the
rest of the configuration already on `ber1-tor-a` and `ber1-tor-b`, whether it
is preserved, replaced or merged, has not been established yet.

**Model support is likely, not tried.** The firmware carries controller
settings, since `no controller cloud-based` is in the running configuration, and
the 6.3.0.45 web bundle's device table lists both `SX3832` and `TL-SG3452`,
hardware version 1.0. The SG3452 has been adopted; the SX3832 has not.

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
   `ber1-edge` (its rack-edge pod, and the route in its render). Its wizard and
   Open API client are the one-time manual step; record its tailnet IP as
   `management.controller.address`.
2. **The standalone configuration to return to** is in git history:
   `backups/ber1/ber1-mgmt.cfg` as it was before adoption, taken after zero touch
   provisioned and sealed it.
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

## Adoption, measured on ber1-mgmt

Steps 1 to 3 ran on 2026-09-23, against the staging controller (6.3.0.45) and
`ber1-mgmt` on firmware 1.30.0.

- **The path needs its MSS clamped.** The switch opens its management
  connection to TCP 29814 advertising an MSS for a 1500-byte link; the tailnet
  carries 1280. The controller's full-size segments never arrived, so the switch
  saw only the last segment of each reply, gave up after five seconds, and the
  controller reported the adoption as failed. Discovery on UDP 29810 and the Open
  API were unaffected, being small. `ber1-edge` now clamps the MSS of what it
  forwards into `tailscale0` (`lib/edge.sh`), and adoption succeeded on the next
  try.
- **The controller must advertise its tailnet address** as the device
  management host, which starts unset. `rack:omada controller`, and `adopt`
  before it adopts, set it from `management.controller.address`.
- **Adoption did not reboot the switch.** Its uptime ran on through it.
- **Adoption applies the site's SSH setting, which starts disabled.** Port 22
  refused connections until the site's SSH was turned on through the API; then
  it answered again. `rack:omada controller` keeps it on.
- **Adoption replaces the switch's login with the site's device account.**
  Afterwards `tuist`, with the fleet key or its password, is refused. The
  account the controller set is the site's device account (`admin` here, from
  the setup wizard), one account for every switch in the site. So under the
  controller there are no per-switch logins, and the fleet key does not survive
  adoption.
- **What adoption kept:** the management address on VLAN 1, the route to the
  tailnet, RSTP and per-port spanning tree, LLDP, `telnet disable`,
  `no snmp-server` and the console baud rate.
- **What it changed:** the hostname became the switch's MAC; VLAN 1 was renamed
  `Default`; the NTP servers were removed; the web server was turned back on
  (`ip http server`); `no controller cloud-based privacy-policy` went.
- **What it added,** all controller defaults: `ip ssh block-l3`, which allows
  SSH only from the switch's own subnet; IPv6 routing and autoconfiguration on
  the management interface; loopback detection; auto-VoIP;
  `cloud-firmware upgrade auto-check`; `sdm prefer omada`; and on every port a
  `PortN` description and `lldp med-status`. The diff is the commit that
  replaced `backups/ber1/ber1-mgmt.cfg` with the adopted configuration; the
  standalone one is the version before it.
- **Writes through the Open API are honoured and kept** (steps 4 to 6). The
  hostname (`PATCH switches/{mac}/general-config`), a port description
  (`PATCH switches/{mac}/ports/{port}`, which needs the port's `profileId`) and
  the spanning-tree mode (`PUT switches/{mac}/config/loopback`, which replaces
  the whole block: mode, priority and timers) were written, and the first two
  read back through the API. Then the switch was rebooted through the
  controller, came back adopted about three minutes later, and its running
  configuration over SSH carried all three and nothing else changed.
  `rack:omada apply` does this from the render.
- **A reboot keeps what the controller wrote.** So the confirmed commit this
  directory built on `reboot-schedule` does not carry over: under the
  controller, going back is writing the previous values again.
- **The SX3832 behaves the same.** Both ToRs were adopted the same day; the
  controller does to them what it does to the SG3452, with ten-gigabit port
  names (`controller-baselines/sx3832.tsv`).

The login was the finding that shaped the design. Every SSH path in this
directory, including the spanning-tree read-back the reconciler sketch keeps,
authenticated as `tuist` with the fleet key, which adoption removes. So the
site's device account is now set deliberately, from the 1Password item
`management.controller.device_account_item` names, by `rack:omada controller`
before anything is adopted; fleet sessions to a switch marked `adopted` log in
with that account's password instead of the key.

## VLANs, port settings, link aggregation and addressing, measured

On `ber1-tor-b` and `ber1-mgmt`, 2026-09-23, each written through the Open API,
read back over SSH, then undone.

- **VLANs are site networks.** `POST lan-networks` with `purpose: 0` and the VLAN
  id creates one, and it is carried tagged on every port whose profile is `All`,
  which is every port by default (`switchport general allowed vlan 20 tagged`,
  plus `vlan 20` with its name and a controller `profile network` line).
  `DELETE lan-networks/{id}` removes it everywhere. A port needs an override only
  when its tagged set differs from every site network.
- **Per-port settings are overrides on the port's profile.** VLAN membership
  (`profileVlanOverrideEnable`, native and tagged network ids) and spanning tree
  off (`no spanning-tree` on the switch) both took. Returning a port to its
  profile is `profileOverrideEnable: false`; asking for the VLAN part alone to
  follow the profile is refused. The port list does not echo overrides back, so
  they are verified over SSH, like spanning-tree mode.
- **Link aggregation is LACP only.** `operation: aggregating` with `lagType: 2`
  made `interface port-channel 1` with `channel-group 1 mode active` on its
  members; the static type (`lagType: 1`) was refused with a bare "General
  error". Members cannot be changed through the port endpoint afterwards, and
  `DELETE switches/{mac}/lags/{id}` dissolves the group.
- **The management address and gateway are writable and readable.** `POST
  switches/{mac}/networks/{id}` with the object as read and a static `ip`
  (including the fallback fields, without which it is refused) moved a switch
  from DHCP to its site address with the edge node as gateway, without dropping
  its controller connection. The switch prints it as `ip address <a> <mask>
  gateway <g>`. So every switch's management gateway is now the edge node, and
  the static tailnet route the ToRs carried is gone: the API had no way to write
  it, so a reset switch could never get it back.
- **Raw CLI goes through device CLI configurations** for anything the API does
  not model. One config per device (`devices: [{deviceMac}]` at creation; adding
  a device later is refused), then `apply`. That removed the ToRs' old route.

## Zero touch through the controller, measured

A factory reset of `ber1-mgmt` on 2026-09-23 (`POST devices/{mac}/forget`, which
resets a switch and reboots it), with DHCP served on `ber1-edge` by a systemd
unit that the rack-edge pod has since replaced:

1. The factory switch asked for DHCP and for option 138 among its options, got
   its site address from its reservation, with the edge node as router and the
   controller's tailnet address in option 138, and announced itself to the
   controller. It was pending about two minutes after the reset.
2. Its Auto Install is on at the factory: it asked the DHCP server for a file
   over TFTP unprompted. That closes the question zero touch through Auto
   Install left open; the controller path does not need it.
3. Adoption with the factory login (`admin`/`admin`) took under a minute, and
   the site's device account replaced the login.
4. After one pass of the Open API (hostname, spanning-tree mode), the only
   difference from the render was the management address being DHCP; writing
   it static with the edge node as gateway left the switch matching its render.

Repeated the same day with the rack-edge pod serving DHCP and the reconciler
doing the adoption and the writes (its `apply` command, since it deploys only
once merged). Reset at 13:05:28 UTC; the pod acknowledged the switch's request
at 13:07:43 with its reservation, the edge node as router and option 138 as
`64:54:84:5c` (100.84.132.92), which the switch had asked for; pending at
13:08:12; `apply` adopted it and wrote its render by 13:14:27; the controller
reported it connected at 13:15:29, and a minute later SSH found it matching its
render. A diff taken in between, while the controller was still pushing its
writes, showed per-port spanning tree and the static management address
missing, so read a switch only once the controller has settled.

So a switch behind the edge node is zero touch: plugged in, it gets its address
and its controller, and adoption plus one write pass bring it to its render. The
reconciler does both. A switch on the house network, like the ToRs at home, gets
the house router's DHCP, which names no controller; in the data center the
management segment is the rack's own.

## What the reconciler looks like

Built as [`infra/rack-switch-controller`](../rack-switch-controller/AGENTS.md),
from the sketch below; that node records where it differs. Adoption holds on
the TL-SG3452, measured above, and `rack:omada apply` is the shell form of its
write half for one switch at a time.

- **It lives in the rack's cluster**, staging while the rack is at home, as one
  replica holding a `Lease` per site, which replaces the laptop-local lock.
  Every writer goes through it, including a human, so the apply order and the
  one-change-at-a-time rule stay properties of the system rather than of a
  careful operator.
- **Its input is the `RackSwitch` objects**, which already follow git into the
  cluster. A change starts from a merged `configRevision`, never from drift on
  its own: a change someone made during an incident is one they meant.
- **It adopts, then converges, through the Open API.** A switch whose MAC shows
  as pending is adopted with its login (option 138 is what makes that zero
  touch); then the hostname, management interface, spanning-tree mode,
  per-port settings, LLDP and SNMP are written through the endpoints in the
  table above, in the site's apply order, one switch at a time.
- **It pays no SSH budget to write**, because the controller keeps its own
  management channel. It reads back what the API returns, and reads
  spanning-tree state, which the API cannot return, over SSH once per revision
  rather than on a timer.
- **Its credentials** (the API client and the switch logins) come from
  1Password through an ExternalSecret into its namespace, as everything else
  in the cluster does; nothing in the repository carries them.
- **Its rollback** writes the previous values back. A reboot of an adopted
  switch keeps what the controller wrote, so the reboot-schedule shape of
  `apply`'s confirmed commit does not carry over. What protects a change that
  cuts off the controller's own path to a switch is still open.
- **It is Go**, like `infra/cluster-api-provider-tuist`, because a long-running
  watch-and-converge loop is what controller-runtime is for and a shell loop is
  not.

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
