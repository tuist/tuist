#!/usr/bin/env bash
#MISE description="Run one step of moving ClickHouse onto the in-cluster server, as a one-off Job outside any deploy."
#USAGE arg "<env>" help="Environment (staging | canary | production)"
#USAGE arg "<step>" help="clone | backfill | parity | check-reads | enable-reads | disable-reads"
#USAGE flag "--cutoff <instant>" help="backfill only: copy rows written before this UTC instant, e.g. 2026-09-15T12:00:00Z"
#USAGE flag "--dry-run" help="Print the Job manifest without creating it"

# Runs a `Tuist.Release` ClickHouse task as its own Job, cloned from the
# server's migrate Job so it gets the deployed image, service account, secrets
# and ClickHouse settings. The Job is not part of the Helm release, so a failed
# step fails the Job and nothing else.
#
# Canary and production need an active `/elevate <env>` in Slack to create the
# Job. See infra/clickhouse/migration.md.

set -euo pipefail

readonly ENV="${usage_env:?}"
readonly STEP="${usage_step:?}"
readonly CUTOFF="${usage_cutoff:-}"
readonly DRY_RUN="${usage_dry_run:-false}"

log() { printf '\n\033[1;34m==> %s\033[0m\n' "$*"; }
err() { printf '\n\033[1;31mERROR: %s\033[0m\n' "$*" >&2; }

case "$ENV" in
  staging)    CONTEXT="tuist-k8s-staging"    ; NAMESPACE="tuist-staging" ;;
  canary)     CONTEXT="tuist-k8s-canary"     ; NAMESPACE="tuist-canary" ;;
  production) CONTEXT="tuist-k8s-production" ; NAMESPACE="tuist" ;;
  *) err "env must be one of staging|canary|production"; exit 64 ;;
esac

case "$STEP" in
  clone)         TASK="clone_clickhouse_schema" ;;
  backfill)      TASK="backfill_clickhouse" ;;
  parity)        TASK="check_clickhouse_parity" ;;
  check-reads)   TASK="check_clickhouse_reads" ;;
  enable-reads)  TASK="enable_clickhouse_bare_metal_reads" ;;
  disable-reads) TASK="disable_clickhouse_bare_metal_reads" ;;
  *) err "step must be one of clone|backfill|parity|check-reads|enable-reads|disable-reads"; exit 64 ;;
esac

if [[ "$STEP" == "backfill" ]]; then
  if [[ ! "$CUTOFF" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$ ]]; then
    err "backfill needs --cutoff as a UTC instant, e.g. --cutoff 2026-09-15T12:00:00Z"
    exit 64
  fi
elif [[ -n "$CUTOFF" ]]; then
  err "--cutoff only applies to backfill"
  exit 64
fi

JOB_NAME="clickhouse-${STEP}-$(date -u +%Y%m%d-%H%M%S)"
WORKDIR="$(mktemp -d)"
readonly JOB_NAME WORKDIR
trap 'rm -rf "$WORKDIR"' EXIT

k() { kubectl --context "$CONTEXT" -n "$NAMESPACE" "$@"; }

if ! k get job tuist-tuist-server-migrate -o json > "$WORKDIR/migrate-job.json"; then
  err "Could not read the server's migrate Job (tuist-tuist-server-migrate) in $NAMESPACE. Every server deploy recreates it."
  exit 1
fi

if ! jq -e '.spec.template.spec.containers | length == 1' "$WORKDIR/migrate-job.json" > /dev/null; then
  err "The migrate Job does not have exactly one container, so there is no single container to run the task in."
  exit 1
fi

if ! jq -e '.spec.template.spec.containers[0].env // [] | any(.name == "TUIST_CLICKHOUSE_BARE_METAL_URL")' "$WORKDIR/migrate-job.json" > /dev/null; then
  err "$ENV has no in-cluster ClickHouse configured for the server, so $STEP has nothing to run against."
  exit 1
fi

# The deadline only bounds a hung task: a backfill cut short resumes from its
# ledger on the next run. Finished Jobs stay a week so their logs can be read.
jq \
  --arg name "$JOB_NAME" \
  --arg namespace "$NAMESPACE" \
  --arg step "$STEP" \
  --arg task "Tuist.Release.$TASK" \
  --arg cutoff "$CUTOFF" \
  '{"app.kubernetes.io/name": "tuist", "app.kubernetes.io/component": "clickhouse-migration", "tuist.dev/clickhouse-migration-step": $step} as $labels
  | {
      apiVersion: "batch/v1",
      kind: "Job",
      metadata: {name: $name, namespace: $namespace, labels: $labels},
      spec: {
        backoffLimit: 0,
        activeDeadlineSeconds: 86400,
        ttlSecondsAfterFinished: 604800,
        template: {
          metadata: {labels: $labels},
          spec: (.spec.template.spec
            | .restartPolicy = "Never"
            | .containers[0] |= (
                .name = "clickhouse-migration"
                | .command = ["/app/bin/tuist", "eval", $task]
                | del(.args)
                | .env = ([(.env // [])[] | select(.name != "TUIST_CLICKHOUSE_BACKFILL_CUTOFF")]
                    + (if $cutoff == "" then [] else [{name: "TUIST_CLICKHOUSE_BACKFILL_CUTOFF", value: $cutoff}] end))
              ))
        }
      }
    }' "$WORKDIR/migrate-job.json" > "$WORKDIR/job.json"

if [[ "$DRY_RUN" == "true" ]]; then
  cat "$WORKDIR/job.json"
  exit 0
fi

log "Running Tuist.Release.$TASK on $ENV as Job $JOB_NAME ($(jq -r '.spec.template.spec.containers[0].image' "$WORKDIR/job.json"))"

if ! k create -f "$WORKDIR/job.json"; then
  err "Could not create the Job. On canary and production that needs an active elevation: /elevate $ENV <duration> <intent> in Slack."
  exit 1
fi

readonly RESUME="kubectl --context $CONTEXT -n $NAMESPACE logs -f job/$JOB_NAME"
trap 'printf "\nStopped following. The Job keeps running. Follow it again with:\n  %s\n" "$RESUME"; exit 130' INT

log "Waiting for the pod to start"
phase=""
for _ in $(seq 1 120); do
  phase="$(k get pods -l "job-name=$JOB_NAME" -o jsonpath='{.items[0].status.phase}' 2> /dev/null || true)"
  [[ -n "$phase" && "$phase" != "Pending" ]] && break
  sleep 5
done

if [[ -z "$phase" || "$phase" == "Pending" ]]; then
  err "The pod has not started after 10 minutes. The Job is still there. Follow it with: $RESUME"
  exit 1
fi

k logs -f "job/$JOB_NAME" -c clickhouse-migration || true

for _ in $(seq 1 24); do
  conditions="$(k get job "$JOB_NAME" -o jsonpath='{range .status.conditions[?(@.status=="True")]}{.type} {end}')"
  case "$conditions" in
    *Complete*) log "$STEP finished on $ENV"; exit 0 ;;
    *Failed*) err "$STEP failed on $ENV. The log above has the reason."; exit 1 ;;
  esac
  sleep 5
done

err "The log stream ended before the Job finished. Follow it again with: $RESUME"
exit 1
