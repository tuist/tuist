#!/usr/bin/env bash
# Offline deployment contract: Pulse telemetry and exact ServiceAccount trust.
set -euo pipefail
chart="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
for environment in staging canary production; do
  server_namespace="tuist-$environment"
  [[ "$environment" != production ]] || server_namespace=tuist
  helm template symptoms "$chart" --namespace "symptoms-$environment" \
    -f "$chart/values-$environment.yaml" -f "$chart/values-ci.yaml" |
    yq eval-all -o=json '.' | jq --slurp '.' > "$work/render.json"
  jq --exit-status --arg server_namespace "$server_namespace" '
    (.[] | select(.kind == "Deployment") | .spec.template.spec.containers[0].env |
      map({key: .name, value: .value}) | from_entries) as $env |
    ($env.SYMPTOMS_PROMETHEUS_URL == "http://pulse.observability.svc.cluster.local:4000/v1/prometheus") and
    ($env.SYMPTOMS_PROMETHEUS_USER == "dashboard") and
    ($env.SYMPTOMS_PAGING_ENABLED == "false") and
    ($env.SYMPTOMS_SERVER_NAMESPACE == $server_namespace) and
    ($env.SYMPTOMS_SERVER_SERVICE_ACCOUNT == "tuist-server") and
    (.[] | select(.kind == "ExternalSecret" and .metadata.name == "symptoms-runtime") |
      ([.spec.data[].remoteRef.key] | sort) ==
        (["PULSE_TOKEN/password", "PULSE_TOKEN/password"] | sort) and
      .spec.target.template.data.SYMPTOMS_PROMETHEUS_TOKEN == "{{ .pulse_token | trim }}") and
    (.[] | select(.kind == "ExternalSecret" and .metadata.name == "symptoms-backup-credentials") |
      .spec.dataFrom == [{extract: {key: "S3_BACKUP_CREDENTIALS"}}]) and
    ([.[] | select(.kind == "ClusterRole")] | length == 2) and
    (.[] | select(.kind == "ClusterRole" and (.metadata.name | endswith("-token-review"))) |
      .rules == [{apiGroups: ["authentication.k8s.io"], resources: ["tokenreviews"], verbs: ["create"]}]) and
    ([.. | objects | select(has("toFQDNs"))] | length == 0)
  ' "$work/render.json" > /dev/null
  if grep -Eiq 'grafana_cloud|grafana\.net|IRM_WEBHOOK|SECRET_KEY_BASE|SYMPTOMS_API_TOKEN|SYMPTOMS/api_token' "$work/render.json"; then
    echo "Unexpected cloud, IRM or session-key dependency in $environment" >&2
    exit 1
  fi
done

# Custom evaluator names and an events-reader-disabled deployment must retain
# only the independent, narrowly scoped TokenReview role and exact binding.
helm template detector "$chart" -n detector-system \
  -f "$chart/values-staging.yaml" -f "$chart/values-ci.yaml" \
  --set fullnameOverride=custom-evaluator --set eventsReader.enabled=false \
  --set tuist.namespace=custom-server --set tuist.serviceAccount=custom-server-sa |
  yq eval-all -o=json '.' | jq --slurp '.' > "$work/custom.json"
jq -e '
  ([.[] | select(.kind == "ClusterRole")] | length == 1) and
  (.[] | select(.kind == "ClusterRole") |
    .rules == [{apiGroups: ["authentication.k8s.io"], resources: ["tokenreviews"], verbs: ["create"]}]) and
  (.[] | select(.kind == "ClusterRoleBinding") |
    .subjects == [{kind: "ServiceAccount", name: "custom-evaluator", namespace: "detector-system"}] and
    .roleRef.name == "custom-evaluator-detector-system-token-review") and
  (.[] | select(.kind == "Deployment") | .spec.template.spec |
    .serviceAccountName == "custom-evaluator" and
    .automountServiceAccountToken != false and
    (.containers[0].env | map({key: .name, value: .value}) | from_entries |
      .SYMPTOMS_SERVER_NAMESPACE == "custom-server" and
      .SYMPTOMS_SERVER_SERVICE_ACCOUNT == "custom-server-sa") and
    (.volumes[] | select(.name == "tuist-symptoms-state") |
      .projected.sources == [{serviceAccountToken: {audience: "tuist-symptoms-state", expirationSeconds: 3600, path: "token"}}]))
' "$work/custom.json" > /dev/null

for missing in namespace serviceAccount; do
  if helm template symptoms "$chart" -f "$chart/values-staging.yaml" -f "$chart/values-ci.yaml" \
      --set "tuist.$missing=" > "$work/invalid" 2>&1; then
    echo "Accepted missing server principal field: $missing" >&2
    exit 1
  fi
  grep -q "tuist.$missing is required" "$work/invalid"
done

tuist="$chart/../tuist"
for environment in staging canary production; do
  namespace="tuist-$environment"
  [[ "$environment" != production ]] || namespace=tuist
  for enabled in false true; do
    helm template tuist "$tuist" -n "$namespace" \
      -f "$tuist/values-managed-common.yaml" -f "$tuist/values-managed-$environment.yaml" \
      -f "$tuist/values-ci.yaml" --set "server.symptoms.enabled=$enabled" |
      yq eval-all -o=json '.' | jq --slurp '.' > "$work/server.json"
    jq -e --argjson enabled "$enabled" '
      (.[] | select(.kind == "Deployment" and .metadata.name == "tuist-tuist-server") |
        .spec.template.spec | .serviceAccountName == "tuist-server" and
        ([.volumes[]? | select(.name == "tuist-symptoms-api")] | length == (if $enabled then 1 else 0 end)) and
        (.containers[0] |
          ([.env[] | select(.name == "TUIST_SYMPTOMS_TOKEN_PATH")] | length == (if $enabled then 1 else 0 end)) and
          ([.volumeMounts[]? | select(.name == "tuist-symptoms-api")] | length == (if $enabled then 1 else 0 end)))) and
      ([.. | objects | select(.name? == "TUIST_SYMPTOMS_TOKEN" or .secretKey? == "TUIST_SYMPTOMS_TOKEN")] | length == 0)
    ' "$work/server.json" > /dev/null
    if [[ "$enabled" == true ]]; then
      jq -e '
        .[] | select(.kind == "Deployment" and .metadata.name == "tuist-tuist-server") | .spec.template.spec |
        (.volumes[] | select(.name == "tuist-symptoms-api") |
          .projected.sources == [{serviceAccountToken: {audience: "tuist-symptoms-api", expirationSeconds: 3600, path: "token"}}]) and
        (.containers[0] |
          (.volumeMounts[] | select(.name == "tuist-symptoms-api") | .readOnly == true and .mountPath == "/var/run/secrets/tuist-symptoms-api") and
          (.env[] | select(.name == "TUIST_SYMPTOMS_TOKEN_PATH") | .value == "/var/run/secrets/tuist-symptoms-api/token"))
      ' "$work/server.json" > /dev/null
    fi
  done
  # Assert the managed overlay itself leaves sync disabled.
  yq -e '.server.symptoms.enabled == false' "$tuist/values-managed-$environment.yaml" > /dev/null
done

# Self-hosted/custom releases need neither vault wiring nor default SA names.
helm template custom "$tuist" -n custom-server -f "$tuist/values-ci.yaml" \
  -f "$tuist/values-self-hosted-ci.yaml" \
  --set server.serviceAccount.name=custom-server-sa \
  --set server.symptoms.enabled=true --set server.symptoms.url=http://detector \
  --set server.symptoms.evaluatorNamespace=detector-system \
  --set server.symptoms.evaluatorServiceAccount=custom-evaluator |
  yq eval-all -o=json '.' | jq --slurp '.' > "$work/server-custom.json"
jq -e '
  .[] | select(.kind == "Deployment" and .metadata.name == "custom-tuist-server") | .spec.template.spec |
  .serviceAccountName == "custom-server-sa" and
  (.containers[0].env | map({key: .name, value: .value}) | from_entries |
    .TUIST_SYMPTOMS_EVALUATOR_NAMESPACE == "detector-system" and
    .TUIST_SYMPTOMS_EVALUATOR_SERVICE_ACCOUNT == "custom-evaluator" and
    .TUIST_SYMPTOMS_TOKEN_PATH == "/var/run/secrets/tuist-symptoms-api/token")
' "$work/server-custom.json" > /dev/null
echo 'PASS: Pulse credentials, exact principal trust, TokenReview RBAC, projections and disabled sync'
