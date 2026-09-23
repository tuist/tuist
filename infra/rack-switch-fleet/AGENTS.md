# Rack switch fleet configuration

The configuration that applies to a rack's switches as a set: VLANs, the
management interface, the services that are on and off, and the port roles.
Rendered from a site definition, compared against the live switch, and applied
in an order chosen by blast radius.

[`infra/rack-switch-prep`](../rack-switch-prep/AGENTS.md) is the other half.
It gives one switch an identity over its USB-C console (hostname, management
address, SSH, fleet key) before the switch has any usable network presence.
Everything after that first touch lives here, because it applies to switches as
a group and belongs in a reviewed change rather than in a per-device bring-up.

## Testing what is built, when the rack is reachable

Grouped by what each piece needs rather than in one sequence, because two of the
three groups do not touch the running rack and can happen in any order or at the
same time. Only group C needs care.

### Before starting

- dnsmasq, for group B: installed with Homebrew on 2026-09-22.
- The USB Ethernet adapter, for group B, is `en7` (`USB 10/100/1000 LAN`,
  Realtek). `en4`, `en5` and `en11` are not physical adapters. Check with
  `networksetup -listallhardwareports`.
- A password on `ber1-mgmt`'s 1Password item, which `rack:ztp` reads (1Password
  asks for Touch ID) and serves as `secret 0`. No hash to prepare.
- `ber1-mgmt` out of storage, for group B, cabled to `en7`, and its console
  cable in reach in case Auto Install has to be armed by hand.

### Group A: answers the biggest open question, and needs no switches at all

The Omada API question can be settled without touching the rack, which makes it
the cheapest useful thing here.

```
helm dependency update infra/helm/omada
helm upgrade --install omada infra/helm/omada -n omada --create-namespace \
  -f infra/helm/omada/values.yaml -f infra/helm/omada/values-staging.yaml
kubectl -n omada port-forward svc/omada-omada-controller 8043:8043
```

Then open `https://localhost:8043/doc.html` and answer one question: **which
switch settings have write endpoints in the Open API.** Compare against the
capability table in [omada-assessment.md](omada-assessment.md). That decides
whether the controller path is a documented vendor API or an undocumented
community one, which are different decisions, and it decides how much of this
directory survives.

**Done on 2026-09-22**, with the controller run locally in Docker rather than on
staging, since the spec needs no cluster:
`docker run -p 8043:8043 mbentley/omada-controller:6.3.0.45`, then
`curl -k https://localhost:8043/v3/api-docs`. On 6.3 every rendered setting has
a write endpoint; on 5.15 spanning-tree mode and LAGs were stacks-only, so the
chart now pins 6.3.0.45. Spanning-tree state is write-only, so verification
stays on SSH. It is a documented vendor API. The table is in
[omada-assessment.md](omada-assessment.md). What remains is its adoption prototype on
`ber1-mgmt`, now against the staging controller; see "The rack in the staging
cluster" below for the steps and who does each.

### Group B: zero touch, on the bench, with a switch nobody depends on

For a switch the controller will adopt this group is superseded: the rack-edge
pod serves DHCP on the edge node's switch port, which gives each known switch
behind the edge its site address, the edge node as router and the controller's
address in option 138, and a factory switch then appears in the controller by
itself (measured; see "Zero touch through the controller, measured" in
omada-assessment.md). What follows is the Auto Install path for a standalone
switch, and `rack:ztp` refuses to serve while that pod runs (see "Auto Install
on the edge node").

`ber1-mgmt` cabled to `ber1-edge`'s i226-LM port (`enp89s0`), which is where its
management link goes in the real rack anyway, with nothing else on that segment.
Serving from the edge node rather than a laptop is also how it would work in a
data center. This never touches the ToRs.

```
mise run rack:ztp ber1-mgmt --via tuist@<ber1-edge> --interface enp89s0 --dry-run
mise run rack:ztp ber1-mgmt --via tuist@<ber1-edge> --interface enp89s0 --create-credentials
```

`ber1-mgmt` had no 1Password item, since it was never prepped;
`--create-credentials` makes one with a generated password, as prep-switch does.

The provisioning address is `management.edge.provisioning` in the site, and the
rack-edge pod puts it on the switch port. `rack:ztp --via` needs dnsmasq on the
edge node itself (`dnsmasq-base`), and only the password read here asks for
anything (Touch ID); sudo there is passwordless. From a laptop instead,
use the USB Ethernet adapter and drop `--via`:
`sudo ifconfig en7 inet 192.168.50.1 netmask 255.255.255.0 up`, then
`--interface en7`.

Before serving, check the segment really is just the switch:
`sudo tcpdump -i enp89s0 -e -n -c 50` on the edge node should show one source
MAC. On 2026-09-22 it showed `a8:29:48:fe:b4:be`, the SG3452 announcing itself
over LLDP, already asking for DHCP from its factory fallback address
192.168.0.1. That MAC is now in the site definition, and with a MAC recorded
`rack:ztp` answers nothing else on the segment.

With that running, power the switch on. A factory switch may start Auto Install
by itself; if dnsmasq logs no DHCP request within a few minutes, arm it over the
console with `boot autoinstall auto-save` then `boot autoinstall start`.
`auto-save` matters: without it the fetched configuration is applied and never
saved. Do not use `persistent-mode`, which re-runs Auto Install on every boot
and moves VLAN 1 to DHCP each time.

Watch dnsmasq's log for three things in order: the DHCP lease, the TFTP read of
`ber1-mgmt.cfg`, and the TFTP read of `fleet.pub`, which is the served file
downloading the fleet key. The switch then moves to its site address,
192.168.0.13, still on that segment. To reach it there without moving a cable,
give the edge node a host route to it; otherwise move the cable to a free copper
port on a ToR, which puts it on the rack LAN.

Success is the switch coming up on its site address with the rendered
configuration and a working key login, having been touched only for power and
a cable. That is the console cable gone from racking a switch. Confirm with
`mise run rack:fleet preflight ber1-mgmt`, and note the model is
`verified: false` in models.json until its port naming is read off the unit, so
`apply` and `replace` will refuse it until that is corrected.

If it fails, the useful question is which half: no DHCP lease is the segment or
the interface, a lease but no TFTP read is Auto Install not armed or option 67
not reaching it, and a read but no change is the configuration being rejected.
A config read with no `fleet.pub` read means Auto Install did not run the
download line: the switch has the password login only, and
`rack:prep-switch ber1-mgmt --import-key ~/.ssh/ber1-switch-rsa.pub` over the
console finishes the job. Record which it was.

**Done on 2026-09-22, end to end.** Served from `ber1-edge` (the cable was in
`enp87s0`, the i226-V port, that time), Auto Install fetched `ber1-mgmt.cfg`,
saved it and rebooted, and the switch came up at 192.168.0.13 matching the
render and reachable with the fleet key. What it took, in order:

1. The switch ignored every DHCP offer until they were sent by unicast; see
   the SG3452 entry under the traps below. `rack:ztp --via` now does that.
2. This unit was not factory fresh: someone had once added the `tuist` login
   (with `ber1-tor-b`'s password) and the fleet key over the console, and its
   management VLAN was on DHCP. Auto Install was `Stop` with auto-save and
   auto-reboot enabled, so it was started over SSH with
   `boot autoinstall start`. Whether a factory-fresh SG3452 starts it on its
   own is still open, and so is whether the served key download ran, since
   the key was already there.
3. Auto Install saves the fetched file verbatim, so the startup configuration
   held the login in plaintext and the key download, which then failed at
   every boot. `mise run rack:fleet save ber1-mgmt` sealed it, and `preflight`
   now refuses a switch in that state.
4. The switch now carries its own `ber1-mgmt switch admin` login, which
   `--create-credentials` made.

On its site address the switch sits on a segment only `ber1-edge` reaches, so
the fleet tools got to it through the edge node: a macvlan on the served port
in a network namespace holding 192.168.0.250, and `ssh` with
`ProxyCommand=ssh tuist@<ber1-edge> sudo ip netns exec <ns> nc %h %p`, which
keeps the fleet key on the laptop. Giving the rack a routed path to the
management segment is convergence work on the edge node, not this directory's.

### Group C: the live ToRs, where care is needed

Both switches were left with wedged SSH daemons, so **reboot both first**; that
also resets the connection budget, about eight per boot, which decides how
much fits. `locate` and `ports` cost nothing, `preflight` one, `recover` two,
`replace` two and a reboot.

**Done on 2026-09-22.** `ber1-tor-b` came back on DHCP at 192.168.0.82 as
predicted; `locate` found it, `recover` put it back and saved, and its startup
configuration now carries the static address. `ber1-tor-a` confirmed clean.
Kept below as the procedure for the next switch that moves.

Two things the real run showed. `recover`'s first session always leaks a
terminal line, because changing the address ends the session before a logout can
reach the switch; it now clears that line itself, in the session that saves.
The first session reads `show users` while it is open and records its own line,
the newest task, by tid and name; the second clears a line only if exactly that
tid and name are still listed. Anyone who connected in between sits directly
below the second session, which is why the line is never picked by position.
When the identity was not captured or nothing matches it, nothing is cleared
and recover prints how to free the line with `sessions`.
And a save written by the switch from its running configuration puts the
firmware's `#` padding back, while one pushed by `replace` does not, so the
committed backup flips between the two forms. Only padding changes; the diff
ignores it.

`clear line <tid>` was also exercised for the first time, on the line that
leak left, and freed it.

1. `mise run rack:fleet locate ber1-tor-b`
2. `mise run rack:fleet recover ber1-tor-b --from <where locate found it>`
3. `mise run rack:fleet preflight ber1-tor-b`

**Required, on ber1-tor-a.** `mise run rack:fleet preflight ber1-tor-a`, and
nothing else. It was left correct and saved; this confirms it.

**Both experiments ran on 2026-09-22.** The rollback one showed that
`reboot-schedule` gives this hardware a confirmed commit, and `apply` now uses it;
see "Apply is a confirmed commit" below. The connection-limit one, one session
every ten minutes on a fresh boot, separates a leak from a rate limiter; see the
connection budget notes for its result.

Read any unfamiliar command's syntax without probing a complete command with
`?`, which has twice executed something.

## Usage

```
mise run rack:fleet render                  # write the desired configs
mise run rack:fleet render --check          # fail if they are out of date
mise run rack:fleet preflight <device>      # users, drift and a backup, in ONE connection
mise run rack:fleet publish <device> [--context <ctx>]  # what preflight saw, into the RackSwitch status
mise run rack:fleet diff [device]           # live switch against the render
mise run rack:fleet apply <device> --dry-run
mise run rack:fleet apply <device>          # rolls itself back unless it verifies
mise run rack:fleet resolve <device>        # lift the hold a pending rollback left, once it is over
mise run rack:fleet save <device>           # save running, once it matches the render
mise run rack:fleet backup [device]         # startup config into the repo
mise run rack:fleet drift                   # every switch; non-zero on drift
mise run rack:fleet replace <device>        # push the whole config, needs a reboot
mise run rack:fleet locate <device>         # find a switch that moved, by MAC
mise run rack:fleet recover <device> --from <address>   # put it back and save
mise run rack:fleet ports [device]          # what is plugged into each port
mise run rack:fleet sessions <device> [tid] # terminal lines, and free one
mise run rack:fleet probe-tftp <device>     # is the TFTP export text or opaque?
mise run rack:ztp <device> [--via <host>] --interface <iface> [--create-credentials]  # zero touch
mise run rack:edge-join --context <ctx>     # the edge node into the rack's cluster, for the rack-edge pod
mise run rack:omada controller|devices|inform|adopt|apply|api [device]  # the Omada controller's side
mise run rack:fleet-test                    # the suite; needs no hardware
```

The suite runs in CI on any change under `infra/rack-switch-fleet/` or
`mise/tasks/rack/` (`.github/workflows/rack-switch-fleet.yml`), because most of
what it checks exists to catch an edit that looks like tidying, made by someone
who has never read the change that introduced the rule. A guard that only fires
when a human remembers to run it locally is not much better than a comment. CI
also fails if a credential hash ever reaches this directory.

A note on reading its output: a test runner's prose is a convenience and its
exit code is the fact. Three of these tests were red for several rounds of work
because the tail of the `bats` output looked green.

`--site` selects the rack and defaults to `ber1`.

Shell and `ssh`, like `rack:prep-switch` beside it. `fleet.sh` is the
implementation and `mise/tasks/rack/fleet.sh` the operator entry point; the
pieces worth testing on their own are in `lib/`. Rendering needs `jq`,
normalising is `awk`, and the diff is `diff -u`, so there is no interpreter to
install and nothing to build.

## What the site definition is for

`sites/ber1.json` holds the rack, not the switches: the management prefix and
VLAN, the services the rack wants on or off, and one entry per device giving its
role, model, address and port assignments. A switch's configuration is rendered
from that, so `us1-tor-a` will differ from `ber1-tor-a` only in site variables
and nothing about a switch gets typed twice.

Port naming is a property of the hardware rather than of the rack, so it lives
in `models.json`. A model whose port naming has not been read off a live unit is
marked `verified: false`: it renders, so the design can be reviewed, but `apply`
refuses it. Both models are verified. `tl-sg3452` was confirmed off `ber1-mgmt`
on 2026-09-22 (hardware 1.30, firmware 1.30.0 Build 20251114): all 52 ports are
`gigabitEthernet 1/0/N`, including the four Gigabit SFP slots, and its running
configuration differed from the render only in hostname and DHCP. An earlier
`ten-gigabitEthernet` guess for 49 to 52 would have put four interfaces it does
not have into its zero-touch configuration.

Network settings beyond the management VLAN are optional and nothing in BER1
uses them yet; each form was read off `ber1-tor-b` after the controller wrote it:

- `vlans`, at the site: `[{id, name}]`. A port carries every site VLAN tagged
  unless it names its own, which is what the controller does with a port on its
  `All` profile.
- On a port in a device's `ports`: `description` (letters, digits, space,
  `. _ -`, since the controller refuses parentheses), `spanning_tree: false`,
  and `vlans`, the tagged VLAN ids it carries.
- `lags`, on a device: `[{id, name, ports}]`, LACP, the only kind the controller
  would make. The members take the lag's name and VLANs.

The `RackSwitch` object carries the same settings as `spec.config`, for the
reconciler that writes them through the controller, rendered from the same data
as the configuration text so the two cannot disagree.

## Ports, and the machines on the other end

A port's configuration should follow from the role of whatever is plugged into
it, so racking a machine is an edit to data rather than to a template. The site
definition carries that join in two halves, and `fleet_port_map` reads them as
one:

- **`nodes`** is everything in the rack with an identity, whether or not it
  occupies a port: the x86 machines, the crash-cart KVMs, the transfer switches
  and PDUs, and the environmental probes, which occupy no port at all. Each has
  a name, a role from `node_roles`, a `hardware` key into `node_models.json`, a
  `status`, and a `links` entry per cable giving the switch, the port and the
  NIC it leaves from. A link whose `port` is `null` is planned but not patched
  yet, which is most of them today, and a node with no links is a node that is
  reached some other way.
- **`devices[].ports`** carries only what is neither a machine nor an appliance:
  the ISL and the router uplink.

An appliance is a node like any other. Giving the PDU and the KVMs their own
concept would put them back where the compute ports started, as port numbers
typed into a template with no record of what is on the end.

### Out-of-band, and the socket that looks identical

Every x86 node reaches `ber1-mgmt` on copper, alongside its SFP+ DACs, and that
link is its out-of-band path. Which socket matters: **AMT rides the MS-01's
i226-LM only**, and the i226-V beside it is an identical-looking 2.5G port with
no AMT at all. A management link recorded without its NIC is a link that gets
patched into the wrong hole, and nothing reveals it until the node is the one
that needs recovering.

`node_models.json` is therefore hardware fact, the way `models.json` is for
switches: it names each interface and marks the one that carries out-of-band.
Three things are then checked on every render, so the distinction survives
whoever edits the site next:

- a link's NIC has to exist on that node's hardware
- a management link has to land on an interface marked out-of-band
- a node whose hardware declares an out-of-band interface has exactly one
  management link, and it goes to `ber1-mgmt`; a node whose hardware declares
  none has zero

The third matters because `ber1-mgmt` uplinks to `ber1-edge` directly and never
through a ToR. A management link landing on a ToR would put out-of-band access
behind the thing it exists to recover.

### Things reached over a bus rather than a port

An environmental probe has an identity and no port. An Eaton EMP Gen 2 has no
Ethernet at all: it hangs off a PDU's USB socket through a USB-to-RS485
converter and draws its power over the same link. Its hardware entry declares no
interfaces, which the out-of-band rule below already reads correctly as "no
management link", and it carries an `attachment` instead of a NIC: the host it
chains off, the bus, its Modbus address, and whether it is the terminated one.

That is the same class of trap as i226-LM versus i226-V, so it is checked the
same way. Every address on a chain has to be unique, address 0 is never
detected, and exactly one probe, the last, carries the termination. Break any of
them and the chain silently fails to enumerate with nothing naming the cause.

### The hardware with no out-of-band path

It is scoped to the hardware rather than to every node because **a Mac mini has
no out-of-band network path at all.** Apple silicon has no BMC and no AMT. Its
recovery is a PDU outlet cycle plus `pmset autorestart 1`, and its console is a
crash-cart KVM wheeled to the box, not a permanent link. Requiring a management
link of one would be wrong; allowing one would record a cable that cannot exist.
Both are refused.

That is worth stating as a fact rather than as an exemption. A mini's
out-of-band is not a network path, it is an outlet, which is what makes the
switched PDU a recovery dependency rather than a convenience: until it has a
driver, a wedged mini in the colo has no remote recovery at all. Having the data
say the hardware declares no out-of-band interface keeps that dependency
visible.

There are no minis in the site definition yet and there will eventually be forty
or more, split A/B across the ToRs. They are the bulk of this rack, so the tests
pin this rule down with a fixture mini rather than waiting for the first real
one.

Separate trap, same port: a host OS that bridges the LM port or changes its MAC
kills AMT silently. That is not something this repository can check, but it does
have an owner. The x86 prep track activates AMT with `rpc-go` after the OS
install, and that stage can confirm AMT is actually reachable on the management
VLAN before calling the node done, which a bridged or re-MACed LM port fails.

Nothing may claim a port twice, no link may name a switch the site does not
have, and no port may exceed what the model has. All three are checked on every
render, because a rack grows by editing this data.

The model expresses a node's links individually rather than as "which ToR", so
dual-homing is just a second link. `ber1-edge` has one DAC to each ToR.

Everything else is single-homed, and for two different reasons that the data has
to keep apart.

**By design:** the storage pair splits one node per ToR, matching the split
across opposite ATS chains, so losing a ToR costs one storage node and never
both. `ber1-store-a` is on ToR A and `ber1-store-b` on ToR B. That is redundancy
that looks like an untidiness, so a later edit moving them onto one switch would
remove it without appearing to remove anything; the tests fail if the two
storage nodes ever share a ToR. Mac minis follow the same rule for the same
reason: one NIC each, split A/B the way the power feeds are.

**Not by design:** `ber1-svc` has one link, to ToR B, and it holds DHCP, DNS,
NTP and the tailnet subnet router, so losing ToR B takes those and half the
runners at once. A seventh DAC dual-homes it and the fix is one line here. That
is a rack decision, not a modelling one.

A node carries a `status`. `ber1-store-b` is `planned`: it is the one x86 node
not yet bought, arriving November, and in the prep bay it is the empty slot in
racknex #2 beside `ber1-svc`. Recording it as planned rather than leaving it out
keeps its ToR assignment reviewable before the hardware exists.

`mise run rack:fleet ports` prints the merged map, including the links still
waiting for a port and the ones belonging to a planned node.

The power gear is Eaton throughout: three EATS16N transfer switches and two
EVMAFC20A PDUs, one order not yet placed, so every power node is `planned`. The
earlier APC choice was superseded when a single vendor across ATS and PDU turned
out to be the stronger argument. Both are managed, so both keep a link to
`ber1-mgmt`; the PDU also speaks a REST API, which is what a power driver should
target, and that is recorded on the hardware rather than left to memory.

### Outlets are not modelled here, because they already are somewhere else

Which outlet feeds which node is deliberately absent, and not for want of a
source. It belongs to another system:
[`RackHost`](../cluster-api-provider-tuist/AGENTS.md) carries a `power` block of
driver, host and outlet, rendered from `rackFleet.hosts[].power` in
`infra/helm/tuist/values-managed-*.yaml` by
`infra/helm/tuist/templates/rack-fleet.yaml`, and the CAPI provider reads it to
power-cycle a wedged host through `internal/power`. A Mac mini's outlet is
recorded there today.

So the question has an answer, and answering it again here would create a second
one. That matters more than a gap would: an acknowledged gap eventually gets
filled, and filling this one would leave two places to look and two chances to
disagree.

Two things follow. `internal/power` ships only a `shelly` driver, a prototype
stand-in, so the rack's Eaton PDUs have none yet and a wedged mini in the colo
has no remote recovery at all until they do. And whoever extends the chart side
should carry the A/B property across: a mini's outlet and its ToR should not
both land on the same side, or the split that the storage pair and the power
feeds already keep is quietly undone for compute.

### The seam between two inventories, and how it is joined

This file's site definition and `rackFleet.hosts` describe overlapping things.
This one owns switches, cabling and appliances; that one owns the Mac minis with
their serials, addresses, rack positions and outlets, which the CAPI provider
reconciles as `RackHost`. A mini appears in both when it is racked.

They are joined by reference rather than by copy. A node may carry
`rack_host: <name>`, and then it may not restate anything `RackHost` owns:
serial, address, rack, position, power or outlet. Both halves are checked on
every render, so a reference to a host that does not exist fails, and so does a
node that keeps its own copy of a serial. Two records of an outlet is two
chances to disagree, and this side is the one nothing would notice had gone
stale, because the controller acts on the other.

So when the first mini is racked it gets a node here for its cable and its ToR,
pointing at its `RackHost` for everything else. Not a second description of the
machine.

## The switches as Kubernetes objects

A switch is a `RackSwitch` in the `tuist.dev` group, so its state is visible next
to the `RackHost`s behind it rather than only in somebody's terminal. The CRD is
`infra/helm/tuist/crds/tuist.dev_rackswitches.yaml`, generated from the Go types
in `infra/rack-switch-controller/api/v1alpha1` by
`mise run rack-switch-controller:generate`, and in `crds/` for the same reasons
as `RunnerPool`. Helm only installs that directory on first
install, so `server-deployment.yml` applies it on every deploy, and the Rack
Switches workflow applies it too before its objects.

**Spec is rendered, not maintained.** `rack:fleet render` writes `k8s/<site>/`
beside `configs/<site>/` from the same site definition, so the cluster's view of
a switch cannot drift from the configuration rendered for it, and CI fails if
the committed objects are stale. The object names the 1Password item holding the
login and never carries the login.

**They live in the rack's cluster.** Each site names its namespace
(`kubernetes.namespace`); BER1 is `tuist-staging`, beside its `RackHost`, while
the rack is at home, and moves to production with the rack. On a merge to
`main`, the Rack Switches workflow applies the CRD and each site's rendered
objects there, so the cluster's desired state follows git.

**Status is pushed by an operator**, with `rack:fleet publish`, into the site's namespace in
the cluster `--context` names (never whatever context happens to be current), which runs a
preflight and records drift, reachability, when it was verified and how many of
the boot's connections have been spent. It is reported against the
`configRevision` it was measured with, so a status can never be read as applying
to a revision it did not see. A switch whose object says `managedBy: controller`
is adopted and converged by the rack switch controller, which writes its status
instead; see [`rack-switch-controller/AGENTS.md`](../rack-switch-controller/AGENTS.md).
The renderer does not emit `mac`, `managedBy` or `config` yet, so every object
is standalone until it does.

### Why this cannot be managed the way a datacentre switch would be

The reasonable objection to all of this is that plenty of people manage switches
programmatically, so a switch that dies after eight logins would be notorious.
Both halves of that are true, and the resolution is that the switches people
manage programmatically at scale are not this kind of switch. They expose
NETCONF, gNMI or RESTCONF, and the tooling talks to an API with a session model
designed for it.

This one offers three surfaces and no API. The SSH CLI, which is what this tool
drives and which degrades with use. A web interface that is a forms UI rather
than an interface, `Server: Web Switch`, answering 501 to a HEAD and serving
XHTML to a GET, so scraping it would be worse than the CLI and not obviously
more robust. And the Omada cloud controller, which is a real management plane
and was rejected deliberately, because controller mode limits the feature set
and wants to own the configuration, which is the opposite of rendering it from
git.

So the constraint is not that nobody automates switches. It is that this class
of switch is not built to be automated, and the one path the vendor leaves open
when you decline its controller is the least robust one it has.

### What a switch with an API would cost instead

Worth weighing when the next rack's switches are bought, because a unit with
NETCONF would make most of this file unnecessary. The shape has to stay the
same: the Mac minis are 10GBASE-T, so this is a multi-gigabit copper switch with
SFP+ uplinks, not a datacentre SFP28 box.

| | Ports | Management | Price |
|---|---|---|---|
| TP-Link SX3832, what we have | 24x 10GBASE-T, 8x SFP+ | SSH CLI, or the Omada controller | **EUR 1,035** each, bought 2026-09-15 |
| FS S5860-24XMG | 24x multigig 10GBASE-T, 4x SFP+, 4x SFP28 | PicOS: NETCONF, RESTCONF, Ansible, OpenFlow | **USD 2,749** |
| Juniper EX4400-24MP | 24x multigig, 100G uplinks | Junos: NETCONF, gNMI, mature ZTP | **GBP 15,460** list |

So an API costs roughly **two and a half times** what we paid, not ten times.
The Juniper number is list, for a PoE++ unit with an 1800 W budget this rack has
no use for, and is here only to mark the far end. The FS box is the like for
like comparison and the one to price properly if this comes up again.

One thing to check before choosing it: our SFP+ ports carry six DACs across the
pair, four of them on ToR B, and the FS has four SFP+ plus four SFP28 rather
than eight SFP+. That is enough, since SFP28 takes a 10G DAC, but it is exactly
enough rather than comfortably.

### Would an API switch make bring-up zero touch?

Not by itself, and the distinction matters. Zero touch comes from ZTP, not from
NETCONF: the switch boots, DHCP hands it a config location, it fetches and
applies. NETCONF is what you get *afterwards*, and it is the part that would
delete this file's SSH machinery and its connection budget.

Both halves are worth separating because **this switch already has the ZTP
half**, and the commands have now been read off the unit rather than assumed:

```
boot autoinstall persistent-mode   # run it again on the next boot
boot autoinstall auto-save         # save what is downloaded as the startup config
boot autoinstall auto-reboot       # reboot once it completes
boot autoinstall retry-count <n>
boot autoinstall start             # begin now
show boot autoinstall              # mode, persistent, save, reboot, retry, state
```

Defaults on a prepped switch: Auto Save enabled, Auto Reboot enabled, retry
count 1, persistent mode disabled, mode Stop.

**Starting it puts VLAN 1 on DHCP**, and the state becomes "Waiting for restart
timeout". That is the feature working, since a switch hunting for a provisioning
server has to get an address from one, but it means a switch with Auto Install
running is not at the address the site definition gives it. Find it by MAC in
the ARP table.

The TFTP check settled what the path was blocked on: the export is text, so a
rendered config is something Auto Install can be handed. **`rack:ztp` serves
it**: dnsmasq for DHCP and TFTP, the configuration rendered from the site
definition, and the boot file offered to one switch by MAC rather than to
whoever asks.

The dangerous half is the DHCP server, not the switch. A second one on a network
people live on hands addresses to their laptops, so `rack:ztp` requires
`--interface`, refuses the interface carrying the default route, refuses one
with no address, binds to exactly one interface and disables DNS entirely
(`port=0`). Use a USB Ethernet adapter with only the switch on the other end.

Two things Auto Install needs that `replace` does not, because a switch being
provisioned from scratch has none of our credentials:

- **A login.** `replace` carries the existing one across from the switch. Here it
  goes in as `user name tuist privilege admin secret 0 <password>`, with the
  password from the switch's 1Password item, and the switch hashes it itself;
  the CLI reference documents `secret 0` as a plaintext password. The dry run
  writes it redacted and a real run deletes the served files when it stops.
- **Its controller, once there is one.** When `management.controller.address`
  is set, `rack:ztp` also sends DHCP option 138 naming it, and the edge path
  translates the provisioning segment into the tailnet, so a factory switch
  shows up in the controller as pending with no configuration file at all. That
  is the zero-touch path through Omada; it has not met hardware yet.
- **The fleet key.** It is not configuration, no export carries it, and Auto
  Install fetches only the configuration file. So the served file runs
  `ip ssh download v2 fleet.pub ip-address <server>` itself, ahead of
  `interface vlan`, while the switch still has its DHCP address on the
  segment; `rack:ztp` serves `fleet.pub` beside the config, converted to the
  RFC4716 form the firmware wants. Whether Auto Install runs a download line is
  what group B finds out; the fallback is `rack:prep-switch --import-key`.

Still to do end to end: an isolated segment, and a switch nobody depends on,
which is what `ber1-mgmt` is while it sits in storage. See group B above for
how to arm it.

What Junos and PicOS offer over that is not the feature but its maturity. ZTP on
those is a mainstream path that thousands of deployments use; DHCP Auto Install
here is a feature on a unit whose SSH daemon stops accepting connections after
eight of them, which is not encouraging about the parts nobody exercises.

So: a NETCONF switch would very likely give zero touch, because of its ZTP
rather than its NETCONF, and would also remove the reason this tool has to nurse
a CLI. Trying Auto Install on what we already own is the cheap experiment, and
it should happen before anyone spends on the theory.

Nothing specific to the SX3832 turned up in a search, though TP-Link has a
documented history of JetStream firmware leaving switches unmanageable until
rebooted, and this unit runs a build from February 2026. The reproduction here
is clean enough to send them: plain `ssh`, a freshly booted switch, eight
connections, the ninth refused.

### Why there is no controller

Not squeamishness: two measured properties of this hardware.

**A reconcile loop cannot afford it.** A switch stops accepting SSH after about
eight connections in a boot, and spacing them ten minutes apart only stretched
that to ten. Observing costs one. Hourly checks are twenty-four a day, so a
loop takes a switch out within half a day without changing anything, and the
failure looks like a healthy switch because it keeps forwarding. Anything
automated has to batch its reads the way `preflight` does, or run rarely enough
to be worth a slot.

**The controller would sit in the failure domain it manages.** The cluster's own
nodes are behind these switches. A controller reconciling `ber1-tor-a` reconciles
its own route to `ber1-tor-a`. That is workable with care, and it is why the
console path and the operator CLI stay whichever way the rest goes.

Correcting drift automatically is cheaper than it looks, and an earlier version
of this file said otherwise. `apply` sends the missing commands to the running
configuration and saves, with **no reboot** unless the change fails; only
`replace` always costs one. So the objection is not the reboot. It is that observing is what burns the budget, and
that a change made during an incident is one somebody meant, which is why
changes stay tied to an approved revision rather than being reconciled.

Both objections are about SSH, not about controllers. The Omada controller keeps
its own management channel to each switch, and on 6.3 its Open API writes
everything rendered here (see [omada-assessment.md](omada-assessment.md)), so a
controller that reconciles `RackSwitch` objects through it pays no connection
budget. SSH then stays for what the API cannot read back, spanning-tree state,
and for the console path. That is the direction; the next section is how far it
has got.

## The rack in the staging cluster

The goal: the switches and the edge node managed from the cluster the rack
belongs to, which is staging while BER1 is at home and production once it
is in the data center. Where that stands on 2026-09-23:

- **Built and exercised.** `RackSwitch` objects rendered from the site
  definition; `rack:ztp --via` serving zero-touch provisioning from `ber1-edge`,
  run end to end on `ber1-mgmt`; the switches behind the edge node given a path
  into the tailnet by `ber1-edge` (ber1-mgmt carries the route and is reached
  through the edge node by every fleet command).
- **Running in staging.** The controller, deployed by `omada-deployment.yml` and
  on the tailnet as `omada` at `100.84.132.92`, recorded as
  `management.controller.address`, with its site `ber1` and an Open API client
  in 1Password as "omada staging open api" (`client-id`, `client-secret`). The
  `RackSwitch` CRD and the site's objects in `tuist-staging`; editing them needs
  `tuist-edit-rackswitches-write` from
  `infra/helm/pomerium/templates/access-tiers.yaml`, since the built-in `edit`
  role covers no custom resources. `ber1-edge` on the tailnet as
  `tag:tuist-rack-edge`.
- **Adopted: all three switches**, on 2026-09-23. `ber1-mgmt` first, once
  `ber1-edge` clamped the MSS of what it forwards into the tailnet; then
  `ber1-tor-b` and `ber1-tor-a`, once they had a path to the tailnet through
  the edge node (they reach its address on the house network) and the edge node
  translated all three. Every switch's management gateway is now the edge node,
  written by the controller with the address; the ToRs' interim static route
  was removed through a controller CLI configuration. The SX3832 took the same
  treatment from the controller as the SG3452; its baseline is
  `controller-baselines/sx3832.tsv`, measured on `ber1-tor-b` and confirmed on
  `ber1-tor-a`. Adoption replaces a switch's login with the
  site's device account, one account for every switch in the site, and applies
  the site's SSH setting, which starts off. `rack:omada controller` sets both
  from the site definition: SSH on, and the device account from the 1Password
  item `management.controller.device_account_item` names ("ber1 switch device
  account", user `tuist`). A device marked `adopted` in the site definition is
  one the fleet reaches with that account's password, handed to ssh through an
  askpass program reading a file only the operator can open, removed when the
  session closes; every other switch still uses the fleet key. What adoption
  kept and changed of the configuration is in "Adoption, measured on ber1-mgmt"
  in the assessment. Through `rack:omada apply` it takes the hostname,
  spanning-tree mode and port descriptions from its render and keeps them
  across a reboot, and with the controller's own lines left out it matches its
  render; see "Switches the controller has adopted".
- **Zero touch, measured.** `ber1-mgmt` was factory reset through the controller
  and came back by itself: DHCP on `ber1-edge` (measured before it moved into
  the rack-edge pod, with the configuration the pod runs) gave it its site
  address and the controller's, it appeared pending, adoption with the factory
  login and one API pass brought it to its render. See "Zero touch through the
  controller, measured" in the assessment.
- **The reconciler.** [`infra/rack-switch-controller`](../rack-switch-controller/AGENTS.md)
  watches `RackSwitch` objects and drives the controller: it adopts a pending
  switch whose MAC an object names, writes the management address and the
  rest of the render through the Open API, and reports status. Deployed by
  `omada-deployment.yml`. All three objects now say `managedBy: controller`.
- **The edge node is a node.** `ber1-edge` joined staging on 2026-09-23
  (`rack:edge-join`), and the switches' path and their DHCP run there as the
  rack-edge DaemonSet rather than as systemd units; see "The edge node" below.
  A reboot of `ber1-edge` with no units left brought the path and DHCP back
  from the pod within half a minute of boot.

## The edge node

The rack's edge node is a node of the rack's cluster that runs one pod: the
rack-edge DaemonSet ([`infra/helm/rack-edge`](../helm/rack-edge)), deployed with
the Omada controller by `omada-deployment.yml`. The pod runs what
`rack:fleet render` writes into `infra/helm/rack-edge/sites/<site>/` from the
site definition (`lib/edge.sh`), and `render --check` in CI fails when those
files no longer match it:

- `mgmt-path.sh`, the switches' path to the tailnet: the edge address on the
  switch port (`management.edge.interface`) without its prefix route, the
  provisioning address, a host route to each switch marked `behind_edge`, and
  two nft tables. One translates every switch's management address, and the
  provisioning range, into tailscale0 and clamps the MSS of what it forwards;
  the other addresses DHCP replies to each known switch's MAC. It runs at pod
  start and again every five minutes, and refuses a port that carries the
  node's default route. What it installs stays in the kernel when the pod goes,
  so a rollout never cuts the switches off.
- `dnsmasq.conf`, DHCP on the switch port: each known switch behind the edge
  gets its site address and the edge node as router, anything else the
  provisioning range, and both get the controller's tailnet address in option
  138. That option is what makes a factory switch zero touch.

The pod uses host networking, with NET_ADMIN (and NET_RAW and
NET_BIND_SERVICE for dnsmasq) rather than privileged. Its image
(`edge/Dockerfile`, built by `rack-edge-image.yml`) carries only dnsmasq,
iproute2 and nftables.

A new edge node, once Ubuntu is installed and the site definition names it
(`management.edge.ssh`, `.interface`, `.address`):

```
mise run rack:edge-join --context <kube context> --dry-run
mise run rack:edge-join --context <kube context>
```

It installs Tailscale when it is missing and says how to join the tailnet,
which is the one step that needs a person. It refuses until the cluster's
Cilium agent stays off nodes labelled `cilium.io/no-schedule=true`: the edge
node's own networks sit inside the pod CIDR (staging gave `192.168.0.0/24`,
the house network, to a runner node), and an agent would route them into the
tunnel and cut the node off. Then kubeadm's join, with a one-hour bootstrap
token it deletes afterwards, the node's tailnet address as its InternalIP, the
labels `tuist.dev/rack-edge=<site>`, `node.cluster.x-k8s.io/instance-type=rack`
and `cilium.io/no-schedule=true`, and the taint `tuist.dev/rack-edge=<site>`,
so only the rack-edge pod lands there (and the node exporter, which tolerates
everything and uses host networking too). The kubelet gets a local CNI
configuration in `10.254.254.0/24`, used by nothing, so it reports Ready.
`--leave` deletes the node and resets kubeadm.

**Reading the pod's logs.** The API server cannot reach the kubelet at a tailnet
address, the same as for the Mac minis, so `kubectl logs` and `exec` time out
for this node. On the node: `sudo crictl -r unix:///run/containerd/containerd.sock
logs <container>`.

### Auto Install on the edge node

`rack:ztp --via` refuses to serve while anything holds port 67 on the edge
node, which is the rack-edge pod. To serve Auto Install from there, take the
pod off the node and put it back afterwards:

```
kubectl label node ber1-edge tuist.dev/rack-edge-
mise run rack:ztp ber1-mgmt --via tuist@ber1-edge --interface enp87s0
kubectl label node ber1-edge tuist.dev/rack-edge=ber1
```

The provisioning address stays on the port while the pod is away.

## Apply is a confirmed commit

Before sending anything, `apply` arms `reboot-schedule in 5` without
`save_before_reboot`. It then applies to the running configuration only, reads
it back, and diffs it against the render. Only a clean diff cancels the timer,
and only then is the configuration saved. A change that cuts off the session, a
command the switch rejects, or a result that does not verify all end the same
way: the timer fires and the switch comes back on its saved configuration within
five minutes, with nobody at a console.

Rolling back means returning to the saved configuration, so `apply` refuses a
switch whose running configuration differs from its startup configuration: the
rollback would throw those unsaved changes away along with its own. That
comparison covers every line, including the ones the render does not own and
`diff` ignores, such as `user name` and `system-time ntp`: a rollback restores
those too, so an unsaved credential change is as much at risk as a managed
line. Only terminal noise is normalised away. Both configurations are read in
the session that applies, after the confirmation rather than before it, so a
change made while the prompt waited counts; a running configuration that is
saved but no longer the one the plan was made from stops the run too, with
nothing changed. Neither costs an extra connection.

A run that ends with the timer armed and not confirmed cancelled holds the
rack. That covers a command the switch rejected, a result that did not verify,
an interrupt, and a cancel that failed after the switch already matched the
render. The last is the one the apply ordering cannot catch: the switch passes
it while minutes from rebooting, so without the hold the other ToR could be
changed as this one goes down. The one-change-at-a-time lock (a directory
under `FLEET_LOCK_DIR`, `/tmp` by default) is released as usual, but the run
leaves `rack-fleet-<site>.rollback` beside it, naming the switch, when the
timer was armed and when it fires. Every command that takes the lock (`apply`,
`save`, `replace`, `recover`, and `rack:omada apply` for an adopted switch)
refuses while it is there and says why. The lock and the hold are in
`lib/lock.sh`, which both tools source.

`mise run rack:fleet resolve <device>` is the only thing that lifts it. It
refuses without connecting until the timer's deadline plus five minutes for the
switch to boot, because before then a switch running its saved configuration
does not show it rebooted: the change saved by hand reads the same with the
reboot still to come. After that it opens one session, and lifts the hold only
if the switch answers and its running configuration equals its startup
configuration, every line. If it still differs, the timer was probably
cancelled after all and the change is running unsaved; `preflight` shows where
it stands, and removing the record by hand is the deliberate way out once the
state is one you accept. No later run lifts it on its own, since none can tell
a rollback that finished from one still to come.

Measured on `ber1-tor-b` on 2026-09-22 before it was built: an unsaved change
was discarded when the timer fired, three minutes to the second after arming,
and `reboot-schedule cancel` stopped a second timer from firing. Then `apply`
itself restored a saved `no lldp` drift through this path in fifteen seconds.
`replace` does not use it: it writes the startup configuration and reboots on
purpose, so there is no saved state to fall back to.

## Apply ordering, which is enforced rather than written down

Switches are applied one at a time, in the order `apply_order` gives:

1. `ber1-tor-b`. No WAN path lands on it, so a bad change costs one half of the
   rack's redundancy rather than the site's connectivity. It is also the only
   switch a change is tried on.
2. `ber1-tor-a`. Carries the WAN optic and the router uplink, so a bad change
   takes the site off the internet and takes the path used to fix it along with
   it.
3. `ber1-mgmt`, alone and last. There is one management switch and it is the
   path to JetKVM, AMT and ATS monitoring at once. Its uplinks go straight to
   `ber1-edge` and never through a ToR, so a ToR change cannot isolate it.

This is a property of the rack's roles, not of a runbook, so it lives in the
site definition. `apply` reads it and refuses a switch whose predecessors have
not been brought up to the render yet, which makes "never both ToRs at once" a
precondition the tool checks rather than a line someone has to remember.
`--skip-order-check` exists for recovering a single switch.

## The export carries a credential, and TFTP is in clear

A full export is not safe to commit. It contains `user name ... secret 5 <hash>`,
and a hash in git history is an offline cracking target that cannot be removed
without rewriting history. `backup` therefore redacts on the way in, and
`probe-tftp` leaves its export in a temp file outside the repository and says
so. Nothing in `backups/` holds a hash, and it should stay that way.

Restoring a dead switch does not need the export either, which is what makes
the redaction free. `rack:prep-switch` installs a login from 1Password over the
console, and `replace` then merges that switch's own unmanaged lines into the
render. The credential goes from 1Password to the switch and never through git.

Separately: **TFTP is unauthenticated and unencrypted**, so every export and
every replace moves that hash across the wire in clear. The server here listens
only for the length of a transfer, which is the right shape, but the thing that
matters is where it listens. This path belongs on the management VLAN and
nowhere else.

## Why the backups are committed

There is exactly one management switch per rack. If it dies, JetKVM, AMT, ATS
monitoring and switch management all go at the same moment. The accepted
mitigation is a cold spare plus a restorable configuration, which turns recovery
into `rack:prep-switch` followed by a restore instead of an afternoon of
archaeology. That makes `backups/` load-bearing rather than hygiene.

`backup` captures `show startup-config` and redacts the local admin hash on the
way in. The password itself lives in 1Password and is `rack:prep-switch`'s to
own.

## Drift

The web UI is right there and it gets used during incidents, which is fine. The
operating rule is that a change made in the UI gets landed in git the same day,
and `rack:fleet drift` is what enforces it: it re-reads every switch, compares
against the render, and exits non-zero when they disagree.

It is not wired to a scheduler yet. The only sensible host is one with
management-VLAN reach that runs repo-checked-out jobs, which today means
`ber1-edge`, and the x86 nodes are out of scope for this change. Until then it
is a command to run.

## What the render deliberately does not own

- **The local admin login.** A rendered config is committed, and a password hash
  does not belong in git. `rack:prep-switch` owns it out of 1Password.
- **`system-time ntp`.** A live SX3832 holds
  `system-time ntp UTC <a> <b> 12 <c> <d> <e>`, and where the fetch interval
  sits among the servers is a guess until `system-time ntp ?` is read off a
  unit. Rendering a guess would push it. Worth closing soon: the clock on
  `ber1-tor-b` reads 2006, so NTP is not actually syncing, and the servers it
  points at are the vendor defaults.
- **Anything else whose syntax has not been seen on a real unit.** Guessing a
  command and pushing it is how a switch is lost.

`apply` will not invent a `no` form for a command that is on the switch but not
in the render either. It reports those and leaves them alone, because turning an
arbitrary line into its negation is the same class of guess.

## Hardware and firmware facts worth keeping

- **SSH needs legacy algorithms.** The firmware negotiates only
  `diffie-hellman-group14-sha1` and `ssh-rsa`, which a current OpenSSH refuses.
  The failure reads like an unreachable host, not like a rejected algorithm.
- **One authentication attempt per connection.** The switch closes on the first
  key the client offers, so an agent holding other keys locks you out of your
  own switch. `IdentitiesOnly=yes` and `IdentityAgent=none` are not optional.
- **The coprocess descriptors do not survive a pipeline.** Bash closes a
  coprocess's file descriptors in the subshell a pipeline creates, so nothing in
  `lib/session.sh` may be piped or captured with `$(...)`. `switch_run` leaves
  the output in `SWITCH_OUTPUT` and the caller writes that to a file. Piping it
  fails with "Bad file descriptor" only once a switch is on the other end.
- **A write to a dead coprocess must never be allowed to raise SIGPIPE.** A
  shell killed by SIGPIPE does not run its EXIT trap, so the logout is skipped,
  the switch keeps the session, and enough of those wedge its SSH daemon. That
  is how this tool took `ber1-tor-b` down twice while it was being written.
  SIGPIPE is ignored for as long as a session is open, every write checks its
  status, and `switch_close` runs on INT and TERM as well as EXIT. Depending on
  whether bash has reaped the coprocess yet, the same dead session shows up
  either as SIGPIPE or as "Bad file descriptor", so both are handled.
- **Bash deletes the coprocess array, and `NAME_PID` with it, the moment the
  coprocess is reaped.** A connection that fails fast therefore turns every
  `${SWITCH[0]}` into an unbound variable under `set -u`, which is what a
  refused or wedged switch gives you instead of an error message. Every access
  goes through `switch_alive`, ssh's diagnostics go to a log file so there is
  something left to print once the descriptors are gone, and the dead-session
  check runs before the first read rather than after it.
- **`$?` after a failed `if` is not the condition's status.** An `if` with no
  `else` exits 0, so a `read` timeout was indistinguishable from a successful
  read and the drain gave up on its first interval with an empty buffer. Against
  a real switch that made every command look like it produced nothing at all. A
  fake switch that answers within one read interval hides this completely, which
  is why the one in the tests waits before replying.
- **Answer the pager on a separate window, never by editing the transcript.**
  Removing the prompt from the buffer as it is answered leaves its padding
  spaces behind, and the normaliser needs to see the prompt to know that those
  spaces are an erased line rather than indentation. Getting this wrong makes
  every diff show whitespace drift that is not there.
- **The SSH daemon allows a bounded number of connections per boot, and a clean
  logout does not extend it.** Measured on `ber1-tor-b` on 2026-09-22, freshly
  booted, one connection at a time, nothing else touching the rack: connections
  one to seven succeeded and the eighth was refused, after which port 22 stopped
  completing a handshake entirely. The switch kept forwarding, kept answering
  ping and kept serving its web UI throughout. It does not recover on its own;
  an hour was not enough on two occasions. Recovery is a reboot.

  What is visible in `show users` is that each connection gets a task named
  `tSshNN`, the number only ever goes up, `tSsh00` through `tSsh06` across those
  seven, never reused, while the session table held exactly one row throughout.
  So the logout does end the session and something is still not given back.

  **It is not this tool.** The obvious suspicion, that the coprocess driver
  leaves connections half-open and the switch holds each task until a TCP
  timeout, was tested with plain `ssh` in a loop: no coprocess, no driver, let
  ssh exit on its own. It reached a prompt eight times on a fresh boot and the
  ninth timed out with port 22 closed, which is the same behaviour the driver
  gets. So the count belongs to the switch.

  **Why it happens is still not established**, and it remains a strange thing
  for a switch to do, so do not treat the number as understood. Two explanations
  survive: the daemon leaks a task or a descriptor per accepted connection, or a
  login rate limiter is counting. The connections in both runs were seconds
  apart, so a limiter has not been ruled out, though an hour never cleared it.

  **The knob that exists does not reach this.** `show ip ssh` reports
  `MAX Clients: 5` and `Session Timeout: 360`, and `ip ssh max-client ?` on the
  SX3832 answers `<1-5>`: five is the ceiling, not just the default, so it
  cannot be raised. It is also a limit on *concurrent* clients, and only one was
  ever open. Nothing in the vendor's CLI documents a per-boot total, which is
  what a designed limit would have, and is consistent with this being a defect.

  **Spacing does not reclaim it**, measured on 2026-09-22. On a fresh boot, one
  short session every ten minutes (one gap was three): all ten were accepted,
  `tSsh00` through `tSsh09`, each listing only itself, and the eleventh, ten
  seconds after the tenth, timed out at the TCP connect with the same wedge.
  Ten minutes clears the 360 second session timeout, so neither a rate limiter
  with a short window nor the timeout reclaiming slots explains it. Spacing
  bought two or three connections over back-to-back runs, not a budget that
  refills. Treat it as a per-boot count of roughly eight to ten. A reconcile
  loop is still out: even one read an hour exhausts a switch within half a day.

  The run armed `reboot-schedule in 115` without saving before its first
  connection, so the wedge it ended in cleared itself: the switch rebooted onto
  its saved configuration on schedule with nobody touching it. That is the
  pattern for any experiment that may end in a wedge.

  One trap when measuring this. `logout` makes the switch close the connection,
  so ssh exits 255 and prints "Connection closed by remote host" on a completely
  successful session. Treating the exit code as the result reports every healthy
  connection as a failure, which is how the first attempt at the control above
  "proved" the switch was broken when it was answering perfectly. The signal is
  whether a prompt came back.

  This was worth measuring rather than assuming. The earlier wedge happened
  fifteen seconds after `ber1-tor-a` rebooted and flapped the ISL, which looked
  like an obvious cause and was not: with the rack quiet, a switch wedges on its
  own at the same point.

  **Treat connections as a consumable: about eight per boot, ten at best.** A
  full pass of the runbook costs six of them, because `sessions`, `diff` and `backup` are one
  each and `replace` is two. That leaves one spare, which is too close to plan a
  working session around, and is the argument for batching several reads into a
  single connection rather than for logging out more carefully.

- **A write to a dead coprocess must never be allowed to raise SIGPIPE.** A
  shell killed by SIGPIPE does not run its EXIT trap, so the logout is skipped,
  the switch keeps the session, and enough of those wedge its SSH daemon. That
  is how this tool took `ber1-tor-b` down twice while it was being written.
  SIGPIPE is ignored for as long as a session is open, every write checks its
  status, and `switch_close` runs on INT and TERM as well as EXIT. Depending on
  whether bash has reaped the coprocess yet, the same dead session shows up
  either as SIGPIPE or as "Bad file descriptor", so both are handled.
- **Bash deletes the coprocess array, and `NAME_PID` with it, the moment the
  coprocess is reaped.** A connection that fails fast therefore turns every
  `${SWITCH[0]}` into an unbound variable under `set -u`, which is what a
  refused or wedged switch gives you instead of an error message. Every access
  goes through `switch_alive`, ssh's diagnostics go to a log file so there is
  something left to print once the descriptors are gone, and the dead-session
  check runs before the first read rather than after it.
- **`$?` after a failed `if` is not the condition's status.** An `if` with no
  `else` exits 0, so a `read` timeout was indistinguishable from a successful
  read and the drain gave up on its first interval with an empty buffer. Against
  a real switch that made every command look like it produced nothing at all. A
  fake switch that answers within one read interval hides this completely, which
  is why the one in the tests waits before replying.
- **Answer the pager on a separate window, never by editing the transcript.**
  Removing the prompt from the buffer as it is answered leaves its padding
  spaces behind, and the normaliser needs to see the prompt to know that those
  spaces are an erased line rather than indentation. Getting this wrong makes
  every diff show whitespace drift that is not there.
- **The SSH daemon wedges after a handful of connections, and a clean logout
  does not prevent it.** The switch keeps forwarding, keeps answering ping and
  keeps serving its web UI while port 22 stops completing a handshake. It does
  not recover on its own; an hour was not enough on two separate occasions.
  Recovery is a reboot, or the web UI.

  `exit` from privileged mode drops to user EXEC and keeps the session, so only
  `logout` ends one, and this tool always logs out. That was believed to be the
  fix and **it is not**. On 2026-09-22 `ber1-tor-b` refused its fifth connection
  since boot with every previous one logged out cleanly and `show users` showing
  a single line each time. The logout keeps the session table tidy; something
  else leaks per connection.

  The cause is not established. Two candidates, and they have not been
  separated: the daemon may leak a task slot per connection, which the
  monotonically increasing `tSshNN` name in `show users` is consistent with; or
  the management plane may have been disturbed by the ISL flapping when
  `ber1-tor-a` rebooted fifteen seconds earlier. The experiment that would tell
  them apart is to open connections to a freshly booted switch, one at a time,
  with nothing else happening in the rack, and see whether it wedges at a
  similar count.

  Until it is understood, treat connections as a consumable: **a switch tolerates
  roughly four or five per boot.** A full pass of the runbook costs six, because
  `sessions`, `diff` and `backup` are one each and `replace` is two. That is at
  or over the threshold, which is worth knowing before planning a session and is
  an argument for batching several reads into one connection.
- **`show users` lists the terminal lines and `clear line <tid>` frees one**,
  which is the recovery that does not involve power, and
  `mise run rack:fleet sessions <device> [tid]` is the front end for it. It only
  helps while the daemon still accepts a connection, so run it after any failed
  run rather than waiting until nothing can get in.
- **A failed transfer says `Failed to initialize TFTP.`**, which contains
  neither "Error" nor "Bad command". Matching only on those made a copy that
  reached no server look like a success.
- **`show` output pages** with `Press any key to continue (Q to quit)`, and the
  pager erases itself with a carriage return.
- **A bare CR arrives as CR NUL**, the telnet convention. Two traps follow.
  NUL is not whitespace, so an unscrubbed pager line reads as a configuration
  command that is not there; and awk truncates a record at NUL, which silently
  drops whichever configuration line the pager erased itself in front of. Both
  are why `tr -d '\000'` runs before every awk pass and not after.
- **Port 80 and 443 answer even with `no ip http server`** in the running
  config. Do not read that line as "the web UI is off".
- **`reboot-schedule in <minutes>` asks `(Y/N)`; `reboot-schedule cancel` does
  not.** A pending timer does not appear in `show running-config`, so it never
  shows up as drift. Use the relative `in` form only: the clock comes back as
  2006-01-01 after a reboot while NTP is not syncing, so `at <time>` fires at the
  wrong moment.
- **A switch behind the edge node is reached through it.** `ber1-mgmt`'s only
  uplink is `ber1-edge`'s port, so `management.edge` in the site definition
  names the edge node and every fleet command dials the switch with a
  `ProxyCommand` through it; the switch key never leaves the operator's
  machine. The switch prints static routes after `lldp`, which is where the
  render puts the route to the tailnet, because the diff is order-sensitive.
- **The SG3452 ignores broadcast DHCP replies.** Its DHCP client (firmware 1.30)
  sets the broadcast flag, and dnsmasq, following RFC 2131, broadcasts back;
  the switch never answers those, whatever they carry, while it takes a home
  router's unicast offer within 4 ms. Measured on `ber1-mgmt` on 2026-09-22 by
  capturing both. `rack:ztp --via` addresses the replies to the switch's MAC
  with an egress rule on the served port, which needs a Linux server and a MAC
  in the site definition; from a Mac it cannot, so serve an SG3452 `--via`.
- **Firmware lines are not interchangeable.** Hardware `1.20` takes `1.20.x`,
  `V1.6` takes `1.0.x`, and the `V1.6` builds carry higher dates and lower
  version numbers, so "newest" is the wrong instinct and flashing across lines
  bricks the switch.

## Switches the controller has adopted

A device marked `adopted` in the site definition belongs to the site's Omada
controller, and three things change for it.

- **It is changed through the controller.** In the cluster that is the
  reconciler, [`infra/rack-switch-controller`](../rack-switch-controller/AGENTS.md),
  which writes the object's `spec.config` through the Open API when its
  revision moves: management address and gateway, hostname, port descriptions,
  spanning-tree mode, VLANs, lags, every port's VLAN membership and spanning
  tree, and the site's services; and it adopts a pending switch whose MAC an
  object names. From a laptop, `rack:omada apply <device>` writes the hostname,
  spanning-tree mode and descriptions, taking the rack lock and waiting out a
  pending rollback on a ToR; the reconciler's own one-shot `apply` does the
  whole of it for one object. Whatever the API cannot read back is checked
  over SSH with `rack:fleet diff`. The
  SSH write paths, `apply`, `save`, `replace` and `recover`, refuse the device:
  the controller owns its configuration, and TP-Link documents SSH in controller
  mode as show commands only.
- **Drift leaves out what the controller does.** Adoption overrides a few
  rendered lines and adds a set of its own; `controller-baselines/<model>.tsv`
  records both, measured, as `owns` and `adds` rules over (context, command)
  pairs. `diff`, `preflight` and `publish` compare the render less what the
  controller owns against the switch less what it adds, so anything else still
  shows, a change made in the controller's UI included. A model with no baseline
  has not been measured under the controller, and an adopted device of that
  model is refused before its connection is spent. The TL-SG3452 and the SX3832
  have one.
- **It logs in with the controller's device account**, from the 1Password item
  `management.controller.device_account_item` names, instead of the fleet key,
  which adoption removes.

There is no confirmed commit on this path. A reboot of an adopted switch keeps
what the controller wrote, measured on `ber1-mgmt`, so `reboot-schedule` cannot
undo a change; going back means changing the render back and applying again.

## Why not the Omada SDN controller

**The original reasoning does not hold on either count.** See
[omada-assessment.md](omada-assessment.md).

The decision was recorded as "controller mode limits the feature set and wants
to own the configuration". Checked against TP-Link's own list of what a
controller-managed switch can do, everything this directory renders is
supported: management address and VLAN, hostname, RSTP, per-port spanning tree,
LLDP, VLANs, port configuration. The capability objection was wrong.

The write API was the other open question, and it is answered: on controller
6.3 the Open API has a write endpoint for everything rendered here, measured
from the document a running controller serves. On 5.15 spanning-tree mode and
LAGs were writable only for stacks, so the version matters and the chart pins
it. Spanning-tree state is write-only through the API, which keeps SSH as the
verifier.

What adoption does to a configured switch is now measured, on `ber1-mgmt`; see
"Adoption, measured on ber1-mgmt" in the assessment and "Switches the
controller has adopted" above.
