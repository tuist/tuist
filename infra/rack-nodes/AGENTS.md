# Rack nodes

How the BER1 rack's x86 Linux machines (the MS-01s: edge, services and storage)
become cluster nodes. Plugging in the install stick is the only step on site:
the machine installs Ubuntu, joins the tailnet on first boot, and the cluster's
operator joins it as a node and keeps it converged.

## The pieces

- **Inventory** is `rackLinuxFleet.hosts` in the env's tuist chart values,
  rendered as one `RackLinuxHost` per box (pool `<pool>-<role>`, role, site,
  tailnet tags). Each role present gets a MachineDeployment of
  `RackLinuxMachine`s with that role's `rackLinuxFleet.roles.<role>` labels and
  taints. The node name, the hostname and the tailnet name are all the host's
  name.
- **The stick** (`mise run rack:write-install-usb`) reads the host from the
  same values, so the install and the operator agree on it.
- **The operator** (`infra/cluster-api-provider-tuist`, `controllers/linux`)
  finds the host on the tailnet and joins it. See "Rack-owned Linux hosts" in
  its AGENTS.md.

**Install a new host before the deploy that declares it, or within the hour
after.** The tuist chart deploys with `helm --atomic --wait`, which waits for the
role's MachineDeployment, and its Machine is only Running once the host has
joined. A host on the tailnet with no `RackLinuxHost` yet simply waits; the
operator joins it within minutes of the deploy.

## Writing a stick

```
mise run rack:write-install-usb /dev/disk4 --host ber1-edge
mise run rack:write-install-usb --host ber1-edge --output ber1-edge.iso
```

It needs `op` signed in (it reads the vault `tuist-k8s-<env>`), `xorriso`, and
an `openssl` with SHA-512 crypt (Homebrew's). The Ubuntu 24.04 ISO is fetched
once, checked against Ubuntu's SHA256SUMS, and cached in
`~/Library/Caches/tuist-rack`.

The stick carries:

- network configuration for the SFP+ uplinks only (DHCP on the X710's `i40e`
  ports), so the 2.5G ports stay unmanaged for the node's pods: the edge
  node's rack-edge pod owns the switch port;
- the host's hostname and role, the `tuist` account with passwordless sudo and
  a console password from the 1Password item `<host> console` (created on
  first use), SSH with password authentication off, and the rack's fleet key
  (`BER1_FLEET_SSH` public key) plus the writer's own key;
- a tailnet join key minted now from the OAuth client in `TAILSCALE_RACK_NODES`:
  single-use, pre-authorized, not ephemeral, carrying the host's tags, expiring
  after `--key-hours` (24 by default). The OAuth client never reaches the stick.

A first-boot unit, `tuist-tailnet-join`, installs Tailscale, joins with the key,
deletes it, and disables itself; it retries every minute until it succeeds.
Tagged devices have key expiry off, so nothing about the join needs a person.
`/etc/tuist-rack-node` records the node, role, build time and the join key's
ID; an install that answers SSH without it was not built from this stick.

**Until the install has used it, the stick is a credential.** Its key admits one
device with the rack's tags. A stick that is lost before use is dealt with by
deleting its key, whose ID the task prints, in the Tailscale admin console.

**A stick installs a machine once.** Its early-commands look for an install that
carries the stick's key ID and, finding one, set `BootNext` to it (with the
installed system's own `efibootmgr`) and reboot into it rather than wiping it.
The MS-01s boot USB first, so this is what turns the reboot at the end of the
install into the new system's first boot. Pull the stick once the node is up:
left in, it costs every reboot a pass through the installer. Reinstalling takes
a new stick.

## Reinstalling

Reinstalling is the same stick flow. The new install registers a new tailnet
device (`ber1-edge-1` while the old one exists); once it is connected, the host
controller deletes the old device and renames the new one to the host's name.
The machine controller sees the new device ID, pins the new SSH host key, finds
a kubelet with no identity, deletes the stale Node and joins the host afresh, so
the Node registers with its declared labels and taints again.

## Break glass

If the join key is gone (expired, or spent by an install that then had to be
redone) and no new stick can be written, join the tailnet by hand; the operator
takes over from there:

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

The rack moves to production by moving its inventory: the hosts go from
`values-managed-staging.yaml` to `values-managed-production.yaml`, the
`TAILSCALE_RACK_NODES` item goes to the `tuist-k8s-production` vault, the ACL
grants `tag:tuist-k8s-production` what it grants `tag:tuist-k8s-staging` for
`tag:tuist-rack-edge`, and each node is reinstalled from a stick written with
`--env production`. Production's Cilium must exclude `cilium.io/no-schedule=true`
first (`infra/k8s/mgmt/bootstrap/cilium-values.yaml`); the operator refuses to
join the node until it does.

## Tests

`mise run rack:nodes-test` renders the seed against fake `op` and `curl`, and
runs in the Rack Switches workflow.
