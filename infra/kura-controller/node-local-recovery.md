# Recovery from a node-local Kura network partition

On 2026-09-22 the sole EU East node repeatedly lost its Kubernetes API
connection. Kubernetes' default five-minute `not-ready` / `unreachable`
tolerations expired and both ordinals of multiple instances were evicted.
The replicas' local volumes still pinned their replacements to that same node.
After the node returned, DNS and mesh-fetch failures prevented some restarted
processes from passing the initial peer-view readiness gate. A subsequent
partition repeated the eviction cycle.

## Preventing repeated eviction

For the managed `scw-local-nvme` storage class, the controller supplies these
defaults when the StatefulSet is created or changes runtime image:

```yaml
tolerations:
  - key: node.kubernetes.io/not-ready
    operator: Exists
    effect: NoExecute
  - key: node.kubernetes.io/unreachable
    operator: Exists
    effect: NoExecute
```

There is intentionally no `tolerationSeconds`. A cached process that survives a
control-plane partition can resume without reopening its store or fetching its
initial mesh view. A process that actually crashes still follows normal kubelet
restart and readiness behavior. The change does not mark an unreachable node or
unready pod healthy, and does not tolerate the `NoSchedule` taints that block
new pods while the node is unavailable.

Explicit `spec.tolerations` remain authoritative, including finite deadlines
and matching wildcard tolerations. Network-backed and unspecified storage
classes keep their existing policy. The new defaults do not independently roll
an existing StatefulSet: deployment alone leaves its current policy in place,
and the next runtime-image change adopts them. Once present, reconciliation
retains them. Set explicit finite tolerations to opt back into timed eviction.

Indefinite toleration deliberately gives up automatic pod deletion on a failed
host. Such deletion cannot relocate a bound node-local volume anyway. Confirmed
host loss still needs the existing lost-node storage recovery path; planned
replacement still uses explicit evacuation and its catch-up gates. Do not force
delete a pod or discard its volume based solely on a missed heartbeat.

## Incident response

1. Check node conditions and events, both replicas, Service endpoints, Cilium
   health, and the exact runtime readiness reason. A replica-count warning can
   represent a regional outage when neither ordinal is serving.
2. If a rollout is worsening recovery, save the affected StatefulSets'
   `spec.updateStrategy` and temporarily use `OnDelete`. This pauses rolling
   updates, not node-loss eviction or replacement of already missing pods.
   The controller image-change deletion path also respects `OnDelete` and
   positive rolling partitions; it must not bypass an incident pause. A
   StatefulSet annotated `kura.tuist.dev/resize-rollout-hold` is already on
   `OnDelete` for a data volume resize, and the controller lifts it once every
   replica is Ready. Remove the annotation to keep it as an incident pause.
3. Compare an unauthenticated `/ready` request to the control-plane Service by
   normal hostname, absolute hostname, and its current ClusterIP. Preserve the
   initial mesh gate: bypassing it would let a process serve with an incomplete
   peer view. A DNS bypass is appropriate only if the same Service is reachable
   by IP. Do not infer it from DNS errors alone.
4. A temporary control-plane/auth URL override in the selected KuraInstances
   can use that verified ClusterIP without changing credentials or storage.
   Save the original URLs; a fixed IP is incident state, not a durable service
   address. Updating the CR alone does not change an existing pod's environment.
   Under `OnDelete`, replace only a non-serving replica after observing the
   corrected template, then verify it before touching its sibling.
5. During recovery, explicit node-loss tolerations can be added to the selected
   CRs and existing non-terminating pods without restarting the latter. On live
   pods, remove `tolerationSeconds` from the matching admission-injected
   five-minute entries instead of merely appending an indefinite entry:
   Kubernetes' eviction controller uses the first matching toleration, so an
   earlier finite entry still wins. The pod API permits changing that deadline
   in place. Save the old list and use UID and old-field preconditions. They
   cannot cancel a deletion already in progress. Verify the effective first
   match for both taints, and preserve an explicitly configured finite policy
   instead of silently extending it.
6. Verify both ordinals, primary selection, public HTTP/gRPC availability and
   stable node connectivity. Restore temporary DNS overrides only after DNS
   succeeds within the runtime's connection budget. Restore saved update
   strategies in a controlled sequence with a serving sibling.

All live operations follow the production elevation rules in
[`../AGENTS.md`](../AGENTS.md). Keep the recovery's saved values and actions in
the incident record until temporary state has been removed.

This change prevents a recovery amplifier; it does not repair packet loss or
provide node redundancy. The current placement deliberately co-locates a warm
standby for deployments and relies on the cross-region mesh for box-level
recovery. Continuous service through physical node failure needs a tested
traffic failover path to an independent serving copy: another region, or a
second prepared regional host with different replica placement and gateway
failover. Merely increasing the replica count on one host is insufficient.

See [the incident analysis](incidents/2026-09-22-eu-east.md) for measured network
evidence, the remaining uncertainty, and the staged prevention plan.
