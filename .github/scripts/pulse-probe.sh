# Sourced by the Pulse operations scripts. SQL goes through a probe pod that
# mounts the pilot login, as the smoke probes do, so the credential never
# reaches the runner.
namespace=${PULSE_NAMESPACE:-observability}
probe=${PULSE_ROLLOUT_POD:-pulse-rollout-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}}

k() { kubectl -n "$namespace" "$@"; }

# Creates the probe and deletes it when the calling script exits.
start_probe() {
  trap 'k delete pod "$probe" --ignore-not-found --wait=false > /dev/null 2>&1 || true' EXIT
  # A deployment runs these scripts more than once with the same probe name,
  # and the previous run deletes its probe without waiting.
  k delete pod "$probe" --ignore-not-found --wait=true --timeout=120s > /dev/null
  jq -n --arg name "$probe" '
    {apiVersion:"v1",kind:"Pod",metadata:{name:$name,namespace:"observability"},spec:{
      restartPolicy:"Never",activeDeadlineSeconds:5400,automountServiceAccountToken:false,
      nodeSelector:{"node.cluster.x-k8s.io/pool":"general"},
      securityContext:{runAsNonRoot:true,runAsUser:65532,fsGroup:65532,seccompProfile:{type:"RuntimeDefault"}},
      volumes:[{name:"auth",secret:{secretName:"pulse-auth",defaultMode:288}}],
      containers:[{name:"probe",image:"curlimages/curl:8.12.1",command:["sleep","5400"],
        securityContext:{allowPrivilegeEscalation:false,readOnlyRootFilesystem:true,capabilities:{drop:["ALL"]}},
        volumeMounts:[{name:"auth",mountPath:"/auth",readOnly:true}],
        resources:{requests:{cpu:"10m",memory:"16Mi"},limits:{memory:"64Mi"}}}]}}
  ' | k create -f - > /dev/null
  k wait --for=condition=Ready "pod/$probe" --timeout=120s > /dev/null
}

# Prints the result rows of one statement as JSON arrays, one per line.
# PULSE_SQL_TIMEOUT_SECONDS bounds the request on both ends (default 60); the
# frontend otherwise stops statements after its 30s HTTP timeout.
sql() {
  # shellcheck disable=SC2016 # Expanded by the probe's shell, not this one.
  k exec "$probe" -- sh -c '
    curl -sS --fail-with-body --max-time "$2" -u "pilot:$(sed -n "s/^pilot=//p" /auth/passwd)" \
      -H "X-Pulse-DB-Name: public" -H "X-Pulse-Timeout: $2s" --data-urlencode "sql=$1" \
      "http://pulse.observability:4000/v1/sql?db=public"' sh "$1" "${PULSE_SQL_TIMEOUT_SECONDS:-60}" |
    jq -c '.output[0].records.rows[]?'
}
