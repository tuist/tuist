#!/usr/bin/env bash
# Render-only regression checks. Never use a kubeconfig or impersonate a user.
set -euo pipefail

ROOT="${ROOT:-$(git rev-parse --show-toplevel)}"
chart="$ROOT/infra/helm/pomerium"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

for env in staging canary production; do
  helm lint "$chart" -f "$chart/values-$env.yaml" \
    --set kubeImpersonator.image.tag=ci >/dev/null
  helm template pomerium-kube "$chart" --namespace pomerium \
    -f "$chart/values-$env.yaml" --set kubeImpersonator.image.tag=ci \
    | yq -o json -I0 'select(.kind != null)' | jq -s . > "$work/$env.json"

  jq -e --arg env "$env" '
    def role($name):
      [.[] | select(.kind == "ClusterRole" and .metadata.name == $name)]
      | if length == 1 then .[0] else error("missing/duplicate role: " + $name) end;
    def bindings($group):
      [.[] | select(.kind == "ClusterRoleBinding" or .kind == "RoleBinding")
       | select(any(.subjects[]?; .kind == "Group" and .name == $group))];
    def includes($value): any(.[]; . == $value or . == "*");
    def statusWriter:
      any(.rules[]?;
        (.apiGroups | includes("postgresql.cnpg.io")) and
        (.resources | any(.[]; . == "clusters/status" or . == "*/status" or . == "*")) and
        any(.verbs[]; . != "get" and . != "list" and . != "watch"));

    . as $resources |
    # Keep the complete CNPG grant narrow: parent writes, status PATCH only,
    # and existing ad-hoc backups. In particular no status UPDATE or wildcard.
    (role("tuist-edit-cnpg-write") |
      .metadata.labels["rbac.authorization.k8s.io/aggregate-to-edit"] == "true" and
      .metadata.labels["rbac.authorization.k8s.io/aggregate-to-view"] != "true" and
      (.rules | sort_by(.resources | join(","))) == ([
        {apiGroups: ["postgresql.cnpg.io"], resources: ["clusters", "poolers", "scheduledbackups"],
         verbs: ["get", "list", "watch", "update", "patch"]},
        {apiGroups: ["postgresql.cnpg.io"], resources: ["clusters/status"], verbs: ["patch"]},
        {apiGroups: ["postgresql.cnpg.io"], resources: ["backups"], verbs: ["get", "list", "watch", "create"]}
      ] | sort_by(.resources | join(",")))) and

    # No other rendered role may introduce a status mutation path.
    ([.[] | select(.kind == "ClusterRole" or .kind == "Role") | select(statusWriter) |
      .metadata.name] == ["tuist-edit-cnpg-write"]) and
    # Every extension to view remains strictly read-only.
    (all(.[] | select(.kind == "ClusterRole" and
      .metadata.labels["rbac.authorization.k8s.io/aggregate-to-view"] == "true");
      all(.rules[].verbs[]; . == "get" or . == "list" or . == "watch"))) and
    (role("tuist-view-infra-read") | any(.rules[];
      (.apiGroups | includes("postgresql.cnpg.io")) and
      (.resources | includes("clusters")) and (.verbs | index("get") != null))) and

    # Both ordinary identity groups bind only to view, in every environment.
    (all("tuist-admins", "tuist-eng";
      . as $group | $resources | bindings($group) |
      length == 1 and .[0].roleRef == {
        apiGroup: "rbac.authorization.k8s.io", kind: "ClusterRole", name: "view"
      })) and
    # Edit is reached only through the current environment write group. Staging
    # uses the same binding, with standing membership supplied by its policy.
    ([.[] | select(.kind == "ClusterRoleBinding" or .kind == "RoleBinding") |
      select(.roleRef.name == "edit")] |
      length == 1 and .[0].kind == "ClusterRoleBinding" and
      .[0].roleRef == {apiGroup: "rbac.authorization.k8s.io", kind: "ClusterRole", name: "edit"} and
      .[0].subjects == [{kind: "Group", name: ("tuist-" + $env + "-write"),
        apiGroup: "rbac.authorization.k8s.io"}]) and
    # Do not bypass aggregation with a direct binding to the CNPG role.
    (all(.[] | select(.kind == "ClusterRoleBinding" or .kind == "RoleBinding");
      .roleRef.name != "tuist-edit-cnpg-write"))
  ' "$work/$env.json" >/dev/null || {
    echo "FAIL: $env CNPG permissions or access-tier isolation changed" >&2
    exit 1
  }
  echo "PASS: $env CNPG status patch is isolated to its write tier; chart lint/render passed"
done
