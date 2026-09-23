# Rack nodes

How the BER1 rack's x86 Linux machines (the MS-01s: edge, services and storage)
become cluster nodes. A host netboots from the rack's edge node, installs
Ubuntu, joins the tailnet on first boot, and the cluster's operator joins it as a
node and keeps it converged. Nobody touches it: a box with an empty disk
netboots on its own, and a running one is reinstalled with an annotation. The
edge node runs the boot server, so it is the one host installed from a stick.

## The pieces

- **Inventory** is `rackLinuxFleet.hosts` in the env's tuist chart values,
  rendered as one `RackLinuxHost` per box (pool `<pool>-<role>`, role, site,
  tailnet tags, and `bootMAC`, the MAC of the NIC it netboots from: the
  MS-01's i226-LM, on the management switch). Each role present gets a
  MachineDeployment of `RackLinuxMachine`s with that role's
  `rackLinuxFleet.roles.<role>` labels and taints. The node name, the hostname
  and the tailnet name are all the host's name.
- **The operator** (`infra/cluster-api-provider-tuist`, `controllers/linux`)
  publishes each host's install, finds the host on the tailnet and joins it.
  See "Rack-owned Linux hosts" in its AGENTS.md.
- **The boot server** (`rackLinuxFleet.boot`, a DaemonSet in the tuist chart
  running `files/rack-boot.sh` on the edge node) serves what the operator
  publishes, on the site's provisioning address.
- **The edge node's DHCP** (`management.edge.netboot` in the site definition,
  rendered into the rack-edge chart) points UEFI firmware on the management
  switch at the boot server. See `infra/rack-switch-fleet/AGENTS.md`.
- **The seed** is rendered by `internal/rackinstall` in the operator, for PXE
  and for the stick alike.

A host that is declared but not installed does not hold up a deploy: the chart
renders each rack MachineDeployment at its live replicas, and the host
controller scales it up as the pool's hosts come onto the tailnet.

## Netboot

For a host with a `bootMAC` that is not on the tailnet, or that carries
`tuist.dev/reinstall=true`, the host controller mints a join key and writes three
files under the MAC to the `<fleet>-boot` Secret: the autoinstall `user-data`
and `meta-data`, and a GRUB menu. The boot server mirrors the Secret within a
minute or two. The chain a netbooting host goes through:

1. The firmware's PXE asks the edge node's dnsmasq for an address and gets one
   in the provisioning range, with `bootx64.efi` from the provisioning address.
2. The shim (the installer ISO's own, signed by Microsoft) loads Ubuntu's signed
   network GRUB, which reads `grub.cfg-01-<mac>`, or `grub.cfg`, which looks for
   `hosts/<mac>.cfg`. A host with no install published finds neither and goes
   back to its firmware's next boot entry.
3. GRUB loads the installer's kernel and initrd over TFTP; the kernel downloads
   the ISO into memory over HTTP (`url=`), keeps its DHCP on the NIC that
   netbooted (`BOOTIF`), and reads the seed from `/hosts/<mac>/`.
4. The install is the same as a stick's: Ubuntu with network configuration for
   the SFP+ uplinks only, the fleet key, and a first-boot unit that joins the
   tailnet with the single-use key.
5. Once a tailnet device that is not the one the install replaced shows up, the
   host controller withdraws the install, so the key stops being served, and
   removes the annotation.

The chain is signed end to end, so it boots with Secure Boot on: Microsoft's
signature on the shim, Canonical's on GRUB and the kernel.

The installer can get its default route from its provisioning lease, through
the edge node, as well as from the uplinks' DHCP, so the edge node translates the
provisioning range onto its uplinks as well as into the tailnet.

**A fresh box** installs itself when powered on with its disk empty: the disk has
no boot entry, so the firmware falls through to PXE. A disk that already boots
something is booted first; pick the i226-LM's network entry from the boot menu
(F7 on the MS-01) once.

**Reinstalling a running host:**

```
kubectl annotate racklinuxhost ber1-svc tuist.dev/reinstall=true
```

People annotate through the kubectl gateway's `tuist-fleet-unwedge` role
(`infra/helm/pomerium`), standing in staging and on a write elevation in
production.

The operator publishes the install, waits two minutes for the boot server to
have it, then sets `BootNext` to the host's PXE entry for its `bootMAC` over SSH
and reboots it. It does this once: a host that comes back on its old install
reports `Installed` False with `ReinstallDidNotBoot` after half an hour, and
removing the annotation and setting it again tries again. The new install
registers a new tailnet device; once it is connected the host controller deletes
the old one and renames the new one to the host's name, and the machine
controller joins the host afresh.

Watch it with:

```
kubectl get racklinuxhost -o wide -w
kubectl describe racklinuxhost ber1-svc
```

**The console password** of each host is in the `<fleet>-console` Secret, under
the host's name, minted with its first netboot install and kept across
reinstalls.

**A published install is a credential.** Its key admits one device with the
host's tags, and anything on the management switch can fetch it from the boot
server until the install has used it. Keys expire after a day, and the operator
publishes a fresh one while the host still needs it.

## The stick

The edge node runs the boot server, so it cannot netboot from it; the operator
never publishes an install for an `edge` host. It is installed from a stick,
and so is any host when the edge node is down:

```
mise run rack:write-install-usb /dev/disk4 --host ber1-edge
mise run rack:write-install-usb --host ber1-edge --output ber1-edge.iso
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
  ports), so the 2.5G ports stay unmanaged for the node's pods: the edge
  node's rack-edge pod owns the switch port;
- the host's hostname and role, the `tuist` account with passwordless sudo and
  a console password, SSH with password authentication off, and the rack's
  fleet key (`BER1_FLEET_SSH`) plus people's keys
  (`rackLinuxFleet.authorizedKeys`, or the stick writer's own);
- a tailnet join key minted from the OAuth client in `TAILSCALE_RACK_NODES`:
  single-use, pre-authorized, not ephemeral, carrying the host's tags. The
  OAuth client never reaches the host. It mints keys for its own tag
  (`tag:tuist-rack-edge`) and the tags it owns (`tag:tuist-rack-node`, for
  every other role).

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
grants `tag:tuist-k8s-staging` for the rack tags, the edge node is reinstalled
from a stick written with `--env production`, and the other hosts are reinstalled
by annotation once it is up. Production's Cilium must exclude
`cilium.io/no-schedule=true` first (`infra/k8s/mgmt/bootstrap/cilium-values.yaml`);
the operator refuses to join the node until it does.

## Tests

`mise run rack:nodes-test` renders the stick's seed against fake `op` and
`curl`, and runs the boot server's script against a fake Secret and ISO
(`tests/boot.bats`); it runs in the Rack Switches workflow. The netboot seed,
the GRUB menu and the install lifecycle are Go tests in the operator
(`internal/rackinstall`, `controllers/linux/racklinuxhost_install_test.go`).
