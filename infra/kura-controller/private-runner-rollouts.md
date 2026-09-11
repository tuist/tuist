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
  primary-pinned Service. Selection prefers fully joined members; if none are available, a Ready
  serving survivor can retain or take over the role while its sibling restarts.
- The existing SIGUSR1 preStop and termination budget drain connections.
  The normal disruption budget and node-evacuation machinery apply. Kubernetes
  defaults new StatefulSets to RollingUpdate; an operator-set OnDelete pause
  is preserved during reconciliation.

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
suffix is empty, `-staging`, or `-canary`. Its A record uses a Ready gateway node's
`tuist.dev/pn-ipv4` label, never the public Node InternalIP. Initial placement
prefers the selected primary's node, with a deterministic fallback. A healthy
published gateway stays selected across primary handoffs and Pod List reordering;
only losing that gateway requires a DNS-address change. Public peer DNS keeps
its existing public address. The hostname is public DNS metadata pointing to a
private address; DNS-01 issues the same managed TLS certificate as other Kura
hosts. It is not a secret hostname or a floating private IP.

The platform chart runs the same ingress-nginx chart and streaming settings on
the runner-cache nodes. Host-network listeners bind host interfaces. Both HTTP
and gRPC Ingresses require the runner subnet allowlist, with forwarded headers,
real-IP rewriting and PROXY protocol disabled on this direct entrance. Ingress
status publication is disabled: only the per-account DNSEndpoint may advertise
the hostname's IP. Empty or invalid allowlists suppress private ingress creation.

The gateway-to-backend hop is explicitly allowed by a CiliumNetworkPolicy for
pods labelled `tuist.dev/host-network-gateway=true`: only TCP port 4000 from the
`host` and `remote-node` identities. It selects private gateway backends. The existing Kubernetes NetworkPolicy retains the runner
CIDRs for legacy NodePorts and the usual pod/namespace rules; the gateway checks
the external client CIDR and Kura authenticates the request. Cilium classifies
host-network traffic by node identity, so an ipBlock cannot replace this rule
([Cilium policy reference](https://docs.cilium.io/en/stable/security/policy/layer3/)).

The controller publishes `status.privateURL` after observing a fresh Ready,
serving primary with its writer lock, a Ready certificate covering the hostname,
a Ready gateway and matching DNS. A missing sibling does not make the selected
primary unavailable. An explicitly stale certificate generation is rejected;
a Ready condition may omit that optional field. `endpointReason` and
`endpointMessage` distinguish primary, certificate, gateway and DNS failures.

Shared client routing and `endpointLastCheckedAt` update before storage
maintenance can yield. They do not depend on `lastReconciledAt`, which describes
a completed workload pass. The server requires the current spec generation and
an endpoint observation less than 120 seconds old, then persists that exact
observation time in `last_ready_at`. Dispatch uses the same shared 120-second
window, so rereading an old observation cannot extend it. Missing readiness
preserves the stored URL; dispatch falls back when the last observation expires.
In-cluster callers retain Service DNS. NodePort Services remain solely for jobs
that already hold their URL; there is no NodePort-dispatch branch in the catalog.

Gateway pod discovery uses a shared 30-second snapshot per ingress class through
the list-only `platform` Role, rather than a LIST per account. Nodes and
certificates use the informer. DNS answers are cached per hostname for the
60-second record TTL (five seconds for negative answers), with a two-second
lookup deadline. Changes are therefore observed within these bounded windows.

A primary process handover changes the Service selector, not the client URL.
Moving the gateway's host changes DNS and requires clients to reconnect and
re-resolve, exactly as in the public bare-metal regions. The configured fleet
currently has one host; two process replicas do not provide host redundancy.

## Resource sizing

Runner caches use the same account disk sizing and plan memory/CPU profiles as
public managed regions. New instances and cold returns start with the account's
sized claim (or the plan default: 8Gi for Air/Pro, 16Gi for Enterprise). The
storage-sizing worker includes runner-region occupancy and eviction telemetry
in the existing account-wide decision, so a runner region can drive growth and
must agree with the other measured regions before a shrink.

The enrollment migration immediately pins previously unpinned live runner rows
to the account's sized claim, or the current plan default if none exists. The
one-time enrollment is capped at the historical 50Gi: it can release reservations
but cannot grow them without admission checks. Existing explicit pins stay
unchanged. The migration locks only eligible instance rows and validates the
whole batch before writing. Unsupported claim formats fail explicitly and
require repair; the 8Gi/16Gi defaults remain frozen for deterministic historical
replay. This deliberately permits warm-cache eviction to unblock scheduling;
it does not wait for the ordinary 30-day shrink confirmation. Subsequent sizing
uses the normal measured policy. Rollback retains the applied pins, because
restoring 50Gi would reintroduce the blockage without recovering evicted data.

The production deployment runs the migration in its pre-upgrade hook after the
release pipeline reaches production. The server reconciler runs every minute;
its disk revision changes when the pin changes, so even an existing server
process can begin applying the new disk budget after the migration commits.
The controller re-templates the StatefulSet, retains larger existing PVCs, and
rolls replicas to their smaller runtime budgets and ephemeral-storage requests.
Unscheduled Pending pods still carrying the old larger reservation are recreated
once the smaller template is observed, so the ordered readiness gate cannot
strand them indefinitely. Resource-version preconditions protect pods scheduled
in the meantime. Operator OnDelete or partition pauses remain respected.
Convergence still depends on controller rollout, scheduling and pod readiness;
there is no fixed merge-to-recovery deadline. This does not resolve independent
private gateway certificate failures.

Memory requests and limits follow the standard plan profiles. CPU requests stay
measured by the controller; CPU limits follow the same plan profiles. The runner
hosts do not advertise `tuist.dev/memory-ceiling-mib`, so they must not request
that extended resource. Their memory floor remains a scheduler reservation;
kernel MemoryQoS protection depends on the host configuration. Capacity accounting
without a pin or loaded account retains a conservative 50Gi regional fallback;
governed provisioning still pins the account claim. The native disk reservation
continues to count both replicas' full claims against the host.

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
   `endpointLastCheckedAt`, `endpointReason`, and `endpointMessage`; confirm new
   jobs receive the HTTPS hostname. Verify from
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
readiness (including stale/public/mixed DNS answers), missing-sibling serving,
resize early returns, orphan gateway pods, sticky DNS across hosts, bounded
discovery caches and preservation of an operator rollout pause. The provisioner tests cover
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
