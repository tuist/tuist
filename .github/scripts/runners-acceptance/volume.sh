#!/usr/bin/env bash
# Round-trips cache volumes between two jobs on canary's one rack host: two
# custom volumes and the managed Xcode and module cache volumes.
#
#   attach   attaches every volume through the in-repo action sources and
#            requires a real APFS mount. An unavailable volume falls back to a
#            job-local directory and the job still succeeds, so a fallback
#            fails here. The one exception is a volume refused because GitHub
#            had not yet reported which job the runner runs: that is a GitHub
#            webhook delay, not a regression, so the volume is reported as
#            inconclusive and left out of the checks. Writes the inconclusive
#            volumes to the step's `pending` output.
#   seed     writes this run's id into `probe`, `xcode` and `module`, and
#            writes `static` only when it holds nothing, so after the first
#            write that volume never changes.
#   payload  the seed job's last step: writes PAYLOAD_MB of random data into
#            `probe`, so the host's incomplete-image check and the guest's
#            detach flush handle a large final write.
#   verify   runs in a later job and requires every volume to be a saved copy
#            (cache-hit=true) holding exactly what the seed job wrote. A copy
#            an overlapping probe run saved over this one is inconclusive.
#
# Usage: volume.sh attach|seed|payload|verify. Env for verify: SEED_PENDING,
# the seed job's inconclusive volumes; GH_TOKEN and VOLUME_LABEL, to find the
# seed jobs of this run and of the run that saved a copy.
set -euo pipefail
source "$(dirname "$0")/lib.sh"

mode="${1:-}"
run="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-0}"
actions="$(cd "$(dirname "$0")/../../actions" && pwd)"
state="${RUNNER_TEMP:-${TMPDIR:-/tmp}}/runners-acceptance-volumes"
marker=.runners-acceptance-run
PAYLOAD_MB=256
# errExecutionPending in infra/linux-runner-image/cmd/tuist-cache-volume/main.go.
PENDING_PATTERN='GitHub had not yet reported which job this runner is running'

# name, kind, key or managed cache, path (managed caches report theirs).
VOLUMES="probe custom runners-acceptance-probe ${HOME}/runners-acceptance-volume
static custom runners-acceptance-static ${HOME}/runners-acceptance-static
xcode managed xcode -
module managed module -"

label() {
  case "$1" in
    probe) echo "custom volume runners-acceptance-probe" ;;
    static) echo "unchanged custom volume runners-acceptance-static" ;;
    xcode) echo "managed Xcode cache volume (tuist/xcode-cache)" ;;
    module) echo "managed module cache volume (tuist/module-cache)" ;;
  esac
}

static_content() {
  yes 'Tuist runners acceptance: written once, never changed.' 2>/dev/null | head -c 8388608 || true
}

volume_path() { cat "${state}/$1.path"; }

pending_here() { [ -e "${state}/$1.pending" ]; }

inconclusive() {
  local name="$1" reason="$2"
  echo "::warning title=Cache volumes inconclusive::$(label "${name}"): ${reason}, so its round trip is unchecked"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf -- '- Inconclusive: %s, %s\n' "$(label "${name}")" "${reason}" >> "${GITHUB_STEP_SUMMARY}"
  fi
}

pending_reason() { echo "GitHub had not yet reported which job the runner runs when $1 attached it"; }

# Prints, in epoch seconds, when a run attempt's seed job (the macOS job on the
# volume label) started and when the host may still have been saving its
# volumes: PUBLISH_SECONDS after the job ended, which volume-wait allows for.
# Prints nothing when the run has no seed job.
PUBLISH_SECONDS=120
seed_window() {
  gh api "repos/${GITHUB_REPOSITORY}/actions/runs/$1/attempts/$2/jobs?per_page=100" --jq \
    "[.jobs[] | select((.name | startswith(\"macOS \")) and (.name | endswith(\" (${VOLUME_LABEL})\")) and (.name | startswith(\"macOS cache volume\") | not))][0] // empty | \"\(.started_at // \"2100-01-01T00:00:00Z\" | fromdateiso8601) \((.completed_at // \"2100-01-01T00:00:00Z\" | fromdateiso8601) + ${PUBLISH_SECONDS})\""
}

# Sets device to the disk the volume is mounted from.
require_mount() {
  local name="$1" target="$2" filesystem
  [ -L "${target}" ] || fail "Cache volumes" "$(label "${name}"): ${target} is not a symlink to a mounted volume, so the job fell back to a job-local directory"
  device="$(df -P "${target}/" | awk 'NR == 2 { print $1 }')"
  case "${device}" in
    /dev/disk*) ;;
    *) fail "Cache volumes" "$(label "${name}"): ${target} is on ${device}, not a disk image, so the job fell back to a job-local directory" ;;
  esac
  filesystem="$(diskutil info -plist "${device}" | plutil -extract FilesystemType raw -)"
  [ "${filesystem}" = apfs ] || fail "Cache volumes" "$(label "${name}"): ${target} is ${filesystem}, not APFS"
}

attach_volume() {
  local name="$1" kind="$2" ref="$3" target="$4"
  local log="${state}/${name}.log" output="${state}/${name}.output" env_file="${state}/${name}.env" status=0
  : > "${output}"
  : > "${env_file}"
  case "${kind}" in
    custom)
      GITHUB_OUTPUT="${output}" TUIST_VOLUME_KEY="${ref}" TUIST_VOLUME_PATH="${target}" TUIST_VOLUME_SIZE="" \
        TUIST_ACTION_PATH="${actions}/cache-volume" bash "${actions}/cache-volume/attach.sh" > "${log}" 2>&1 || status=$?
      ;;
    managed)
      command -v tuist-runner-cache > /dev/null 2>&1 ||
        fail "Cache volumes" "$(label "${name}"): this runner has no tuist-runner-cache, so tuist/${ref}-cache is a no-op"
      GITHUB_OUTPUT="${output}" GITHUB_ENV="${env_file}" \
        bash "${actions}/${ref}-cache/activate.sh" "${ref}" > "${log}" 2>&1 || status=$?
      ;;
  esac
  # Replayed so the client's annotations still reach the job.
  cat "${log}"
  [ "${status}" -eq 0 ] || fail "Cache volumes" "$(label "${name}"): attaching exited ${status}"

  if grep -qF "${PENDING_PATTERN}" "${log}"; then
    : > "${state}/${name}.pending"
    inconclusive "${name}" "$(pending_reason "this job")"
    return 0
  fi

  if [ "${kind}" = managed ]; then
    case "${ref}" in
      xcode) target="$(sed -n 's/^TUIST_COMPILATION_CACHE_CAS_PATH=//p' "${env_file}" | tail -n 1)" ;;
      module) target="$(sed -n 's/^TUIST_XDG_CACHE_HOME=//p' "${env_file}" | tail -n 1)" ;;
    esac
    [ -n "${target}" ] || fail "Cache volumes" "$(label "${name}"): tuist/${ref}-cache exported no cache location, so the runner did not enable the cache"
  fi
  printf '%s' "${target}" > "${state}/${name}.path"
  sed -n 's/^cache-hit=//p' "${output}" | tail -n 1 > "${state}/${name}.hit"
  require_mount "${name}" "${target}"
  pass "Attached the $(label "${name}") at ${target} on ${device} (cache-hit=$(cat "${state}/${name}.hit"))"
}

# The saved copy must carry this run's id or a later one: overlapping probe
# runs share the volumes, and run ids and attempts only grow, so a later id
# still proves publication works. An older one is stale, unless that run's seed
# job, saves included, overlapped this run's: both cloned the same saved copy
# and the host turns down whichever saves second ("cache generation advanced"),
# so the round trip is inconclusive and marked `.raced`.
require_run() {
  local name="$1" saved our_start our_end their_start their_end
  saved="$(cat "$(volume_path "${name}")/${marker}" 2>/dev/null || echo none)"
  if [ "${saved}" = "${run}" ]; then
    return 0
  elif [[ "${saved}" =~ ^([0-9]+)-([0-9]+)$ ]] && [[ "${run}" =~ ^([0-9]+)-([0-9]+)$ ]]; then
    if [ "${saved%-*}" -gt "${run%-*}" ] || { [ "${saved%-*}" -eq "${run%-*}" ] && [ "${saved##*-}" -gt "${run##*-}" ]; }; then
      echo "$(label "${name}"): attached the copy saved by run ${saved}, which seeded after this one"
      return 0
    fi
    read -r our_start our_end <<< "$(seed_window "${run%-*}" "${run##*-}")"
    read -r their_start their_end <<< "$(seed_window "${saved%-*}" "${saved##*-}")"
    if [ -n "${their_start}" ] && [ "${their_start}" -lt "${our_end}" ] && [ "${their_end}" -gt "${our_start}" ]; then
      : > "${state}/${name}.raced"
      inconclusive "${name}" "run ${saved}'s seed job overlapped this run's: both cloned the same saved copy and the host kept run ${saved}'s save"
      return 0
    fi
  fi
  fail "Cache volumes" "$(label "${name}"): the verify job attached the copy saved by run ${saved}, which predates this run's seed job (${run}). The host withheld the seed job's save (an incomplete image, a failed guest detach or a refused save) or had not published it before the verify job attached; the seed job's teardown on the host says which"
}

require_entries() {
  local name="$1" expected="$2" actual
  actual="$(cd "$(volume_path "${name}")" && find . -mindepth 1 -maxdepth 1 | sed "s|^\./||" | LC_ALL=C sort | tr "\n" " ")"
  [ "${actual}" = "${expected}" ] || fail "Cache volumes" "$(label "${name}"): the saved copy holds '${actual% }', not exactly the seed job's '${expected% }'"
}

mkdir -p "${state}"

case "${mode}" in
  attach)
    while read -r name kind ref target; do
      attach_volume "${name}" "${kind}" "${ref}" "${target}"
    done <<< "${VOLUMES}"
    pending=""
    while read -r name _; do
      if pending_here "${name}"; then
        pending="${pending:+${pending} }${name}"
      fi
    done <<< "${VOLUMES}"
    echo "pending=${pending}" >> "${GITHUB_OUTPUT:-/dev/null}"
    ;;
  seed)
    while read -r name _; do
      if pending_here "${name}"; then
        continue
      fi
      path="$(volume_path "${name}")"
      case "${name}" in
        probe)
          find "${path}/" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
          printf "%s" "${run}" > "${path}/${marker}"
          pass "Emptied the $(label "${name}") and seeded it with run ${run}"
          ;;
        xcode | module)
          printf '%s' "${run}" > "${path}/${marker}"
          pass "Seeded the $(label "${name}") with run ${run}"
          ;;
        static)
          if [ -e "${path}/content" ]; then
            pass "Left the $(label "${name}") unchanged"
          else
            static_content > "${path}/content"
            pass "Wrote the $(label "${name}") for the first time (cache-hit=$(cat "${state}/${name}.hit"))"
          fi
          ;;
      esac
    done <<< "${VOLUMES}"
    sync
    ;;
  payload)
    if pending_here probe; then
      echo "The $(label probe) is inconclusive; no payload to write."
      exit 0
    fi
    path="$(volume_path probe)"
    started=$(date +%s)
    rm -f "${path}/payload" "${path}/payload.sha256"
    head -c $((PAYLOAD_MB * 1048576)) /dev/urandom > "${path}/payload"
    (cd "${path}" && shasum -a 256 payload > payload.sha256)
    sync
    pass "Wrote a ${PAYLOAD_MB} MB payload into the $(label probe) in $(($(date +%s) - started)) s"
    ;;
  verify)
    while read -r name _; do
      case " ${SEED_PENDING:-} " in
        *" ${name} "*)
          inconclusive "${name}" "$(pending_reason "the seed job")"
          continue
          ;;
      esac
      if pending_here "${name}"; then
        continue
      fi
      [ "$(cat "${state}/${name}.hit")" = true ] ||
        fail "Cache volumes" "$(label "${name}"): the verify job attached no saved copy (cache-hit=$(cat "${state}/${name}.hit"))"
      path="$(volume_path "${name}")"
      case "${name}" in
        probe)
          require_run probe
          [ -e "${state}/probe.raced" ] && continue
          require_entries probe "${marker} payload payload.sha256 "
          (cd "${path}" && shasum -a 256 -c -s payload.sha256) ||
            fail "Cache volumes" "$(label probe): the saved ${PAYLOAD_MB} MB payload, the seed job's last write, does not match its checksum, so the host saved an image that lost writes"
          ;;
        static)
          require_entries static "content "
          [ "$(shasum -a 256 < "${path}/content" | awk '{ print $1 }')" = "$(static_content | shasum -a 256 | awk '{ print $1 }')" ] ||
            fail "Cache volumes" "$(label static): the saved copy's content changed, though no job writes it after the first"
          ;;
        xcode | module)
          require_run "${name}"
          [ -e "${state}/${name}.raced" ] && continue
          ;;
      esac
      pass "The $(label "${name}") holds the seed job's saved copy"
    done <<< "${VOLUMES}"
    ;;
  *)
    echo "usage: volume.sh attach|seed|payload|verify" >&2
    exit 2
    ;;
esac
