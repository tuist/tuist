#!/usr/bin/env bash
# Restarts Pulse datanodes onto the StatefulSet's update revision one at a
# time without taking their regions offline. Before each restart it moves the
# datanode's leader regions to the other datanodes with ADMIN migrate_region
# (the WAL is in Kafka and the data in object storage, so a move only flushes
# and reopens), lowers the StatefulSet partition to that datanode, waits for it
# to come back Ready, and moves the same regions back, so placement is
# unchanged afterwards.
#
# Acts only where the chart holds the StatefulSet at partition = replicas
# (cluster.datanode.drainedRolloutEnvironments); elsewhere it exits and the
# StatefulSet rolls itself. Datanodes already on the update revision are
# skipped, so a rerun resumes a failed rollout. It ends holding the partition
# again, so later template changes wait for the next run.
#
# `pulse-datanode-rollout.sh rebalance` moves no datanode onto a new revision.
# It spreads leader regions so each datanode holds a similar share of the
# stored bytes (SST plus memtable). Restarts here keep placement, but region
# failover after an unplanned stop never moves regions back, so placement
# drifts toward the datanodes that stayed up: on 2026-11-16 production's
# datanode-0 led nothing while datanode-2 led the metric, logs and most trace
# regions. While the fullest and emptiest datanode differ by more than a
# quarter of the mean, it moves the fullest datanode's region closest to half
# that gap to the emptiest one.
set -euo pipefail
mode=${1:-rollout}
if [[ "$mode" != rollout && "$mode" != rebalance ]]; then
  echo "usage: $0 [rollout|rebalance]" >&2
  exit 2
fi
namespace=${PULSE_NAMESPACE:-observability}
statefulset=pulse-datanode
probe=${PULSE_ROLLOUT_POD:-pulse-rollout-${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}}
# A move flushes the region and replays its WAL tail on the target.
replay_timeout=${PULSE_MIGRATION_TIMEOUT_SECONDS:-120}

k() { kubectl -n "$namespace" "$@"; }

read -r replicas partition < <(k get statefulset "$statefulset" -o json | jq -r '
  [.spec.replicas, (.spec.updateStrategy.rollingUpdate.partition // 0)] | @tsv')
if [[ "$mode" == rollout && "$partition" -lt "$replicas" ]]; then
  echo "pulse-datanode is not held (partition ${partition} of ${replicas} replicas); the StatefulSet rolls itself."
  exit 0
fi

revision() { k get statefulset "$statefulset" -o jsonpath='{.status.updateRevision}'; }
pod_current() {
  k get pod "$statefulset-$1" -o json 2>/dev/null | jq -e --arg revision "$(revision)" '
    .metadata.deletionTimestamp == null and
    .metadata.labels["controller-revision-hash"] == $revision and
    any(.status.conditions[]?; .type == "Ready" and .status == "True")' > /dev/null
}
stale=()
if [[ "$mode" == rollout ]]; then
  for ((ordinal = replicas - 1; ordinal >= 0; ordinal--)); do
    pod_current "$ordinal" || stale+=("$ordinal")
  done
  if [[ ${#stale[@]} -eq 0 ]]; then
    echo "Every datanode runs revision $(revision)."
    exit 0
  fi
fi

# SQL goes through a probe pod that mounts the pilot login, as the smoke
# probes do, so the credential never reaches this runner.
cleanup() { k delete pod "$probe" --ignore-not-found --wait=false > /dev/null 2>&1 || true; }
trap cleanup EXIT
# A deployment runs this script more than once with the same probe name, and
# the previous run deletes its probe without waiting.
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

# Prints the result rows of one statement as JSON arrays, one per line.
sql() {
  # shellcheck disable=SC2016 # Expanded by the probe's shell, not this one.
  k exec "$probe" -- sh -c '
    curl -sS --fail-with-body --max-time 60 -u "pilot:$(sed -n "s/^pilot=//p" /auth/passwd)" \
      -H "X-Pulse-DB-Name: public" --data-urlencode "sql=$1" \
      "http://pulse.observability:4000/v1/sql?db=public"' sh "$1" |
    jq -c '.output[0].records.rows[]'
}

# Physical regions only: region_peers also lists every metric-engine logical
# table under its physical table's route, with region IDs that do not exist.
leaders() {
  sql "SELECT p.region_id FROM information_schema.region_peers p
    JOIN information_schema.tables t ON p.table_catalog = t.table_catalog
      AND p.table_schema = t.table_schema AND p.table_name = t.table_name
    WHERE p.is_leader = 'Yes' AND p.peer_id = $1
      AND t.create_options NOT LIKE '%on_physical_table=%'
    ORDER BY p.region_id" | jq -r '.[0]'
}
leader_of() {
  sql "SELECT peer_id FROM information_schema.region_peers
    WHERE region_id = $1 AND is_leader = 'Yes'" | jq -r '.[0]' | head -n 1
}

# Moves one region and waits for the procedure. Submission is retried while
# the target is not yet accepting regions (it just restarted).
migrate() {
  local region=$1 from=$2 to=$3 started=$SECONDS deadline=$((SECONDS + 300)) pid state
  while :; do
    if pid=$(sql "ADMIN migrate_region($region, $from, $to, $replay_timeout)" 2>&1); then
      pid=$(jq -r '.[0] // empty' <<< "$pid")
      break
    fi
    if ((SECONDS >= deadline)); then
      echo "::error::Could not move region $region from datanode $from to $to: $pid"
      return 1
    fi
    sleep 5
  done
  while [[ -n "$pid" ]]; do
    state=$(sql "ADMIN procedure_state('$pid')" | jq -r '.[0]')
    case "$(jq -r .status <<< "$state")" in
      Done) break ;;
      Running|Retrying) ;;
      *) echo "::error::Moving region $region from datanode $from to $to failed: $state"; return 1 ;;
    esac
    if ((SECONDS >= deadline)); then
      echo "::error::Moving region $region from datanode $from to $to did not finish: $state"
      return 1
    fi
    sleep 2
  done
  # No procedure means there was nothing to do; either way the leader moved.
  if [[ "$(leader_of "$region")" != "$to" ]]; then
    echo "::error::Region $region is not led by datanode $to after its move."
    return 1
  fi
  echo "  region $region: datanode $from -> $to in $((SECONDS - started))s"
}

all_ready() {
  k get statefulset "$statefulset" -o json | jq -e '.status.readyReplicas == .spec.replicas' > /dev/null
}

# Reads [region_id, peer_id, bytes] rows and prints "region from to" moves.
# Each move takes a region smaller than the gap off the fullest datanode, so
# the spread shrinks every time; 32 moves bounds one run.
plan_moves() {
  jq -s -r --argjson replicas "$replicas" '
    def abs: if . < 0 then -. else . end;
    reduce range(0; 32) as $_ ({regions: map({id: .[0], peer: .[1], bytes: .[2]}), moves: []};
      if .done then . else
        .regions as $regions
        | [range(0; $replicas) as $peer
            | {peer: $peer, load: ([$regions[] | select(.peer == $peer) | .bytes] | add // 0)}] as $loads
        | ($loads | max_by(.load)) as $full | ($loads | min_by(.load)) as $empty
        | ($full.load - $empty.load) as $gap
        | ([$regions[] | select(.peer == $full.peer and .bytes > 0 and .bytes < $gap)]
            | min_by(($gap - 2 * .bytes) | abs)) as $region
        | if $gap <= ($loads | map(.load) | add) / $replicas / 4 or $region == null then .done = true
          else .moves += [[$region.id, $full.peer, $empty.peer]]
            | .regions |= map(if .id == $region.id then .peer = $empty.peer else . end)
          end
      end)
    | .moves[] | @tsv'
}

if [[ "$mode" == rebalance ]]; then
  if ! all_ready; then
    echo "::error::A datanode is not Ready; refusing to move regions."
    exit 1
  fi
  # Captured first: a failed query inside a process substitution would read as
  # "already balanced".
  rows=$(sql "SELECT p.region_id, p.peer_id,
      COALESCE(s.sst_size, 0) + COALESCE(s.memtable_size, 0)
    FROM information_schema.region_peers p
    JOIN information_schema.tables t ON p.table_catalog = t.table_catalog
      AND p.table_schema = t.table_schema AND p.table_name = t.table_name
    LEFT JOIN information_schema.region_statistics s ON s.region_id = p.region_id
    WHERE p.is_leader = 'Yes' AND t.create_options NOT LIKE '%on_physical_table=%'")
  jq -s -r --argjson replicas "$replicas" '
    "Datanode leader regions and stored bytes: " + ([range(0; $replicas) as $peer
      | [.[] | select(.[1] == $peer)] | "\($peer)=\(length)/\(map(.[2]) | add // 0)"] | join(" "))' <<< "$rows"
  if jq -s -e 'length > 0 and (map(.[2] // 0) | add) == 0' <<< "$rows" > /dev/null; then
    echo "::warning::Region statistics report no stored bytes; not rebalancing from them."
    exit 0
  fi
  mapfile -t moves < <(plan_moves <<< "$rows")
  for move in "${moves[@]}"; do
    read -r region from to <<< "$move"
    migrate "$region" "$from" "$to"
  done
  echo "Rebalanced Pulse datanodes with ${#moves[@]} region moves." | tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
  exit 0
fi

for ordinal in "${stale[@]}"; do
  if ! all_ready; then
    echo "::error::A datanode is not Ready; refusing to move regions onto it."
    exit 1
  fi
  targets=()
  for ((other = 0; other < replicas; other++)); do
    [[ "$other" -ne "$ordinal" ]] && targets+=("$other")
  done
  mapfile -t regions < <(leaders "$ordinal")
  echo "Draining datanode $ordinal: ${#regions[@]} leader regions."
  moved=()
  for index in "${!regions[@]}"; do
    target=${targets[$((index % ${#targets[@]}))]}
    migrate "${regions[$index]}" "$ordinal" "$target"
    moved+=("${regions[$index]}:$target")
  done
  left=$(leaders "$ordinal" | wc -l | tr -d ' ')
  if [[ "$left" -ne 0 ]]; then
    echo "::error::Datanode $ordinal still leads $left regions; not restarting it."
    exit 1
  fi

  echo "Restarting datanode $ordinal onto revision $(revision)."
  k patch statefulset "$statefulset" --type merge \
    -p "{\"spec\":{\"updateStrategy\":{\"rollingUpdate\":{\"partition\":$ordinal}}}}" > /dev/null
  deadline=$((SECONDS + 900))
  until pod_current "$ordinal"; do
    if ((SECONDS >= deadline)); then
      echo "::error::Datanode $ordinal did not come back Ready on the update revision."
      exit 1
    fi
    sleep 5
  done

  echo "Returning ${#moved[@]} regions to datanode $ordinal."
  for entry in "${moved[@]}"; do
    migrate "${entry%%:*}" "${entry##*:}" "$ordinal"
  done
done

# Every pod is updated, so the StatefulSet completes the rollout and advances
# currentRevision; then hold it again for the next template change.
k patch statefulset "$statefulset" --type merge \
  -p "{\"spec\":{\"updateStrategy\":{\"rollingUpdate\":{\"partition\":0}}}}" > /dev/null
deadline=$((SECONDS + 300))
until k get statefulset "$statefulset" -o json | jq -e '
    .status.currentRevision == .status.updateRevision and
    .status.updatedReplicas == .spec.replicas and .status.readyReplicas == .spec.replicas' > /dev/null; do
  if ((SECONDS >= deadline)); then
    echo "::error::pulse-datanode did not complete its rollout."
    exit 1
  fi
  sleep 5
done
k patch statefulset "$statefulset" --type merge \
  -p "{\"spec\":{\"updateStrategy\":{\"rollingUpdate\":{\"partition\":$replicas}}}}" > /dev/null
echo "Restarted datanodes ${stale[*]} onto revision $(revision) with their regions moved away first." |
  tee -a "${GITHUB_STEP_SUMMARY:-/dev/null}"
