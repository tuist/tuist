# Rack nodes

How the BER1 rack's x86 Linux machines (the MS-01s: the two edges and the
storage pair) become cluster nodes. A host boots its installer, installs
Ubuntu, joins the tailnet on first boot, and the cluster's operator joins it as
a node and keeps it converged. The installer is the install stick every host
keeps plugged in, which boots with the firmware as it ships, or a netboot from
the rack's edges, which needs the firmware's network stack on. Both run with
Secure Boot on. Either way it installs what the edges' boot server publishes for the host:
a box with an empty disk boots it on its own, and a running one is reinstalled
by raising its `reinstallGeneration`. The edges run the boot server, each serving the other, so
only the first edge of a site is installed from a stick of its own.

Bringing up a whole new site, from boxes to taking jobs, follows
[`site-bring-up.md`](site-bring-up.md).

## The pieces

- **Inventory** is `rackLinuxFleet.hosts` in the env's tuist chart values,
  rendered as one `RackLinuxHost` per box, named after the machine's SMBIOS UUID:
  its hostname (the node, OS and tailnet name), role, site, and optionally its
  `bootMAC`, the MAC of the NIC it netboots from (the MS-01's i226-LM, on the
  management switch), which otherwise comes from the machine's announcement.
  Its role's `rackLinuxFleet.sites.<site>.roles.<role>`, else
  `rackLinuxFleet.roles.<role>`, gives its tailnet tags, labels and taints. The operator keeps a CAPI Machine for each host, which makes it a
  node.
- **The operator** (`infra/cluster-api-provider-tuist`, `controllers/linux`)
  publishes each host's install, finds the host on the tailnet and joins it.
  See "Rack-owned Linux hosts" in its AGENTS.md.
- **The boot server** (`rackLinuxFleet.boot`, a DaemonSet in the rack-nodes chart
  running the operator's `rack-boot` on both edges) serves what the operator
  publishes, on the site's provisioning address, from whichever edge holds it,
  hands each install's seed to its host alone, and lists the machines sticks
  announce as RackLinuxCandidates.
  It serves nothing until it has the installer ISO, so each edge offers its
  verified ISO, and only it, on its address on the edges' VRRP link (`vrrp0`),
  and a freshly installed edge fetches it from there before the internet, which
  took 45 minutes on 09-25.
- **The edges' DHCP** (`management.edge.netboot` in the site definition,
  rendered into the rack-edge chart) points UEFI firmware on the management
  switch at the boot server. keepalived moves the provisioning address, and
  with it the DHCP and the boot server that answer, to the standby edge when
  the active one goes. See `infra/rack-switch-fleet/AGENTS.md`.
- **The seed** is rendered by `internal/rackinstall` in the operator, for PXE
  and for the stick alike.

A host that is declared but not installed does not hold up a deploy: its
Machine waits for it to come onto the tailnet.

## The install stick

Every host keeps the install stick plugged in. It is the same for every host of
an env and carries no credential:

```
mise run rack:write-install-usb /dev/disk4 --any-host
```

Its installer takes DHCP on every wired port, fetches `rack-node` from the boot
server (`/tools/rack-node`), asks with `rack-node seed` for the seed published
under each of its NICs, attesting with the machine's TPM when the host's is
pinned, and installs the first it gets: the seed a netboot reads (below). A
stick written before its installer asked through `rack-node` gets only the
loader for a host whose TPM is pinned, installs nothing, and needs writing
again. With nothing published it boots a rack
install already on the disks as soon as the boot server says so (a 404 for
every NIC), or after five minutes of not reaching the boot server; a machine
without one waits and announces itself (below). The MS-01's firmware keeps a
fixed boot order, the installed disk first, and rewrites `BootOrder` at every
boot, so an installed host boots its stick only through `BootNext` or once its
disk no longer boots. The seed carries its install's key ID (`# tuist-install-id:`), so a
stick booted again after its install hands over to that system, as a netboot
does. Its installer also keeps the live system from ejecting the stick when the
install reboots (`casper.service`, overridden under `/run`): an ejected stick
reports no medium until `eject -t` loads it, so the next reinstall would not
find it.

The stick's five minutes are on the clock: a machine without its
provisioning lease sends the request out the default route an uplink's DHCP
gave it, where nothing answers, so each try lasts until curl's ten-second
connect timeout. While the boot server does not answer, the console says once
a minute which addresses the installer holds, so a stick that never got a
provisioning lease shows it.

The installer's DHCP is the live ISO's own, `en*` (cloud-init prefers the
ISO's system configuration to the seed's `network-config`). Once it has an
install, subiquity applies that install's network section, DHCP on the
uplinks only, to the live system and unmanages its 2.5G ports, about nine
seconds after they come up. An installer that sends one `DHCPDISCOVER` on the
management segment and then nothing is often just that; see "An offer in the
log with no request after it" in
[`infra/rack-switch-fleet`](../rack-switch-fleet/AGENTS.md). At the colo, where
nothing serves DHCP on an edge's uplinks, it also takes away an edge install's
only route out, its provisioning lease.

- A box with an empty disk boots the stick on its own, with the firmware's
  defaults: Secure Boot on and the network stack off.
- To reinstall a running host, the operator boots the installer partition of a
  preinstalled host (below), else looks for a USB disk whose ISO
  carries `nocloud/tuist-install-stick`, gives its EFI partition a boot entry of
  its own (`tuist install stick`, left out of `BootOrder`), sets `BootNext` to
  it and reboots. A host without one netboots instead.

**Declaring a new box** needs no one to read its label. Racked with its stick
and powered on, it finds nothing published and announces itself to the boot
server once a minute, and the operator lists it:

```
kubectl get rlc -o wide
```

A `RackLinuxCandidate` is named after the machine's SMBIOS UUID and shows its
serial, product and `BOOTMAC`, its i226-LM. Declaring the box is adding its
UUID, a hostname and a role to `rackLinuxFleet.hosts`:

```yaml
- uuid: 04450c00-63f4-11f1-81f4-3582298d5c00
  hostname: ber1-edge-b
  role: edge
```

The host takes its boot MAC, model and NICs from the candidate once
(`status.hardware`), and its TPM (`status.tpm`) when the stick announced one;
an installed host's TPM is read over SSH otherwise. Its AMT is activated
when its model is one of `rackLinuxFleet.amt.products`, and AMT gets an address
from `amt.addressRange`. The operator then publishes its install, and the
stick, still waiting, installs it. A candidate that a host declares shows the
hostname under `DECLAREDAS`, and stays. What a machine announced first is
kept: an announcement under its UUID that differs is refused and shows under
`CONFLICT`, and a host takes nothing from a candidate with one.

## Netboot

For a host that is not on the tailnet yet, or whose `reinstallGeneration` is
above the generation it was installed for, the host controller mints a join key
and an SSH host key and writes three files under the boot MAC to the
`<fleet>-boot` Secret: the autoinstall `user-data` and `meta-data`, and an iPXE
script, with the host's UUID and the join key's ID beside them. The boot server
watches the Secret, and each edge's boot server reports the install servable
on the host's `status.boot.servers`; the operator reboots a running host into
it only once the edge holding the provisioning address did, or, for an edge,
every other edge of the site. The chain a netbooting host goes through:

1. The firmware's PXE asks the active edge's dnsmasq for an address and gets one
   in the provisioning range, with iPXE's Secure Boot shim (`snponly-shim.efi`)
   from the provisioning address over TFTP; the shim loads the iPXE beside it
   (`snponly.efi`).
2. iPXE asks for an address again, is told to run `boot.ipxe`, and fetches
   `hosts/<mac>.ipxe` over HTTP, then `hosts/<uuid>.ipxe` by the machine's
   SMBIOS UUID: a network boot through AMT comes from whichever NIC the
   firmware lists first. A host with no install published finds nothing and
   goes back to its firmware's next boot entry.
3. The host's script loads the installer's kernel and initrd over HTTP and
   boots them through Ubuntu's shim from the ISO (iPXE's `shim` command), which
   verifies the kernel under Secure Boot; the kernel downloads the ISO into
   memory (`url=`), keeps its DHCP on the NIC that netbooted (`BOOTIF`), and
   reads the seed from `/hosts/<mac>/`. The seed carries the join key, the
   host key and the console password. For a host whose TPM is pinned (`status.tpm`), `user-data` is the
   install stick's loader, which asks for the seed with `rack-node seed`, and
   the boot server seals it to that TPM (`status.boot.attested`). For any
   other, the boot server hands `user-data` only to one of the MACs the host
   took (`status.hardware`), as its neighbor table shows the address that
   asked, and after the first to that MAC alone (`status.boot.servedTo`).
4. The install is the same as a stick's: Ubuntu with network configuration for
   the SFP+ uplinks only, the fleet key, the operator's host key in place of
   the ones the package generated (cloud-init told not to replace it), and a
   first-boot unit that joins the tailnet with the single-use key, which lives
   two hours.
5. Once a tailnet device that is not the one the install replaced shows up, the
   host controller withdraws the install, so the key stops being served, and
   records the generation it installed. It holds that device to the install's
   host key only when the boot server handed out the seed
   (`status.boot.servedAt`); a device that joins otherwise came from another
   installer, such as the host's own stick, and is trusted on first use.

The iPXE is the iPXE project's Secure Boot build (pinned in the operator's
image): a shim signed by Microsoft's UEFI CA 2011, the CA that signs Ubuntu's
shim, which loads the `snponly.efi` signed by the iPXE project's CA. The shim
finds that file from the boot file name in the DHCP packet's file field, which
the edges' dnsmasq keeps there (`dhcp-no-override`) instead of moving it to
option 67. Ubuntu's own network chain (shim, then network GRUB) cannot be used
on the MS-01: GRUB's UEFI network driver cannot send a packet through its Intel
network driver ("couldn't send network packet" on both i226 ports), so it never
reads its menu.

An edge serves the segment from its i226-V (ber1-mgmt port 48 for `ber1-edge-a`,
47 for `ber1-edge-b`), not its i226-LM: an i226-LM with vPro never puts a DHCP
offer it sends on the wire, while the daemon logs it and a capture on the host
shows it. An edge's i226-LM carries only AMT, and the host keeps it up with
nothing of its own on it.

The installer can get its default route from its provisioning lease, through
the edge, as well as from the uplinks' DHCP, so each edge translates the
provisioning range onto its uplinks as well as into the tailnet.

**Racking an MS-01** is its cables and the install stick. Its i226-LM is cabled
to the management switch, the port AMT answers on. With its disk empty it boots
the stick, which installs it once the host is declared, and the operator
activates its AMT. From then on AMT powers it on after a power loss (below), so
a host that is not an edge needs nothing in Setup.

**An edge needs one visit to Setup**, because AMT is reached through an edge and
nothing powers on an edge while no edge is up: Advanced → ACPI Settings →
Restore On AC Power Loss: **Always On**. The MS-01 ships with Always Off. Always
On, not Last State: `online` decides whether a host stays off, and the operator
shuts down one that comes back on against it. Setting it on another host as
well brings that host back without waiting for an edge and AMT.

Netbooting needs the same kind of visit, on any host: Advanced → Network Stack
Configuration → Network Stack and IPv4 PXE Support enabled. Then it netboots
whenever its disk does not boot. Secure Boot stays on either way.

An installed host reboots straight into Setup, over a console such as a JetKVM
on its HDMI and USB:

```
ssh tuist@<host> sudo systemctl reboot --firmware-setup
```

Save & Exit applies the change and boots the installed system.

**The stick is the MS-01's route, a workaround for its firmware.** The MS-01 ships
with its network stack off, and nothing but a person in Setup turns it on:
AMT can override the next boot but not change a Setup setting, and writing the
firmware's Setup variables from the OS means poking an undocumented AMI
variable layout that changes between firmware releases, where a wrong write
can leave the box unbootable, and changing a security setting behind the
person racking it. A stick boots with the firmware's defaults, Secure Boot
included, so a factory box needs no one in Setup to install: it announces
itself, installs once declared, and is reinstalled through `BootNext` to the
stick. Restore On AC Power Loss is the same kind of Setup setting, which is why
an edge's is set by hand. Netboot is what AMT's recovery of a box that no
longer boots needs; a box without it is recovered by booting its stick. Every
box needs its stick left plugged in, so the next machine model should be
something like an ASRock Rack board, whose BMC sets the boot order and firmware
settings and mounts an installer out of band, and which netboots with no stick.

**A box whose disk already boots something** boots that first; pick the stick,
or the i226-LM's network entry, from the boot menu (F7 on the MS-01) once.

**Reinstalling a host** is raising its `reinstallGeneration`, in the values or
directly:

```
kubectl patch racklinuxhost 04450c00-63f4-11f1-81f4-3582298d5c00 --type merge \
  -p '{"spec":{"reinstallGeneration":2}}'
```

People patch through the kubectl gateway's `tuist-fleet-unwedge` role
(`infra/helm/pomerium`), standing in staging and on a write elevation in
production.

The operator publishes the install, waits for the boot server answering the
host's netboot to report it servable (`status.boot.servers`), then sets `BootNext` to the host's install stick, or without one to its
PXE entry for its boot MAC, over SSH and reboots it. It does this once: a host
that comes back on its old install reports `Installed` False with
`ReinstallDidNotBoot` after half an hour, and raising the generation again tries
again. A host that is off the tailnet cannot be reached over SSH; with its AMT
activated the operator power-cycles it through AMT into its network boot
instead, once (AMT's Force PXE Boot, which boots the firmware's first network
entry, the i226-V on the MS-01, found by the machine's UUID). That needs the
firmware set up to netboot (below). Otherwise, and without AMT, boot its stick
by hand. The new install registers a new tailnet device; once it is connected
the host controller deletes the old one, names the new one after the host and
records the generation in `status.provisioning.installedGeneration`, and the
machine controller joins the host afresh. A host with `online: false` is
powered off (below) and not rebooted into an install.

**Powering a host** is its `online` field: `false` shuts it down from its OS, or
through AMT when it is not on the tailnet, and `true` powers it back on through
AMT. A one-off reboot through AMT is the `tuist.dev/reboot` annotation (`cycle`,
`reset` or `pxe`).

**After a power loss** a host whose firmware restores comes back by itself. One
that does not is off, and the operator powers it on through AMT once a host
that should be on is off the tailnet and AMT reports it off, retrying with a
backoff (`PowerMatchesOnline`, `PowerChanged` events). AMT is reached through an
edge, so this needs an edge back first: with both edges off, only an edge's own
Restore On AC Power Loss brings the rack back, which is why every edge has it
(above). `PowerReachable` (in `kubectl get rlh -o wide`) shows, before it is
needed, whether a host could be powered on that way; `AMTLinkDown` is a
management port with no link, a cable to look at.

Watch it with:

```
kubectl get racklinuxhost -o wide -w
kubectl describe racklinuxhost 04450c00-63f4-11f1-81f4-3582298d5c00
```

**Retiring a host** is removing it from `rackLinuxFleet.hosts`, deploying, and
deleting its `RackLinuxHost`, which the chart keeps
(`helm.sh/resource-policy: keep`):

```
kubectl delete racklinuxhost 04450c00-63f4-11f1-81f4-3582298d5c00
```

People delete through the kubectl gateway's `tuist-fleet-unwedge` role. The
operator withdraws the host's install and deletes its Machine. Once the
Machine's delete has stopped the kubelet and removed the Node, it deletes the
host's tailnet device and its key in `<fleet>-console`, and the `RackLinuxHost`
goes. A host still in the values is created again by the next deploy.

**Renaming a host** is changing its `hostname`. The host keeps its UUID, so it
is the same box and the same Machine: the operator renames its tailnet device,
deletes the Node it joined under, and joins it again under the new name, with
its OS hostname changed, no reinstall. An edge's rename also needs its entries
in the site definition (`infra/rack-switch-fleet`) renamed, since the rack-edge
pod picks its configuration by node name.

**The console password** of each host is in the `<fleet>-console` Secret, under
the host's name, minted with its first netboot install and kept across
reinstalls. The seed carries it for cloud-init's `chpasswd`, so the installed
system hashes it with its own crypt on the first boot; the installer's
`identity` gives the account a locked password until then.

**A published install is a credential.** Its seed carries a join key that
admits one device with the host's tags, the host's SSH host key and its console
password. The boot server seals it to the host's pinned TPM, or, for a host
with no pinned TPM, hands it only to one of the host's NICs. Keys expire after
two hours, and the operator publishes a fresh one while the host still needs
it.

## A host's own stick

An edge netboots from the other edge: the operator publishes its install only
while another edge of its site is on the tailnet to serve it. The first edge of
a site has no other edge, so it is installed from a stick, and so is any host
when both edges are down:

```
mise run rack:write-install-usb /dev/disk4 --host ber1-edge-a
mise run rack:write-install-usb --host ber1-edge-a --output ber1-edge-a.iso
```

The env is the one the rack is in, by its site definition's
`kubernetes.namespace` (`mise run rack:fleet env`), unless `--env` names
another. It needs `op` signed in (it reads the vault `tuist-k8s-<env>`), `xorriso`, and
`go`, which renders the seed with the operator's renderer. The Ubuntu 24.04 ISO
is fetched once, checked against Ubuntu's SHA256SUMS, and cached in
`~/Library/Caches/tuist-rack`. The console password comes from the 1Password
item `<host> console` (created on first use), and the writer's own key is
authorized beside the fleet key.

**Until the install has used it, the stick is a credential.** A stick lost
before use is dealt with by deleting its key, whose ID the task prints, in the
Tailscale admin console.

**A stick installs a machine once.** Its early-commands look for an install that
carries the stick's key ID and, finding one, set `BootNext` to it (with the
installed system's own `efibootmgr`) and reboot into it rather than wiping it.
The MS-01s boot USB first, so this is what turns the reboot at the end of the
install into the new system's first boot. Pull the stick once the node is up:
left in, it costs every reboot a pass through the installer. A netboot install
carries the same guard.

## What an install carries

- network configuration for the SFP+ uplinks only, so the 2.5G ports stay
  unmanaged for the node's pods: an edge's rack-edge pod owns its switch port.
  That is DHCP on the X710's `i40e` ports, except on an edge whose
  RackLinuxHost carries `spec.edge` (rendered from the site definition at a
  site with a WAN): its uplinks take no address, and it goes out over the
  site's VRRP VLAN through the other edge, an active-backup bond `vrrp0` over
  `vrrp0-<n>` on the n-th uplink with its VRRP address and a default route
  through the other edge at metric 200, built the way the rack-edge pod
  builds it, plus global resolvers in
  `/etc/systemd/resolved.conf.d/10-tuist-edge.conf`. Once the site's WAN
  address is known, an edge also gets a first-boot WAN service. The first
  edge of a site has no other edge to go out through, so it takes the site's
  static WAN itself until its rack-edge pod runs ("The first edge of a site" in
  `infra/cluster-api-provider-tuist/AGENTS.md`). Nothing serves DHCP on
  the management VLAN at the colo, so that is how a reinstalled edge reaches
  the tailnet and gets converged. It needs the other edge up as master, so the
  edges are reinstalled one at a time. A per-host stick (`--host`) renders no
  edge network; install an edge at the colo by netboot or with the site's stick
  (`--any-host`). See "Rack-owned Linux hosts" in
  [`infra/cluster-api-provider-tuist`](../cluster-api-provider-tuist/AGENTS.md);
- `blacklist btusb` in `/etc/modprobe.d/tuist-rack.conf`, which the converge
  also keeps: the MS-01's Bluetooth dereferences NULL on a warm boot of the 6.8
  kernel, and the node's `panic_on_oops` turns that into a reboot every 70
  seconds;
- `10-tuist-no-start-limit.conf` drop-ins for `ssh.service` and `ssh.socket`,
  which the converge also keeps: five sshd starts within 10s otherwise leave
  nothing listening on `:22`, and the operator reaches the host over SSH alone.
  See "sshd stays reachable on Linux hosts" in
  [`infra/cluster-api-provider-tuist`](../cluster-api-provider-tuist/AGENTS.md);
- nothing for the management port (the i226-LM, the host's boot MAC). The
  converge keeps it up with no address, no IPv6 link-local and no ARP
  (`/etc/systemd/network/10-tuist-management.network`), because AMT shares the
  port and loses its link when the host leaves it down;
- the host's hostname and role, the `tuist` account with passwordless sudo and
  a console password, SSH with password authentication off, and the rack's
  fleet key (`BER1_FLEET_SSH`) plus people's keys
  (`rackLinuxFleet.authorizedKeys`, or the stick writer's own);
- for a published install, an SSH host key the operator generated for it:
  the install replaces the host keys the package generated with it alone, and
  tells cloud-init to keep it, and the operator trusts the new install by its
  fingerprint rather than by whatever answers first. A per-host stick carries
  none, and the host generates its own, which the operator pins on first use
  even while an install is published for the host, since the boot server never
  handed that install's seed out;
- a tailnet join key minted from the OAuth client in `TAILSCALE_RACK_NODES`:
  single-use, pre-authorized, not ephemeral, carrying the host's tags, and
  valid for two hours. One no host fetched is renewed before it expires, and a
  replaced or withdrawn one is revoked. The
  OAuth client never reaches the host. It mints keys for its own tag
  (`tag:tuist-rack-edge`, which both edges carry) and the tags it owns
  (`tag:tuist-rack-node`, for every other role).

A first-boot unit, `tuist-tailnet-join`, installs Tailscale, joins with the key,
deletes it, and disables itself; it retries every minute until it succeeds.
Tagged devices have key expiry off, so nothing about the join needs a person.
`/etc/tuist-rack-node` records the node, role, build time and the join key's
ID; an install that answers SSH without it was not built by either path.

## Break glass

If the join key is gone (expired, or spent by an install that then had to be
redone), join the tailnet by hand; the operator takes over from there:

```
ssh tuist@<LAN address> sudo tailscale up --hostname=<host> --advertise-tags=<tags>
```

A tailnet admin opens the login URL it prints.

## The preinstall image

A box a vendor ships straight to a site arrives with its installer on its own
boot drive, so it needs no stick, the first edge of a site included. The
vendor boots the preinstall image once on the box:

```
mise run rack:write-install-usb --preinstall --output tuist_preinstall_<date>.iso [--internet-server https://<host>]
```

It writes `tuist_preinstall_<date>.iso` and its `.sha256`. The image is
Ubuntu's live server ISO with Ubuntu's signed boot chain, so it boots with
Secure Boot on, and carries no credential. Booted once (PXE, HTTP boot,
virtual media or a stick), its deploy seed:

1. picks the smallest internal disk of at least 100 GB, the M.2 boot drive,
   never a storage node's data drive, and refuses one that holds anything but
   an installer partition;
2. writes partition 1 (4 GiB, ESP type, FAT label `TUISTINST`, GPT name
   `tuist-installer`) with the ISO's tree, checked against its `md5sum.txt`,
   and the resident seed in place of its own;
3. adds a UEFI boot entry `tuist installer`, first in `BootOrder`, with the
   efibootmgr from the ISO's pool (the live system has its libraries but not
   the binary), after deleting any entry of that name: the ASUS firmware keeps
   an entry whose partition is gone, turned into a group of its network
   entries (`VenHw(99e275e7-…)`). Without the entry the firmware lists no disk
   option and boots the partition only after every network entry failed;
4. prints the unit sheet on the screen and the serial console, and to
   `TUISTINST:/tuist/unit-sheet.txt`: product, serial, SMBIOS UUID, each NIC's
   MAC, driver and name, the TPM endorsement key's SHA-256, and its check
   code, the first 16 hex digits in four groups, for the vendor's acceptance
   report;
5. powers the box off.

From then on the box boots the resident installer: the `--any-host` stick's
installer, which casper boots from `TUISTINST` alone
(`live-media=/dev/disk/by-label/TUISTINST`) with persistence off
(`nopersistent`: casper otherwise turns the drive's free space into a
`writable` partition). It asks the env's boot server and then
`--internet-server` for the install published for one of its NICs. With no
default route from DHCP, it tries each site's static WAN
(`management.edge.wan` of `infra/rack-switch-fleet/sites/*.json`) on each
port with a link, untagged and on the site's VLAN, and keeps the one whose
address nobody answers for and whose gateway does (`busybox arping`).

**A preinstalled box earns its install with its TPM.** The vendor's acceptance
report carries the box's SMBIOS UUID and its TPM check code from the unit
sheet. Declaring the box takes both:

```yaml
- uuid: 03de3d42-4a8e-9278-ee1a-a0ad9f25c75f
  hostname: larch-edge-b
  role: edge
  tpmCheckCode: 1a2b-3c4d-5e6f-7a8b
```

The operator then pins the host's TPM only from an announcement whose key has
that code (`TPMCheckCodeMismatch` on `HardwarePinned` otherwise), and the
internet boot server (`rackLinuxFleet.boot.internet`, `rack-boot --internet`
on cloud nodes behind the ingress) takes announcements only from hosts
declared with one. Anyone on the internet reaches that server, so it hands out
nothing but seeds sealed to a pinned TPM, which only that TPM can open, and
serves nothing to netboot. With it configured, the operator publishes the
install of an edge whose TPM is pinned even with no other edge of its site to
serve it: the first edge of a site asks the internet boot server for it.
Production runs it at `rack-boot.tuist.dev` and lists the RS501A in
`rackLinuxFleet.preinstall.products`, so a vendor's image for production is
written with `--internet-server https://rack-boot.tuist.dev`.

casper takes the first live medium it finds. Booting the image on a drive that
already holds an installer partition can boot that partition's tree instead,
whose seed is the resident one; the deploy seed refuses to run from it. Wipe
the drive to deploy again.

## The ASUS RS501A and its BMC

From rack 2 on, edges and storage nodes are ASUS RS501A-E12-RS12U/1G servers
with an ASMB11-iKVM BMC (AMI MegaRAC on an AST2600), driven over Redfish by
`rack-bmc` (`infra/cluster-api-provider-tuist/cmd/rack-bmc`, client in
`internal/redfish`). The BMC's dedicated port is the leftmost of the three
RJ45 ports at the back, LAN port 1 the middle one, LAN port 2 the right one.

```
go build -o rack-bmc ./cmd/rack-bmc        # in infra/cluster-api-provider-tuist
export RACK_BMC_PASSWORD=...               # the BMC's admin password
./rack-bmc -bmc https://<bmc> inventory    # serial, SMBIOS UUID, MACs, versions, TPM, Secure Boot
./rack-bmc -bmc https://<bmc> check        # the BIOS, BMC and IPMI against the baseline; exits 3 on drift
./rack-bmc -bmc https://<bmc> power off && ./rack-bmc -bmc https://<bmc> apply && ./rack-bmc -bmc https://<bmc> power on
./rack-bmc -bmc https://<bmc> rotate Administrator <new-password-file
```

The baseline (`redfish.Baseline`): Restore AC Power Loss Power On
(`AridApmLastState`), Network Stack, IPv4 PXE and IPv4 HTTP boot on
(`NWSK000`, `NWSK001`, `NWSK006`), TPM on (`TCG001`), console redirection on
COM2 for serial-over-LAN (`TER002`), and Secure Boot on with the factory keys,
whose db holds Microsoft's UEFI CA 2011 and 2023, so Ubuntu's shim boots.

The BMC's own baseline (`redfish.BMCBaseline`, and IPMI in `cmd/rack-bmc`):
- **SSDP off.**
- **The NC-SI sideband off** (`eth1`, which takes a DHCP lease of its own
  through the host's LAN port 2), so the BMC is reachable only on its
  management port.
- **IPMI over LAN on cipher suite 17 alone** (HMAC-SHA256, AES-128); the BMC
  ships taking the SHA-1, MD5 and unencrypted suites too.
- **Serial-over-LAN forcing encryption and authentication.**

The BMC and IPMI settings apply at once, with the host running. Redfish has
no setting for the IPMI ones, so `rack-bmc` sets them through `ipmitool`
(`-I lanplus -C 17`), which has to be installed. A BMC firmware update
resets them, and the rotated logins and the network, unless the
UpdateService's `PreserveConfiguration` flags, all off as shipped, are set
first, so `check` again after one. SNMP is not in the baseline: this BMC keeps it on,
and its version switches are read-only over Redfish, but with no community
and no account enabled for SNMP, v1 and v2c answer nothing. IPMI 1.5
(`-I lan`, MD5) cannot log in with a password longer than 16 bytes, which a
rotated one is.

What the BMC does differently from the standard:

- BIOS settings go to `Systems/Self/Bios/SD` and the BIOS applies them at its
  next POST, which takes about three minutes. The BMC answers 503 to a BIOS
  write, and to a one-time boot, while the host is running or in POST
  (`ServiceTemporarilyUnavailableDueToHostBooting`): write them with it off.
- The BIOS lists in its `MAPIDS` attribute which attributes Redfish may set.
  Secure Boot (`SECB001`) is not one of them, and the BIOS drops it at POST;
  `rack-bmc` enables it through `Systems/Self/SecureBoot` instead.
- The attribute registry (`/redfish/v1/Registries/BiosAttributeRegistryS0310.en-US.13.1.0.json`)
  is served gzip-compressed.
- Reset takes On, ForceOff, ForceRestart and GracefulShutdown; a power cycle
  is ForceOff, then On.
- A one-time boot is `Systems/Self/SD` with `Boot.BootSourceOverrideEnabled: Once` and mode UEFI.
  A CD boot needs the virtual CD attached for some seconds before power-on,
  or POST finds no USB CD and falls through to network boot. The BMC accepts
  `Boot.HttpBootUri` but the firmware ignores it: HTTP boot takes its URL from
  DHCP alone.
- With no UEFI entry for a disk, the firmware lists no disk boot option: it
  tries every network entry (about eight minutes with no DHCP on LAN port 1),
  then falls back to the first disk's `\EFI\BOOT\BOOTX64.EFI`.
- Virtual media needs the OEM actions `AMIVirtualMedia.EnableRMedia` and
  `AMIVirtualMedia.ConfigureCDInstance` before `VirtualMedia/CD1` exists. It
  reads an HTTPS image only from port 443, with a file name of letters, digits
  and underscores, and refuses one without a user name and password for the
  server. It takes a self-signed certificate, but only one that names the
  server's address: with another name it hangs up after the handshake without
  a request. It offers `h2` in ALPN, and a server that negotiated HTTP/2 got
  no HTTP/2 preface from it; one that offers only HTTP/1.1 works. A failed
  open leaves `CD1` at `Stopped - Unable to Open`, and the BMC makes no
  further attempt until it restarts.
- `CertificateService.ReplaceCertificate` on
  `Managers/Self/NetworkProtocol/HTTPS/Certificates/1` takes the certificate
  followed by its private key (PKCS#1) in `CertificateString`; the web server
  serves it within seconds and keeps it across a BMC restart. A certificate
  alone, even one issued for the BMC's own `GenerateCSR`, answers 204 and
  shows in the collection, but the web server never serves it and a restart
  reverts it. `GenerateCSR` also puts the IP addresses in `AlternativeNames`
  as DNS names. A BMC restart (`Manager.Reset` takes `ForceRestart` only)
  takes about two and a half minutes and leaves the host running.
- A PSU that loses AC keeps `Status.State: Present` in `Chassis/Self/Power`,
  and its `Status.Health` becomes a raw hex code (`0x2849`) rather than
  Warning or Critical. The SEL records `Power Supply PSUn AC lost`
  asserted and deasserted, and the PSU's `PowerInputWatts` and
  `LineInputVoltage` drop to about zero. `PowerControl` `PowerConsumedWatts`
  lags and reads low; the PSU inputs are the chassis's draw.
- The BMC's clock follows NTP (`pool.ntp.org`), but `DateTimeLocalOffset`
  is a fixed offset, `+02:00` from the factory, which DST does not move, and
  the SEL is stamped in local time. Set it to `+00:00` (PATCH
  `Managers/Self`).
- Serial-over-LAN is IPMI over LAN with the same accounts
  (`ipmitool -I lanplus -H <bmc> -U admin -E sol activate`).
- Besides `admin` and the factory `Administrator`, the BMC carries a
  `HostInterfaceAdministrator` account for the in-band Redfish host
  interface (`usb0`, 169.254.0.17 on the BMC side).

## Roles

`edge` and `services` install with Ubuntu's `direct` layout. `storage` lays out
its largest disk for cache volumes, the shape the rented cache fleets take
(`controllers/linux/linux_cloudinit.go`, `internal/ovh`, `internal/scaleway`):

| Partition | Size | Filesystem | Mount |
|---|---|---|---|
| 1 | 1 GiB | FAT32 | `/boot/efi` |
| 2 | 2 GiB | ext4 | `/boot` |
| 3 | 64 GiB | ext4 | `/` |
| 4 | the rest | LVM PV, VG `kura-volumes` | — |
| data LV | 128 GiB | XFS, `prjquota` | `/data` |

Kura claims use individual encrypted LVs after regional LVM enrollment. Auxiliary
local-path volumes still use directories on the bounded data LV. XFS
takes `prjquota` only when it mounts, so `/data` carries it in fstab from the
install. The install also bind-mounts `/data/kubelet` onto `/var/lib/kubelet`,
`/data/containerd` onto `/var/lib/containerd` and `/data/local-path-provisioner`
onto `/opt/local-path-provisioner`, so images and volumes land on `/data` from
the node's first boot. `/` stays ext4 because a stick finds the install it made
by mounting the ext4 partitions. Changing the layout is a reinstall.

A rack Linux node runs the local CNI and carries `cilium.io/no-schedule=true`,
unless its host sets `publicAddress` (below). The edges hold addresses in the
rack's management VLAN, 192.168.0.0/24, which sits inside the cluster's pod
CIDR (192.168.0.0/16 in staging and production alike), so they stay off
Cilium for good. A storage node holds no address in that range.

### A storage node on the cluster network

A host with `publicAddress` in `rackLinuxFleet.hosts` (`spec.clusterNetwork`)
is an ordinary Cilium node. ber1-store-a is one, so the `ber1-runners` Kura
region runs on the cluster network and replicates pod to pod with each
account's other regions. Every Cilium node tunnels to every other at its
InternalIP (VXLAN on 8472/udp), probes their health on 4240/tcp, and the API
server reaches its kubelet on 10250/tcp. So:

- **Its InternalIP is the site's WAN address**, 149.6.170.31 at BER1, which
  the operator publishes as the node's address. There is no kubelet proxy and no
  ExternalIP. The host holds the address on a dummy interface (`tuist-cluster`)
  so the kubelet takes it as `--node-ip` and Cilium can bind its health
  responder to it. An nft rule (`tuist_cluster_health`) hands health probes,
  which the edge delivers to the host's machines address, to it.
- **The edges forward those three ports** on the WAN address to the host's
  machines address, from the cluster's Cilium nodes only. The forwards are the
  edge's `tuist_cluster_forwards` table, in its node configuration. The node
  agent on each edge keeps the table's `nodes` set equal to the Linux nodes'
  addresses without the Cilium exclusion, ExternalIPs included: Hetzner
  Cloud nodes and the control plane have no InternalIP. The set is not in the
  configuration, so a node joining the cluster restarts nothing on the edge.
  The WAN filter lets through what the edge translated (`ct status dnat`).
  Cilium decapsulates VXLAN from any source, so this allowlist is what keeps
  the overlay off the internet.
- **Cilium attaches to the `en*` uplinks only** (the `CiliumNodeConfig` in
  `rack-linux-fleet.yaml`): it would take the dummy for a device otherwise.
- The site's one public IPv4 address fits one such host. A second waits for
  the site's own range.

Switching a host is a deploy. The operator rewrites the host's
configuration: dummy, health rule, no bridge CNI, kubelet at the public
address. It repoints the Node's addresses, and once the host has applied that
configuration it removes the Node's Cilium exclusion, and Cilium's DaemonSet
schedules there. Cilium binds its health responder to the public address once,
at start: a Cilium that starts before the dummy exists (as on ber1-store-a on
2026-10-16, before the operator waited) answers no node probe on 4240 until
its pod is deleted. Pods that started on the bridge keep
their bridge addresses until they are recreated. Delete them (`kubectl delete
pod --field-selector spec.nodeName=ber1-store-a`, skipping host-network pods)
once Cilium is Ready on the node. The bridge interface goes at the next reboot.

### Pods on a rack node off the cluster network

On a node without `publicAddress`, a pod off the host network sits on the node's bridge (`10.254.254.0/24`), which
is its default gateway and masquerades it behind the node, so it reaches what
the node reaches: the internet, the rack's segments and the tailnet. It reaches
no cluster Service, no cluster DNS and no pod on another node, and nothing in
the cluster reaches it.

- **The API server.** The node translates the kubernetes Service's ClusterIP
  to the API server it joined through (`/etc/tuist/kubernetes-service.nft`,
  which the node agent loads on every apply), so an in-cluster client on the
  node, host network or not, reaches the API at the address it is given.
- **Names.** A pod that needs them sets its own nameservers, such as
  Tailscale's `100.100.100.100`, which answers tailnet names and fails others
  over, then public resolvers.
- **Telemetry.** `alloy-rack` (`infra/helm/k8s-monitoring`) on each rack node
  ships its pods' logs, scrapes any node-local Kura pods (none since the
  storage node joined the cluster network) and exports the host's own
  metrics, and pushes them to the Alloy receiver at its tailnet name.
- **Being reached.** A pod the cluster has to read from is reached through the
  API server: the Kura controller samples node-local pods through a
  port-forward, which goes through the kubelet.

## Deploys and the rack's health

A rack is dark for days at a time: while it travels to the colo, through a power
event, whenever its one uplink is down. Deploys go on regardless, and nothing
needs doing to the cluster first.

Deploys wait on the tuist, k8s-monitoring and platform releases with Helm 4's
`--wait`, which reads a DaemonSet as ready only when every pod it wants is
Ready, the pods on dark nodes included, and a Deployment only when all its
replicas are available. So nothing in those releases runs a pod on a rack
node:

- The rack node agent, the boot server and the VM image cache are the
  rack-nodes chart's (`infra/helm/rack-nodes`), installed by
  `server-deployment.yml` after the tuist release, from the tuist chart's
  values and the operator's image.
- The Kura gateways on storage nodes are the rack-cache-gateways chart's
  (`infra/helm/rack-cache-gateways`), installed by `k8s:install-platform` after
  the platform release, from the platform chart's values.
- node-exporter skips rack nodes; `alloy-rack`, an Alloy resource the wait does
  not look through, exports their host metrics.

Both charts install with `--wait=hookOnly`, so a deploy applies them and moves
on; the DaemonSet controller rolls their pods out on the nodes that are up and
on the others as they return. A broken rollout there does not fail the deploy:
check the DaemonSets after one that changes them. Kura instances on rack nodes
belong to no release. `mise -C infra run helm:rack-independence` (in the Helm
workflow) renders every env's waited releases and fails when one schedules a
pod onto a rack node: one per role in `rackLinuxFleet.roles`, a rack Linux node
with no role, and a rack's Mac mini.

### Downtime

For planned downtime, a move or work on the rack:

1. **The minis** (remote). Cordon each one's Node and let its running jobs
   finish (`kubectl get rh` names the Machine, which is also the Node), then
   set `parked: true` on each host in `rackFleet.hosts` and deploy. Parking
   deletes the Machine and the Node, so the rack's pools have no nodes to place
   runners on and nothing tries to bootstrap a mini that is off. Unparking them
   afterwards (and deploying) bootstraps each one again.
2. **The Linux hosts** need nothing. Their Nodes go NotReady and their pods are
   evicted after five minutes; the Kura pods on a storage node stay Pending,
   bound to their local volumes, until it is back. A host that comes back on
   the tailnet keeps its install and its Node, so leave `online` and
   `reinstallGeneration` alone.

An unplanned outage needs nothing at all. The rack fleet's MachineHealthCheck
remediates a mini whose Node has been NotReady for 30 minutes, but only while
at most one is (`unhealthyRange: "[0-1]"`): a rack-wide outage remediates no
mini, and once the rack is back, a mini that stayed down is remediated on its
own.

## The rack's VM image cache

A mini starts a runner by cloning a golden base it materialized once per
image, with `tart pull` and `tart clone` (see "macOS runner runtime" in
`infra/tart-kubelet/AGENTS.md`). Without a cache every mini pulls every image
it runs from ghcr.io. When b04-b09 joined on 2026-10-14 each pulled 33 to 62
GB in its first hour and a half, peaking at 0.3 to 0.5 Gbit/s per mini, so
one 60 GB image took 16 to 27 minutes against the pull's 20 minute timeout,
while edge-a's WAN took 5.8 Gbit/s
and half the rack's guest slots sat in `CreatingVM`. Every runner image release
repeats that on every mini. The cache makes an image cross the WAN once per
rack.

`rackFleet.imageCache` in the tuist chart values declares it, and
`templates/image-cache.yaml` in the rack-nodes chart runs it: a zot registry
(the full image; the minimal one has no sync), one Deployment per entry of
`nodes`, pinned to that storage node, on the host network at the node's
machines address and `port` (`10.10.0.11:5000` on ber1-store-a), in plain
HTTP. Its storage is a `scw-local-nvme` volume of `sizeGi` on the node's XFS
`/data`, under a project quota, and the pod requests the same as
`ephemeral-storage`, so the ber1-runners Kura region's placement, which reads
every pod's request on the node, places its instances around it. A cache
that fills fails its next sync and those hosts pull from ghcr.io; it never
takes the Kura region with it.

- **What it holds.** zot syncs an image of `repositories` from `upstream` on
  its first manifest request and answers only once all of it is local, with
  the upstream's manifest bytes, so the digest is ghcr.io's. Requests for an
  image that is already being fetched share that one fetch, and the fetch
  carries on when a requester gives up. A `prewarm` container asks for each
  `prewarm` Xcode's image every `syncInterval`, one at a time, so a release's
  images are fetched as soon as a deploy names them. zot's own periodic sync
  cannot be used: it starts from the registry's repository listing, which
  ghcr.io refuses. The tags come from the same catalog values as the pools'
  images; the deploy passes `runnersFleet.runnerImageSemver` to this release
  too. Pools name each image by the digest of that tag, so a host's probe
  asks the cache for the digest and gets the manifest the prewarm synced. An
  Xcode outside `prewarm` is synced on demand by digest, which zot stores
  untagged, so retention frees it at the next garbage collection: list every
  Xcode the rack keeps warm in `prewarm`.
- **Eviction.** A retention policy keeps the `prewarm` tags and any tag pulled
  within `keepPulledWithin`, and deletes the rest; garbage collection then
  frees their blobs. A release's previous images go a day after the rack has
  rolled off them.
- **How the minis use it.** Tart has no mirror configuration, only `--insecure`
  for plain HTTP, so tart-kubelet chooses the reference. Each host named in
  `routeHosts` (`["*"]` for all of them) gets, through the operator's
  `--rackhost-image-mirrors` and `--rackhost-image-mirror-hosts`, a tart-kubelet
  with `--image-mirror=ghcr.io=http://10.10.0.11:5000`. When it materializes a
  golden base it asks the cache for the image's manifest. If the cache holds
  it, tart-kubelet pulls `10.10.0.11:5000/tuist/tuist-runner@<that digest>`
  with `--insecure`. If the cache is still fetching it, the Pod is requeued
  (`ImageCacheSyncing`) for up to 30 minutes rather than pulling the same
  image from ghcr.io beside it. If the cache is down, does not hold the image,
  or the pull fails, tart-kubelet pulls from ghcr.io as before. The golden
  keeps the name the Pod's image gives it, so Pods, golden Node labels, the
  runners-controller's affinity and the GC key on nothing new.
- **Pre-pull.** A joining host's prewarm (`podagent.Prewarmer`) materializes
  through the same `ensureGolden`, so it goes through the cache too, and it
  asks again every 30 seconds for an image the cache is still fetching rather
  than letting Pods onto the host to wait on that fetch.
- **Integrity.** Tart does not check a blob against its digest. The cache's
  bytes are what zot fetched over TLS and wrote under its digest, and the hop
  to the mini is the machines segment, which carries only our hosts; guests
  are behind the hosts' NAT. Pulling by digest pins the manifest the probe
  saw.
- **Private images.** Everything mirrored today is public, so the cache syncs
  anonymously. A private repository needs zot's `credentialsFile` for the
  upstream, from a 1Password item through ESO, mounted into the cache pod. The
  credential stays on the storage node; the minis keep pulling unauthenticated
  from the segment.

Sizing, as of the 0.32.0 runner images: each is 55 to 62 GB compressed (263
layers of up to 512 MiB). All nine catalog images are 537 GB, 404 GB of
distinct blobs; a release shares about 57% of its blobs with the one before,
so a release beside its predecessor is 578 GB. ber1-store-a's `/data` is
928 GB, also home to the Kura region, which takes precedence on it. So
production's cache is 64 GiB, one image: the latest Xcode minor, 27.1,
which moves to the next minor when one ships. The other versions come from
ghcr.io, and so does 27.1 for about a day after a new image, until the old
tag ages out (`keepPulledWithin`) and frees the room. Prewarming a second
version beside it needs about 160 GiB through a release change, and every
image the rack runs about 578 GB. Raise it once a drive in store-a's spare M.2 slots, or store-b,
gives the site more disk.

The claim is named after its size, because a claim cannot shrink: a new
`sizeGi` makes a new volume, which the cache fills again from the upstream,
and Helm deletes the old claim once the Deployment's Recreate has released
it. The pod's `ephemeral-storage` request follows `sizeGi`, and that request
is what the Kura region's placement counts.

Turning it on is a deploy per step, and `routeHosts` is the feature flag: set
`enabled`; once
`kubectl -n tuist logs deploy/tuist-tuist-rack-image-cache-ber1-store-a -c prewarm`
shows the prewarm set fetched, add `ber1-runner-b01` to `routeHosts` (real rack
hardware, running staging's jobs); then the other hosts, or `"*"`. Routing
needs an operator image with `--rackhost-image-mirror-hosts`, and re-pushes the
launchd config of the hosts added, and only theirs, through the drift loop.
`tart_kubelet_image_mirror_probe_total{result}` and
`tart_kubelet_image_pull_seconds{source}` show what the hosts did; the
`upstream` and `mirror` pull times on the same hosts are the before and after.
Taking a host out of `routeHosts` is its rollback. `mise run rack:fleet-test` checks
that every cache and cache gateway is a storage node of the site at its
RackLinuxHost's address.

## Production

The rack's env is its site definition's `kubernetes.namespace`
(`infra/rack-switch-fleet/sites/ber1.json`): `tuist-staging` puts it in
staging, `tuist` in production (`mise run rack:fleet env`). The Omada controller,
the rack switch controller and the edge DaemonSet (`omada-deployment.yml`), the
switches' and power devices' objects (the Rack Switches workflow), the install
stick, the card passwords and the smoke run follow it. The tuist chart's
inventory does not: the hosts, the `ber1` runner pool, the `ber1-runners` Kura
region and the rack's telemetry and cache gateway live in the env's values
files, and `fleet_check_env` (in `mise run rack:fleet-test`) fails when an env
other than the site's declares the rack's hosts or pools, or when the
controller's vault, address or tailnet name belong to another env.

Moving the rack is two pull requests. The first is inert while the rack is in
staging: production's Omada values (its tailnet name is `omada-production`,
since both controllers run during the move), and the ACL grants
`tag:tuist-k8s-production` has for the rack. The second, the cutover, moves the
inventory from the staging values to the production ones, has production's
egress proxies accept the edges' subnet routes, and points `ber1.json` at
production.
Production's Cilium already excludes `cilium.io/no-schedule=true`
(`infra/k8s/mgmt/bootstrap/cilium-values.yaml`); the operator refuses to join a
rack node until it does.

Every step below says whether it needs someone at the rack (hands-on) or not
(remote). Writes to production go through a JIT elevation (`/elevate
production`); staging is writable. The commands use

```
S="--context kube-staging.tuist.dev"; P="--context tuist-k8s-production"
EDGE_A=44312e80-1dc6-11f1-853e-8f903547d200
EDGE_B=04450c00-63f4-11f1-81f4-3582298d5c00
STORE_A=3a898800-6402-11f1-ab1d-b1bd5a0f6400
```

### Before the move

1. **Merge the first pull request and paste the ACL** (remote). Paste
   `infra/tailscale/acls.json` into the admin console's Access controls.

2. **Copy the rack's 1Password items** (remote) from `tuist-k8s-staging` to
   `tuist-k8s-production`, byte for byte, with 1Password's own copy to another
   vault: each is something the hardware already holds.
   - `BER1_FLEET_SSH`: the minis' key and sudo password, which MDM installed,
     and the key every rack Linux install authorizes.
   - `BER1_RACK_CARD_ROOT`: the PDU and transfer switch cards' passwords are
     derived from it, and the cards hold the ones staging set.
   - `ber1 switch device account`: the login adoption put on every switch.
   - `TAILSCALE_RACK_NODES`: the OAuth client that mints the rack nodes' join
     keys. Its tags are the rack's, not an env's, so the same client serves.
   - `AMT_PROVISIONING_CERT`: what AMT was activated with.

   Check each field matches, for example
   `cmp <(op read op://tuist-k8s-staging/BER1_RACK_CARD_ROOT/key) <(op read op://tuist-k8s-production/BER1_RACK_CARD_ROOT/key)`.
   The Omada admin login and its Open API client are made in step 3, and the
   console passwords (`<host> console`) are minted again by the installs.

3. **Stand up production's Omada controller** (remote). Dispatch
   `omada-deployment.yml` with `environment: production`, which installs the
   controller alone, as `omada-production` on the tailnet. Its tailnet IP is in
   `tailscale status | grep omada-production` (`100.91.73.50`, done on
   2026-10-09). This uses TP-Link's Controller Migration
   ([how to migrate an Omada controller](https://www.omadanetworks.com/us/document/13126/)),
   which takes only a backup of the same Major.Minor.Patch, so both
   controllers run the chart's pinned `6.3.0.45`.
   - In the staging controller (`https://omada.taild6d7bb.ts.net:8043`),
     Global View, Settings, Migration, Controller Migration, Start Export:
     every Backup Contents box, 7 days, Export to Local File. Leave it at the
     next step, Migrate Controller, until step 7.
   - In production's first-boot wizard
     (`https://omada-production.taild6d7bb.ts.net:8043`), Create a Local
     Account (not a TP-Link ID, which binds the controller to TP-Link's
     cloud) and save it in 1Password's Infrastructure vault: the import does
     not carry the controller's own logins over, so this account is
     production's. Finish the wizard, then Global View, Settings, Migration,
     Controller Migration, Start Import with the exported file. Production
     then knows the site, the device account and the three switches, shown
     disconnected.
   - The import does carry staging's Open API client, so `omada production
     open api` is a byte-for-byte copy of `omada staging open api` in
     `tuist-k8s-production`.
   - The import also carries staging's address for the switches to connect
     back to. From the cutover branch, `mise run rack:omada controller` sets
     it to production's, and `mise run rack:omada devices` lists the three
     switches.

   A controller without the backup sees each switch as managed by another
   controller and has to adopt it afresh, which needs it forgotten in staging
   first, and forgetting a switch its controller still manages factory-resets
   it: ToR A carries the rack's uplinks.

4. **Finish the cutover branch** (remote): set `management.controller.address`
   in `ber1.json` to the production controller's tailnet IP, run
   `mise run rack:fleet render` (it renders option 138 into
   `infra/helm/rack-edge/sites/ber1/dnsmasq.conf`) and `mise run rack:fleet-test`,
   which refuses the empty address the branch carries until then. While there,
   record the boot MACs staging learned, so production publishes those hosts'
   installs without waiting for them to announce:
   `kubectl $S -n tuist-staging get rlh -o custom-columns=HOST:.spec.hostname,BOOTMAC:.status.bootMAC`,
   as `bootMAC` on `ber1-edge-b` and `ber1-store-a` in
   `values-managed-production.yaml`.

5. **Copy the edges' VRRP password** (remote) into production's `omada`
   namespace, which step 3 created, so the production edge and one still
   running staging's pod accept each other's adverts instead of both holding
   the addresses. The Helm labels and annotations come along, so the rack-edge
   release adopts it and keeps the password:

   ```
   kubectl $S -n omada get secret rack-edge-ber1-vrrp -o json |
     jq '{apiVersion, kind, type, data, metadata: {name: .metadata.name, labels: .metadata.labels, annotations: .metadata.annotations}}' > vrrp.json
   kubectl $P -n omada apply -f vrrp.json && rm vrrp.json
   ```

### Out of staging

6. **Tear down the rack's Kura cache in staging** (remote). Turn the
   `runner_site_cache` flag off for every account at
   `https://staging.tuist.dev/ops/flags`, and wait until staging has no
   KuraInstance on the storage node:

   ```
   kubectl $S -n kura get kurainstances -o json |
     jq -r '.items[] | select(tostring | test("rack-storage-ber1")) | .metadata.name'
   ```

   Until that prints nothing, the `ber1-runners` region has to stay in
   staging's `TUIST_KURA_AVAILABLE_REGIONS`: a region taken out of the list is
   no longer reconciled, and its instances and server rows are stranded.

7. **Move the switches to production's controller** (remote; be at home in
   case a switch has to be reached by its console). Stop staging's rack switch
   controller so it reports nothing and writes nothing meanwhile:
   `kubectl $S -n omada scale deployment rack-switch-controller --replicas=0`.
   Check the path first: the switches reach the controller through the edge
   holding `192.168.0.10`, so from it
   `nc -z 100.91.73.50 29811` through `29817` should all answer. Then, in
   staging's Controller Migration from step 3 (Start Export, Skip), click
   Confirm, enter production's controller tailnet IP in Controller IP/Inform
   URL (an address: the switches resolve no tailnet names), and Migrate
   Devices. The controller warns that it may push each switch its full
   configuration and drop it briefly. Done on 2026-10-09 with all three at
   once: production showed them adopting, configuring, then connected within
   90 seconds, and the rack kept every node Ready. One at a time limits a
   blip to half the rack, for when it carries jobs. Do not click Forget
   Devices in staging; its controller is uninstalled in step 17. If a switch
   does not come over, `mise run rack:omada inform <device>` from the cutover
   branch tells it the new controller directly.

8. **Retire the rack from staging** (remote), in this order. First delete its
   objects while staging still runs the deploy from `main`: the operator's
   rack controllers are switched on by the same values the cutover removes,
   and an object deleted after they are gone keeps its finalizer for good.
   Helm keeps the RackHosts and RackLinuxHosts, so they are deleted by hand,
   and the switches' and power devices' objects with them, whose finalizers log
   the controller out of each card:

   ```
   kubectl $S -n tuist-staging delete rh ber1-runner-b01 ber1-runner-b02 ber1-runner-b03
   kubectl $S -n tuist-staging delete rlh $STORE_A $EDGE_B $EDGE_A
   kubectl $S -n tuist-staging delete -f infra/rack-switch-fleet/k8s/ber1/
   ```

   The finalizers are done when these list nothing:

   ```
   kubectl $S -n tuist-staging get rh,rlh,rackswitch,rackpdu,rackats
   kubectl $S get nodes -l node.cluster.x-k8s.io/instance-type=rack
   kubectl $S get nodes -l tuist.dev/fleet=tuist-tuist-rack-fleet
   ```

   A RackLinuxHost shows `Deprovisioning` while its Machine stops the kubelet
   and removes the Node, then deletes its tailnet device and its console key.
   The boxes keep running their installs, off the tailnet: the switches keep
   forwarding, the minis keep their addresses, and nothing in the rack reaches
   either cluster until step 12. A staging deploy from `main` now would declare
   them again, and a merge touching `infra/rack-switch-fleet` would apply the
   switches' objects to staging again; delete what reappears.

   Then dispatch a staging deploy of the cutover branch's commit:

   ```
   gh workflow run server-deployment.yml -f environment=staging -f commit_sha=<cutover commit>
   ```

   It drops the rack's inventory and the `ber1` pool (so only production will
   answer `tuist-ber1-smoke`), the region, `alloy-rack`, the cache gateway and
   the egress proxies' routes from staging.

9. **Delete the minis' tailnet devices** (remote) in the admin console:
   `ber1-runner-b01` to `b03`, tagged `tag:tuist-macmini-staging`. A mini is a
   standard device that outlives its Machine, and bootstrap's `tailscale up`
   uses its key only when it has to log in, so a mini still logged in would
   keep its staging tag under production. Once its device is gone, the next
   bootstrap joins it as `tag:tuist-macmini-production`.

10. **Copy the hosts' AMT Secrets** (remote) from `tuist-staging` to `tuist`.
    AMT keeps the admin password staging generated, and production can drive
    a host's AMT only with it:

    ```
    for uuid in $EDGE_A $EDGE_B $STORE_A; do
      kubectl $S -n tuist-staging get secret "$uuid-amt" -o json |
        jq '{apiVersion, kind, type, data, metadata: {name: .metadata.name}}' > amt.json
      kubectl $P -n tuist apply -f amt.json
    done; rm amt.json
    ```

### Into production

11. **Merge the cutover** (remote), only once production deploys no longer wait
    on rack nodes (the change that keeps them independent of the rack's
    health merges first): from here on the rack's Linux nodes are
    production's, and a Helm wait on a DaemonSet with pods on dark nodes
    would roll every production deploy back. Production's deploy declares
    the hosts, the pool, the region, `alloy-rack` and the cache gateway;
    `omada-deployment.yml` deploys the rack switch controller, watching `tuist`,
    and the edge DaemonSet, which has no node yet; the Rack Switches workflow
    applies the objects to `tuist`. Paste the ACL again: the cutover drops
    staging's rack grants. `kubectl $P -n tuist get rlh` shows each host
    waiting: no device, and for the edges, no other edge to serve a netboot.
    Production's egress proxies now accept the tailnet's subnet routes,
    staging's Connector's `10.128.0.0/12` among them, which is production's
    Service CIDR too: once they have rolled, check that the Scaleway minis'
    jobs still start and that
    `kubectl $P -n tailscale-operator exec macmini-egress-0 -- ip route show table 52`
    lists the routes while the proxies keep answering.

12. **Reinstall `ber1-edge-a` from a stick** (hands-on). On `main`, the env
    is production:

    ```
    mise run rack:write-install-usb /dev/disk4 --host ber1-edge-a
    ```

    Swap it for the edge's install stick, boot it (F7, the stick), and put the
    install stick back once the node is up:

    ```
    kubectl $P -n tuist get rlh $EDGE_A -w
    kubectl $P get node ber1-edge-a
    kubectl $P -n omada get pods -o wide        # rack-edge-ber1 on it
    ```

    With the edge up, the switches' path and their DHCP, the machines' routes
    and the boot server are back, from production.

13. **Reinstall the rest** (hands-on, or remote through the edge). With
    `ber1-edge-a` serving, the operator publishes `ber1-edge-b`'s and
    `ber1-store-a`'s installs, since neither has a tailnet device. It does not
    reboot them into the installs: a host is rebooted over SSH on its tailnet
    address, and through AMT only once production has read the host's AMT,
    which it does over SSH too. So boot each one's install stick: at the rack
    (F7, the stick), or from a laptop through the edge to the old install and
    its firmware's stick entry:

    ```
    ssh -J tuist@ber1-edge-a tuist@10.255.255.2   # ber1-edge-b, on the VRRP link
    ssh -J tuist@ber1-edge-a tuist@10.10.0.11     # ber1-store-a, on the machines segment
    sudo efibootmgr                               # the "tuist install stick" entry, or the USB disk
    sudo efibootmgr -n <entry> && sudo reboot
    ```

    The stick asks `ber1-edge-a`'s boot server for its install and runs it. A
    host whose boot MAC was not recorded in step 4 announces itself first
    (`kubectl $P -n tuist get rlc -o wide`), and the operator publishes once it
    has.

14. **The minis bootstrap** (remote) as soon as an edge advertises their
    addresses again: the production operator dials each through the edges,
    checks its serial and installs everything, Tailscale under
    `tag:tuist-macmini-production` included.

    ```
    kubectl $P -n tuist get rh,rasm
    kubectl $P get nodes -l tuist.dev/fleet=tuist-tuist-rack-fleet
    ```

15. **Turn the rack's cache on in production** (remote): the
    `runner_site_cache` flag for the accounts that should have it, at
    `https://tuist.dev/ops/flags`, and wait for their KuraInstance on
    `ber1-store-a` (`kubectl $P -n kura get kurainstances`).

16. **Run the smoke** (remote): `gh workflow run ber1-smoke.yml`. It talks to
    the server of the env the rack is in.

17. **Clean up staging** (remote), once the smoke passes:
    `helm --kube-context kube-staging.tuist.dev -n omada uninstall rack-edge rack-switch-controller omada`, the
    controller's volumes (`kubectl $S -n omada delete pvc --all`), the leftover
    candidates (`kubectl $S -n tuist-staging delete rlc --all`), the hosts' AMT
    Secrets in `tuist-staging`, and the staging copies of the 1Password items
    in step 2.

Until step 8, going back is redeploying staging from `main` and turning its
flag on again. After it, the hosts are reinstalled into whichever env takes
them.

## Customer jobs

`rackFleet.runners` renders the runner catalog a second time onto the rack:
for each Xcode, a pool named `<release>-runner-pool-macos-<site>-<xcode>`
(plus the shapes `rackFleet.runners.shapes` names) that selects the rack
fleet, with the same image as the rented fleet's pool for that Xcode. The
server learns them through `TUIST_RUNNERS_SITE_POOLS`. An account on the
`runner_site` flag (`https://tuist.dev/ops/flags`) has its macOS profiles
(`tuist-macos` and the rest) routed to the rack's pool for the profile's Xcode
and shape, and to the rented fleet when the rack has none. While the rack is
up, the account's jobs run only there: they queue for as long as the rack is
busy, and no rented runner is minted for them, so none can pick one up. GitHub
hands a queued job to any idle runner of the org that carries its labels, and
a rack runner carries the same label as a rented one, so keeping rented
runners from being minted is what keeps the jobs on the rack.

### Several sites

A job is bound to its Xcode and shape, not to a site. The rack's pools are
rendered once, named after `rackFleet.site` (`…-ber1-<xcode>`), and select the
rack fleet. A second site (`rackFleet.sites.<site>`, e.g. `larch`) joins that
fleet when its `runners.enabled` is true: its minis' Nodes then carry the rack
fleet's `tuist.dev/fleet` instead of their own `<rack fleet>-<site>`, so every
rack pool spans both sites and the runners-controller apportions all their
guest slots together. Until then the site's minis get no runners.

- **Where a job runs.** Whichever site's runner claims it first. The claim
  reads the claiming Node's `node.cluster.x-k8s.io/rack-site` label and hands
  out that site's Kura runner cache (`server/lib/tuist/runners/AGENTS.md`). A
  runner passes over a job whose account's runner cache is warm at the other
  site for the job's first 60 seconds, so the warm site gets it first while it
  has an idle runner.
- **A dark site.** Its minis go NotReady, drop out of the autoscaler's budget,
  and the runners-controller retires their idle runners after two minutes
  (`infra/runners-controller/AGENTS.md`), so the pools' queued jobs run at the
  sites still up. Nothing moves jobs between sites. Jobs already running there
  are lost with the site.
- **One guest per pool.** A RunnerPool has one guest size, so a site whose
  runners are on runs `rackFleet.runners` as is. The render fails when
  `rackFleet.sites.<site>.runners` sets `guestShapes`, `shapes`,
  `stackedImages`, `autoscaling`, `rollout` or `xcodeOverrides` differently,
  when `rackFleet.runners` is off, or when the site names its own `nodeFleet`.
  Different hardware at a site needs a different design, not a per-site
  override.
- **Pinned pools.** An explicit `runnersFleet.pools` entry with a `site` runs
  only on that site's minis (`spec.site`), which is how the `ber1` smoke pool
  keeps testing ber1.
- **Pool names.** They keep ber1 in them. Renaming them is part of turning a
  second site's runners on, with the queued jobs on the old names moved in the
  same deploy.

Staging and canary rent no macOS runner hosts: their only macOS runners are
the rack hosts production lends them (b01 and b02, "Lending a host to
another env" below), and `runner_site` is on for every account there
(`Tuist.FeatureFlags.runner_site_enabled?/1`). Their `runnersFleet.hostCount`
is 0, so the chart renders no rented macOS pools and sets
`TUIST_RUNNERS_RENTED_MACOS_FLEET=false`: dispatch sends every macOS profile
to the rack's pool, and nothing spills over. A job waits while its env's host
is down, cordoned or busy. Their Scaleway minis only run the xcresult
processor (`macosFleet`).

A catalog shape can run a bigger guest on the rack than on the rented fleet
(`rackFleet.runners.guestShapes`): in production the 6 vCPU / 14 GB shape runs
8 vCPU / 24 GB guests and the 12 vCPU / 28 GB shape 16 vCPU / 48 GB, which the
hosts' 16 CPU / 48 GB sizing fits two and one of. The pool keeps the shape's
name, so a job is still recorded, billed and counted against the account's
concurrency limit at the shape its profile names, and one that spills over to
the rented fleet runs at that shape.

The rack's pools (one per Xcode and shape, plus the `ber1` smoke pool) share
its guest slots through the runners-controller's fleet allocator. When one of
them has queued jobs whose Pods the scheduler refuses for lack of resources,
the others give up idle warm runners straight away instead of after their
scale-down cooldown (`infra/runners-controller/AGENTS.md`, "Cross-pool
preemption").

The rented fleet is the rack's backup while it is down (`Tuist.Runners.Sites`):

- **No capacity:** no Node of the rack fleet is Ready, schedulable and large
  enough for the pool's guest. Power, the uplink and a drain all show up this
  way within the node-monitor grace period.
- **Stalled:** a pool's oldest queued job has waited 10 minutes and nothing at
  the rack held or took a claim in that time; 30 minutes while no eligible
  Node holds the pool's golden image, so a cold pull is not an outage.

While a pool is down, dispatch routes new jobs to the rented pool for the same
Xcode and shape, and `SiteSpilloverWorker` moves its queued ones there every
minute. A cluster the server cannot read leaves the rack up. An env that
rents no macOS fleet (staging, canary) has no backup, so neither happens there.

The flag also gives the account a node in the site's runner-cache region
(`ber1-runners`, `larch-runners`), as `runner_site_cache` does. With the
flag off for everyone, the rack's pools idle at their floors and nothing a
customer runs lands on them.

The rack's pools autoscale against the rack's own guest slots: the
runners-controller apportions a fleet's capacity among the autoscaling pools
that share its `fleetSelector`, so the rack and the rented fleet are separate
budgets. That is also why the `ber1` smoke pool autoscales from zero instead
of holding a fixed count: the allocator counts only autoscaling pools, and a
fixed count would hold slots it believes free.

A Tart guest cannot be newer than its host. Every catalog image is a macOS 26
guest and the rack's hosts run macOS 27, so every Xcode runs there; a catalog
entry on a newer guest needs the hosts updated first.

### More than one site

One rack fleet holds every site's minis: one operator, one set of credentials
and one CAPI fleet, whose Machines are `<rackFleet.name>-<host>` at every site.
`rackFleet.site` (ber1) is the default site, and every other site is a key of
`rackFleet.sites` (larch). A host at such a site sets `site: <site>` and takes
that site's block:

- **Its Node's fleet.** The host's Node carries `tuist.dev/fleet:
  <rackFleet.name>-<site>` (`RackHost.spec.nodeFleet`, overridable as the
  site's `nodeFleet`), not the default site's fleet. Runner pools select Nodes
  by that label alone, so without it ber1's pools would place runners on larch
  minis. The Machine keeps the operator's fleet, its name and its credentials,
  as for any `nodeFleet`. A lent host (`lendTo`) keeps the borrower's fleet.
- **Its SSH ingress** is the site's `sshIngressAllowCIDRs`, the site's own
  edges. It never falls back to the default site's, and the chart refuses a
  host at a site whose block has none.
- **Its pools.** The site's `runners` is a runner catalog of its own, with the
  same keys as `rackFleet.runners`. It renders
  `<release>-runner-pool-macos-<site>-<xcode>` pools that select the site's
  fleet, so each site's pools share only that site's guest slots, and
  `TUIST_RUNNERS_SITE_POOLS` lists them as `<pool>=<site>:macos` after the
  default site's.
- **Its VMs' cache gateways** (`vmCacheGatewayCIDRs`) join the operator's
  fleet-wide `--rackhost-vm-cache-gateway-cidrs`: the pf pass is the same on
  every rack host, and a host has no route to another site's gateway.

A host naming a site that is neither `rackFleet.site` nor a key of
`rackFleet.sites` fails the render. Keep a site's `runners` disabled until
its minis are declared and its uplink is up. The rack fleet's
MachineHealthCheck still spans every site, so while one site is dark its
`unhealthyRange` also holds back remediation of a single mini at the other.

### Lending a host to another env

A rack host can run another env's runners while it stays production's.
Production keeps the site: the host's Machine, power, MDM, OS updates and
bootstrap from a reinstall. The borrowing env's operator runs the host's runner
runtime (tart-kubelet and its config, the VM egress firewall, cache volumes,
Tailscale, the Node) from its own fleet config and rolls it with its own
deploys, as it does its rented minis, so a rack runtime change reaches a rack
host in staging first. The two operators hand the host over through a
RackHostLease in the borrowing cluster, and never push to it at the same time.
How it works is "A host lent to another env" in
[`infra/cluster-api-provider-tuist`](../cluster-api-provider-tuist/AGENTS.md).

**Once per borrowing env** (remote, by a person: it writes a credential into
1Password). The borrowing env's values set `rackFleet.borrow.enabled` (staging
and canary do), which renders the `rack-lender` identity production's operator
writes that env's leases with. With `C` the borrowing cluster's context, `N`
its namespace and `E` its name. Every variable is quoted, since zsh does not
word-split an unquoted one, and each step runs only if the one before it
succeeded:

```
C=kube-staging.tuist.dev; N=tuist-staging; E=STAGING
umask 077; d="$(mktemp -d)"
kubectl --context "$C" -n "$N" get secret tuist-tuist-rack-lender-token -o json >"$d/s.json" && server="$(kubectl --context "$C" -n kube-public get cm cluster-info -o jsonpath='{.data.kubeconfig}' | yq -r '.clusters[0].cluster.server')" && test -n "$server" && test -n "$(jq -r .data.token "$d/s.json")" && printf 'apiVersion: v1\nkind: Config\ncurrent-context: rack-lender\nclusters:\n  - name: cluster\n    cluster:\n      server: %s\n      certificate-authority-data: %s\ncontexts:\n  - name: rack-lender\n    context:\n      cluster: cluster\n      user: rack-lender\n      namespace: %s\nusers:\n  - name: rack-lender\n    user:\n      token: %s\n' "$server" "$(jq -r '.data["ca.crt"]' "$d/s.json")" "$N" "$(jq -r .data.token "$d/s.json" | base64 -d)" >"$d/kubeconfig" && KUBECONFIG="$d/kubeconfig" kubectl auth whoami && jq -n --rawfile k "$d/kubeconfig" --arg t "RACK_BORROWER_${E}_KUBECONFIG" '{title: $t, category: "API_CREDENTIAL", fields: [{id: "kubeconfig", label: "kubeconfig", type: "CONCEALED", value: $k}]}' >"$d/item.json" && op item create --vault tuist-k8s-production --template "$d/item.json"; rm -rf "$d"
```

`kubectl auth whoami` must print
`system:serviceaccount:<N>:tuist-tuist-rack-lender` before anything is stored.
To replace an item that exists already, run the same with `op item edit <item>
--vault tuist-k8s-production --template "$d/item.json"` in place of `op item
create`.

Staging's and canary's entries in `rackFleet.borrowers` in
values-managed-production.yaml name their items already; a new borrowing env
needs an entry with its `kubeconfigItem`, and a production deploy. Rotating it
is deleting the token Secret in the borrowing env (its next deploy makes a new
one), storing the new kubeconfig under the same item, and waiting for ESO's
five-minute refresh.

**Lend a host** (remote). Only a host production has bootstrapped: production
does not bootstrap a host while it lends it, so a new one joins production
first.

1. In the borrowing env's values, add the host to `rackFleet.borrow.hosts` and
   deploy. A host not on that list is refused.
2. In production's `rackFleet.hosts`, set the host's `lendTo` to the borrowing
   env and deploy.
3. Watch it: `kubectl get rh` in production shows the lease's state (Offered,
   Draining while production's jobs on the host finish, then Lent), and
   `kubectl $S get rhl` in the borrowing env shows the borrower's (Accepted,
   then Active once its runtime is on the host, with the Node it registers as
   `<rackFleet.name>-<host>`).

**Return it**: drop `lendTo` in production and deploy. The borrower drains its
Node, so its running jobs finish, and releases the host; production then takes
the runtime back and bootstraps its own (Returning, then Reclaimed). It also
deletes the tailnet devices the host ran as; if its tailnet API cannot, a
`TailnetCleanupFailed` event names them for the Tailscale admin console.
Remove the host from `rackFleet.borrow.hosts` afterwards. A borrower that is
gone cannot release the host: `kubectl annotate rh <host> tuist.dev/reclaim-runtime=true`
in production takes it back without it (whatever the borrower ran there is
lost), and remove the annotation once the host is back.

**Rotate the borrower's key**: delete `rack-lease-<host>-ssh` in the borrowing
env. Its operator mints a new key and waits for production to authorize it,
which takes a minute; the host keeps running meanwhile.

**Power-cycle or update a lent host** from the borrowing env, which holds no
credential for either: annotate its lease, and production does it.

```
kubectl $S annotate rhl ber1-runner-b01 tuist.dev/power-cycle=wedged
kubectl $S annotate rhl ber1-runner-b01 tuist.dev/os-update=26.7
```

An update drains the borrower's Node first, so its jobs finish, and the
borrower pushes its runtime again afterwards. Follow it in the lease's
`SiteRequest` condition, `status.siteRequest` and `spec.siteRequestResult`. A
reinstall is not a site request: return the host, reinstall it in production,
and lend it again.

#### Moving ber1-runner-b01 and b02 off the manual lend

b01 (staging) and b02 (canary) were lent the earlier way: production pushed its
own runtime with a kubeconfig the borrowing env issued (`nodeCluster`,
`nodeFleet`, `rackFleet.joiningNodes`). The change that brought `lendTo` also
switches them, and each env takes its host over as soon as it can:

- **canary** on the merge's own cascade. Canary deploys first, with its lease
  controller and `rack-lender` identity, and its runners acceptance gate still
  runs on b02's old Node. Production then deploys with `lendTo: canary`, and
  the lend starts once `RACK_BORROWER_CANARY_KUBECONFIG` exists (above), which a
  person stores after that canary deploy; ESO picks it up within five minutes.
- **staging** once it has run the change: a staging deploy of the branch before
  the merge (with the operator image built from it, `capi_image_tag`) lets
  `RACK_BORROWER_STAGING_KUBECONFIG` be stored ahead, and production lends b01
  as soon as it deploys.

Until its item exists and its env runs the change, a host stays exactly as it
is: production pushes nothing to it, and its old Node keeps running jobs. The
borrower drains that Node (`tuist-tuist-rack-fleet-<host>`) only once it has
reached the host with its own key, which needs the staging and canary grants in
`infra/tailscale/acls.json` pasted, then takes the host over and deletes it.
Each env's rack jobs wait out that drain and the push, a few minutes.

Afterwards, in a later change: drop canary's `joiningNodes`, staging's leftover
`tart-kubelet-tuist-tuist-rack-fleet-ber1-runner-b01` identity, the
`BER1_RUNNER_B0{1,2}_*_KUBECONFIG` items, and the leftover staging
RackAppleSiliconMachines and Machines for b01..b03 (step 17 of "Into
production"); then `nodeCluster`, `nodeFleet` and `rackFleet.joiningNodes` go
from the chart and the operator.

Any account's jobs can run on a rack host, since staging and canary route all
of theirs there. A runner VM is isolated from the rack's private networks, the
host's own listeners, its sibling guests and the tailnet: the VM egress
firewall in `infra/macos-host-bootstrap` filters guest traffic before the host
translates it, and `infra/tailscale/acls.json` has no catch-all grant. The
`vm_isolation` job in `.github/workflows/runners-staging-smoke.yml` probes it
from a VM on the host it lands on (`environment` picks staging's or canary's
runners); run it on a host before lending it to an env, and after a change to
either. The one rack target a guest reaches on purpose is the site's Kura
gateway (`rackFleet.vmCacheGatewayCIDRs`). The probe's cluster DNS check fails
on a host lent by hand, which has no route to the borrowing cluster's Service
CIDR.

## Tests

`mise run rack:nodes-test` renders the stick's seed against fake `op` and
`curl`; it runs in the Rack Switches workflow. The boot server, the netboot
seed, the iPXE script and the install lifecycle are Go tests in the operator
(`internal/rackboot`, `internal/rackinstall`,
`controllers/linux/racklinuxhost_install_test.go`). `mise -C infra run
helm:rack-independence` checks that deploys do not wait on rack nodes (see
"Deploys and the rack's health"); it runs in the Helm workflow.

### Kura volume encryption

The independently deployed `rack-nodes` release owns `kura-volumes-csi-rack`,
selected by `kuraVolumesCSI.rackPools`. The main waited release owns the CSI
identity, RBAC and StorageClasses, and excludes those pools from its own plugin.
Both plugins use the same projected identity and mount/key contract; their
DaemonSets never overlap. An offline rack cannot hold the main Helm upgrade.
Set the pinned CSI image on both releases. Keep them installed while claims exist.

Fresh storage installs create `kura-volumes` directly through curtin, including
resident-installer layouts. Existing hosts require an explicit spare-host
migration and reinstall; neither a deploy nor Machine reconciliation converts
populated disks. Verify the VG and plugin before enrolling `ber1-runners` in
`kuraVolumesCSI.lvmRegions`. Enrollment makes encryption the default. Account
flags cannot move an unenrolled rack onto loop files. Enrollment renders at
least two replicas so the current one-replica rack region gets a standby and
complete backfill before its original claim is replaced. Both replicas need
prepared capacity; an in-place reinstall of the only storage host is an outage.
Reserve the 128 GiB data LV for images/system/auxiliary volumes (including any
image cache); grow it before enabling auxiliary claims that exceed that budget.
See [the migration runbook](../kura-volumes-csi/lvm-rollout.md).
