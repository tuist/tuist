# Rack nodes

How the BER1 rack's x86 Linux machines (the MS-01s: the two edges and the
storage pair) become cluster nodes. A host boots its installer, installs
Ubuntu, joins the tailnet on first boot, and the cluster's operator joins it as
a node and keeps it converged. The installer is the install stick every host
keeps plugged in, which boots with the firmware as it ships, or a netboot from
the rack's edges, which needs the firmware's network stack on. Both run with
Secure Boot on. Either way it installs what the edges' boot server publishes for the host:
a box with an empty disk boots it on its own, and a running one is reinstalled
with an annotation. The edges run the boot server, each serving the other, so
only the first edge of a site is installed from a stick of its own.

## The pieces

- **Inventory** is `rackLinuxFleet.hosts` in the env's tuist chart values,
  rendered as one `RackLinuxHost` per box, named after the machine's SMBIOS UUID:
  its hostname (the node, OS and tailnet name), role, site, and optionally its
  `bootMAC`, the MAC of the NIC it netboots from (the MS-01's i226-LM, on the
  management switch), which otherwise comes from the machine's announcement.
  Its role's `rackLinuxFleet.roles.<role>` gives its tailnet tags, labels and
  taints. The operator keeps a CAPI Machine for each host, which makes it a
  node.
- **The operator** (`infra/cluster-api-provider-tuist`, `controllers/linux`)
  publishes each host's install, finds the host on the tailnet and joins it.
  See "Rack-owned Linux hosts" in its AGENTS.md.
- **The boot server** (`rackLinuxFleet.boot`, a DaemonSet in the tuist chart
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

Its installer takes DHCP on every wired port, asks the boot server for
`hosts/<mac>/user-data` for each of its NICs, and installs the first it gets:
the seed a netboot reads (below). With nothing published it boots a rack
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

- A box with an empty disk boots the stick on its own, with the firmware's
  defaults: Secure Boot on and the network stack off.
- To reinstall a running host, the operator looks for a USB disk whose ISO
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
(`status.hardware`), its AMT is activated
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
   reads the seed from `/hosts/<mac>/`. The boot server hands `user-data`, which
   carries the join key and the host key, only to one of the MACs the host took
   (`status.hardware`), as
   its neighbor table shows the address that asked, and after the first to
   that MAC alone (`status.boot.servedTo`).
4. The install is the same as a stick's: Ubuntu with network configuration for
   the SFP+ uplinks only, the fleet key, the operator's host key in place of
   the ones the package generated (cloud-init told not to replace it), and a
   first-boot unit that joins the tailnet with the single-use key, which lives
   two hours.
5. Once a tailnet device that is not the one the install replaced shows up, the
   host controller withdraws the install, so the key stops being served, and
   removes the annotation.

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

**Racking an MS-01** is its cables and the install stick. Its firmware stays as
it ships: with its disk empty it boots the stick, which installs it once the
host is declared. Netbooting instead needs, once, in Setup: Advanced → Network
Stack Configuration → Network Stack and IPv4 PXE Support enabled; Secure Boot
stays on. Then it netboots whenever its disk does not boot.

**The stick is the permanent route, not a bootstrap crutch.** The MS-01 ships
with its network stack off, and nothing but a person in Setup turns it on:
AMT can override the next boot but not change a Setup setting, and writing the
firmware's Setup variables from the OS means poking an undocumented AMI
variable layout that changes between firmware releases, where a wrong write
can leave the box unbootable, and changing a security setting behind the
person racking it. A stick boots with the firmware's defaults, Secure Boot
included, so a factory box needs no one in Setup: it announces itself,
installs once declared, and is reinstalled through `BootNext` to the stick.
Netboot, with its one Setup visit, is what AMT's recovery of a box that no
longer boots needs; a box without it is recovered by booting its stick.

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
reinstalls.

**A published install is a credential.** Its key admits one device with the
host's tags, and anything on the management switch can fetch it from the boot
server until the install has used it. Keys expire after a day, and the operator
publishes a fresh one while the host still needs it.

## A host's own stick

An edge netboots from the other edge: the operator publishes its install only
while another edge of its site is on the tailnet to serve it. The first edge of
a site has no other edge, so it is installed from a stick, and so is any host
when both edges are down:

```
mise run rack:write-install-usb /dev/disk4 --host ber1-edge-a
mise run rack:write-install-usb --host ber1-edge-a --output ber1-edge-a.iso
```

It needs `op` signed in (it reads the vault `tuist-k8s-<env>`), `xorriso`, and
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

- network configuration for the SFP+ uplinks only (DHCP on the X710's `i40e`
  ports), so the 2.5G ports stay unmanaged for the node's pods: an edge's
  rack-edge pod owns its switch port;
- `blacklist btusb` in `/etc/modprobe.d/tuist-rack.conf`, which the converge
  also keeps: the MS-01's Bluetooth dereferences NULL on a warm boot of the 6.8
  kernel, and the node's `panic_on_oops` turns that into a reboot every 70
  seconds;
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
  none, and the host generates its own;
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

## Roles

`edge` and `services` install with Ubuntu's `direct` layout. `storage` is refused
until its layout is designed: a node that serves cache volumes needs `/boot`, a
capped `/` and a separate XFS `/data` with project quotas, fixed at install time
(see `controllers/linux/linux_cloudinit.go` and the `baremetal:prep-*` tasks for
the shape the rented fleets use).

Every rack Linux node runs the local CNI and carries `cilium.io/no-schedule=true`,
because the rack's networks at home sit inside staging's pod CIDR. A storage node
that serves pods through Services needs the cluster's CNI, which is a
`RackLinuxMachine` change to make once the rack's networks no longer overlap.

## Production

The rack moves to production by moving its inventory: the hosts and
`rackLinuxFleet.boot` go from `values-managed-staging.yaml` to
`values-managed-production.yaml`, the `TAILSCALE_RACK_NODES` item goes to the
`tuist-k8s-production` vault, the ACL grants `tag:tuist-k8s-production` what it
grants `tag:tuist-k8s-staging` for the rack tags, `ber1-edge-a` is reinstalled from
a stick written with `--env production`, and the other hosts, `ber1-edge-b`
included, are reinstalled by annotation once it is up. Production's Cilium must exclude
`cilium.io/no-schedule=true` first (`infra/k8s/mgmt/bootstrap/cilium-values.yaml`);
the operator refuses to join the node until it does.

## Tests

`mise run rack:nodes-test` renders the stick's seed against fake `op` and
`curl`; it runs in the Rack Switches workflow. The boot server, the netboot
seed, the iPXE script and the install lifecycle are Go tests in the operator
(`internal/rackboot`, `internal/rackinstall`,
`controllers/linux/racklinuxhost_install_test.go`).
