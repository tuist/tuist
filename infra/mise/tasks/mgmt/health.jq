# A missing check is not a healthy check. Require every configured listener.
def healthy_lb_target($ports):
  . as $target |
  .type == "server" and ($ports | length > 0 and all(.[];
    . as $port | any($target.health_status[]?; .listen_port == $port and .status == "healthy")
  ));

def control_plane_state:
  [.items[] | select(.metadata.labels.component | IN("kube-apiserver", "kube-controller-manager", "kube-scheduler"))] |
  if ([.[].metadata.labels.component] | unique | length) != 3 then "missing-components=false"
  else sort_by(.metadata.name) | map(
    "\(.metadata.name)=\(.metadata.uid):\(.status.containerStatuses[0].restartCount):ready=\(.status.containerStatuses[0].ready // false)"
  ) | join(" ") end;
