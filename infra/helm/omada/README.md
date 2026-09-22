# Omada SDN Controller

Wraps [mbentley's chart](https://github.com/mbentley/docker-omada-controller/tree/master/helm/omada-controller-helm)
so the controller's lifecycle is handled the way everything else here is.

**This is an evaluation, not a decision.** It exists to answer whether the
controller can take over switch management from
[`infra/rack-switch-fleet`](../../rack-switch-fleet/AGENTS.md)'s SSH driver. It
is deliberately not wired into any deployment workflow: standing it up is a
deliberate act.

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

## Adoption across subnets

A switch finds its controller by L2 broadcast on UDP 29810, which does not cross
from the management VLAN into the cluster. Two ways across:

- **DHCP option 138**, the documented path, and one the rack can already serve:
  `mise run rack:ztp` runs a dnsmasq on an isolated segment and option 138 is
  one more line in the config it generates.
- **Adopting by hand** in the controller UI, giving the switch's address.

Either way the controller needs a stable address reachable from the management
VLAN, which is what the tailnet is for here rather than an ingress, since the
rack's other management paths already go that way. The chart's default
`LoadBalancer` service is therefore overridden to `ClusterIP`.

## What it costs to run

A StatefulSet with two volumes. The data volume holds adoption state for every
device, so losing it means re-adopting the rack by hand; it is 5Gi and a real
PVC rather than an emptyDir even while this is an evaluation.

And it puts the switches' management plane inside the cluster whose network
those switches carry. That is the same failure-domain question as a switch
operator, and it is why the console path and the local CLI stay whichever way
this goes.

## Standing it up

```
helm dependency update infra/helm/omada
helm upgrade --install omada infra/helm/omada \
  -n omada --create-namespace \
  -f infra/helm/omada/values.yaml \
  -f infra/helm/omada/values-staging.yaml
```

The admin account and any Open API client credentials are created in the
controller's own UI on first boot, so they cannot be bootstrapped from
1Password by an ExternalSecret the way the rest of the chart's secrets are.
Create them, then put them in the `Infastructure` vault.
