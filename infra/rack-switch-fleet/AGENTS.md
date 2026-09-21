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
mise run rack:fleet diff [device]           # live switch against the render
mise run rack:fleet apply <device> --dry-run
mise run rack:fleet apply <device>
mise run rack:fleet backup [device]         # startup config into the repo
mise run rack:fleet drift                   # every switch; non-zero on drift
mise run rack:fleet ports [device]          # what is plugged into each port
mise run rack:fleet sessions <device> [tid] # terminal lines, and free one
mise run rack:fleet probe-tftp <device>     # is the TFTP export text or opaque?
mise run rack:fleet-test                    # the suite; needs no hardware
```

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

- **`nodes`** is the rack's machines: a name, a role from `node_roles`, and one
  `links` entry per cable, giving the switch and the port. A link whose `port`
  is `null` is planned but not patched yet, which is most of them today.
- **`devices[].ports`** carries only what is not a machine: the ISL and the
  router uplink.

Nothing may claim a port twice, no link may name a switch the site does not
have, and no port may exceed what the model has. All three are checked on every
render, because a rack grows by editing this data.

The model expresses a node's links individually rather than as "which ToR", so
dual-homing is just a second link. `ber1-edge` has one DAC to each ToR.
`ber1-svc` has one, to ToR B, and that is a live rack risk rather than a
modelling choice: it holds DHCP, DNS, NTP and the tailnet subnet router, so
losing ToR B takes those and half the runners at once. A seventh DAC fixes it
and the fix is one line here. A Mac mini has a single NIC, so it lands on
exactly one ToR; minis are split A/B the same way the power feeds are.

`mise run rack:fleet ports` prints the merged map, including the links still
waiting for a port.

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

**Does the configuration round-trip as readable text?** Not yet known. The
commands exist and their syntax was read off the device:

```
copy startup-config tftp ip-address <server> filename <name>
copy tftp startup-config ip-address <server> filename <name>
```

Whether the exported file is text or an opaque blob was not determined, because
TFTP is always requested on port 69 and serving it needs root, which the session
that built this did not have. `mise run rack:fleet probe-tftp ber1-tor-b`
performs exactly that check: it serves TFTP, exports the startup config, and
reports whether what came back is text.

Until that answer exists this stays CLI-driven, with `show running-config` as
the source for the diff. If the export turns out to be text, the better shape is
a whole-config replace: idempotent by construction, and it collapses the change
path and the disaster-recovery path into one piece of code, at the cost of a
reboot per change that the A/B pair is exactly what makes affordable.

## Does this make switch setup zero touch? No.

Racking a switch today is still: plug a USB-C cable in, run `rack:prep-switch`,
unplug it, then run `rack:fleet apply`. That is one physical touch per switch,
which is one fewer than before but is not zero.

Zero touch means DHCP Auto Install: the switch boots, DHCP hands it a TFTP
server and a file name, and it fetches and applies its configuration with nobody
in the room. Three things stand between here and there.

- **The TFTP question above.** Auto Install consumes a configuration *file*. If
  the exported file turns out to be opaque rather than text, there is nothing
  for this renderer to hand it, and zero touch cannot be built on a rendered
  desired state at all. That check gates both whole-config replace and zero
  touch, which is why it is the first thing to close.
- **Nothing serves the files yet.** Auto Install needs a DHCP server handing out
  options 66 and 67 on the management segment, and something serving a config
  per switch keyed by an identity the switch presents before it has one.
- **The identity still has to come from somewhere.** The admin login and the
  fleet SSH key are what `rack:prep-switch` installs over the console. An
  Auto Install config could carry both, which is what would remove the cable.

Pre-staging a switch at the bench and shipping it configured is the other half
of the same answer, and both want this rendered desired state to exist first.
Neither is built here.

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
- **The session table does not reap abandoned sessions.** `exit` from privileged
  mode drops to user EXEC and keeps the session open; only `logout` ends it.
  Leaking sessions wedges the SSH daemon: the switch keeps forwarding and keeps
  answering ping, the web UI stays up, and port 22 simply stops completing a
  handshake. It did not recover within an hour. Recovery is the web UI or a
  reboot, or `clear line`. Hence one session per run and a logout that runs even
  when the work raised.
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
