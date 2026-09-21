# Design: Redfish out-of-band management for rack x86, single-board pilot

Status: pilot spec, **deferred and re-targeted 2026-09-21**. Nothing has been
ordered and no rack hardware was touched. Every price below is a snapshot,
dated and sourced.

**Decision (Marek, 2026-09-21): do not buy a dedicated bench board. Build this
as `ber1-svc`, and move that role's already-bought MS-01 into the spares pool.**

The spec below is unchanged and still describes what the pilot must answer and
how. Only the hardware it runs on changed, twice on the same day: first from a
bench board to `store-b`, then from `store-b` to `svc` once it was established
that **`svc` is still boxed and nothing is racked until mid-October**.

`svc` wins on three things that `store-b` cannot offer, at the same money:

- **It does not touch the storage pair.** `store-a` and `store-b` stay
  identical MS-01s, so the rf=2 pair keeps its symmetry. This was the single
  largest objection to putting the board in the `store-b` slot.
- **It funds the spares pool.** The freed MS-01 becomes the spare chassis that
  is recorded as required and unfunded, and which is the compensating control
  for a fleet with no hot-swap and no redundant PSU.
- **The answers arrive before mid-October rather than in November**, and the
  box is on a desk for all of that window, which is exactly when destructive
  firmware questions are free to ask.

It also puts the board on the role already designated for this: the AMISCE
validation doctrine sends everything destructive to `ber1-svc` as the least
critical box, and sends `ber1-edge` last and probably never.

Consequences to hold onto, because this is the cheaper option and not the
free one:

- **The bench window closes at mid-October racking.** Every destructive
  question in the list below has to be answered while the box is still on a
  desk. After that `svc` is serving DHCP, DNS and NTP, and "least critical"
  stops meaning what it means today.
- **Question 6 is circular on this role.** `svc` is the rack's PXE server, so
  a one-time PXE boot override cannot be tested against itself. Bench it with
  a separate PXE source.
- **BER1 still ends up running two platforms**, so two spares pools rather
  than the four-identical-boxes property the rack was designed around. The
  freed MS-01 covers the MS-01 pool; this board has no spare and will not get
  one.
- **The fallback is free.** If the parts slip or the answers are bad, rack the
  MS-01 as `svc` exactly as planned and the only loss is time. That MS-01 is
  already paid for either way.

### Why not `ber1-edge`

Edge is where out-of-band access looks most valuable and is worth the least. A
BMC sits on the management VLAN, which reaches an operator through a subnet
router and the WAN, and the WAN is edge. **Edge down means its own BMC is
unreachable**, which is the same circular limitation AMT already has, so the
money would not buy the failure mode it appears to buy. Fixing that needs a
second uplink or an LTE out-of-band path, which is a different purchase.

## The question this pilot exists to answer

> Does ASRock Rack's AMI MegaRAC / ASPEED AST2600 Redfish implementation
> actually expose usable **BIOS attributes**, or only power and inventory?

Everything below is arranged around answering that. Vendor Redfish
implementations vary enormously in which resources they really serve, and a
BMC that does power and inventory well but cannot write firmware settings is a
plausible, unremarkable outcome. If that is the result, a large part of the
argument for moving off mini PCs collapses, and the pilot has still paid for
itself: it is cheaper to learn this from one board on a desk than from a rack
of them.

Do not read the rest of this document as a plan that assumes success.

## Why this exists

BER1 is a colo rack in Berlin running four x86 nodes on Minisforum MS-01 mini
PCs (`ber1-edge` as WAN router, `ber1-svc` for DHCP/DNS/NTP, `ber1-store-a` and
a future `ber1-store-b` as the kura storage pair) plus a Mac mini runner fleet.
The 2026-09-21 bootstrap investigation concluded:

- **The MS-01 has no BMC.** Automating its BIOS settings means AMISCE
  (`SCELNX_64`), a closed-source AMI binary that builds and loads an
  out-of-tree kernel module, cannot run under Secure Boot (Ubuntu's kernel
  lockdown blocks unsigned out-of-tree modules and `/dev/mem`), and whose
  failure mode for a bad NVRAM import is a physical CMOS clear.
- **On a board with a BMC the same job is an authenticated HTTP call**, out of
  band, working with the machine powered off.
- **Decision: the current rack keeps its MS-01s.** The trigger for better
  hardware is BER2, because a second site is where each bespoke thing gets
  built a second time.

So this pilot is not about replacing anything now. It is about de-risking every
hardware decision after this one, and it was deliberately decoupled from the
storage-pair purchase it was originally bundled into: the Redfish question
survives on its own and does not need a 5 to 7 k EUR storage buy attached to
it.

## The board

**ASRock Rack `B650D4U-2L2T/BCM`**. Confirmed from the board's own user manual
(`download.asrock.com/Manual/B650D4U-2L2TBCM.pdf`, read 2026-09-21):

| | |
|---|---|
| Form factor | Micro-ATX, 244 mm x 244 mm |
| Socket | AM5 (LGA 1718), up to 170 W TDP |
| CPU support | AMD EPYC 4005 / 4004, Ryzen 9000 / 8000 / 7000 |
| Chipset | AMD B650E |
| Memory | 4 DIMM (2DPC), DDR5 ECC/non-ECC UDIMM, 48 GB max per DIMM (192 GB), **5600 MHz at 1DPC, 3600 MHz at 2DPC** |
| Network | Broadcom BCM57416 2x 10GBASE-T, Intel i210 2x 1GbE |
| BMC | ASPEED AST2600, IPMI 2.0 with iKVM and vMedia |
| Management LAN | **1 dedicated IPMI port** (Realtek RTL8211F), separate from the four data ports |
| Expansion | PCIe 5.0 x16, PCIe 5.0 x4, PCIe 4.0 x1, **1x M.2 PCIe 5.0 x4** on this variant, 4x SATA |
| Power | 1x 24-pin ATX, **2x 8-pin ATX 12V** |
| Rear | VGA, DisplayPort, HDMI, **1x DB9 serial**, 4x USB 3.2 Gen1 |

Two of those lines change the BOM and are easy to miss: the board wants **two**
EPS12V connectors, and this variant has only **one** M.2 slot.

### Why AM5 rather than the Intel W680/W880 alternatives

Because the rented fleet is already AM5 and this repo already selects boxes by
CPU family. From the deployed values:

- [`values-managed-production.yaml:1072`](../../helm/tuist/values-managed-production.yaml#L1072):
  `offer: "ADVANCE-2 | AMD EPYC 4344P"`, the OVH box behind the `ap-southeast`
  cache region. The EPYC 4344P is an EPYC 4004 part on AM5.
- [`values-managed-production.yaml:1086`](../../helm/tuist/values-managed-production.yaml#L1086):
  OVH RISE-L, Ryzen 9 9950X, the ten-box Gravelines Linux runner fleet.
- [`values-managed-canary.yaml:654`](../../helm/tuist/values-managed-canary.yaml#L654)
  and [`values-managed-staging.yaml:702`](../../helm/tuist/values-managed-staging.yaml#L702):
  OVH RISE-S, Ryzen 7 9700X.
- [`values-managed-canary.yaml:861`](../../helm/tuist/values-managed-canary.yaml#L861):
  Hetzner AX42-U, Zen 4 Ryzen.

The canary file justifies its box choice in exactly these terms: "same Zen 5
AM5 family, same single-thread class (4,643 vs 4,728), same soft-RAID NVMe
layout and the same OVHDedicatedMachine code path". That existing practice is
the reason for the pick, not a preference for AMD.

Spec the **EPYC 4004/4005** part rather than a desktop Ryzen: validated ECC,
longer parts availability, and better idle behaviour for a colo where power is
metered.

## What the documentation already settles, and what it cannot

This is the part that reframes the primary question. Read it before the
question list, because it moves several questions and retires none.

ASRock Rack publishes no Redfish API reference for this board that could be
found on 2026-09-21. What exists is documentation for the **same AMI MegaRAC /
AST2600 stack** from other board vendors, plus one bug filed against ASRock
Rack by name. Treat the first as indicative of the stack and the second as
evidence about the vendor.

**1. BIOS attributes are present on this stack, and are not the problem.**
Gigabyte's "Redfish API Reference Guide for ASPEED AST2600" (Redfish v1.11.0)
documents `GET /redfish/v1/Systems/{instance}/Bios` returning `Attributes` and
`AttributeRegistry`. So the pessimistic "power and inventory only" outcome is
already unlikely for reads.

**2. The write path is not the one the Redfish specification defines.** There is
no `Bios/Settings` in that guide. Instead there is
`/redfish/v1/Systems/{instance}/Bios/SD`, accepting POST, PATCH and PUT with an
`Attributes` body. Ironic bug
[#2073518](https://bugs.launchpad.net/bugs/2073518), titled "Redfish - Future
State (SD) - AsRock Rack", names the vendor directly: a boot-device write to
`/redfish/v1/Systems/{id}` is refused with

> Support of this Operation for Boot Properties is moved to FutureState
> URI(/redfish/v1/Systems/Self/SD)

and the same payload succeeds at the `/SD` path. Ironic merged a fix in
September 2025 and backported it to 2025.1 and 2025.2. So the deviation is
real, upstream has hit it, and it is the kind of thing a driver has to be
written for rather than around.

**3. Attribute names are vendor-opaque codes, and they are version-scoped.**
The documented examples are `NWSK000` (Network Stack), `NWSK001` (IPv4 PXE
Support), `PCIS003`, and a BIOS password handle `SETUP001`. Values are
namespaced enums, for example `NWSK000Enabled`. The decoder is an attribute
registry whose filename carries a version, for example
`/redfish/v1/Registries/BiosAttributeRegistryA5335.en-US.XX.X.X.json`. That
answers half of "does the same board and firmware always produce the same
names" before the pilot starts: the names are pinned to a BIOS build, and a
driver that hardcodes them is one flash away from writing nothing.

**4. The single most important setting may not be a BIOS attribute at all.**
Restore-on-AC-power-loss is the x86 equivalent of `pmset autorestart 1`, and it
is the one setting the whole AMISCE track exists to write. The DMTF
`ComputerSystem` schema (v1_22_0, fetched 2026-09-21) has:

```
PowerRestorePolicy   readonly: false   enum: AlwaysOn | AlwaysOff | LastState
```

If ASRock Rack honours it, that setting is a standard `PATCH` against the
system resource and never touches an opaque attribute name. In the same schema,
`Boot/BootSourceOverrideTarget`, `BootSourceOverrideEnabled` and
`BootSourceOverrideMode` are all `readonly: false`. So of the three settings
that matter, two have standard homes and only network stack / PXE clearly needs
the attribute path.

**5. Power, auth and TLS have working third-party precedent.** `bmcctl`
(github.com/j4y-w4lk3r/bmcctl) is a CLI for AMI MegaRAC BMCs on ASRock Rack
boards. It uses HTTP Basic, skips TLS verification but gates destructive
operations on the certificate subject containing `MEGARAC`, and drives `On`,
`ForceOff`, `GracefulShutdown`, `PowerCycle` and `ForceRestart` through
`ComputerSystem.Reset`. Gigabyte's guide lists a narrower set for the same
stack: `On`, `ForceOff`, `GracefulShutdown`, `ForceRestart`. The difference
between those two lists is itself a pilot question.

**6. iKVM, virtual media and SOL exist as products, which is not the same as
exposed over Redfish.** The board's BMC user guide (AST2600, Rev. 1.01) covers
H5Viewer KVM, a Virtual Media application and a Serial Over LAN page, and lists
Redfish as a preservable configuration category on restore. All of that is the
web UI. Whether the same functions are reachable as
`Managers/{id}/VirtualMedia/.../VirtualMedia.InsertMedia` is a separate
question, and Gigabyte's guide does list those actions for the stack.

**What none of this settles:** every one of the above is either another
vendor's build of the same stack or a bug report against unspecified ASRock
Rack firmware. Which resources *this board* at *its shipped BMC firmware*
serves is unknown, and that is precisely what an emulator can never tell us.

## Deliverable 1: bench bill of materials

All prices from **Geizhals.de, 2026-09-21**, lowest listed offer, incl. German
VAT, excl. shipping. The offer count is a rough stock signal.

| Line | Part | Price | Offers |
|---|---|---|---|
| Board | ASRock Rack B650D4U-2L2T/BCM | 339.00 EUR | 15 |
| CPU | AMD EPYC 4344P, 8C/16T, 3.80-5.30 GHz, tray | 228.00 EUR | 9 |
| Cooler | Thermalright Peerless Assassin 120 SE (AM5) | 29.15 EUR | 108 |
| Memory | 2x Kingston Server Premier `KSM56E46BS8KM-16HA`, 16 GB DDR5-5600 ECC UDIMM | 991.74 EUR | 24 |
| Storage | Samsung 990 Pro 1 TB, M.2 2280 PCIe 4.0 x4 (`MZ-V9P1T0BW`) | 203.90 EUR | 75 |
| PSU | be quiet! Pure Power 13 M 750W, ATX 3.1 (`BP026EU`) | 104.89 EUR | 50 |
| Bench | Streacom BC1 Open Benchtable V2 | 159.90 EUR | 7 |
| | **Total** | **2,056.58 EUR** | |

Notes, because three of these lines are not obvious:

- **Memory is 49% of the BOM, and that is a market condition, not a
  configuration mistake.** DDR5 is in a price spike on this date: plain
  non-ECC DDR5-4800 16 GB starts at 205.00 EUR (about 12.81 EUR/GB), where
  historically it sat nearer 4 EUR/GB. ECC UDIMM carries a further premium at
  30.99 EUR/GB. Two 16 GB modules (991.74 EUR, 30.99 EUR/GB) are both cheaper
  per GB and dual-channel versus one 32 GB module (1,086.17 EUR, 33.94
  EUR/GB). **This is the line to revisit before ordering**, and the one most
  likely to have moved. Dropping to a single 16 GB DIMM saves 495.87 EUR and
  is technically sufficient for the pilot, at the cost of single-channel and a
  second buy later.
- **The PSU is 750 W for connector reasons, not power reasons.** The board has
  two 8-pin ATX 12V headers. be quiet!'s published cable table for the Pure
  Power 13 M 750W lists `P4+4 (CPU) 1` and `P8 (CPU) 1`, which populates both.
  The 550W model of the same line is 82.24 EUR, and its connector complement
  was not verified; an 8-core 65 W part would run from a single EPS in
  practice, so this is a 22 EUR insurance line, not a requirement.
- **The OS drive is the 990 Pro because the rack already runs that part, not
  because the bench needs 1 TB.** Three were bought on 2026-09-12 as the boot
  drives for `ber1-edge`, `ber1-svc` and `ber1-store-a` (219.99 EUR each then,
  203.90 EUR on 2026-09-21). A fourth identical drive is also the **spare OS
  NVMe** the spares pool is recorded as needing and not having, so it survives
  either pilot outcome the same way the board does. The cheap alternative is a
  Kingston NV3 500 GB (`SNV3S/500G`) at 94.90 EUR, which saves 91.00 EUR and is
  more than enough to boot Ubuntu and be poked over Redfish.
- **Do not plan on reusing `ber1-store-a`'s drives.** Its boot 990 Pro is one of
  exactly three bought for three nodes, so taking it strands a node. Its data
  drive is the PM9A3 7.68 TB **U.2** (`MZQL27T6HBLA-00A07`, 3,612.07 EUR): wrong
  form factor for this board, which has one M.2 and four SATA and no U.2 or
  OCuLink, so it would need a PCIe-to-U.2 adapter off the x16 slot. It is also
  the one part the rack is blocked on.
- **The benchtable is the most substitutable line.** Any mATX case works. An
  open bench is preferred for the same reason the AMISCE validation doctrine
  prefers it: the CMOS jumper stays reachable, which matters on the one class
  of experiment that can brick a board.

**Lead times.** Nothing here is exotic. The thinnest lines are the benchtable
(7 offers), the CPU (9 offers) and the board (15 offers); the rest are
broadly stocked. No line looked at risk of a multi-week wait on 2026-09-21, but
re-check the board and CPU at order time.

**Buy the board that would be standardised on, not a representative sample.**
Same price either way, and under the 2026-09-21 decision this unit is
`ber1-svc` rather than a bench board, so it is the standard part by
construction.

The table above is the full-fat bench configuration and is kept because it
prices every line the board needs. **The build to actually order is the
`ber1-svc` one below**, which is smaller and cheaper: 16 GB instead of 64 GB, a
4-core CPU, a rackmount case instead of a benchtable, and no new boot drive.

## Costed as `ber1-svc`

This is the build to order. All prices Geizhals 2026-09-21.

| Line | Part | Price |
|---|---|---|
| Board | ASRock Rack B650D4U-2L2T/BCM | 339.00 EUR |
| CPU | AMD EPYC 4124P, 4C/8T, tray | 143.00 EUR |
| Cooler | Thermalright Peerless Assassin 120 SE | 29.15 EUR |
| Memory | 1x 16 GB DDR5-5600 UDIMM (`LD5U16G56C46ST-BGS`) | 213.37 EUR |
| PSU | be quiet! Pure Power 13 M 750W | 104.89 EUR |
| Case | Inter-Tech 3U-30765, 3HE | 124.99 EUR |
| Boot | reuse this role's already-bought 990 Pro 1 TB | 0.00 EUR |
| | **Total** | **954.40 EUR** |

Against that, the MS-01 this displaces (709.00 EUR, already paid) becomes the
spare chassis the spares pool needs and does not have, so the **net cost of
switching is 245.40 EUR**.

Three notes on the line items. The CPU is the 4-core EPYC 4124P rather than the
8-core 4344P, because DHCP, DNS and NTP do not need eight cores and Redfish
behaviour does not depend on the part; the 4344P is 228.00 EUR if uniformity
with a future storage node matters more. The memory is a single DIMM, which is
1DPC and therefore the full 5600 MHz. It is **non-ECC**, which is right for
this role and saves 282.50 EUR over the ECC UDIMM, at the cost of leaving the
BMC as the only reason this board class was chosen; the pilot questions do not
depend on it either way.

## The alternative that was considered: `ber1-store-b`

Kept because it is the comparison that justifies the choice, and because it is
the fallback if `svc` turns out to be the wrong role.

`store-b` was planned as a fourth MS-01. All prices Geizhals 2026-09-21 except
the barebone, which Minisforum sells direct and which is a 2026-09-12 figure
worth re-checking before ordering.

Two lines are identical either way and cancel out of the decision: the PM9A3
7.68 TB U.2 (3,520.40 EUR) and the 990 Pro 1 TB boot drive (203.90 EUR),
3,724.30 EUR together. Everything below is the machine around them.

| | MS-01 | this build, ECC | this build, non-ECC |
|---|---|---|---|
| Barebone, or board + CPU + cooler | 709.00 | 596.15 | 596.15 |
| 64 GB memory | 858.00 (SO-DIMM) | 2,172.34 (ECC UDIMM) | 938.00 (UDIMM) |
| PSU | incl. | 104.89 | 104.89 |
| Chassis / rack mount | 0 (racknex kit already bought) | 124.99 | 124.99 |
| U.2 carrier | 0 (own bay) | ~25.00 (PCIe to SFF-8643) | ~25.00 |
| Machine subtotal | **1,567.00** | **3,023.37** | **1,789.03** |
| Total with both drives | **5,291.30** | **6,747.67** | **5,513.33** |
| Delta | | **+1,456.37** | **+222.03** |

**Ninety percent of the ECC premium is memory, not platform.** Strip memory out
and this build is 851.03 EUR against 709.00 EUR for an MS-01 barebone, so the
machine itself is **142.03 EUR** dearer. The remaining 1,314.34 EUR is the DRAM
supercycle taxing ECC UDIMM at 33.94 EUR/GB against 13.41 EUR/GB for SO-DIMM.

**If this route is ever taken, ECC or not is the open question.** The ECC
requirement for the storage role was retired when content-hashing of the volume
plane merged (PR #13190, 2026-09-16), and the data is a reconstructible cache,
so non-ECC is defensible and saves 1,234.34 EUR. Against that, ECC UDIMM with
EDAC counters is one of the two reasons this board class was picked at all, and
dropping it leaves only the BMC.

**Nothing from the MS-01 fleet offsets this.** The 990 Pro and the PM9A3 carry
over and are already counted as the common lines above. Nothing else does: the
MS-01 takes DDR5 **SO-DIMM** and this board takes **288-pin UDIMM**, which
cannot mate, and the barebone and racknex kit are chassis-specific. So the
delta above is already the reuse-maximised figure.

### Head to head

Net of what each option gives back, the two are the same money:

| | `store-b` route | `svc` route |
|---|---|---|
| ASRock machine | 1,789.03 | 954.40 |
| 4th MS-01 for `store-b` | not bought | 1,567.00 |
| Spare MS-01 gained | none | (709.00) |
| **Net** | **1,789.03** | **1,812.40** |

A 23.37 EUR difference decides nothing, so the choice was made on the three
properties in the decision block above: pair symmetry, a funded spares pool,
and answers before mid-October instead of in November.

## Deliverable 2: the question list

Each question names the request that answers it and what each outcome implies.
Q1 to Q4 are the pilot; the rest are cheap once the board is on the bench.

### Q1. Are BIOS attributes present and enumerable?

```
GET /redfish/v1/Systems/Self/Bios
```

- **Populated `Attributes` plus an `AttributeRegistry` string**: expected, per
  the stack documentation. Proceed.
- **`Attributes` absent or empty**: the primary question is answered `no` and
  the rest of the BIOS track stops. Go to "If they do not" below.
- **Also fetch the registry it names** from `/redfish/v1/Registries/`. If the
  registry is missing or 404s, the names are undecodable in practice even
  though they are present, which is materially the same as absent for
  automation.

### Q2. What are the attribute names for the three settings that matter?

Search the registry for restore-on-AC-power-loss, network stack / PXE enable,
and boot order. Record the exact keys, their allowed values and their
`ResetRequired` flags.

- The documented stack examples give `NWSK000` (Network Stack) and `NWSK001`
  (IPv4 PXE Support) for the second. Confirm on this board.
- **Try the standard path for the other two first**, because they may not be
  BIOS attributes at all (see Q3a and Q6).

### Q3. Are the names stable across the same board and firmware?

Export the registry, flash a different BIOS version, export again, diff.

- **Identical**: a rendered desired-state file can name attributes directly.
- **Changed**: which the version-stamped registry filename strongly suggests,
  so any tooling must resolve names through the registry at run time and pin
  the BIOS version alongside the desired state. This is the same trap the
  AMISCE plan hit, where vendor documentation warns that importing an NVRAM
  export across BIOS versions misbehaves. A BMC does not remove that trap; it
  just makes the export readable over the network.

### Q3a. Is `PowerRestorePolicy` honoured?

```
GET   /redfish/v1/Systems/Self                     # read current value
PATCH /redfish/v1/Systems/Self  {"PowerRestorePolicy": "AlwaysOn"}
```

Then cut mains at the bench outlet and see whether the board comes back.

- **Honoured**: the single most operationally important setting is a standard,
  non-opaque, one-line write, and the AMISCE track loses most of its purpose
  even if Q1 had failed. Verify against the BIOS setup screen too, because a
  BMC that accepts the PATCH and does not move the underlying setting is a
  worse outcome than one that refuses it.
- **Refused or silently ignored**: fall back to the Q2 attribute name.

### Q4. What are the apply semantics, and how long do they take?

```
GET   .../Bios/Settings      # and .../Bios/SD ; note which exists
PATCH <whichever>  {"Attributes": {...}}   # with If-Match: <ETag>
POST  .../Actions/ComputerSystem.Reset {"ResetType": "ForceRestart"}
GET   .../Bios               # re-read and compare
```

Measure stage, reboot and verify end to end with a stopwatch. Specifically:

- **Which resource accepts the write**, `Bios/Settings` or `Bios/SD`. The probe
  tries standard-first so a conformant board is not recorded as needing a
  workaround.
- **Is the ETag precondition required**, and is it `If-Match` or `If-None-Match`?
  The Blackcore procedure for this BMC family documents `If-None-Match`, which
  is not what a precondition on a PATCH normally means, and `bmcctl` reports
  `If-Match` for account writes on ASRock Rack. One of those is wrong for this
  board and the probe will say which.
- **Is a single re-read after one reboot sufficient to confirm?** The AMISCE
  plan verifies across two reboots because an NVRAM import is not observable
  until POST has consumed it. If Redfish's pending-versus-current split is
  honest, one reboot and one re-read is enough, and that is a genuine
  simplification worth measuring rather than assuming.
- **What happens to a bad attribute or value?** A rejected PATCH is fine. A
  202-then-silently-discarded is the failure mode that matters, because it
  makes a drift loop report convergence it never achieved.

### Q5. Power control

```
POST /redfish/v1/Systems/Self/Actions/ComputerSystem.Reset
     {"ResetType": "On" | "ForceOff" | "GracefulShutdown" | "ForceRestart"}
GET  /redfish/v1/Systems/Self     # PowerState
```

Record which `ResetType` values the board's `Actions` block advertises and
which actually work, since the two published lists for this stack disagree.
Also record whether `PowerState` reports transitional values
(`PoweringOn` / `PoweringOff`) and how long it lingers in them, because
`power.Cycle` verifies the off before powering back on and a driver that reads
a transitional state as `Off` would defeat that check.

### Q6. One-time boot override

```
PATCH /redfish/v1/Systems/Self
      {"Boot": {"BootSourceOverrideEnabled": "Once",
                "BootSourceOverrideTarget": "Pxe"}}
```

- **Accepted**: standard, and the network-install path is a one-liner.
- **Refused with the FutureState message**: retry at
  `/redfish/v1/Systems/Self/SD`, per Ironic bug 2073518.
- Then reboot and confirm it **actually PXE-booted** and that the override
  **self-cleared** afterwards. An override that is honoured but sticky turns
  every subsequent reboot into a netboot, which is a much worse failure than
  one that is ignored.

### Q7. Virtual media

```
POST /redfish/v1/Managers/Self/VirtualMedia/{id}/Actions/VirtualMedia.InsertMedia
     {"Image": "http://.../ubuntu.iso", "Inserted": true}
```

Does it mount from an HTTP URL, does the board boot it, and **does it survive a
reboot**? Virtual media that detaches on reset cannot drive an unattended
install, which is most of its value here. Note whether it needs the OEM
`AMIVirtualMedia.ConfigureCDInstance` action the stack documentation lists.

### Q8. Serial console

Try SOL over IPMI (`ipmitool -I lanplus ... sol activate`) and the Redfish
serial-console resource under `Managers/Self`. The board also has a physical
DB9. Record which works headless and whether the console survives a host
reboot, because that is the difference between a debugging tool and a recovery
path.

### Q9. Auth and transport

- **Basic versus session.** Both should work; `bmcctl` uses Basic against these
  boards. Establish whether the BMC rate-limits or audit-logs them differently
  and whether sessions expire mid-reconcile.
- **Certificate.** Almost certainly self-signed. Record the exact subject,
  issuer and validity. `bmcctl` gates destructive operations on the subject
  containing `MEGARAC`, which is a pragmatic pattern but not authentication.
  Decide between pinning the leaf's public key and provisioning a real
  certificate through the BMC's own certificate-upload path. **Do not ship a
  driver that skips verification**; the probe does, and says so.
- **Credential lifecycle.** Default account and password, whether the board
  forces a change on first login, how many accounts exist, and how a rotation
  is scripted (`PATCH /redfish/v1/AccountService/Accounts/{id}`, which `bmcctl`
  reports needs an ETag). Credentials would live in 1Password via ESO like the
  rest of the fleet's.

### Q10. Firmware version dependence, and updating the BMC itself

Record the shipped BMC and BIOS versions before changing anything. Then:

- Does `UpdateService` accept a firmware image over Redfish, or is the web UI
  the only path? If only the UI, BMC firmware is a manual step forever and that
  belongs in the serviceability argument, not the automation one.
- After a BMC update, re-run Q1, Q4 and Q6. **Any of them changing across a BMC
  revision is a first-class finding**, because it means the driver is coupled to
  firmware versions and the fleet needs a pinned-and-tested BMC build the same
  way it needs a pinned BIOS.

### Q11. Does `power.Outlet` still fit?

Not a hardware question, but answer it with the board in hand. The probe
implements `power.Driver` over the existing `Outlet` struct with no new fields:
`Host` becomes the BMC endpoint, `Outlet` the ComputerSystem id, and
`Username` / `Password` the BMC account. If that holds, a `redfish` driver
needs no CRD change on the power path.

## Deliverable 3: the driver-shape probe

[`internal/power/redfishprobe/`](../internal/power/redfishprobe/) is a probe,
not a driver. It is not registered in `power.NewRegistry`, so nothing in the
controller can reach it, and the production driver is deliberately not written:
its shape depends on the answers above.

`internal/power` already defines a `Driver` interface with `shelly` as the only
implementation, and its package comment says in as many words that adding
backends should be a new `Driver` rather than a change to the machine
controller. The probe takes that at face value and implements `State` and `Set`
over Redfish, plus `BiosAttributes` and `StageBiosAttributes` for the pilot
questions.

Three things it already establishes without hardware:

- **The interface fits.** `State` maps to `ComputerSystem.PowerState` and `Set`
  to `ComputerSystem.Reset`, over the existing `Outlet` struct.
- **`power.Cycle` drives it unmodified**, including its verified-off step, which
  is exercised in `TestCycleDrivesTheProbe`.
- **One semantic does not transfer, and the pilot should decide it.**
  `power.Cycle` owns the settle interval because an Apple silicon mini that
  loses mains for less than a few seconds can come back with the PSU still
  charged, in exactly the wedged state the cycle was meant to clear. A BMC
  `ForceOff` is not a mains cut: the PSU keeps standby power up, which is how
  the BMC stays reachable at all. So the settle interval's justification does
  not carry over, and a `redfish` driver either wants a different default or
  the rack's real remedy for a wedged x86 node stays the PDU outlet, with
  Redfish as the softer first rung of the ladder. **That is an argument for
  keeping both drivers, not for replacing one with the other.**

### What an emulator can settle, and what it cannot

**Evaluated and recommended:** build the probe against
[`sushy-tools`](https://opendev.org/openstack/sushy-tools) (`sushy-emulator`).
Reading its `main.py` on 2026-09-21 confirms it serves
`/redfish/v1/Systems/<id>/BIOS` (GET) and `/redfish/v1/Systems/<id>/BIOS/Settings`
(GET, PATCH), keeps a pending-versus-current split, and calls
`apply_pending_bios` on `On`, `ForceOn`, `ForceRestart` and `GracefulRestart`.
BIOS is gated behind `SUSHY_EMULATOR_FEATURE_SET=full`; the `minimum` and
`vmedia` sets do not serve it. DMTF also publishes static mockup bundles, which
are useful for schema shape but serve no state transitions.

An emulator settles:

- that the `Driver` interface fits Redfish at all;
- the pending-versus-current state machine and the stage/reboot/verify loop;
- error handling, timeouts, context cancellation, retries;
- most of the code, written and tested before a board exists.

An emulator cannot settle **any** of Q1 through Q10, and it is worth being
blunt about why: **an emulator implements the specification, and this vendor's
departures from the specification are the entire question.** Three concrete
examples already visible:

| | sushy-emulator | what the vendor documentation describes |
|---|---|---|
| Settings resource | `BIOS/Settings` | `Bios/SD` |
| Path casing | `BIOS` (uppercase) | `Bios` |
| Reset types | includes `ForceOn`, `GracefulRestart` | `On`, `ForceOff`, `GracefulShutdown`, `ForceRestart` |

A probe validated only against the emulator would fail on first contact with
the board in at least the first two of those.

So the test suite fakes **both**. `redfish_test.go` runs a fake BMC in two
modes: the standard shape, and the MegaRAC shape with `Bios/SD`, an ETag
precondition, and a boot-override write refused with the verbatim FutureState
message from Ironic bug 2073518. Those fakes are written from documentation,
not captured traffic, and say so in the file. The point is not that they are
right; it is that when the board arrives, **whichever fake turns out to be
wrong is the finding**.

## Deliverable 4: what the result changes

### If BIOS attributes work

- **A `redfish` driver in `internal/power`.** Promote the probe, drop
  `InsecureSkipVerify` for a pinned or provisioned certificate (Q9), and
  register it in `NewRegistry`. The `RackHost` CRD already carries
  `powerDriver`, so the inventory shape does not change.
- **A `RackX86Machine` kind reusing `controllers/linux`.** The three Linux
  fleet kinds (Dedibox, OVH, Elastic Metal) already share
  `linux_cloudinit.go`, the kubelet and containerd drift checks, and the
  operator-minted kubelet identity. A rack x86 node is those, with the pool
  moved in-cluster to `RackHost` exactly as `RackAppleSiliconMachine` does. It
  would be the first x86 kind whose reboot is out-of-band rather than a
  provider API call or a PDU outlet.
- **The AMISCE track can be retired rather than maintained**, but only for
  boards that have a BMC. The MS-01s do not, so AMISCE still has to exist for
  BER1's life. What changes is that it stops being the *strategic* answer and
  becomes a legacy adapter with a known end date, which is the difference
  between tooling that is temporary and tooling that accretes until it is
  load-bearing.
- **The serviceability argument gets a data point, not a conclusion.** The
  BMC was ranked *last* of five criteria for the next purchase, behind
  serviceable-by-a-stranger, hot-swap and redundant PSU, rails and airflow, and
  five-year parts availability. A successful pilot does not promote it.

### If they do not

Say it plainly, in the repo, on the day it is known.

- **A BMC that only does power and inventory still beats no BMC.** Out-of-band
  power, a serial console and inventory without a person in Berlin is real
  value, and it is strictly more than an MS-01 offers.
- **But it does not retire firmware-config tooling.** Something still has to
  write restore-on-AC-power-loss and the network stack, and on an AMI board
  that something is still AMISCE with its kernel module, its Secure Boot
  incompatibility and its CMOS-clear failure mode. The only difference is that
  it can now be driven over a serial console instead of in person.
- **The hardware argument has to be re-made on serviceability alone**, which is
  where it should have been anyway per the priority order above. That is a
  defensible argument, just a different one, and it should be made explicitly
  rather than inherited from a pilot that failed.
- **Check Q3a separately before concluding.** If `PowerRestorePolicy` works
  while BIOS attributes do not, the single most important setting is still
  automated and the verdict is much closer to success than failure. Do not
  collapse these into one result.

### Metal3 / Ironic: do not adopt, with one narrowed caveat

The prior conclusion stands and this research strengthens it:

- **Ironic's value is entirely mediated by a BMC**, and `HostFirmwareSettings`
  is Redfish/iRMC/iLO only. For the MS-01s, which have none, it buys nothing.
- **It would be a second bare-metal lifecycle model** beside
  `cluster-api-provider-tuist`, which already owns adoption, self-join, drift
  and release for five machine kinds.
- New, and worth recording: **Ironic needed a vendor-specific fix for exactly
  these boards** (bug 2073518, merged September 2025, backported November
  2025). Adopting Ironic would not have avoided the deviation; it would have
  meant waiting on someone else's release train for it. That cuts against the
  usual "upstream has already solved the quirks" argument.

**Is `HostFirmwareSettings` worth mirroring in our own CRDs?** Its shape is
`spec.settings` as desired state, `status.settings` as observed, plus a
`FirmwareSchema` resource holding per-attribute types and allowed values, which
maps onto the Redfish attribute registry.

At this scale, **no**. Four x86 nodes, one board model, one BIOS version at a
time. A plain rendered desired-state file, checked in beside the rest of the
rack's inventory and applied by a small command, gives the same convergence
without a controller, a CRD and a reconcile loop. The **one part worth
borrowing is the split**: desired state and observed state are separate, and
the observed side records the registry version the names were resolved against
(Q3). Without that, a drift check cannot tell "converged" from "the names
stopped matching after a flash".

Revisit if a second board model or a second site appears, which is the same
BER2 trigger as everything else here.

## Practical: where the board lives

- **On a bench first, racked mid-October.** The pilot includes experiments that
  can require a CMOS clear. Under the 2026-09-21 decision this board is
  `ber1-svc` rather than a spare, so "nothing in Berlin is at risk" is not
  free: it holds only while the box is still on a desk, and that window closes
  at mid-October racking. Answer every destructive question before then. No
  existing rack hardware is touched either way, and if the window is missed the
  already-bought MS-01 racks as `svc` exactly as originally planned.
- **Bring a separate PXE source to the bench.** `svc` is the rack's PXE server,
  so question 6 cannot be tested against the box under test.
- **Powered from a normal wall outlet**, ideally through a switched plug so the
  Q3a mains-loss test is a command rather than a trip to the socket. The
  existing `shelly` driver is exactly this and already works, which makes the
  bench setup a small reuse rather than new work.
- **The BMC goes on its own port.** The board has a dedicated IPMI LAN
  separate from the four data ports, so the management interface is physically
  isolated by default. In the rack that port belongs on the management VLAN;
  on the bench, a laptop on the same switch is enough.
- **Tailnet, not a public address, for anything beyond the bench.** A BMC is a
  full out-of-band console with a factory self-signed certificate and default
  credentials, and it must never be reachable from the internet. The rack's
  existing pattern applies unchanged: a subnet router advertises the host, with
  a /32 per host rather than the rack prefix, and the router's LAN address in
  the SSH ingress allow list. For CI to drive it later, the same tailnet path
  the provider already uses for `RackHost` power polling is the model.
- **First session is read-only.** Service root, Systems, Bios, Registries,
  Managers, and the certificate. Nothing is written until Q1 and Q2 have
  answers, because the first write is the first thing that can require a
  physical recovery.

## Sources

All read or fetched 2026-09-21.

- ASRock Rack B650D4U-2L2T/BCM user manual: https://download.asrock.com/Manual/B650D4U-2L2TBCM.pdf
- ASRock Rack BMC user guide, AST2600, Rev. 1.01: https://download.asrock.com/Manual/BMC/B650D4U.pdf
- Gigabyte, Redfish API Reference Guide for ASPEED AST2600, Redfish v1.11.0: https://download.gigabyte.com/FileList/Manual/server_manual_redfish_v1.11.0.pdf
- Ironic bug 2073518, "Redfish - Future State (SD) - AsRock Rack": https://bugs.launchpad.net/bugs/2073518
- Blackcore Technologies, "Modify BIOS settings with Redfish": https://support.blackcoretech.com/support/solutions/articles/70000661814-modify-bios-settings-with-redfish
- bmcctl, a CLI for AMI MegaRAC BMCs on ASRock Rack boards: https://github.com/j4y-w4lk3r/bmcctl
- DMTF ComputerSystem schema v1_22_0: https://redfish.dmtf.org/schemas/v1/ComputerSystem.v1_22_0.json
- sushy-tools emulator source: https://opendev.org/openstack/sushy-tools
- Prices: https://geizhals.de
- be quiet! Pure Power 13 M 750W cable table: https://www.bequiet.com/en/powersupply/5960
