# rack-switch-controller

Kubernetes controller that adopts a rack's switches into the Omada SDN
controller and writes their configuration through its Open API, from the
`RackSwitch` objects (`tuist.dev/v1alpha1`) in the rack's namespace. It is the
reconciler [`rack-switch-fleet/omada-assessment.md`](../rack-switch-fleet/omada-assessment.md)
sketches, and the Go form of `rack:omada controller`, `adopt` and `apply`
([`rack-switch-fleet/omada.sh`](../rack-switch-fleet/omada.sh)), whose calls
against the real controller are the measured reference for everything here.

It never opens SSH to a switch. SSH stays with
[`rack:fleet`](../rack-switch-fleet/AGENTS.md) for what the API cannot read
back and for the console path.

## Which switches

Only objects with `spec.managedBy: controller`. A standalone object, the
default, gets `status.message` saying so and nothing else: no Omada call, no
other status field. `spec.mac`, `spec.managedBy` and `spec.config` are rendered
by `fleet_render_k8s` in `rack-switch-fleet/lib/config.sh`; until it emits
them every object is standalone and the controller does nothing.

## What a reconcile does

1. **Site settings**, read and written only where they differ: the address the
   Omada controller tells adopted switches to connect back to
   (`--controller-address`, its tailnet IP), site SSH on at port 22, and the
   site's device account from its Secret. The device account replaces every
   adopted switch's login.
2. **Adoption.** The switch is found by MAC in the site's device list, or its
   pending list. A pending switch is adopted with the device account first and
   the factory login (`admin`/`admin` unless a Secret says otherwise) second,
   with an event naming which. An "adoption failed" state counts only once the
   switch has shown another state since the request, since a failure from an
   earlier attempt persists until the controller picks the new one up. The
   attempt lives in memory and is polled every 15 seconds; a new leader starts
   it again. Not in the site at all is `Adopted=False`, reason `NotSeen`.
3. **Converge a connected switch**, in order: the management address, hostname,
   each port's description (empty means `Port<n>`), spanning-tree mode, then
   each other gated step. What the API reads back is written only where it
   differs; what it cannot read back (spanning-tree mode, a port override's
   content) is written on every apply. It then reads the switch again, and the
   drift it reports is what is left. A factory switch adopted through zero
   touch (DHCP option 138 names the controller) comes up on DHCP, which is why
   the address is written first; measured with a factory reset of `ber1-mgmt`,
   after which it was the only difference from the render.

**When it writes.** Adoption, site settings and switch writes happen when the
spec's `configRevision` or `metadata.generation` has moved past
`status.observedRevision` / `status.observedGeneration`, or when the switch has
just been adopted, and never while a switch of the same site with a lower
`applyOrder` is not Ready. A controller-managed switch is Ready by its
condition, which must be about its current generation and revision; a
standalone one when `rack:fleet publish` last saw it at its revision with no
drift. One reconcile at a time, one replica holding the leader lease.

Between changes it only reads, every `--resync-interval` (10 minutes), so drift,
the site settings' included (device host, site SSH, device account), is
reported (`drift: drifted`, `Converged=False` reason `Drifted`, one warning
event) and not written over: a change made during an incident is one somebody
meant. A new revision converges it, and so does the one-shot `apply` below.

## Status

`adopted`, `controllerStatus` (the Omada controller's name for the device's
state), `reachable` (connected), `observedRevision` and `observedGeneration`
(set once a converge wrote everything for them and read back clean), `drift`
(`unknown` when not connected), `lastVerified`, `message`, and conditions
`Adopted`, `Converged`, `Ready`. `connectionsUsedSinceBoot` is only ever
written by `rack:fleet publish`.

## The API, and the gates

Every call was measured on controller 6.3.0.45 and a real switch;
`internal/omada/omadatest` is a fake that answers the same way, refusals
included. Each step beyond hostname, descriptions and spanning-tree mode is
behind a flag (`gates` in the chart); all are on by default:

- `--enable-management-addressing`, on by default: the static address, mask
  and gateway (the site's edge node, which is the path to the controller) of
  the interface with `mvlan` true, sent back as read less its `status`, with
  the fallback fields the controller refuses the block without. The switch
  keeps its controller connection across the change. Its VLAN is reported,
  never moved. Verified end to end on all three BER1 switches.
- `--enable-vlans`: creates the site networks `config.vlans` lists (never
  deletes one; a site network is shared by every switch in the site) and writes
  every port's VLAN membership as the spec's list, never as "Allow All", even
  for a port naming every network the site has: "Allow All" would carry a
  network added to the site later without a new revision. The renderer expands
  "every site VLAN" into that list, so a new site VLAN reaches a port through a
  new revision. Every port, because a port the API reports as following its
  profile can still hold an old custom list on the switch (measured on
  ber1-tor-b), and the API cannot return an override's content. Verified end
  to end.
- `--enable-lags`: creates LACP groups through the first member's port
  endpoint, with the spec's `name` (the renderer defaults it to `lag<id>`),
  which the members then carry as their description; the SX3832's
  controller refused a static LAG. `portList` says only that a port is in some
  LAG, with no id (measured on ber1-tor-b), so a LAG is known by the name its
  members carry, and the spec's LAG names must be unique. A LAG whose members
  differ from the spec is deleted and created again, every such LAG deleted
  before any is created, so ports can move between LAGs; drift names the
  members each has and wants. A LAG the spec does not name is reported and
  left, and a wanted port inside one stops the pass before anything is written,
  since its id is unknowable. LAG members are skipped by every other port step,
  as the controller refuses changes to them, and the LAG step runs first so a
  port it frees takes its own settings in the same pass. Verified end to end.
- `--enable-port-spanning-tree`: every port's `spanningTreeEnable`, for the
  same reason as VLAN membership: an override written for its VLANs alone would
  keep an earlier spanning-tree setting. Verified end to end.
- `--enable-site-services`: the site-wide LLDP (nested as `{"lldp":
  {"enable": ...}}`) and SNMP (`snmpV1V2CEnable`, `snmpV3Enable`). Measured;
  SNMP is only ever turned off, since the spec carries no community or user to
  turn it on with.

The controller refuses a port or LAG name that is empty or has parentheses in
it; the CRD admits only `[A-Za-z0-9 ._-]`, up to 32, as the renderer does. A
write the controller refuses anyway ends the pass with `Converged=False`,
reason `ConvergeFailed`, carrying its message, and is retried with backoff.

Two measured endpoints it deliberately does not call:
`POST devices/{mac}/forget` factory-resets a switch and releases it from the
controller, and the device CLI configurations (`cli/config/cli-type/1/save`,
then `cli/configs/config-id/{id}/apply`, one configuration per device, devices
named by `deviceMac`) run configuration lines the structured API does not
model; they removed the ToRs' pre-adoption static route by hand.

## Where it differs from the assessment's sketch

- One leader lease for the controller, not one per site. `rack:fleet` and
  `rack:omada` from a laptop do not take it; they keep their own lock in
  `lib/lock.sh`, so do not run them against a site the controller is changing.
- It does not read spanning-tree state over SSH. What the API cannot read back
  is verified with `mise run rack:fleet diff <device>`.
- No rollback. Going back is a revision with the previous values.

## Where it runs

`infra/helm/rack-switch-controller`, installed into the Omada controller's
namespace (`omada`) by `.github/workflows/omada-deployment.yml`, watching the
rack's namespace (`tuist-staging` for BER1). The pod has a required node
affinity away from rack nodes (`rackNodeLabels`: `kubernetes.io/os=darwin`,
`tuist.dev/runtime=tart`, and `node.cluster.x-k8s.io/instance-type=rack` for the
edge node), because a controller behind the switches it changes would be
reconciling its own path to the Omada controller. A rack node of another kind
joining the cluster adds its label there.

It verifies the Omada controller's certificate against the CA in the
`omada-controller-tls` Secret (`omada.caSecret`), which `infra/helm/omada` has
cert-manager issue; only its `ca.crt` is mounted.

Credentials are files in one directory (`--credentials-dir`): `client-id`,
`client-secret`, `device-username`, `device-password`, and optionally
`factory-username` and `factory-password`. They are read on every reconcile,
so a rotated secret needs no restart. In the cluster two ExternalSecrets fill
them from the `onepassword` ClusterSecretStore, whose vault is
`tuist-k8s-staging`: items "omada staging open api" and "ber1 switch device
account", which have to exist in that vault.

## Running it once from a laptop

```
cd infra/rack-switch-controller
go build -o rack-switch-controller ./cmd/manager
./rack-switch-controller apply --object <RackSwitch yaml> \
  --omada-url https://omada.<tailnet>.ts.net:8043 --site ber1 \
  --controller-address 100.84.132.92 --credentials-dir <dir> \
  --omada-ca-file <(kubectl -n omada get secret omada-controller-tls -o jsonpath='{.data.ca\.crt}' | base64 -d)
```

The tailnet name is in the controller's certificate; the jsonpath reads only
the CA, not the key beside it.

It runs the same site settings, adoption and converge for one object, writing
everything its spec asks for, prints each write, and exits non-zero when the
switch does not match afterwards. It sees one object, so it checks no apply
order and takes no lock; do not run it while the in-cluster controller is
changing the same site.

## Development

```
cd infra/rack-switch-controller
go test ./...
go vet ./...
mise run rack-switch-controller:generate   # after editing api/v1alpha1
```

The CRD in `infra/helm/tuist/crds/tuist.dev_rackswitches.yaml` is generated
from `api/v1alpha1`, and CI fails when the committed one is stale.
`controllers/envtest_test.go` runs against a real API server when
`KUBEBUILDER_ASSETS` is set, as CI does.
