($fleets | split("\n")) as $fleetNames |
[.items[] |
  select(.metadata.labels["node.cluster.x-k8s.io/pool"] as $pool | $fleetNames | index($pool)) |
  select(.metadata.deletionTimestamp == null and .spec.unschedulable != true) |
  select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))] as $nodes |
all($fleetNames[]; . as $fleet | any($nodes[]; .metadata.labels["node.cluster.x-k8s.io/pool"] == $fleet)) and
all($nodes[];
  . as $node |
  .metadata.labels["tuist.dev/kata-kvm"] == "true" and
  (.status.nodeInfo.bootID // "") != "" and
  ((.metadata.annotations["tuist.dev/kata-kvm-config"] // "") | endswith(":" + $node.status.nodeInfo.bootID)) and
  ((.status.allocatable.pods // "0") | tonumber) > 0 and
  ((.status.allocatable["devices.tuist.dev/kvm"] // "0") | tonumber) >= ((.status.allocatable.pods // "0") | tonumber)
)
