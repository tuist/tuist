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

## Usage

```
mise run rack:fleet render                  # write the desired configs
mise run rack:fleet render --check          # fail if they are out of date
mise run rack:fleet preflight <device>      # users, drift and a backup, in ONE connection
mise run rack:fleet diff [device]           # live switch against the render
mise run rack:fleet apply <device> --dry-run
mise run rack:fleet apply <device>
mise run rack:fleet backup [device]         # startup config into the repo
mise run rack:fleet drift                   # every switch; non-zero on drift
mise run rack:fleet replace <device>        # push the whole config, needs a reboot
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

## Would this be better as Kubernetes objects?

Partly, and the part that is cheap has been done: the join above is the
reference-not-copy shape a `RackSwitch` and a `RackSite` would give, without the
machinery. The rest is a real design direction and not a refactor to reach for
yet, for two reasons this rack has demonstrated rather than predicted.

**A reconcile loop cannot afford this hardware.** The switch stops accepting SSH
after seven connections in a boot. A controller that observes on a timer
exhausts it in under a day and then cannot reach it to fix anything, and the
failure looks like a healthy switch, because it keeps forwarding. Anything
automated here has to be parsimonious in a way the usual reconcile pattern is
not, which is a constraint on the controller's design rather than an argument
against having one.

**The controller would sit inside the failure domain it manages.** The cluster's
own nodes are in this rack, behind these switches, on a management path that
runs through them. A controller that reboots `ber1-tor-a` reboots its own route
to `ber1-tor-a`. That is workable with care, and it is the reason the console
path and the operator CLI stay whichever way the rest goes.

What would genuinely be better as objects is observation and status: desired
against applied revision, drift, reachability, last verification. Those are
reads, they suit a status subresource, and they are what someone actually wants
on a dashboard.

Correcting drift automatically is cheaper than it first looks, and an earlier
version of this file got that wrong. `apply` sends the missing commands to the
running configuration and saves, with **no reboot at all**; only `replace` costs
one, because a startup configuration does nothing until the switch restarts. So
"every correction costs a reboot" was false, and the real objections are the
other two.

The first is the budget again, and it bites the observer harder than the
corrector. Checking drift costs a connection each time. Hourly checks are
twenty-four a day against a switch that tolerates seven per boot, so a naive
observation loop takes the switch out daily without changing anything. Anything
automated has to either batch its reads the way `preflight` does or run rarely
enough to be worth the slot, and that is a real design constraint rather than a
detail.

The second is that correction is not always right. A change made during an
incident is a change someone meant, and reverting it automatically at 3am is
worse than drifting. Tying changes to an approved revision keeps that decision
with a person without giving up the detection.

The sensible order, if it is picked up: keep this driver, model observation
first, leave changes manual, and only then consider a controller that sequences
them.

ToR B also carries a spare LR optic, pre-provisioned so WAN failover is a matter
of moving the LC jumper rather than sourcing hardware. Its port is not recorded
yet; the note on the device is.

## Three things that were checked on the hardware first

These were read off the live `ber1-tor-b` before any of this was written,
because each one decides the shape of the tool.

**Does the CLI survive a paste over SSH?** Yes. The console's defect, where a
line written in one burst arrives with characters missing and produces
`enableshow system-info`, is a console defect only. Multi-line blocks over SSH
arrive intact, so there is no need for a one-character-at-a-time driver here.

**Is `show running-config` a complete, re-appliable dump?** Yes. It is text, it
is the same syntax as the configuration file, it ends with `end`, and it covers
the globals, the management interface and every port. That is what makes a diff
worth acting on rather than advisory.

**Does the configuration round-trip as readable text? Yes**, answered on
2026-09-21 with `mise run rack:fleet probe-tftp ber1-tor-b`. The export is 2742
bytes, 99% printable: the device's own configuration syntax, CRLF throughout,
ending `end` plus one NUL byte. The commands are

```
copy startup-config tftp ip-address <server> filename <name>
copy tftp startup-config ip-address <server> filename <name>
```

Three representations of that switch now agree. What this repository renders,
what the switch prints for `show running-config`, and what it writes over TFTP
all normalise to the same 81 lines.

So a whole-config replace is possible, and it is the better shape: idempotent by
construction, and it collapses the change path and the disaster-recovery path
into one piece of code, at the cost of a reboot per change that the A/B pair is
what makes affordable. DHCP Auto Install has something to serve too.

### What the byte comparison caught

Comparing the export against the render byte for byte, rather than after
normalising, turns up what a normalised diff hides by design. The render is
missing exactly two lines the device holds: `system-time ntp`, and the
`user name` line carrying the admin hash. Both are deliberately unmanaged, which
is right for a file committed to git and **fatal for a file written over the
switch's startup config**. Pushing the render as it stands deletes the account
used to log in and leaves the console as the only way back.

`lib/merge.awk` carries each unmanaged line across from the switch's current
export, re-inserting it in front of whichever configuration line followed it on
the device, so ordering is derived rather than hard-coded. `fleet_device_file`
then applies the CRLF and trailing-NUL encoding read off a real export.
`replace` refuses to push a file with no `user name` line in it at all, which is
the guard of last resort.

**"Exactly two lines" is evidence from one switch, not a fleet law.** It was
measured on `ber1-tor-b`: one device, one model, one firmware, against what the
render covers today. `ber1-tor-a` is the same model but holds configuration that
switch has never had, the WAN optic and the router uplink. `ber1-mgmt` is a
different model entirely. Neither's unmanaged set has been measured.

So the durable thing is the method, not the number: **diff the render against
the device's own export byte for byte before the first push to each device**,
again whenever the render changes what it covers, and again after a firmware
change. A normalised diff will not show this, by construction, because
normalising is what hides the unmanaged lines.

`FLEET_UNMANAGED` in `lib/config.sh` is the single definition, read by both the
normaliser and the merger, because two copies of that list drift and a pattern
added to one but not the other is a line that reads as absent and then gets
deleted. And because the list cannot be trusted to be complete on a device it
was not measured on, `replace` names every line it would remove before it
pushes, in two groups.

A removal is **declared** when the pushed file states the opposite of it: the
render says `no lldp`, the device says `lldp`. Somebody asked for that. A
removal is **undeclared** when the pushed file says nothing about the subject at
all, which is the unmeasured case: configuration this device has that the render
does not model. Only the second group gets the loud block and the differently
worded confirmation.

They are separated rather than listed together because merging them makes the
dangerous one quieter the more the fleet uses deliberate removals. Three
intended removals plus one unmodelled line reads as a routine four-item list,
and that is the shape that trains people to skip the prompt. Keeping them apart
means the alarming question only fires when something is genuinely unaccounted
for, and stays alarming.

## Replacing a switch's configuration

```
mise run rack:fleet replace <device> --dry-run    # export, merge, show the diff
mise run rack:fleet replace <device>              # push; takes effect on reboot
mise run rack:fleet replace <device> --reboot     # push, reboot, verify
```

It exports the switch's current startup config over TFTP, merges the unmanaged
lines into the render, shows what would change, and pushes the result. Without
`--reboot` it stops there, because a replaced startup config does nothing until
the switch restarts. With `--reboot` it answers the firmware's `(Y/N)`, waits
for the switch to go away and come back, re-reads it and diffs against the
render.

Nothing is ever confirmed on the switch's say-so: a command that asks `(Y/N)`
and was not run through `switch_run_confirm` waits out its timeout instead.
Rebooting is not a default.

TFTP needs sudo, because TFTP is always requested on port 69 and `tftpd` only
accepts an upload into a file that already exists and is writable.

### What the first real run showed

Done on 2026-09-22 against `ber1-tor-b`, with a payload that changed nothing:
the switch already matched the render, so the run exercised export, merge, push,
reboot and verify without altering behaviour. It worked first time. The switch
was back in 15 seconds, the verify was clean, and the session table showed one
line afterwards.

Two things worth knowing that only the real run could show.

**A clean verify does not prove the login survived.** The verify diffs the live
config against the render, and the render omits `user name` by design, so the
account could be gone and the diff would still be clean. What actually proves it
is that the post-reboot read authenticates as `tuist` at all, plus a `backup`
afterwards showing the account and `system-time ntp` both present. Check those
rather than the success line.

**The first replace strips the firmware's placeholder padding.** The device's own
export carries long runs of `#` separators for unset sections; a rendered file
does not, so after the first push the startup config is shorter. On `ber1-tor-b`
that was 46 `#` lines and 33 blanks, and not one configuration line. It is
cosmetic, it is a one-time change, and the committed backup shrinks to match.
Worth expecting rather than discovering.

### The first real run, in order

The whole path has been exercised against a fake switch, so the bugs left are
the ones only real hardware shows. Do it in this order:

1. `mise run rack:fleet preflight ber1-tor-b`. One connection, and it answers
   all three of the questions worth asking first: which terminal lines are in
   use and how many connections this boot has left, whether the switch matches
   the render, and a fresh backup in the repository before the first write. Read
   the diff if it is not clean, before doing anything else: either the switch
   changed under us or the render did.
2. `mise run rack:fleet replace ber1-tor-b --dry-run`. Read the merged file it
   names, and check the `user name` line is in it. If there is a "would LOSE
   these, and the render says nothing about them" block, stop and read it: that
   is configuration the switch has which the render does not model. The other
   block, the one headed by the render saying the opposite, is the change
   itself. This is the last cheap step.
3. `mise run rack:fleet replace ber1-tor-b --reboot`.

That is four connections of the seven, and the reboot in the last step resets
the count anyway. Running `sessions`, `diff` and `backup` separately instead
costs three more and is the thing to avoid.

Only `ber1-tor-b`. `ber1-tor-a` carries the WAN and `ber1-mgmt` is the only path
to out-of-band, and neither should see a first run of anything.

**If it goes wrong.** The switch keeps forwarding while its management plane is
unhappy, so the data plane is not the thing to watch. If SSH stops answering,
the web UI on 80 and 443 is still there. `clear line <tid>` frees a stuck
session, but only helps while the daemon still accepts a connection, and the
failure above is the daemon refusing all of them; then it is a reboot. If the switch comes back with a
configuration that is wrong rather than absent, the backup from step 3 is the
undo, pushed the same way. If it comes back with no usable login, that is the
console cable and `rack:prep-switch`.

## Apply ordering, which is enforced rather than written down## Apply ordering, which is enforced rather than written down

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

  **Why is not established, and it is a strange thing for a switch to do, so do
  not treat the count as understood.** Three explanations fit what has been
  measured, and one of them is this tool's fault rather than the firmware's:

  - the daemon leaks a task or a descriptor per accepted connection
  - the client leaves connections half-open, so the switch holds each task until
    a TCP timeout that is longer than the experiment. `switch_close` records
    whether ssh exited after `logout` or had to be signalled, in
    `SWITCH_CLOSED_BY`, and `FLEET_DEBUG_SESSIONS=1` prints it. Against a
    well-behaved fake it is always `logout`; nobody has looked on real hardware.
  - a login rate limiter, which the eight connections in ninety seconds would
    have tripped. Argues against itself a little, since an hour did not clear
    it, but not all limiters are short.

  Two experiments separate them, both needing a freshly booted switch.
  `FLEET_DEBUG_SESSIONS=1` through a run says whether the client is ever the one
  killing the connection. And spacing eight connections over ten minutes says
  whether the limit counts connections or measures a rate: a leak will not care
  about the spacing, a limiter will.

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

Standalone mode exposes the full feature set. Controller mode limits what can be
configured and wants to own the configuration itself, which is the opposite of a
desired state rendered from git.
