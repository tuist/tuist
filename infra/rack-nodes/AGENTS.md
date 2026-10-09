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
   records the generation it installed.

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

**The stick is the MS-01's route, a workaround for its firmware.** The MS-01 ships
with its network stack off, and nothing but a person in Setup turns it on:
AMT can override the next boot but not change a Setup setting, and writing the
firmware's Setup variables from the OS means poking an undocumented AMI
variable layout that changes between firmware releases, where a wrong write
can leave the box unbootable, and changing a security setting behind the
person racking it. A stick boots with the firmware's defaults, Secure Boot
included, so a factory box needs no one in Setup: it announces itself,
installs once declared, and is reinstalled through `BootNext` to the stick.
Netboot, with its one Setup visit, is what AMT's recovery of a box that no
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

`edge` and `services` install with Ubuntu's `direct` layout. `storage` lays out
its largest disk for cache volumes, the shape the rented cache fleets take
(`controllers/linux/linux_cloudinit.go`, `internal/ovh`, `internal/scaleway`):

| Partition | Size | Filesystem | Mount |
|---|---|---|---|
| 1 | 1 GiB | FAT32 | `/boot/efi` |
| 2 | 2 GiB | ext4 | `/boot` |
| 3 | 64 GiB | ext4 | `/` |
| 4 | the rest | XFS, `prjquota` | `/data` |

A cache volume is a local-path directory with an XFS project quota, and XFS
takes `prjquota` only when it mounts, so `/data` carries it in fstab from the
install. The install also bind-mounts `/data/kubelet` onto `/var/lib/kubelet`,
`/data/containerd` onto `/var/lib/containerd` and `/data/local-path-provisioner`
onto `/opt/local-path-provisioner`, so images and volumes land on `/data` from
the node's first boot. `/` stays ext4 because a stick finds the install it made
by mounting the ext4 partitions. Changing the layout is a reinstall.

Every rack Linux node runs the local CNI and carries `cilium.io/no-schedule=true`,
because the rack's networks at home sit inside the cluster's pod CIDR (192.168.0.0/16 in staging and production alike). A storage node
that serves pods through Services needs the cluster's CNI, which is a
`RackLinuxMachine` change to make once the rack's networks no longer overlap.

### Pods on a rack node

A pod off the host network sits on the node's bridge (`10.254.254.0/24`), which
is its default gateway and masquerades it behind the node, so it reaches what
the node reaches: the internet, the rack's segments and the tailnet. It reaches
no cluster Service, no cluster DNS and no pod on another node, and nothing in
the cluster reaches it.

- **The API server.** The node translates the kubernetes Service's ClusterIP
  to the API server it joined through (`/etc/tuist/kubernetes-service.nft`,
  which the node agent loads on every apply), so an in-cluster client on the
  node, host network or not, reaches the API at the address it is given.
- **Names.** A pod that needs them sets its own nameservers. Kura's
  `nodeLocalNetwork` instances use Tailscale's `100.100.100.100`, which
  answers tailnet names and fails others over, then public resolvers.
- **Telemetry.** `alloy-rack` (`infra/helm/k8s-monitoring`) on each rack node
  ships its pods' logs and scrapes its node-local Kura pods, and pushes both to
  the Alloy receiver at its tailnet name. Kura exports its traces there too.
- **Being reached.** A pod the cluster has to read from is reached through the
  API server: the Kura controller samples node-local pods through a
  port-forward, which goes through the kubelet.

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
   Then, in staging's Controller Migration from step 3, click Confirm, enter
   production's controller tailnet IP in Controller IP/Inform URL (an address:
   the switches resolve no tailnet names), and migrate the switches smallest
   blast radius first: `ber1-mgmt` alone (deselect the others), then
   `ber1-tor-b`, then `ber1-tor-a`. Each reaches the new controller through
   the edge, which the ACL lets reach `tag:tuist-k8s-production` on the Omada
   ports. Each shows connected in production's Devices page and in
   `mise run rack:omada devices` from the cutover branch. Only once all three
   are connected there, click Forget Devices in staging, which finishes the
   migration; forgetting one staging still manages resets it. Not measured on
   these switches yet. If a switch does not come over, `mise run rack:omada
   inform <device>` from the cutover branch tells it the new controller
   directly.

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

11. **Merge the cutover** (remote). Production's deploy declares the hosts,
    the pool, the region, `alloy-rack` and the cache gateway;
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

## Tests

`mise run rack:nodes-test` renders the stick's seed against fake `op` and
`curl`; it runs in the Rack Switches workflow. The boot server, the netboot
seed, the iPXE script and the install lifecycle are Go tests in the operator
(`internal/rackboot`, `internal/rackinstall`,
`controllers/linux/racklinuxhost_install_test.go`).
