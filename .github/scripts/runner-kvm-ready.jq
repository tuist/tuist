# Reports KVM preparation of the nested-virtualization fleets' hosts.
# Only Ready, schedulable hosts that are not being deleted are eligible; each
# must carry current-boot preparation and a device per Pod slot. The rest take
# no Pods now, and nested Pods reach them later only through the provider's
# kata-kvm label (withdrawn until the current boot is verified) and devices.
($fleets | split("\n")) as $fleetNames |
[.items[] |
  .metadata.labels["node.cluster.x-k8s.io/pool"] as $fleet |
  select($fleet | IN($fleetNames[])) |
  (.status.nodeInfo.bootID // "") as $boot |
  {
    name: .metadata.name,
    fleet: $fleet,
    ready: any(.status.conditions[]?; .type == "Ready" and .status == "True"),
    unschedulable: (.spec.unschedulable == true),
    deletionTimestamp: .metadata.deletionTimestamp,
    kvm: .metadata.labels["tuist.dev/kata-kvm"],
    proofCurrent: ($boot != "" and ((.metadata.annotations["tuist.dev/kata-kvm-config"] // "") | endswith(":" + $boot))),
    pods: ((.status.allocatable.pods // "0") | tonumber),
    devices: ((.status.allocatable["devices.tuist.dev/kvm"] // "0") | tonumber)
  } |
  .skipped = [
    if .ready then empty else "not Ready" end,
    if .unschedulable then "unschedulable" else empty end,
    if .deletionTimestamp != null then "being deleted" else empty end
  ] |
  .failed = if .skipped != [] then [] else [
    if .kvm == "true" then empty else "tuist.dev/kata-kvm label missing" end,
    if .proofCurrent then empty else "tuist.dev/kata-kvm-config proof is not for the current boot" end,
    if .pods > 0 then empty else "no allocatable pods" end,
    if .devices >= .pods then empty else "devices.tuist.dev/kvm \(.devices) < pods \(.pods)" end
  ] end
] as $nodes |
{
  nodes: $nodes,
  skippedFleets: [$fleetNames[] as $fleet |
    [$nodes[] | select(.fleet == $fleet)] as $hosts |
    select(all($hosts[]; .skipped != [])) |
    {fleet: $fleet, hosts: [$hosts[] | {name, skipped}]}],
  ready: all($nodes[]; .failed == [])
}
