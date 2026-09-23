# Omada SDN Controller

Wraps [mbentley's chart](https://github.com/mbentley/docker-omada-controller/tree/master/helm/omada-controller-helm)
so the controller's lifecycle is handled the way everything else here is.

**The controller for the rack fleet, still under evaluation.** It exists to
answer whether the controller can take over switch management from
[`infra/rack-switch-fleet`](../../rack-switch-fleet/AGENTS.md)'s SSH driver, and it
is deployed to the staging cluster, where the rack belongs while it is at home.

## Why it might replace the SSH driver

TP-Link's own list of what a controller-managed switch can do covers everything
the fleet renders: management address and VLAN, hostname, RSTP, per-port
spanning tree, LLDP, VLANs, port configuration. Under the controller, SSH also
becomes read-only, which would delete the fleet's `apply` and `replace` and
leave its driver doing the reading it is better at.

## What its API can do

On 6.3 the Open API has a write endpoint for every setting the fleet renders on
a standalone switch. On 5.15 it did not: spanning-tree mode and LAGs were
writable only for stacks. That is why `values.yaml` pins the image tag. Two
settings, spanning-tree mode and per-port spanning-tree settings, can be written
but not read back, so verification still reads `show running-config` over SSH.

The endpoint documentation is served by the controller itself, at
`https://<controller>:8043/doc.html`, with the raw document at `/v3/api-docs`.
The measurement and the per-setting table are in
[omada-assessment.md](../../rack-switch-fleet/omada-assessment.md).

## Where it runs, and how switches reach it

One controller for the rack fleet, because a switch can be adopted by only one
at a time: the staging cluster while the rack is at home, production once it is
in the data center. There is no staging or canary copy per environment; the
switch-side equivalent of a canary is the apply order the site definition
enforces.

Nothing about it is public. The Tailscale operator gives its Service a tailnet
device, `omada`, and the switches reach that through the rack's edge node, which
translates their traffic onto its own tailnet address
(the rack-edge DaemonSet, see
[`rack-switch-fleet/AGENTS.md`](../../rack-switch-fleet/AGENTS.md)). L2
discovery does not cross into the cluster, so a switch is told where the
controller is with `controller inform-url` and the controller's tailnet IP
(`mise run rack:omada inform <device>`); switches have no resolver for MagicDNS
names. DHCP option 138 is the equivalent for a factory switch, and `rack:ztp`
serves the segment that would carry it.

## What it costs to run

A StatefulSet with two volumes. The data volume holds adoption state for every
device, so losing it means re-adopting the rack by hand; it is a real PVC rather
than an emptyDir even while this is an evaluation.

Switches keep forwarding when the controller is unreachable; only changes wait.
That is what makes running it in a cluster the switches carry acceptable, and it
is why the console path and the fleet CLI stay whichever way this goes.

## Standing it up

`.github/workflows/omada-deployment.yml` deploys it to staging on a merge that
touches this chart, or on dispatch. It is a workflow rather than a command
because creating the namespace needs rights an engineer does not have in
staging.

The admin account and the Open API client are created in the controller's own
first-boot wizard, at `https://omada.<tailnet>.ts.net:8043`, so no
ExternalSecret can seed them. Store the admin login in 1Password, and the API
client as the item `management.controller.credential_item` in the site
definition names ("omada staging open api"), with `client-id` and
`client-secret` fields; `rack:omada` reads it from there. The API client needs
the Administrator role over the site the switches are adopted into.

After the wizard, `mise run rack:omada controller --create-device-account` sets
what the switches depend on from the site definition, and is safe to re-run:
the address the controller tells switches to connect back to (its tailnet IP;
it starts unset), SSH on for the site's switches (it starts off, and adoption
applies it), and the site's device account, which adoption puts on every
switch in place of its own login. The account comes from the 1Password item
`management.controller.device_account_item` names; the flag creates it with a
generated password the first time. Skip the wizard's device step: adoption
goes through `rack:omada adopt`, which runs the same settings first.
