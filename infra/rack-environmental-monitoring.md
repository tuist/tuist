# BER1 environmental monitoring

> [!IMPORTANT]
> Four facts established on 2026-09-21 that the rest of this document rests on.
>
> - The **Eaton Rack PDU G4** takes **three** daisy-chained EMP Gen 2 probes. The
>   **Eaton EATS16N** ATS names no sensor port at all, and the **APC AP4423A** it
>   replaced has exactly **one** Universal I/O port and therefore one probe.
> - The Mac mini draws air in **and** exhausts it through the **bottom foot**. A flush
>   stack is a recirculation question, not an intake-clearance question.
> - The macOS fleet reports **no temperature at all** today, and would still report
>   none with the collector enabled and the latest release: an upstream bug returns
>   before any sensor is read on a healthy Apple Silicon machine.
> - ASHRAE's own limit for non-tape IT equipment is **no more than 5 °C in any
>   15-minute period**. The rate-of-change alert is not a taste judgement.

## Summary

The rack gets three temperature/humidity probes hanging off one of its two zero-U
Eaton Rack PDU G4s, polled over SNMP by the staging cluster's Alloy through the
same tailnet egress path that already scrapes the Mac minis, with five Grafana
Cloud rules on top. Host thermal telemetry is enabled separately and is not a
substitute. Every threshold here is provisional until the stack-thermal bench test
replaces it with measurements, and this document says what that test has to record.

Nothing is bought, ordered or touched by this document. The BOM is priced for a
decision, not placed.

## The gap this closes

The rack will hold 16 to 20 Mac minis per top-of-rack switch (40+ on the long run),
flush-stacked in MyElectronics 1.25U three-up mounts, plus four x86 nodes, two ToR
switches, a management switch, three rack ATS units and two zero-U switched PDUs.
Nothing in the plan watches rack temperature. The flush-stack thermal question is a
line item on the bench acceptance list and then nothing ongoing.

A dense column of passively arranged mini PCs in a facility nobody visits is the
shape where a fan failure or a blocked intake becomes a fleet event before anyone
notices. The failure does not announce itself: a mini that throttles still answers
SSH, still reports Ready, and still takes jobs, so the first visible symptom is
build times drifting up across a whole pool, which reads as a cache regression long
before it reads as a thermal one.

## What to sense, and with what

### The probes hang off the zero-U Eaton Rack PDU G4, not the ATS

**The decision is the probe count.** The APC Rack ATS AP44XXA user guide's port table
lists a single `Universal I/O` port, described as taking one optional AP9335T
temperature sensor or one optional AP9335TH temperature and humidity sensor. One port,
one sensor, and the CLI confirms it by naming the only sensor `Sensor1`. One probe can
tell you the room got hot. It cannot tell you the middle of a flush-stacked column
is cooking while the room is fine, which is the failure this exists to catch.

The Eaton Rack PDU G4 takes **three EMP Gen 2 probes daisy-chained on one host**,
each carrying one temperature, one humidity and two dry contacts. Three is the
number that separates "the room moved" from "our airflow broke", because it gives
an inlet reading, a second reading at the top of the same face, and an exhaust
reading, and the two deltas between them are what a blocked intake changes while the
room stays at setpoint.

Four supporting reasons, none of which would carry the decision alone:

- The zero-U PDU is 1000 mm of aluminium standing in the rear channel, so it spans
  the column the probes are measuring and every cable run is short.
- The ATS is 1U at one height. A probe hanging off it is a probe at that height.
- The PDU is already on the management VLAN speaking REST, Modbus TCP, SNMP, LDAP and
  HTTPS, so this adds no device, no factory IP and no web UI to enroll. That was the
  stated preference and it is met.
- The rack's power driver is going to target this box anyway, so it is a device we
  are committing to operate regardless.

### Environmental monitoring is single-homed by design, not by omission

The rack has **two** G4 PDUs, one per power chain, mirroring the A/B split that runs
through the whole rack: minis split across chains the way they split across ToR
switches, and the storage pair splits the same way. Two PDUs means six possible probes,
and the spec uses three.

**All three go on `ber1-pdu-a`, and that is a choice rather than an oversight.** The two
deltas are the measurement, and a delta only means something if both readings come from
the same column on the same face. Splitting probes across chains buys independence and
destroys the thing being measured. The cost is stated plainly: losing that PDU, or its
chain, loses the environmental data with it.

That cost is smaller than it looks, because losing a chain already takes half the
cattle down and alerts loudly on its own, so the environmental signal is not the thing
that would have told you. It is worth writing down rather than leaving implicit: this
rack already distinguishes storage being single-homed **by** design from `ber1-svc`
being single-homed **against** it, and an unexplained single point reads as an
oversight to the next person who finds it.

### The probe has no network identity, and that is the argument

**A probe hanging off the PDU adds nothing to the out-of-band plane.** The rack is
accumulating small managed devices and each one is another factory IP, another web UI
and another thing to enrol. An EMP is not one of them: it has no Ethernet port, no
address and no web interface. It is a sensor on a bus, powered over that bus by a
device that already has exactly one management port on `ber1-mgmt` and is already a
node in the site definition.

That is the whole case for this option, and it is the case that dies if a standalone
networked sensor is chosen instead. A standalone sensor becomes a node with its own
management link, and that link has to land on `ber1-mgmt`, never on a top-of-rack
switch, because the management switch uplinks to `ber1-edge` directly and out-of-band
access behind a ToR sits behind the thing it exists to recover. One more address, one
more credential, one more port on the one switch whose loss costs out-of-band access
to everything at once. Not worth it for three numbers.

### The ATS probably carries no probe at all, and could carry one at most

**Do not buy an ATS probe.** The ATS is the **Eaton EATS16N**: the APC AP4423A was
picked on 2026-09-12 and superseded on 2026-09-21, when the earlier Eaton rejection was
re-checked and the deciding argument became coherence with the PDU vendor. The order is
2x EVMAFC20A plus 3x EATS16N in one Mindfactory order at € 5,595.55 including VAT, **not
yet placed**. The site definition carries that shape: three `ber1-ats-1/2/3` on an
`eats16n` entry and two `ber1-pdu-a` / `ber1-pdu-b` on `evmafc20a`, all planned. The
`ber1-ats-nmc` node an earlier draft of this document referred to is gone, because NMC
is APC's name for an add-in card and the Eaton equivalent is a built-in Netpack.

**The EATS16N almost certainly takes no probe.** Eaton's specification page for it
lists Ethernet, SNMP and a serial cable for card configuration, and names no
environmental probe or sensor port; it is a 2015-generation product. The EMP Gen 2
installation guide lists its supported hosts as Network-M2, Network-M3, INDGW, eNMC and
eNMC2, and the EATS16N's built-in card is none of those by name. **Unknown, treated as
no.**

The AP44XXA limit above is therefore the fallback branch rather than the operative one,
and it is worth keeping: if the ATS decision reverts to APC, that box caps at a single
sensor, which still loses to three on the PDU for the same reason. The recommendation
does not move on either answer, which is the point of resting it on probe count.

### The probe host has a condition on it that is not ours to resolve

**The PDU order is not placed, and there is an open question upstream of it.** The rack
notes carry an instruction to ask the facility, before ordering PDUs, whether they offer
switched or intelligent PDUs as a service with a customer-accessible API, on the grounds
that roughly € 2,877 may be avoidable if they do. Whether that question has been put to
Martin, let alone answered, is not established here.

State it as a dependency rather than leaving it implicit in `ber1-pdu-a` being
`planned`: **if the answer is that the facility supplies the PDUs, the probe host may not
be an Eaton G4 at all**, and a facility-managed PDU may host no probes whatsoever and
expose no API to read them through. Everything below about three probes, the daisy
chain, the Modbus attachment and the SNMP scrape assumes the G4. The recommendation is
right for the hardware as currently decided; it is not right unconditionally.

That also makes the AP44XXA fallback branch worth more than it looked. It was kept
against the ATS decision reverting to APC, and it covers this case too: whatever box
ends up in the rack, the question to ask it first is how many probes it takes.

### Where the probes go

Three positions, named for what each one answers:

- **`inlet`**: front face, bottom of the mini column, tie-wrapped to the door
  perforation. This is rack inlet air and it is what every absolute threshold is
  measured against. Eaton documents this mounting explicitly: the probe carries tie
  wrap slots intended for front and rear door perforation, so that it measures air at
  the intake point rather than somewhere in the enclosure.
- **`top`**: front face, top of the mini column, same face as `inlet`. `top` minus
  `inlet` is hot air rolling over the column and coming back down the front, which is
  the classic failure in a rack with unblanked gaps and the one a room-level sensor
  cannot see.
- **`exhaust`**: rear of the rack at mid-column height. `exhaust` minus `inlet` is
  the work the rack is doing, and it moves when airflow drops even if both front
  readings stay put.

**A probe cannot sit where the interesting air is.** The EMP is roughly 57 x 38 x
29 mm and the gap under a flush-stacked mini is millimetres. The air that actually
feeds a machine is in that gap, and it is not the same air as the door reading. The
bench test measures that gap once with a thermocouple and produces the offset
between gap air and rack inlet air; the permanent thresholds then carry that offset.
That is the whole reason the thresholds below are provisional rather than arbitrary.

### How the probes are expressed in the site definition

The BER1 site definition (`infra/rack-switch-fleet/sites/ber1.json`, arriving with
[#13458](https://github.com/tuist/tuist/pull/13458)) holds the probes as data. Three
nodes, `ber1-env-inlet`, `ber1-env-top` and `ber1-env-exhaust`, role `environment`,
hardware `emp-gen2`, all `planned`, all on `ber1-pdu-a`, Modbus addresses 1, 2 and 3,
with `exhaust` carrying the RS485 terminator.

Two things gave, and both were cheap to do now:

- **A hardware entry with no interfaces.** `node_models.json` describes hardware by its
  ports and the EMP has none of the kind that file means, so `emp-gen2` declares none at
  all, the way `mac-mini` declares no out-of-band one: the absence is the fact. The
  existing rule that a node whose hardware declares no out-of-band interface has zero
  management links then holds for free, with no special case.
- **A node with zero links.** `nodes` widened from everything that occupies a port to
  everything with an identity, so a node with no links is one reached some other way.

**The Modbus chain is an `attachment`, not a link field.** The first draft of this
proposed putting the Modbus address where a management link's `nic` goes, by analogy
with the i226-LM trap. That was the wrong shape: a probe has no link for it to be a
property of. It is instead an `attachment` carrying host, bus, address and terminator.

The analogy it was reaching for still holds, and is why the attachment is worth
enforcing rather than merely recording. A management link written without its NIC gets
patched into the i226-V and nothing reveals it until the node is the one that needs
recovering. A daisy-chained EMP fails the same way: each address must be unique and set
**before** the probe is powered up, address 0 is never detected, and the terminator goes
on the last probe and no other. Get any of it wrong and the chain does not enumerate,
with nothing on the PDU naming the cause. All three are checked at render, each with a
test verified to fire, plus a fourth for an attachment naming a host that is not a node.

A probe attaches over USB and RS485, never to an outlet, so the outlet-to-machine map
that lives outside this model is not a dependency here.

### No standalone networked sensor is needed

The PDU route works, so this is closed. Nothing is priced for a standalone box, and
the out-of-band plane gains no device.

## Host telemetry is not environmental monitoring

### The fleet reports no temperature today, three times over

Each of these would suppress the data on its own, and all three are live:

1. **The pinned version has no temperature metric.** `NODE_EXPORTER_VERSION=1.8.2`
   in [`cluster-api-provider-tuist/Dockerfile`](cluster-api-provider-tuist/Dockerfile).
   Its darwin thermal collector declares `node_thermal_cpu_scheduler_limit_ratio`,
   `node_thermal_cpu_available_cpu` and `node_thermal_cpu_speed_limit_ratio`, and no
   temperature at all. Per-sensor temperature on Apple Silicon arrived in node_exporter
   **1.11.0** (2026-04-04, prometheus/node_exporter#3547).
2. **The collector is not enabled.** The bootstrap runs `--collector.disable-defaults`
   with an explicit allowlist in
   [`macos-host-bootstrap/bootstrap.go`](macos-host-bootstrap/bootstrap.go) that names
   cpu, diskstats, filesystem, loadavg, meminfo, netdev, os, time and uname. `thermal`
   is not in it, so even those three ratios are never produced.
3. **The pipeline would drop them.** The macOS scrape in
   [`helm/k8s-monitoring/values.yaml`](helm/k8s-monitoring/values.yaml) keeps a fixed
   metric list with no `node_thermal_` entry.

**Fixing all three would still report nothing, because of a fourth.** Measured on
2026-09-23 on an Apple Silicon Mac: the darwin thermal collector asks macOS for the
CPU power status first and returns before reading a single sensor when there is none
recorded, and "No CPU power status has been recorded" is the normal state of a
healthy machine (`pmset -g therm` says so). Both 1.8.2 and the latest release,
1.12.1, fail that way and emit zero series. Apple Silicon does not implement that
power-status API at all, so the throttle ratios never exist on this fleet either.
The fix is upstream and unmerged,
[prometheus/node_exporter#3767](https://github.com/prometheus/node_exporter/pull/3767)
(issue [#2906](https://github.com/prometheus/node_exporter/issues/2906)); built from
source it reported 45 sensors, including the SoC die sensors, and its author measured
52 on an M5 Pro. **Mac temperatures wait for that release**, then take a version bump,
`--collector.thermal` in the bootstrap, and the metric in the keep regex.

The x86 nodes run Linux and join the staging cluster, so the cluster's node-exporter
DaemonSet covers them. The edge node joined at its tailnet address, which the pod
network cannot reach, so it reads `up 0` until
[#13545](https://github.com/tuist/tuist/pull/13545) points its scrape at its egress
Service; that change also keeps the `hwmon` CPU package, core and NVMe temperatures.
The same PR has the switches report CPU, memory, chassis and transceiver temperature
through the Omada controller.

### What each one is for

They are not alternatives and neither covers the other:

- **Host sensors say "this machine is derating".** Per-machine, exact about which box,
  and the only thing that will tell you a flush stack is quietly costing build time
  when nothing is over any threshold. They are also **silent exactly when a host is
  down**, which is the moment you most want to know why.
- **The ambient probe says "the rack is hot".** One signal, predicts a fleet-wide
  event, sees a blocked intake before any machine reacts to it, and keeps reporting
  after every host has thermally shut itself off.

Both need an `absent_over_time` rule, because both fail by going quiet.

## Thresholds, and the bench test they depend on

### What the stack-thermal bench test must record

The bench acceptance on the M5 Pro unit already lists flush-stack thermals. This is
what it has to produce for that line to yield a usable baseline.

**Geometry.** At least three mounts stacked flush, because a two-high stack has no
middle and the middle is the worst case. Load every position that has a machine and
fit the supplied blind plates to the rest, so the face matches what the rack will
have. Run the whole thing twice: flush, then with the mounts spaced one rack unit
apart. **The spaced run is not optional.** Without it the flush numbers have nothing
to be worse than, and the entire question is comparative.

**Points, logged at 60 s or better.**

1. Room reference, about 1 m from the stack at mid-height.
2. Front face, bottom mount.
3. Front face, middle mount.
4. Front face, top mount.
5. **Gap air**: a thermocouple in the gap between the middle machine's foot and the
   surface below it. This is the number the test exists for, because the Mac mini
   draws air in and vents it back out through the same bottom foot, so a pinched gap
   recirculates a machine's own exhaust into its own intake.
6. Rear, mid-height.

**Per machine.** SoC die temperatures (`PMU tdie*`), from node_exporter built with
#3767 and run by hand on the bench, plus wall-clock for a fixed build repeated
throughout.

**Load.** The real runner workload at full concurrency, one build per machine on
repeat. A synthetic all-core loop understates the GPU and ANE share and is not what
the rack will run. The 2026-09-18 ride-through measurement already showed how far
apart a synthetic and a realistic load sit: on the M1 prototype, eight `yes` loops
reached 13.8 W where a mixed RSA and memory-bandwidth load on the same box reached
23 W, against a 7.2 W idle.

**Duration.** Thirty minutes to soak, then at least two hours at steady load. Steady
state means the front-face readings move less than 0.5 °C over fifteen minutes.

**The fault case is the point of the whole exercise.** After the soak, block the
middle mount's intake with a sheet of card for fifteen minutes, or until a machine
hits a thermal limit, and record the same six points. This is what calibrates the
delta and rate thresholds: an alert has to fire on this and on nothing else in the
run. A threshold that cannot be shown to fire on a deliberately blocked intake is not
a threshold, it is a number.

**Write down**, for the steady state and the fault case, in both geometries: the six
temperatures, the three deltas (`top` minus `inlet`, gap minus `inlet`, rear minus
`inlet`), the hottest die sensor per machine, and the fixed-build wall clock.

**What the result decides.** If the flush stack costs build time or pushes any machine
into sustained derating, the fix is a vented plate between mounts (MyElectronics
article 7002, 0.75U) at 0.75U per gap, and the rack's U budget and mini count change
with it. That is a bigger decision than this document, and it is gated on these
numbers.

### Provisional thresholds

Anchored in published limits, not taste. Every value below is **provisional until the
bench test replaces it**, and the two deltas are provisional twice over because
nothing has measured a normal delta yet.

The anchors:

| Source | Value |
| --- | --- |
| Apple, Mac mini operating environment | 10 °C to 35 °C, 5% to 90% RH noncondensing |
| ASHRAE 2021 recommended, classes A1 to A4 | 18 °C to 27 °C dry bulb |
| ASHRAE 2021 allowable, class A1 | 15 °C to 32 °C |
| ASHRAE 2021 allowable, class A2 | 10 °C to 35 °C |
| ASHRAE 2021 max rate, non-tape IT equipment | 20 °C in an hour, and no more than 5 °C in any 15 minutes |
| Eaton EMP Gen 2 accuracy | ±2 °C, ±5% RH, over 0 °C to 70 °C |
| Eaton EATS16N operating | 0 °C to 40 °C |
| Eaton EVMAFC20A operating | 0 °C to 60 °C |

**The Mac mini is an ASHRAE class A2 box by its own rating.** 10 °C to 35 °C is
exactly the A2 allowable envelope. That is the single most useful thing on the table,
because it means the fleet has less headroom than the A1 equipment a data hall is
designed around, and the ATS at 0 °C to 40 °C is the next narrowest thing in the rack.

- **Warning, `inlet` above 27 °C for 15 minutes.** The top of the ASHRAE recommended
  envelope. Eight degrees from the mini's rating, six once the probe's ±2 °C is
  subtracted. This is the "something changed, act within hours" level.
- **Critical, `inlet` above 31 °C for 5 minutes.** Not 32. A1 allowable tops out at
  32 and the mini is rated to 35, but a reading of 32 with ±2 °C accuracy could be a
  true 34, which is one degree of real headroom and no margin to act in. 31 leaves
  two.
- **Critical, `inlet` rising 5 °C or more in 15 minutes.** ASHRAE's own stated limit
  for non-tape IT equipment, so the number is theirs, not ours. Critical rather than
  warning, deliberately: in a room held at setpoint the rack inlet does not move five
  degrees in a quarter hour for any benign reason, and this fires while there is still
  headroom to act, which the absolute thresholds by definition do not. Revisit the
  severity after a month of real data, not before.
- **Warning, `top` minus `inlet` at or above 10 °C for 15 minutes.** **This number is
  a guess** and is the weakest thing in this document. Replace it with the
  bench-measured normal delta plus 5 °C as soon as that exists.
- **Critical, probes absent for 10 minutes.**

**Humidity is recorded and not alerted.** The probe gives it free, the room is held by
the facility, and the failure it would detect is one we have no action for. Revisit if
the facility turns out not to monitor humidity either.

**Set the same thresholds on the device and leave its email off.** The PDU logs
threshold crossings in its own event history, which is worth having for forensics. Its
email alarm is not worth wiring: it depends on the same network path Grafana does, so
it adds a second source of truth without adding a second failure mode.

## Alerting

### The path

Metrics ride the route the Mac fleet already uses, so nothing new is invented:

- **Collector.** `prometheus.exporter.snmp` plus `prometheus.scrape` in
  `collectors.alloy-metrics.extraConfig`, forwarding straight to
  `prometheus.remote_write.grafana_cloud_metrics.receiver` exactly as the five existing
  Tuist blocks do. The rack pool is `ber1-staging`, so this is the **staging** cluster's
  Alloy.
- **Reachability.** The PDU has no tailnet identity and a Pod has no route to a
  subnet-routed address. Same shape the CAPI provider already uses for a rack host's
  first dial: an ExternalName Service annotated `tailscale.com/tailnet-ip` with the
  PDU's management-VLAN address, declaring `udp:161`.
  `macminiEgress.proxyGroup.acceptRoutes` is already true in staging and is what makes
  a subnet-routed address reachable at all. The existing `macminiEgress.machines` list
  cannot carry this: its template hardcodes `tailscale.com/tailnet-fqdn` and two TCP
  ports.
- **ACL.** A grant in [`tailscale/acls.json`](tailscale/acls.json) from
  `tag:tuist-k8s-staging` to the PDU's address on `udp:161`, as a **/32**, for the
  reason already written at length in that file.
- **Credentials.** SNMPv3 with authentication and privacy, not a v2c community string.
  The G4 supports it and the access control policy calls for changing default community
  strings where feasible; a device on the management VLAN is where feasible.
- **Interval.** 60 s, matching the fleet. A 15-minute rate window then has fifteen
  points.

**Pin the OIDs by hand, do not run the MIB generator.** `prometheus-community/snmp`
carries an `apc` tree and nothing for Eaton (checked 2026-09-21), and the snmp_exporter
default configuration has no Eaton module either. Generating one from the full Eaton MIB
produces hundreds of series to read three numbers. Walk the PDU once at the bench, pin
the three EMP temperature OIDs and the three humidity OIDs, and check in a module of
about twenty lines. The module renames them to `ber1_rack_temperature_celsius` and
`ber1_rack_humidity_percent` with a `probe` label of `inlet`, `top` or `exhaust`,
because the raw OID names are unreadable and the label is what every rule below keys on.

### The rules

Five rules, written in the format
[`helm/k8s-monitoring/alerts.md`](helm/k8s-monitoring/alerts.md) uses. **They are
deliberately not in that file yet.** That document is a build list: its "Create the
rules in Grafana" section says to create everything in it, so rules there that no
hardware can satisfy would either be created and sit in no-data or be skipped, and
skipping one teaches the next reader that the file is advisory. Both are worse than the
rules living here.

**The trigger for moving them is the probe nodes' `status`, not anybody's memory.**
"When the probes are installed" is the shape of deferred step that never happens,
because whoever installs a probe is not thinking about a markdown file. The site
definition already carries the flag: the three `environment` nodes are `planned` today,
and **the flip to `installed` is what releases these rules into `alerts.md`**. It reads
in both directions, which is what makes it checkable: a rule in `alerts.md` whose probe
is still `planned` is a bug, and so is an `installed` probe with no rule.

Once created, the rule id, folder and group go back into `alerts.md` so later checks
read the deployed rule rather than this file.

All five use the Grafana Cloud metrics data source, evaluate every minute, and set
**No Data: Normal**. Error is **Alerting** for the critical and telemetry-missing rules
and **Keep Last State** (`OK` through the provisioning API) for the warnings.

**Rack inlet above the recommended envelope** (warning, pending 15m)

```promql
ber1_rack_temperature_celsius{probe="inlet"} > 27
```

Summary: `BER1 rack inlet {{ $values.A.Value | printf "%.1f" }} °C, above the ASHRAE recommended 27 °C`

**Rack inlet near the Mac mini rated limit** (critical, pending 5m)

```promql
ber1_rack_temperature_celsius{probe="inlet"} > 31
```

Summary: `BER1 rack inlet {{ $values.A.Value | printf "%.1f" }} °C, 4 °C from the Mac mini rated maximum of 35 °C`

**Rack inlet climbing** (critical, no pending period)

```promql
delta(ber1_rack_temperature_celsius{probe="inlet"}[15m]) >= 5
```

Summary: `BER1 rack inlet rose {{ $values.A.Value | printf "%.1f" }} °C in 15 minutes, past the ASHRAE limit for IT equipment`

No pending period: the query is already a fifteen-minute window and a pending period
would make it a thirty-minute one.

**Hot air recirculating down the rack face** (warning, pending 15m)

```promql
ber1_rack_temperature_celsius{probe="top"}
  - ignoring(probe) ber1_rack_temperature_celsius{probe="inlet"}
  >= 10
```

Summary: `BER1 column top is {{ $values.A.Value | printf "%.1f" }} °C above inlet; check for a blocked intake or an unblanked gap`

**Rack environment telemetry missing** (critical)

```promql
absent_over_time(ber1_rack_temperature_celsius{probe="inlet"}[10m])
```

Summary: `BER1 rack environmental probes have reported nothing for 10 minutes`

This rule is what makes the other four trustworthy. With **No Data: Normal** a
threshold rule cannot tell "healthy" from "the exporter stopped", and an ambient probe
whose entire value is that it reports when hosts do not deserves the explicit check.

### Routing: these must not land in the non-prod channel

Metrics from `extraConfig` carry the destination's external labels, so these series
arrive as `cluster="tuist-staging"`, `env="staging"`. The notification policy tree
routes `cluster = tuist-staging` to `#notifications-non-prod`. A rack overheating is
not a non-prod event: that label names which cluster's collector happens to poll the
PDU, not the consequence.

**Pin these five rules to the infrastructure channel with simplified routing**, as the
five IRM-pinned rules already do, rather than leaving them to the tree. The cost is the
documented one: simplified routing sends every instance to one channel regardless of
labels, which is correct while there is one rack and wants revisiting at rack 2. The
alternative, a matcher on a `rack` label ordered above the two staging matchers, is
strictly more machinery for the same outcome today.

Leave `affected_service` off until the rack carries production runners. Adding it now
would put a staging-only rack on the public status page.

## What the facility already does, and what it does not say

**Established from NTT's own published material for Berlin 2** (Lankwitzer Str. 45-47,
12107 Berlin): a redundant water-cooled system supported by free cooling (N+1), CRAH
units in the suites and technical rooms, 2N UPS, N+1 generator backup, and a 24/7
Security Operations Center and Service Control Center. The quote in hand is Tier 3,
ISO 9001 and ISO 27001.

**Not established from any public source**: any room temperature or humidity setpoint,
any tolerance, any environmental SLA figure, and whether the building management system
alerts customers on a room excursion or merely records it. Treat all four as **unknown**.

One thing is already clear from the call record: the facility treats our airflow as our
problem. Three-up tray airflow was pre-cleared subject to a tray fact sheet, and
single-feed gear was explicitly excluded from SLA claims. Nothing about a rack's
internal airflow is theirs.

**Questions for Martin**, to go with the PDU questions already queued:

1. What room temperature and humidity setpoints and tolerances does BER2 hold, and are
   they contractual or operational?
2. Does the BMS alert customers on a room excursion, or only record it? If it alerts,
   through which channel and at what threshold?
3. Is per-rack inlet temperature measured by the facility, and can we see our rack's
   reading?
4. Is there a contractual remedy for a room excursion, or only for power?

**What the answers change.** If the room is monitored and we are alerted, our probes are
about our own airflow and the rules that matter are the delta and the rate; the absolute
thresholds become a backstop. If the room is only recorded, the absolute threshold on
`inlet` is ours to run and is the only thing that will tell us a CRAH failed. Either way
the probes are worth having, because no room-level sensor can see a blocked intake in
our column. Only the weighting of the rules changes.

## BOM

Prices checked **2026-09-21**, in EUR including 19% VAT unless marked net. Nothing
ordered.

**Recommended, Eaton path**

| Item | Qty | Unit | Total | Source |
| --- | --- | --- | --- | --- |
| Eaton EMPDT1H1C2 Environmental Monitoring Probe Gen 2 | 3 | € 139.98 | € 419.94 | galaxus, 1-2 Werktage, free shipping (geizhals, 20 offers, 21.09.2026 22:20) |
| ROLINE 21150933 patch cable Cat.6 U/UTP 3 m | 3 | € 6.68 net (€ 7.95) | € 23.85 | reichelt, ab Lager |
| | | | **€ 443.79** | |

Cheapest offer across the 20 listed is Senetic.de at € 131.65 plus € 6.93 shipping,
saving about € 18 on three, against a 3.1 of 5 rating on 37 reviews. Mindfactory lists
€ 152.11 plus € 8.90 on a 4.6 of 5 rating over 9047 reviews and is the vendor the power
layer order went to, so consolidating there costs about € 45 and buys one supplier.

Three cables, because the probes are daisy-chained: PDU to `inlet`, `inlet` to `top`,
`top` to `exhaust`. Ethernet cable is explicitly **not supplied** with the EMP; the
USB-to-RS485 converter and the RJ45 female-to-female coupler are. The probe is powered
over the link and needs no outlet. Each probe's Modbus address must be set before it is
powered up and must be unique in the chain, and the RS485 termination is set to 1 on
the last probe only.

**Alternative, APC path.** Only if the PDU route is rejected, and only while the ATS
is the AP4423A. One probe maximum, so it buys an inlet reading and neither delta:
AP9335TH temperature and humidity from € 129.35 (43 offers), or AP9335T temperature
only from € 90.87 (23 offers), geizhals 21.09.2026.

**Not priced.** No standalone networked sensor, because the PDU route works. The
MyElectronics 7002 vented 0.75U plate is a contingency the bench test decides, not a
line item.

## Scope

**In:** three probes on one G4 PDU; three `environment` node entries and one hardware
entry in the BER1 site definition; one SNMP scrape in the staging Alloy; one egress
Service and one ACL grant; five Grafana Cloud rules; the bench test definition above.

**Out:** standalone environmental sensors; Mac mini die temperature, which waits on
upstream #3767; per-outlet power metering, which the Managed PDU has and
which belongs with the power driver; water leak, door and smoke sensors on the probes'
six spare dry contacts; anything about rack 2.

## Open questions

1. **Does the facility supply switched PDUs with a customer-accessible API?** Queued for
   Martin from the power side and not established here. This is the only open question
   that can invalidate the recommendation rather than refine it, because a
   facility-managed PDU may host no probes at all. See "The probe host has a condition on
   it" above.
2. **Does the EATS16N support any environmental probe?** Its specification page names
   none and the EMP Gen 2 host list does not include it. Assumed no. Decides only
   whether the ATS could ever carry a backup probe, not where these three go.
3. **Which socket does the EVMAFC20A present for the EMP, USB or RJ45?** The
   installation guide documents both shapes and the G4's module was not established.
   Changes the cabling steps, not the BOM, since the converter ships with the probe.
4. **Does the Tailscale operator's egress proxy forward UDP on our version?** The
   documentation allows a protocol in `spec.ports` and shows UDP examples. Verify once
   against the deployed operator before relying on it; if it does not, the PDU's REST
   API over HTTPS is the TCP fallback and needs something to turn JSON into metrics.
5. **NTT's setpoints, alerting and per-rack measurement.** The four questions above.
6. **Does the MyElectronics 1.25U mount publish any airflow data?** None found in the
   vendor catalogue, and the fact sheet the facility asked for still does not exist.
7. **Does a flush stack actually recirculate?** The intake and the exhaust share the
   bottom foot, which makes it plausible rather than proven. This is what the bench test
   is for, and every threshold here is provisional until it answers.

## References

- [ASHRAE TC 9.9, 2021 Equipment Thermal Guidelines for Data Processing Environments, reference card](https://www.ashrae.org/file%20library/technical%20resources/bookstore/supplemental%20files/therm-gdlns-5th-r-e-refcard.pdf)
- [Mac mini (2024) technical specifications, operating environment](https://support.apple.com/en-us/121555)
- [Apple's M4 Mac mini thermal architecture](https://www.macrumors.com/2024/10/29/m4-mac-mini-thermal-architecture/)
- [APC Rack ATS with Network Management Card 3 user guide, AP44XXA](https://gfx3.senetic.com/akeneo-catalog/3/b/2/4/3b2436d8f349d1257594fbd96fa499b6d55ed063_1725171_AP4423A_icecat_multimedia_manual_pdf_1_en_GB.pdf)
- [AP4423A product page, compatible sensors](https://www.se.com/de/de/product/AP4423A/)
- [Eaton EMPDT1H1C2 installation instructions](https://assets.tripplite.com/owners-manual/eaton-empdt1h1c2-installation-guide.pdf)
- [Eaton EMPDT1H1C2 specifications](https://assets.tripplite.com/product-pdfs/en/empdt1h1c2.pdf)
- [Eaton Rack PDU G4 installation and setup guide](https://assets.tripplite.com/owners-manual/eaton-rack-pdu-g4-installation-and-setup-guide.pdf)
- [EVMAFC20A specifications](https://www.eaton.com/gb/en-gb/skuPage.EVMAFC20A.specifications.html)
- [EATS16N specifications](https://www.eaton.com/gb/en-gb/skuPage.EATS16N.specifications.html)
- [NTT Berlin 2 data center](https://services.global.ntt/en-us/services-and-products/global-data-centers/global-locations/emea/berlin-2-data-center)
- [node_exporter changelog](https://github.com/prometheus/node_exporter/blob/master/CHANGELOG.md)
- [Grafana Alloy `prometheus.exporter.snmp`](https://grafana.com/docs/alloy/latest/reference/components/prometheus/prometheus.exporter.snmp/)
- [Tailscale Kubernetes operator, access an IP behind a subnet router](https://tailscale.com/docs/kubernetes-operator/egress/access-ip-behind-subnet-router)
- BER1 site definition and node model: `infra/rack-switch-fleet/sites/ber1.json`, [#13458](https://github.com/tuist/tuist/pull/13458)
