# Require a current DaemonSet pod actually running the desired image on each
# usable node. Counts alone can accept a duplicate pod or a previous revision.
[.items[]
  | select(.metadata.deletionTimestamp == null and .spec.unschedulable != true)
  | select(any(.status.conditions[]?; .type == "Ready" and .status == "True"))
  | .metadata.name] as $nodes
| ($nodes | length) > 0 and all($nodes[]; . as $node |
    any($pods[0].items[];
      .metadata.deletionTimestamp == null
      and any(.metadata.ownerReferences[]?; .uid == $uid and .controller == true)
      and .spec.nodeName == $node
      and .spec.containers[0].image == $manifest[0].spec.template.spec.containers[0].image
      and .spec.runtimeClassName == $manifest[0].spec.template.spec.runtimeClassName
      and .status.phase == "Running"
      and any(.status.containerStatuses[]?; .name == "pull" and .ready == true and .state.running != null)))
