# Managed OVH private-network reconciliation

The environment's `capi.ovhPrivateNetwork` configuration names an already
provisioned vRack and a reserved private IPv4 CIDR. The CAPI provider reconciles
cache-tainted OVH machines in its own namespace, including existing Ready
machines. Runner machines are excluded. MachineDeployment `OnDelete` does not
prevent this additive repair; no machine replacement or OS reinstall is used.

Address reservations live in a separate controller-owned ConfigMap and survive
Machine deletion. OVH releases reinstall asynchronously, so deleting a Machine
cannot make its address available to another physical host. Network ID and CIDR
are immutable once reservations exist. Neither the controller nor rollback
terminates a vRack or changes a paid bandwidth option.

The controller attaches exactly one non-aggregated private NIC. It refuses to
move an attached interface between vRacks or change its public/OLA mode. After
attachment, it finds the interface by MAC and installs a private address,
peer-specific routes, and a systemd repair timer. Node public identities and
default routes remain unchanged.

Address preparation runs before route publication. Every selected peer's private
next hop must answer before a new route membership is installed. While hosts are
being prepared, existing public routes remain available and previously installed
guards/timers stay intact. This avoids cutting off peers during a partial initial
rollout. Runtime topology remains unpublished until all route attestations agree.

Every selected peer public `/32` has both a preferred route through its private
next hop and a less-preferred unreachable route. The guard lives in the main
routing table because direct Cilium FIB lookups can skip policy-routing rules.
If private reachability fails, the unicast route is withdrawn and the guard
prevents the public default from matching. Guards are restored before containerd
and kubelet start. Each guard records its owning Machine name and UID. A deleting
Machine leaves the preflight and route membership but retains its guard until
the Machine has disappeared from the authoritative API roster. The next successful
convergence removes only that retired Machine's protocol-242 routes. Failed,
NotReady, or temporarily unaddressed Machines retain their guards. Installation
and repair share a lock. Guards from older scripts acquire ownership when their
Machine can be identified; an already-orphaned guard with no ownership evidence
requires explicit cleanup after verifying release. Private address reservations
remain retained, independently of public route retirement.

The script probes private next hops before attesting route installation. The
controller publishes a common membership digest only after the script succeeds,
and publishes the scheduling label after every participating host has installed
that same membership. This prevents a new host from advertising a private path
before its existing peers have installed routes to it.

`kuraController.privateReplication.enabled` derives runtime topology from the
actual provider IDs and matching route attestations of all candidate Nodes.
Mixed providers, missing attestations, different networks, or different route
memberships hold topology publication. Other StatefulSet changes continue. Before
first qualification the instance retains canonical replication; after activation,
the last managed topology and full scheduling selector are preserved during a
qualification gap only while the requested selector is unchanged (excluding the
controller-added network label). An intentional placement change uses the new
selector and withdraws the old managed policy if the destination is unqualified;
a qualified destination receives its own topology. Withdrawing topology restores
canonical replication, which may use public bandwidth. An explicit disable or
manual topology override also remains an operator action. Qualified pods require
the same network label for scheduling. Evacuation checks the StatefulSet template's
selector before deleting a local claim or pod, so an unattested replacement in
the same pool is not counted as a landing node. If the StatefulSet does not yet
exist, it uses the instance's rendered selector, including its defaults.
Each process advertises its own authenticated peer DNS name. Discovery through a
gateway still requires a direct private probe even when the advertised private
and node URLs match. Discovery that already queried the private origin reuses that
successful status response; self-discovery does not issue another probe.

These controller checks establish configuration convergence. Packet captures on
both physical hosts, private-path failure injection, replication catch-up, MTU,
and throughput checks remain required before declaring an environment qualified.
The authoritative rollout evidence and provider limits are in
[private-replication.md](private-replication.md).
