#!/usr/bin/env bash
#MISE description="Test management control-plane readiness and load-balancer health predicates without credentials"
set -euo pipefail
cd "$(git rev-parse --show-toplevel)/infra/mise/tasks/mgmt"

jq -L . -ne '
  include "health";
  def check($ok; $message): if $ok then . else error($message) end;
  {type: "server", server: {id: 1}, health_status: [{listen_port: 6443, status: "healthy"}]} |
  check(healthy_lb_target([6443]); "healthy target rejected") |
  check((healthy_lb_target([6443, 8443]) | not); "missing listener accepted") |
  check((healthy_lb_target([]) | not); "empty ports accepted") |
  check((.health_status = [] | healthy_lb_target([6443]) | not); "empty health accepted") |
  check((del(.health_status) | healthy_lb_target([6443]) | not); "missing health accepted") |
  check((.health_status[0].status = "unknown" | healthy_lb_target([6443]) | not); "unknown health accepted") |
  check((.health_status[0].status = "unhealthy" | healthy_lb_target([6443]) | not); "unhealthy target accepted") |
  check((.type = "ip" | healthy_lb_target([6443]) | not); "non-server target accepted") |
  . as $healthy |
  {targets: [$healthy, ($healthy | .server.id = 2 | .health_status = [])]} |
  check((any(.targets[]; .server.id != 1 and healthy_lb_target([6443])) | not); "last healthy target removable") |
  check(any(.targets[]; .server.id != 2 and healthy_lb_target([6443])); "healthy sibling ignored") |
  true
'

jq -L . -ne '
  include "health";
  def check($ok; $message): if $ok then . else error($message) end;
  {items: (["kube-apiserver", "kube-controller-manager", "kube-scheduler"] | map({
    metadata: {name: ., uid: ., labels: {component: .}},
    status: {containerStatuses: [{restartCount: 0, ready: true}]}
  }))} |
  check((control_plane_state | contains("=false") | not); "healthy control plane rejected") |
  . as $healthy |
  check((.items |= reverse | control_plane_state) == ($healthy | control_plane_state); "API list order resets window") |
  check((.items[0].status.containerStatuses[0].ready = false | control_plane_state | contains("=false")); "unready pod accepted") |
  check((del(.items[0].status.containerStatuses) | control_plane_state | contains("=false")); "missing status accepted") |
  check((.items = .items[0:2] | control_plane_state | contains("=false")); "missing component accepted") |
  check((.items = [] | control_plane_state | contains("=false")); "empty control plane accepted") |
  check((.items[0].status.containerStatuses[0].restartCount = 1 | control_plane_state) != ($healthy | control_plane_state); "restart did not reset window") |
  check((.items[0].metadata.uid = "replacement" | control_plane_state) != ($healthy | control_plane_state); "pod replacement did not reset window") |
  true
'
yq ea -o=json '.' ../../../k8s/mgmt/controller-pdbs.yaml | jq -se '
  length == 6 and all(.[];
    .apiVersion == "policy/v1" and .spec.minAvailable == 1 and (.spec.selector.matchLabels | length > 0)
  )'
echo "Management health predicates and disruption budgets passed"
