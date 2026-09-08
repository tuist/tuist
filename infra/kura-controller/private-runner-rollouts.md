# Private runner caches on the managed rollout

Runner Kura is an ordinary two-replica managed instance with a private entrance.
There is no `PrivateRunner` rollout policy, OnDelete strategy, required
same-host affinity, or runner-specific pod replacement state machine.

## Shared behavior

- StatefulSet `RollingUpdate` replaces pods in descending ordinal order and
  waits for Kubernetes readiness between replacements. Each pod retains its own
  local PVC across process restarts. Both claims and both memory reservations
  count against capacity; co-location is preferred, as in other managed regions.
- Both pods continuously replicate writes through the account mesh and persistent
  outbox. Restarting a pod triggers initial peer backfill. The standby is writable
  and participates in replication throughout its lifetime.
- HTTP and gRPC enter through the regional ingress-nginx gateway and the same
  primary-pinned Service. The primary stays selected while runtime-routable;
  readiness/deletion events cause selection to hand off to a healthy sibling.
- The existing SIGUSR1 preStop and termination budget drain connections.
  The normal disruption budget and node-evacuation machinery apply.

This is asynchronous replication. Kubernetes Ready and runtime-routable do not
prove that initial backfill has completed or every newly acknowledged write has
reached the standby. The change does not introduce a stronger consistency or
zero-error rollout guarantee than the other managed instances. Continuous
outbox progress and backfill health remain operational checks for both.

## Private entrance

The catalog sets `private: true`, `privateHost`, `ingressClassName: kura-runners`,
`publicHostNetwork: true`, and the runner PN `clientCIDRs`. The historical
`publicHostNetwork` field selects the shared host-network gateway mechanism;
`private` determines which address it publishes. A private instance without a
private host retains its legacy cluster/NodePort behavior, even if an old
`publicHost` value is present.

The stable account hostname is
`<account>-scw-fr-par-runners<environment-suffix>.kura.tuist.dev`, where the
suffix is empty, `-staging`, or `-canary`. Its A record uses a Ready cache node's
`tuist.dev/pn-ipv4` label, never the public Node InternalIP. Public peer DNS keeps
its existing public address. The hostname is public DNS metadata pointing to a
private address; DNS-01 issues the same managed TLS certificate as other Kura
hosts. It is not a secret hostname or a floating private IP.

The platform chart runs the same ingress-nginx chart and streaming settings on
the runner-cache nodes. Host-network listeners bind host interfaces. Both HTTP
and gRPC Ingresses require the runner subnet allowlist, with forwarded headers,
real-IP rewriting and PROXY protocol disabled on this direct entrance. Ingress
status publication is disabled: only the per-account DNSEndpoint may advertise
the hostname's IP. Empty or invalid allowlists suppress private ingress creation.

The controller publishes `status.privateURL` after observing the serving primary,
current Ready certificate, Ready gateway pod on the DNS target node and DNS
resolving exclusively to that private IP. Its `platform` Pod read permission is
list-only and explicitly enabled by managed values. The server requires the
matching spec generation and an observation less than 120 seconds old before
activation or refresh. Missing readiness preserves the stored URL and stops its
heartbeat; dispatch eventually falls back to the ordinary cache. In-cluster
callers retain the Service DNS URL.

A primary process handover changes the Service selector, not the client URL.
Moving the gateway's host changes DNS and requires clients to reconnect and
re-resolve, exactly as in the public bare-metal regions. The configured fleet
currently has one host; two process replicas do not provide host redundancy.

## Migration order (no deployment performed by this change)

1. Render and install the platform gateway, updated CRD, and controller with
   `kuraController.privateGateway.enabled: true`. Check the gateway is Ready on
   each runner-cache node. The existing deployment pipeline installs platform
   before the application; CRDs still need applying before controller/server.
2. For the first catalog cutover, let jobs already holding a node-IP URL finish
   before changing replica placement or the runtime image. Retain the original
   host. A legacy `externalTrafficPolicy: Local` NodePort cannot follow its
   primary to a different host; retaining its port alone cannot fix that.
3. Apply the server catalog. Existing instances reapply because replica and
   endpoint configuration contribute to the manifest revision. The new catalog
   creates the private gateway route and scales to two standard replicas.
   `exposeNodePort` remains true, preserving allocated legacy Services/ports.
4. Verify `status.privateURL`, `endpointObservedGeneration`, and
   `lastReconciledAt`; confirm new jobs receive the HTTPS hostname. Verify from
   an actual runner VM before resuming a rollout or retiring a host.
5. Once all old node-IP jobs have finished, use the ordinary managed rollout and
   node-evacuation procedure. Retire legacy NodePorts in a separate change after
   their use has ceased. Do not change them to Cluster traffic policy as a
   shortcut: source NAT can invalidate the network-policy source restriction.

Rollback the application while keeping the gateway, certificate, DNS and host
available to jobs already using the hostname. Do not remove `privateHost` or
uninstall the gateway until those jobs finish. A full rollback to an older
controller removes private ingresses, so it also requires draining hostname jobs.

## Validation

Controller tests in `controllers/client_gateway_test.go` exercise public/private
routing parity, primary handoff, preserved NodePorts, ordinary rollout strategy,
preferred placement, disruption budgets, source restrictions, and publication
readiness (including stale/public/mixed DNS answers). The provisioner tests cover
environment-separated hostnames, replica/endpoint manifest revisions, legacy
NodePort compatibility, stale generations and expired observations.

Before production rollout, exercise this staging scenario from a runner VM:

1. Write and repeatedly read unique cache artifacts through the stable hostname
   while restarting the standby and then rolling the runtime image. Record
   HTTP/gRPC failures, cache misses, latencies and payload digests throughout;
   keep a large streaming transfer running across the primary handover.
2. Observe both pods' `/status/rollout` through the existing authenticated peer
   status path. Check `backfill_initial_cycle` completes and outbox counters
   return toward baseline after writes and after the standby rejoins. Inspect
   `kura_outbox_target_messages` for the sibling target, not only the aggregate.
3. Confirm HTTP and gRPC reject a connection from outside the runner CIDR,
   including a forged `X-Forwarded-For` header, while the same requests succeed
   from the PN. Check DNS has only the private A address and TLS validates.
4. With a second host available, move the primary using the ordinary evacuation
   path. Verify the gateway can reach the Service across hosts, its hostname
   stays unchanged, and clients reconnect after a gateway-address change.
5. Exercise one legacy NodePort job through a same-host process replacement;
   then verify all newly dispatched jobs use HTTPS. Do not retire its host while
   any node-address job is still running.

These live network/streaming checks require the staging runner network. Unit
and Helm render tests do not establish them, and no production rollout is part
of this implementation.
