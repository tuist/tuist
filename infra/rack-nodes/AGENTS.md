# Rack nodes

Unattended installs for the BER1 rack's x86 nodes (the MS-01s): edge, services
and, once its disk layout is settled, the storage pair.

## How a node gets built

```
mise run rack:write-install-usb /dev/disk4 --node ber1-edge
```

`--node` bakes the node's autoinstall config into the image, so the machine
installs itself from the moment it boots the stick: no GRUB editing, no
keystrokes, and nothing served over the network. A node's definition lives in
`nodes.json`, so changing one means rewriting the stick.

`mise run rack:install-node <node>` serves the same config over HTTP instead,
for a machine booting a plain installer stick or a KVM's virtual media. It needs
the printed `autoinstall "ds=nocloud-net;s=http://…/"` appended to the `linux`
line at the GRUB menu by hand.

An install is finished when `/etc/tuist-rack-node` exists on the machine:

```
ssh tuist@<node> 'cat /etc/tuist-rack-node; sudo -n true && echo sudo ok'
```

Both come from the installer's late-commands. A machine that answers SSH without
that file was installed from an older image, or the late-commands did not run.

The MS-01s are set to boot USB ahead of the NVMe, so **a stick left in a built
node reinstalls it on the next reboot**. Pull it when the install is done.

## Ubuntu 24.04 LTS, deliberately

Every Linux machine in the fleet runs stock Ubuntu 24.04 converged after first
boot, across Hetzner, OVH, Dedibox and Scaleway. There is no Linux golden image
anywhere in this repo, and the rack is not the place to invent one: a node that
differs from the fleet is a node whose problems are its own.

## What the install sets, and what it does not

It sets the hostname, an account that exists only as a console login of last
resort, SSH with password authentication off and one authorized key, the disk
layout, and the role's packages.

It does not configure the rack's networking. NAT, VLAN interfaces, the tailnet
subnet router, DHCP, DNS and NTP are convergence, not installation, and they
have to match the switch configuration applied at the same time. None of that
exists in this repo yet: every Linux box here today is a Kubernetes node, so the
edge and services roles are greenfield.

Two things to carry over from what does exist rather than reinventing:

- the pf doctrine in `infra/macos-host-bootstrap/bootstrap.go`: interface-scoped
  first-match rules, the private prefix carved out of the default-route leg so
  RFC1918 traffic is never masqueraded to a public address, and a periodic
  reload so an external flush cannot leave the host unprotected
- `infra/tailscale/acls.json`: the catch-all grant must be removed **before** the
  edge advertises anything wider than a /32, or CI runners executing customer
  build code gain SSH to every machine in the rack

## The storage layout is not implemented

`rack:install-node` refuses the storage role on purpose. A machine that joins the
workload cluster needs `/boot`, a capped `/`, and a separate **XFS** `/data`
mounted with project quotas; the SSH self-join checks and refuses a machine that
cannot enforce them. Partitioning cannot be changed afterwards, so the layout has
to be right the first time. Work it out against
`infra/cluster-api-provider-tuist/controllers/linux/linux_cloudinit.go` and the
`baremetal:prep-*` tasks, which lay down the same shape on rented hardware.

There is also no Cluster API machine kind for owned Linux hardware: `RackHost`
and its claimant are macOS-only, so adopting `ber1-store-a` into the cluster
means building the Linux counterpart first.
