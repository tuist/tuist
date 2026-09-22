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

## The next time the rack is reachable

Both switches were left with their SSH daemons wedged, so **reboot both first**;
that also resets the connection budget, which is about seven per boot and is the
thing that decides how much fits in a session. `locate` and `ports` cost none,
`preflight` costs one, `recover` two, `replace` two plus a reboot.

**Required, on ber1-tor-b (three connections of seven).** Its running config is
correct and its startup config still says DHCP, so it comes back on the wrong
address until this is done.

1. `mise run rack:fleet locate ber1-tor-b`. Free, and tells you whether it is at
   192.168.0.12 or somewhere the router gave it.
2. `mise run rack:fleet recover ber1-tor-b --from <where locate found it>`. Two
   connections. It refuses to save unless the switch identifies itself and the
   address actually took, so a success here means it is genuinely fixed.
3. `mise run rack:fleet preflight ber1-tor-b`. One connection, and confirms the
   diff is clean and takes a fresh backup.

**Required, on ber1-tor-a (one connection).** `mise run rack:fleet preflight
ber1-tor-a` and nothing else. It was left correct and saved; this only confirms
it.

**Then one of these two, not both, because each wants a boot's worth of budget.**

*The rollback capability, which is the higher value.* Whether `reboot-schedule`
gives this hardware a confirmed commit: arm a reboot, apply to the running
config only, verify, then cancel and save, so a change that cuts off the path
used to make it undoes itself. Read the syntax first without probing a complete
command with `?`, which has twice executed something. This is the one capability
that would make changing `ber1-tor-a` safe without a person watching.

*Or the connection-limit question.* Eight connections spaced ten minutes apart
on a freshly booted switch, which separates a per-connection leak from a rate
limiter and also clears the 360 second session timeout in between. Cheap to run
and it decides whether any automated observation is possible at all.

**Needs setup beyond a session, so plan it separately.** The Omada prototype in
[omada-assessment.md](omada-assessment.md) wants a controller deployed and
`ber1-mgmt` out of storage. Reading the Open API endpoint document comes first
and costs nothing. DHCP Auto Install wants an isolated segment with our own DHCP
and TFTP, because the only DHCP server on the current LAN is the household
router.

## Usage

```
mise run rack:fleet render                  # write the desired configs
mise run rack:fleet render --check          # fail if they are out of date
mise run rack:fleet preflight <device>      # users, drift and a backup, in ONE connection
mise run rack:fleet publish <device>        # put what preflight saw into the RackSwitch status
mise run rack:fleet diff [device]           # live switch against the render
mise run rack:fleet apply <device> --dry-run
mise run rack:fleet apply <device>
mise run rack:fleet backup [device]         # startup config into the repo
mise run rack:fleet drift                   # every switch; non-zero on drift
mise run rack:fleet replace <device>        # push the whole config, needs a reboot
mise run rack:fleet locate <device>         # find a switch that moved, by MAC
mise run rack:fleet recover <device> --from <address>   # put it back and save
mise run rack:fleet ports [device]          # what is plugged into each port
mise run rack:fleet sessions <device> [tid] # terminal lines, and free one
mise run rack:fleet probe-tftp <device>     # is the TFTP export text or opaque?
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
in `models.py`. A model whose port naming has not been read off a live unit is
marked `verified: false`: it renders, so the design can be reviewed, but `apply`
refuses it. `tl-sg3452` is currently unverified.

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
`infra/helm/tuist/crds/tuist.dev_rackswitches.yaml`, hand-written and in `crds/`
for the same reasons as `RunnerPool`: helm applies that directory first and does
not touch it on upgrade, so a schema change goes out of band.

**Spec is rendered, not maintained.** `rack:fleet render` writes `k8s/<site>/`
beside `configs/<site>/` from the same site definition, so the cluster's view of
a switch cannot drift from the configuration rendered for it, and CI fails if
the committed objects are stale. The object names the 1Password item holding the
login and never carries the login.

**Status is pushed by an operator**, with `rack:fleet publish`, which runs a
preflight and records drift, reachability, when it was verified and how many of
the boot's connections have been spent. It is reported against the
`configRevision` it was measured with, so a status can never be read as applying
to a revision it did not see.

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
rendered config is something Auto Install could be handed. What has **not** been
done is an end-to-end test, and it should not be improvised on this network. It
needs a DHCP server handing out options 66 and 67, and the only DHCP server on
the rack's current LAN is the household router; standing up a second one there
is a rogue DHCP server on a network people live on. The test wants an isolated
segment, our own DHCP and TFTP, and a switch nobody depends on, which is what
`ber1-mgmt` is while it sits in storage.

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
seven connections in a boot. Observing costs one. Hourly checks are twenty-four
a day, so a loop takes a switch out daily without changing anything, and the
failure looks like a healthy switch because it keeps forwarding. Anything
automated has to batch its reads the way `preflight` does, or run rarely enough
to be worth a slot.

**The controller would sit in the failure domain it manages.** The cluster's own
nodes are behind these switches. A controller reconciling `ber1-tor-a` reconciles
its own route to `ber1-tor-a`. That is workable with care, and it is why the
console path and the operator CLI stay whichever way the rest goes.

Correcting drift automatically is cheaper than it looks, and an earlier version
of this file said otherwise. `apply` sends the missing commands to the running
configuration and saves, with **no reboot**; only `replace` costs one. So the
objection is not the reboot. It is that observing is what burns the budget, and
that a change made during an incident is one somebody meant, which is why
changes stay tied to an approved revision rather than being reconciled.

If it is picked up: keep this driver, keep changes manual, and only then
consider a controller that sequences them, with a `Lease` for the coordination
the per-rack lock does today.

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

  Three experiments separate the explanations, all needing a freshly booted
  switch and none of them expensive:

  - spacing eight connections over ten minutes says whether the limit counts
    connections or measures a rate: a leak will not care about the spacing, a
    limiter will. Ten minutes also clears the 360 second session timeout, so it
    tests reclamation at the same time.

  Until one of those is run, plan around seven and do not assume the knob helps.

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

  **Treat connections as a consumable: seven per boot.** A full pass of the
  runbook costs six of them, because `sessions`, `diff` and `backup` are one
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
- **Firmware lines are not interchangeable.** Hardware `1.20` takes `1.20.x`,
  `V1.6` takes `1.0.x`, and the `V1.6` builds carry higher dates and lower
  version numbers, so "newest" is the wrong instinct and flashing across lines
  bricks the switch.

## Why not the Omada SDN controller

**This is under active reassessment and the original reasoning does not hold.**
See [omada-assessment.md](omada-assessment.md).

The decision was recorded as "controller mode limits the feature set and wants
to own the configuration". Checked against TP-Link's own list of what a
controller-managed switch can do, everything this directory renders is
supported: management address and VLAN, hostname, RSTP, per-port spanning tree,
LLDP, VLANs, port configuration. The capability objection was wrong.

What is not yet established is the write API's coverage, which is not the same
as it being absent. The Open API guide that was read covers site creation and
links an endpoint document that was not reached, so nothing shows the vendor
lacks switch write endpoints. The community Terraform provider does not
implement spanning tree and calls the undocumented web API the only surface with
full coverage, but a provider's scope is evidence about that provider. Reading
the endpoint document, and then the prototype, is what would settle it.

The assessment also carries the prototype that would settle it, and a
confirmed-commit shape using the switch's own `reboot-schedule` that would give
this tool automatic recovery from a change that cuts off the path used to make
it. Neither needs new hardware.
