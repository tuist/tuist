#!/usr/bin/env bash
# Drives one sandboxd daemon through create -> exec -> pause -> resume -> exec
# -> delete over its admin API from inside the cluster, so the substrate can
# be validated on a staging node without the server or an Anthropic
# environment. Creates a Job in the sandboxes namespace labelled as an admin
# client (the NetworkPolicy admits that label) and prints its log.
#
#   infra/sandboxd/hack/validate-job.sh <kubectl-context> [namespace] [admin-url]
set -euo pipefail

CONTEXT="${1:?kubectl context}"
NAMESPACE="${2:-tuist-sandboxes}"
ADMIN_URL="${3:-http://tuist-tuist-sandboxd-admin.${NAMESPACE}.svc.cluster.local:9471}"
JOB="sandboxd-validate-$(date +%s)"

kubectl --context "$CONTEXT" -n "$NAMESPACE" apply -f - <<YAML
apiVersion: batch/v1
kind: Job
metadata:
  name: ${JOB}
spec:
  backoffLimit: 0
  ttlSecondsAfterFinished: 3600
  template:
    metadata:
      labels:
        tuist.dev/sandboxd-admin-client: "true"
    spec:
      restartPolicy: Never
      tolerations:
        - key: tuist.dev/runner-tier
          operator: Exists
          effect: NoSchedule
      containers:
        - name: validate
          image: alpine:3.22
          env:
            - name: ADMIN_URL
              value: "${ADMIN_URL}"
          command: ["/bin/sh", "-ec"]
          args:
            - |
              apk add --no-cache curl jq >/dev/null
              api() { curl -sS -m 300 -H 'content-type: application/json' "\$@"; }
              t() { date +%s%3N; }
              echo "== templates"; api "\$ADMIN_URL/v1/templates" | jq -c .
              echo "== create"; s=\$(t)
              id=\$(api -X POST "\$ADMIN_URL/v1/sandboxes" -d '{"template":"default","vcpus":2,"memory_mb":4096,"workspace_gb":10,"hostname":"sbx-validate"}' | tee /dev/stderr | jq -r .id)
              echo "create_ms=\$(( \$(t) - s )) id=\$id"
              echo "== exec 1"
              api -X POST "\$ADMIN_URL/v1/sandboxes/\$id/exec" -d '{"cmd":["/bin/bash","-lc","uname -a; id; hostname; date -u; df -h /workspace; echo hello > /workspace/marker; nohup sleep 3600 >/dev/null 2>&1 & echo bg=\$!"],"timeout_ms":60000}' | jq .
              echo "== pause"; s=\$(t)
              api -X POST "\$ADMIN_URL/v1/sandboxes/\$id/pause" | jq -c .
              echo "pause_ms=\$(( \$(t) - s ))"
              sleep 5
              echo "== resume"; s=\$(t)
              api -X POST "\$ADMIN_URL/v1/sandboxes/\$id/resume" | jq -c .
              echo "resume_ms=\$(( \$(t) - s ))"
              echo "== exec 2 (state survives pause?)"
              api -X POST "\$ADMIN_URL/v1/sandboxes/\$id/exec" -d '{"cmd":["/bin/bash","-lc","date -u; cat /workspace/marker; pgrep -a sleep; curl -sS -m 10 -o /dev/null -w \"github %{http_code}\\n\" https://api.github.com"],"timeout_ms":60000}' | jq .
              echo "== delete"
              api -X POST "\$ADMIN_URL/v1/sandboxes/\$id/delete" | jq -c .
              echo "== list"; api "\$ADMIN_URL/v1/sandboxes" | jq -c .
YAML

echo "waiting for job ${JOB}"
kubectl --context "$CONTEXT" -n "$NAMESPACE" wait --for=condition=complete --timeout=900s "job/${JOB}" || true
kubectl --context "$CONTEXT" -n "$NAMESPACE" logs "job/${JOB}"
