#!/bin/bash
# POSTs to the Tuist server's runner dispatch endpoint with the
# Pod's projected ServiceAccount token as the Bearer credential
# and execs the GitHub Actions runner with the returned JIT config.
#
# Files (staged by tart-kubelet, read-mounted at
# `/Volumes/My Shared Files/env/`):
#   tuist.env  — env vars from the Pod spec (TUIST_RUNNER_DISPATCH_URL,
#                TUIST_RUNNER_POOL, TUIST_RUNNER_POD_NAME)
#   sa_token   — Pod's projected SA token, minted via TokenRequest
#
# Server contract:
#   POST <url> with header `Authorization: Bearer <sa_token>`
#     200 carrying ONE provider's credential set. GitHub sends
#       `encoded_jit_config`; Buildkite sends `buildkite_acquisition_token`
#       plus `buildkite_job_uuid`, and the agent launched below is chosen
#       on which is present.
#     200 with body { encoded_jit_config: "...", pool: "...", owner: "...",
#                      cache_endpoint_url?: "...", cache_signing_grant?: "..." }
#       -> export TUIST_CACHE_ENDPOINT when cache_endpoint_url is present,
#          export TUIST_CACHE_SIGNING_GRANT when cache_signing_grant is present,
#          then exec ./run.sh --jitconfig <jit> --disableupdate
#     204  -> no work yet, keep polling
#     401  -> auth failed, abort (the SA was likely GCed already)
#     403  -> server-side authz refused the SA, abort
#     5xx  -> transient; sleep + retry
#
# Once the runner exits, the EXIT trap halts the VM. tart-kubelet
# observes the exit and transitions the Pod to Succeeded; the
# runners-controller's PodGC reaper deletes the assignment +
# cascades Pod + SA.

set -uo pipefail

LOG=/var/log/tuist-runner/poll.log
exec >>"${LOG}" 2>&1

# Host-shared status directory. Defined before the EXIT trap is armed,
# because the trap reports through it and the aborts worth reporting
# (missing /etc/tuist.env, missing or empty SA token) all run early.
STATUS_SHARE="/Volumes/My Shared Files/status"

# publish_runner_log copies this script's log into the status share on
# the way out, so it survives the VM. `${LOG}` lives inside the ephemeral
# guest and dies with it, which is why a runner that halts without ever
# taking its job leaves an exit code and nothing that explains it: the
# EXIT trap reports 0 both for a finished job and for a runner that gave
# up, so the code alone cannot separate them. tart-kubelet re-emits a
# bounded tail of this file to its own stdout before teardown deletes the
# share, and that reaches Loki via the host log shipper.
#
# A copy from the trap rather than a `tee` alongside `${LOG}`. A tee is
# the obvious shape and the wrong one here: it would still be running
# when the trap fires, so its buffered tail can land after this copy and
# duplicate it, and bash 3.2 (what /bin/bash is on macOS) does not report
# a process substitution's PID in `$!`, so there is no portable way to
# reap it first. Copying after the last line is written is exact.
#
# The cost is that a guest killed without running its trap publishes
# nothing — but that case already reaches the host distinguishably, as
# `TartRunExited` rather than a reported exit code.
#
# Guarded on the share being mounted, exactly like report_runner_exit:
# pools with the cache-volume feature off have no share, and there the
# guest keeps logging only to `${LOG}`.
publish_runner_log() {
  [ -d "${STATUS_SHARE:-}" ] || return 0
  cp "${LOG}" "${STATUS_SHARE}/runner.log" 2>/dev/null || true
}

# report_runner_exit hands this script's exit code to the host through
# the writable status share, for tart-kubelet to publish as the Pod's
# terminated container state.
#
# It is the ONLY way that code leaves the guest. The EXIT trap below
# halts the VM on every path, clean or not, so `tart run` always exits
# zero and the host cannot otherwise tell a finished job from a runner
# that died on boot — every macOS runner death reads as Succeeded with
# no exit code, no reason, and no log. (Linux runners get this for free:
# the container runtime records the real terminated state.)
#
# Reported from inside the trap rather than after `wait` on the runner
# so it also covers the paths that never reach a runner at all: the auth
# aborts, the missing-file exits, an errexit anywhere above. Those are
# exactly the deaths that are hardest to explain after the fact.
#
# Guarded on the share being mounted, which it is not on hosts with the
# cache-volume feature off; an unreported exit degrades to a Pod with no
# exit code rather than failing the halt.
report_runner_exit() {
  [ -d "${STATUS_SHARE:-}" ] || return 0
  printf '%s' "${1}" >"${STATUS_SHARE}/runner-rc" 2>/dev/null || true
}

# report_heartbeat stamps this script's liveness into the status share for
# tart-kubelet to publish on the Pod.
#
# tart-kubelet implements no container probes, so a macOS Pod reads
# Running/Ready for as long as its VM process is up — whether or not
# anything inside the guest is still polling for work. The
# runners-controller has no other signal on this platform and keeps
# counting such a Pod as warm capacity it can never actually use. Linux
# gets the equivalent for free: its dispatch poller is an init container,
# so the container runtime reports whether it is still running.
#
# The value is the state this script is in, and the file's mtime is the
# beat. Two states, because "alive" and "available" are different
# questions and the host has to answer both:
#
#   polling  - in the warm-standby loop, able to take a job.
#   claimed  - dispatched; running a job. Written once, then left alone:
#              from here the script blocks in `wait` on run.sh and cannot
#              beat again, so the state is what marks the Pod busy rather
#              than freshness. It also says so independently of the
#              server's best-effort owner label.
#
# Best-effort and guarded on the share exactly like report_runner_exit:
# hosts with the cache-volume feature off have no share, and there no
# heartbeat is published at all. That absence reads as "no signal" on the
# controller side, never as "dead" — a runner image or host that does not
# produce this must keep counting as capacity.
HEARTBEAT_POLLING=polling
HEARTBEAT_CLAIMED=claimed

report_heartbeat() {
  [ -d "${STATUS_SHARE:-}" ] || return 0
  printf '%s' "${1}" >"${STATUS_SHARE}/runner-heartbeat" 2>/dev/null || true
}

RUNNER_TCC_DB="/Users/runner/Library/Application Support/com.apple.TCC/TCC.db"
TCC_LOG=/var/log/tuist-runner/tcc.log
TCC_LOG_PID=""

# stream_tcc_log records TCC's unified-log output from boot on, for
# report_finder_automation to read on the way out. Streamed rather than
# read back with `log show` at exit: scanning the log store after a long
# job takes tens of seconds, and a cut-off scan loses the newest lines,
# which are the ones that explain a failure near the end of the job.
stream_tcc_log() {
  /usr/bin/log stream --level info --style ndjson --predicate 'subsystem == "com.apple.TCC"' >"${TCC_LOG}" 2>/dev/null &
  TCC_LOG_PID=$!
}

filter_tcc_log() {
  # JSON preserves multiline request boundaries. Bound parsing to the latest
  # MiB; keep the last denial plus recent AppleEvents requests, not file access.
  tail -c 1048576 "${TCC_LOG}" | jq -Rr '
    fromjson? | select(.eventMessage != null) |
    [.timestamp, .processID, .threadID, (.eventMessage | gsub("[\\n\\r\\t]"; " "))] | @tsv
  ' | LC_ALL=C awk -F '\t' '
    {
      message=$4; thread=$2 ":" $3
      if (match(message, /msgID=[0-9.]+/)) {
        key=$2 ":" substr(message, RSTART, RLENGTH); current[thread]=key
      } else key=current[thread]
      if (key == "") next
      if (message ~ /service="kTCCServiceAppleEvents"|subject=com\.apple\.finder|Handling access request: kTCCServiceAppleEvents/) apple[key]=1
      if (message ~ /REQUEST_MSG/ && message ~ /service="/ && message !~ /service="kTCCServiceAppleEvents"/) other[key]=1
      text=$1 " pid=" $2 " " message
      if (message ~ /REQUEST_MSG|AUTHREQ_SUBJECT/) request[key]=text
      if (message ~ /^(AUTHREQ_ATTRIBUTION|AttributionChain:)/ && (attribution[key]=="" || message ~ /responsible=/)) attribution[key]=text
      if (message ~ /^AUTHREQ_RESULT|^Handling access request: kTCCServiceAppleEvents/) {
        result[key]=text
        if (message ~ /authValue[=:][ ]*0([, ]|$)/) { denied[key]=NR; denied_result[key]=text }
        if (message ~ /authValue[=:][ ]*1([, ]|$)/) uncertain[key]=NR
      }
      seen[key]=NR; order[NR]=key
    }
    function emit(key, decision) {
      if (request[key] != "") print substr(request[key],1,1800)
      if (attribution[key] != "") print substr(attribution[key],1,1800)
      if (decision == "") decision=result[key]
      if (decision != "") print substr(decision,1,1800)
    }
    END {
      for (key in denied) if (apple[key] && !other[key] && denied[key]>last) { last=denied[key]; failure=key }
      if (failure == "") for (key in uncertain) if (apple[key] && !other[key] && uncertain[key]>last) { last=uncertain[key]; failure=key }
      if (failure != "") emit(failure,denied_result[failure])
      for (i=NR; i>0 && count<9; i--) {
        key=order[i]
        if (seen[key]==i && apple[key] && !other[key] && key!=failure) { emit(key); count++ }
      }
    }
  '
}

# report_finder_automation appends the state behind scripted Finder
# access to `${LOG}` on the way out. When the Finder approval was written
# at boot, some jobs failed with an immediate
# `Not authorized to send Apple events to Finder (-1743)`, and nothing
# from those VMs survives them. Written last, after the job's own
# output, it lands in the bounded tail that publish_runner_log hands to
# tart-kubelet and that reaches Loki.
#
# Keep at most ten request summaries within the host 64 KiB tail. Teardown
# is best-effort: a stalled stream or report must not prevent VM shutdown.
report_finder_automation() {
  local prefix pid timer stream="${TCC_LOG_PID}"
  prefix="$(date -u +%FT%TZ) dispatch-poll: tcc:"
  TCC_LOG_PID=""
  if [ -n "${stream}" ] && jobs -pr | grep -qx "${stream}"; then
    ( sleep 1; kill -KILL "${stream}" 2>/dev/null ) >/dev/null 2>&1 &
    timer=$!
    kill "${stream}" 2>/dev/null || true
    wait "${stream}" 2>/dev/null || true
    kill "${timer}" 2>/dev/null || true
    wait "${timer}" 2>/dev/null || true
  fi
  set -m
  (
    stat -f "${prefix} db inode=%i birth=%SB mtime=%Sm" -t '%FT%T' "${RUNNER_TCC_DB}" 2>&1 | head -n 1
    /usr/bin/sqlite3 -readonly -cmd '.timeout 1000' "${RUNNER_TCC_DB}" "SELECT client, auth_value, auth_reason, last_modified FROM access WHERE service = 'kTCCServiceAppleEvents' AND indirect_object_identifier = 'com.apple.finder' LIMIT 10;" 2>&1 |
      head -n 10 | cut -c1-400 | sed "s|^|${prefix} row |"
    ps -axo pid=,user=,lstart=,comm= | awk '$NF ~ /(^|\/)tccd$/' | head -n 5 | cut -c1-500 | sed "s|^ *|${prefix} tccd |"
    [ ! -f "${TCC_LOG}" ] || filter_tcc_log | sed "s|^|${prefix} log |"
  ) &
  pid=$!
  set +m
  ( sleep 5; kill -TERM -- "-${pid}" 2>/dev/null; sleep 1; kill -KILL -- "-${pid}" 2>/dev/null ) >/dev/null 2>&1 &
  timer=$!
  wait "${pid}" 2>/dev/null || true
  kill -KILL -- "-${pid}" 2>/dev/null || true
  kill "${timer}" 2>/dev/null || true
  wait "${timer}" 2>/dev/null || true
}

# Always halt the VM on script exit. tart-kubelet observes `tart run`
# exiting and transitions the Pod to a terminal phase; without this
# trap a non-zero `./run.sh` (errexit), an early `exit 1`
# (auth abort, missing files, etc.), or any other failure path would
# leave macOS up, the Pod stuck Running, and the warm pool never
# refilling. The trap fires once on EXIT so the happy path
# (clean ./run.sh exit) and every error path halt the VM the
# same way.
trap '_rc=$?; report_runner_exit "${_rc}"; report_finder_automation; echo "$(date -u +%FT%TZ) dispatch-poll: exiting (rc=${_rc}); halting VM"; publish_runner_log; sudo /sbin/shutdown -h now || true; exit "${_rc}"' EXIT

if [ ! -f /etc/tuist.env ]; then
  echo "$(date -u +%FT%TZ) dispatch-poll: /etc/tuist.env missing; aborting"
  exit 1
fi
# shellcheck disable=SC1091
source /etc/tuist.env

# Node still embeds the compromised eMudhra roots; use the patched PEM store.
export NODE_OPTIONS="${NODE_OPTIONS:+${NODE_OPTIONS} }--use-openssl-ca"
export SSL_CERT_FILE=/etc/ssl/cert.pem
export SSL_CERT_DIR=/var/empty
export PIP_CERT="$SSL_CERT_FILE"
export REQUESTS_CA_BUNDLE="$SSL_CERT_FILE"

: "${TUIST_RUNNER_DISPATCH_URL:?TUIST_RUNNER_DISPATCH_URL not set}"

# The booted OS version, so both uses follow base-image bumps. Every dispatch
# request reports it, and the server names the runner after it
# (`tuist-macos-26.6-xcode-27.0-…`). GitHub-hosted runners set ImageOS (e.g.
# `macos26`), and setup actions such as erlef/setup-beam read it to pick a
# prebuilt binary for the OS; the runner forwards it to every step.
os_version="$(sw_vers -productVersion)"
ImageOS="macos${os_version%%.*}"
export ImageOS

keep_desktop_interactive() {
  # ByHost screensaver preferences are tied to the cloned VM's
  # runtime host UUID, so the image-build defaults alone are not
  # enough. Re-apply them inside the booted runner session before a
  # job can be probed over VNC.
  sudo pmset -a sleep 0 displaysleep 0 disksleep 0 >/dev/null 2>&1 || true
  sudo defaults write /Library/Preferences/com.apple.loginwindow autoLoginUser -string runner >/dev/null 2>&1 || true
  sudo defaults write /Library/Preferences/.GlobalPreferences com.apple.autologout.AutoLogOutDelay -int 0 >/dev/null 2>&1 || true

  defaults write com.apple.screensaver idleTime -int 0 >/dev/null 2>&1 || true
  defaults write com.apple.screensaver askForPassword -bool false >/dev/null 2>&1 || true
  defaults write com.apple.screensaver askForPasswordDelay -int 0 >/dev/null 2>&1 || true
  defaults -currentHost write com.apple.screensaver idleTime -int 0 >/dev/null 2>&1 || true
  defaults -currentHost write com.apple.screensaver askForPassword -bool false >/dev/null 2>&1 || true
  defaults -currentHost write com.apple.screensaver askForPasswordDelay -int 0 >/dev/null 2>&1 || true
  /usr/bin/killall cfprefsd >/dev/null 2>&1 || true

  if [ -x /usr/bin/caffeinate ]; then
    /usr/bin/caffeinate -dims -w "$$" >/dev/null 2>&1 &
    echo "$(date -u +%FT%TZ) dispatch-poll: desktop sleep and screen lock disabled"
  fi
}

keep_desktop_interactive

# check_tcc_approvals logs whether the standing TCC approvals the image
# build seeded into runner's TCC.db (scripting Finder for `create-dmg`,
# the iOS Simulator's microphone) are still there. It only reads; see
# infra/runner-image/AGENTS.md for why the rows are written at build.
# A missing row means a job that needs it waits on a consent prompt
# nobody can answer.
check_tcc_approvals() {
  local result
  if result=$(/opt/tuist/tcc-approvals.sh check 2>&1); then
    echo "$(date -u +%FT%TZ) dispatch-poll: ${result}"
  else
    echo "$(date -u +%FT%TZ) dispatch-poll: WARNING ${result}"
  fi
  return 0
}

stream_tcc_log
check_tcc_approvals

# In-VM cluster DNS for the runner-cache path. When the
# runners-controller staged TUIST_CLUSTER_DNS_IP (macOS pools in
# environments whose Mac minis have the tailnet route into the
# cluster), point a macOS scoped resolver for the cluster domain at
# kube-dns so the dispatch-provided cache_endpoint_url
# (`*.svc.cluster.local`) resolves inside the VM. Scoped per-domain:
# only cluster-domain lookups go to kube-dns, everything else keeps
# the vmnet default path. getaddrinfo (curl, the Tuist CLI, JVM, Go's
# darwin cgo resolver) honors /etc/resolver entries via
# mDNSResponder. Best-effort: a failure here degrades to "cache URL
# doesn't resolve" which the build treats like any unreachable
# endpoint — never block the job claim on it.
if [ -n "${TUIST_CLUSTER_DNS_IP:-}" ]; then
  cluster_domain="${TUIST_CLUSTER_DOMAIN:-cluster.local}"
  sudo mkdir -p /etc/resolver 2>/dev/null || true
  if printf 'nameserver %s\n' "${TUIST_CLUSTER_DNS_IP}" | sudo tee "/etc/resolver/${cluster_domain}" >/dev/null 2>&1; then
    echo "$(date -u +%FT%TZ) dispatch-poll: cluster DNS resolver installed (/etc/resolver/${cluster_domain} -> ${TUIST_CLUSTER_DNS_IP})"
  else
    echo "$(date -u +%FT%TZ) dispatch-poll: WARNING could not install /etc/resolver/${cluster_domain}; in-cluster cache URLs will not resolve"
  fi
fi

SA_TOKEN_PATH=/etc/tuist-sa-token
if [ ! -f "${SA_TOKEN_PATH}" ]; then
  echo "$(date -u +%FT%TZ) dispatch-poll: ${SA_TOKEN_PATH} missing; aborting"
  exit 1
fi
SA_TOKEN="$(cat "${SA_TOKEN_PATH}")"
if [ -z "${SA_TOKEN}" ]; then
  echo "$(date -u +%FT%TZ) dispatch-poll: SA token empty; aborting"
  exit 1
fi

SHELL_CLAIM_MARKER="${TUIST_RUNNER_SHELL_CLAIM_MARKER:-/tmp/tuist-runner-shell-claimed}"
export TUIST_RUNNER_SHELL_CLAIM_MARKER="${SHELL_CLAIM_MARKER}"
rm -f "${SHELL_CLAIM_MARKER}" 2>/dev/null || true

# Mirrors the lock protocol in runner-shell-agent-supervisor.sh. The lock is
# shared across uids: the supervisor holds it as root from its LaunchDaemon,
# this script runs as `runner`. Liveness therefore goes through ps, not
# kill -0, which from `runner` fails with EPERM against a live root-owned
# holder exactly as it fails with ESRCH against a dead pid. Reading a healthy
# daemon as stale is what started the redundant second supervisor.
shell_agent_lock_active() {
  local lock_dir=/tmp/tuist-runner-shell-agent.lock
  local pid_file="${lock_dir}/pid"
  local lock_pid=""

  if [ ! -d "${lock_dir}" ]; then
    return 1
  fi

  if [ -e "${pid_file}" ] && [ ! -r "${pid_file}" ]; then
    echo "$(date -u +%FT%TZ) dispatch-poll: cannot read ${pid_file}; assuming the supervisor lock is held"
    return 0
  fi

  if [ -f "${pid_file}" ]; then
    read -r lock_pid <"${pid_file}" || lock_pid=""
  fi

  case "${lock_pid}" in
    '' | *[!0-9]*) ;;
    *)
      if ps -p "${lock_pid}" -o pid= >/dev/null 2>&1; then
        return 0
      fi
      ;;
  esac

  echo "$(date -u +%FT%TZ) dispatch-poll: removing stale runner-shell-agent lock"
  if rm -rf "${lock_dir}"; then
    return 1
  fi

  echo "$(date -u +%FT%TZ) dispatch-poll: cannot remove ${lock_dir}; assuming the supervisor lock is held"
  return 0
}

if shell_agent_lock_active; then
  echo "$(date -u +%FT%TZ) dispatch-poll: runner-shell-agent supervisor already active"
elif [ -x /opt/tuist/runner-shell-agent-supervisor.sh ]; then
  echo "$(date -u +%FT%TZ) dispatch-poll: starting runner-shell-agent supervisor"
  (
    trap - EXIT
    exec /bin/zsh -lc 'exec /opt/tuist/runner-shell-agent-supervisor.sh'
  ) &
  echo "$(date -u +%FT%TZ) dispatch-poll: runner-shell-agent supervisor pid=$!"
else
  echo "$(date -u +%FT%TZ) dispatch-poll: runner-shell-agent missing or not executable"
fi

# Each cache lives on its own custom volume (`tuist-xcode`, `tuist-module`).
# stage_runner_caches stages each one's volume and environment in
# RUNNER_CACHES_DIR, tuist-runner-cache attaches a volume when the job's CI
# integration (the module-cache and xcode-cache GitHub actions, Buildkite
# plugins and GitLab snippets) activates its cache, and teardown drains and
# prunes the compilation cache before `tuist-cache-volume --detach-all` saves
# the volumes.
RUNNER_CACHES_DIR="/Users/runner/.tuist-runner-caches"
MANAGED_XCODE_CACHE="/Users/runner/.tuist-compilation-cache"
MANAGED_MODULE_CACHE="/Users/runner/.tuist-module-cache"
MANAGED_XCCONFIG="/Users/runner/.tuist-managed-cas.xcconfig"
# The limits of a default-sized volume: `tuist-xcode` at 30 GB, `tuist-module` at
# 20 GB. tuist-runner-cache replaces them with the limits for the capacity the
# volume attaches at, which a job sets with `size`; the teardown prune reads the
# compilation cache's back from its xcconfig (managed_xcode_cache_limit). The
# compilation cache's limit bounds one generation of a store that keeps two, so
# it is half the space the module cache's would be.
MANAGED_XCODE_CACHE_LIMIT_BYTES=12000000000
MANAGED_MODULE_CACHE_MAX_BYTES=16000000000
# The compilation cache root teardown drains and prunes, and the limit it prunes
# the stores under it to. Empty when the job did not use the compilation cache.
CAS_STORE_ROOT=""
CAS_LIMIT_BYTES=""

# stop_tuist_launch_agents boots out the launch agents the Tuist CLI installed
# during the job: the compilation-cache proxy, the retired per-project cache
# daemons, the metrics sampler. The runner reaps only its own process tree, so
# they outlive the job, still holding files open on the volumes teardown is
# about to detach. The proxy holds the compilation-cache store on its volume,
# and a Tuist installed onto a custom volume (mise's install directory, for
# example) runs every one of them from that volume. A busy custom volume is not
# published at all. Booting out, and not killing, because the agents restart on
# an unsuccessful exit.
#
# `launchctl bootout` returns before the process exits, so this then waits up to
# TUIST_AGENT_STOP_TIMEOUT for each one that was running to be gone.
#
# Labels starting `tuist.` are the CLI's; the image's own agents, this script's
# among them, are `dev.tuist.`.
TUIST_AGENT_STOP_TIMEOUT=10
stop_tuist_launch_agents() {
  local domain agents pid label pids="" polls=0
  domain="gui/$(id -u)"
  agents=$(launchctl list 2>/dev/null | awk 'NR > 1 && $3 ~ /^tuist\./ { print $1, $3 }')
  [ -n "${agents}" ] || return 0
  while read -r pid label; do
    if launchctl bootout "${domain}/${label}" 2>/dev/null; then
      echo "$(date -u +%FT%TZ) dispatch-poll: stopped launch agent ${label}"
      case "${pid}" in ''|*[!0-9]*) ;; *) pids="${pids} ${pid}" ;; esac
    else
      echo "$(date -u +%FT%TZ) dispatch-poll: WARNING could not stop launch agent ${label}"
    fi
  done <<EOF_AGENTS
${agents}
EOF_AGENTS
  for pid in ${pids}; do
    while kill -0 "${pid}" 2>/dev/null && [ "${polls}" -lt $((TUIST_AGENT_STOP_TIMEOUT * 5)) ]; do
      sleep 0.2
      polls=$((polls + 1))
    done
    if kill -0 "${pid}" 2>/dev/null; then
      echo "$(date -u +%FT%TZ) dispatch-poll: WARNING launch agent process ${pid} still running after ${TUIST_AGENT_STOP_TIMEOUT}s"
    fi
  done
}

# CAS_DRAIN_TIMEOUT bounds the wait for this job's compilation-cache
# publications to reach the remote cache before the volume they live on is
# saved. It holds the VM (and its warm-pool slot) open for its duration, so it
# is a ceiling and not a budget to spend: a healthy job has published
# continuously while it built and passes this gate in milliseconds.
CAS_DRAIN_TIMEOUT=120

# The proxy's own socket default (`$HOME/.local/state/tuist/cas-proxy.sock`),
# spelled out rather than left to the client: this shell is not the job's, and
# an unset HOME would send the client looking under /tmp for a socket that is
# not there — which reads as "no proxy" and silently costs the precise wait.
CAS_PROXY_SOCKET="${HOME:-/Users/runner}/.local/state/tuist/cas-proxy.sock"

# cas_spool_dirs lists the publication spools under the compilation cache. The
# plugin keeps one per CAS directory it opens (`<cas dir>/tuist-spool`) and the
# compiler picks the subdirectory under COMPILATION_CACHE_CAS_PATH, so discover
# them rather than assume the layout. No spool is the ordinary case and makes
# the gate a no-op: a plain `xcodebuild` job runs Xcode's builtin lane, which
# has no remote and nothing to publish.
cas_spool_dirs() {
  local root
  root=$(cas_store_root)
  [ -n "${root}" ] || return 0
  find "${root}/" -type d -name tuist-spool 2>/dev/null | sed 's|//|/|'
}

# cas_store_root prints the compilation cache root this job used, or nothing.
# The store is a symlink into its volume, so callers search under "<root>/".
cas_store_root() {
  printf '%s' "${CAS_STORE_ROOT}"
}

# cas_spool_records counts what a spool still owes the remote. A record is
# deleted only by a publication that SUCCEEDED, so the count is exactly the set
# of associations no other host could ever satisfy. `.tags` sidecars are not
# records — the proxy's own accounting skips them for the same reason.
cas_spool_records() {
  find "$1" -type f ! -name '*.tags' 2>/dev/null | wc -l | tr -d ' '
}

# cas_proxy_client finds the binary that can ask the running proxy to drain (so
# the gate waits on the publisher itself instead of sampling a directory) and to
# prune (so the compilation cache is bounded at all).
#
# Follow the installed agent's custom proxy or stable launch target before PATH
# and the image fallback. Legacy agents name the CLI in Program; stable agents
# run /bin/sh and name their JSON pointer in ProgramArguments[2]. The drain wire
# operation remains compatible while the old proxy drains before adopting it.
#
# The image's copy at /opt/tuist is the LAST resort, and it exists for the jobs
# that have neither: a plain `xcodebuild` workflow never runs Tuist, so it
# installs no launch agent and puts no tuist on PATH. Those jobs still write a
# compilation cache — the compilers' own `builtin` lane, into this same volume — and
# without a binary in the image they were exactly the jobs whose store nothing
# could ever prune, which is the unbounded growth this path exists to stop. (The
# drain is a legitimate no-op for them: no plugin means no spool.)
cas_proxy_client() {
  local candidate program plist target configured_proxy
  plist="${HOME:-/Users/runner}/Library/LaunchAgents/tuist.cas-proxy.plist"
  program=""
  configured_proxy=""
  if [ -r "${plist}" ]; then
    program=$(/usr/libexec/PlistBuddy -c 'Print :Program' "${plist}" 2>/dev/null)
    configured_proxy=$(/usr/libexec/PlistBuddy -c 'Print :EnvironmentVariables:TUIST_CAS_PROXY_PATH' "${plist}" 2>/dev/null)
    if [ "${program}" = /bin/sh ]; then
      target=$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:2' "${plist}" 2>/dev/null)
      case "${target}" in
        */cas-launch-target.json)
          program=$(/usr/bin/plutil -extract executable raw -o - "${target}" 2>/dev/null)
          ;;
        *)
          program=$(/usr/libexec/PlistBuddy -c 'Print :ProgramArguments:4' "${plist}" 2>/dev/null)
          ;;
      esac
    fi
  fi
  for candidate in \
    "${TUIST_CAS_PROXY_PATH:-}" \
    "${configured_proxy}" \
    "${program:+$(dirname "${program}")/tuist-cas-proxy}" \
    "${program:+$(dirname "${program}")/lib/tuist-cas-proxy}" \
    "$(command -v tuist-cas-proxy 2>/dev/null)" \
    /opt/tuist/tuist-cas-proxy; do
    if [ -n "${candidate}" ] && [ -x "${candidate}" ]; then
      printf '%s' "${candidate}"
      return 0
    fi
  done
  return 1
}

# drain_cas_publications holds teardown until every compilation-cache
# publication this job recorded has reached the remote, and reports whether it
# got there. A non-zero return withholds the job's cache volumes from saving.
#
# The saved volume carries the local `key -> value` associations this job
# wrote, while the objects behind them are uploaded ASYNCHRONOUSLY, through the
# plugin's spool. Every job that later attaches the volume inherits those
# associations, and its only repair path for an object the store does not hold
# is the remote. So an association whose blobs were still queued when the VM
# halted is one NO later job can ever satisfy, and nothing retracts it: the
# compiler's CAS ABI has no delete, and re-putting the key with a different
# value is refused. It fails every later build of that key until the store
# generation rolls.
#
# It must run before the Tuist launch agents are stopped and the volumes are
# detached, since the publisher is the proxy and the spool lives on the volume.
#
# It runs for a failed job too: the job's compiles did not wait for their
# uploads because this wait would (TUIST_CAS_DRAINED_STORE), and the next job's
# warm cache is made of those uploads whether this one passed or not.
#
# Best-effort by nature, which is why it does not replace the plugin's read-side
# guard.
drain_cas_publications() {
  [ -n "$(cas_store_root)" ] || return 0
  local spools
  spools=$(cas_spool_dirs)
  [ -n "${spools}" ] || return 0

  local client deadline status spool cas_path budget owed
  client=$(cas_proxy_client) || client=""
  deadline=$(( $(date +%s) + CAS_DRAIN_TIMEOUT ))
  status=0

  # A heredoc and not a pipe: a `while read` behind a pipe runs in a subshell,
  # and `status` would never leave it — the gate would pass on every job.
  while IFS= read -r spool; do
    [ -n "${spool}" ] || continue
    cas_path=$(dirname "${spool}")
    budget=$(( deadline - $(date +%s) ))
    [ "${budget}" -lt 1 ] && budget=1
    owed=""
    if [ -n "${client}" ]; then
      # `env -u TUIST_CAS_REMOTE_GRPC_URL` is the version-skew guard, not a
      # tidiness one. A proxy binary older than the drain op does not recognise
      # `--drain` and falls through to its SERVE path, which unlinks the
      # machine's socket and binds its own — killing the live proxy from a
      # teardown script. Without that variable it exits before reaching the bind,
      # every time, and the gate reads it as "could not ask".
      env -u TUIST_CAS_REMOTE_GRPC_URL "${client}" --drain "${cas_path}" \
        --socket "${CAS_PROXY_SOCKET}" \
        --timeout-ms "$(( budget * 1000 ))"
      # 0 drained, 3 records remain. Every other code is "could not ask" — an
      # unreachable proxy, one too old to know the op, or a shim that never got
      # as far as running the binary — which is NOT an answer and must neither
      # read as drained nor as a verdict. 3 and not 1 for exactly that reason:
      # 1 is what a failing wrapper returns.
      case "$?" in
        0) owed=0 ;;
        3) owed=$(cas_spool_records "${spool}") ;;
      esac
    fi
    # No client, or none that could answer: watch the spool itself. It proves
    # the same thing (a record only disappears when its publication landed),
    # just at polling granularity.
    if [ -z "${owed}" ]; then
      while :; do
        owed=$(cas_spool_records "${spool}")
        [ "${owed}" = "0" ] && break
        [ "$(date +%s)" -ge "${deadline}" ] && break
        sleep 2
      done
    fi
    if [ "${owed}" != "0" ]; then
      echo "$(date -u +%FT%TZ) dispatch-poll: WARNING ${owed} CAS publication(s) under ${cas_path} did not reach the cache within ${CAS_DRAIN_TIMEOUT}s"
      status=1
    else
      echo "$(date -u +%FT%TZ) dispatch-poll: CAS publications drained for ${cas_path}"
    fi
  done <<EOF
${spools}
EOF
  return "${status}"
}

# cas_store_dirs lists the llcas STORES under the compilation cache. A store is a
# directory holding `v1.N` generation dirs; Swift Build picks the lane name under
# COMPILATION_CACHE_CAS_PATH (`plugin` for ours, otherwise `builtin` for the
# compilers and `generic` for Swift Build itself), so discover them by that shape
# rather than assume the set. All need bounding.
cas_store_dirs() {
  local root
  root=$(cas_store_root)
  [ -n "${root}" ] || return 0
  find "${root}/" -maxdepth 3 -type d -name 'v1.*' 2>/dev/null | sed 's|//|/|' |
    while IFS= read -r generation; do dirname "${generation}"; done | sort -u
}

# allocated_bytes prints the bytes allocated under $1, 0 when it is absent.
# Allocated rather than logical, because what the stores share is space on a
# volume.
allocated_bytes() {
  local kib
  kib=$(du -sk "$1" 2>/dev/null | awk '{print $1}')
  case "${kib}" in ''|*[!0-9]*) kib=0 ;; esac
  printf '%s' "$((kib * 1024))"
}

# split_by_use divides a budget ($1) between the parties on stdin, one
# "<used bytes><TAB><name>" line each, by what each uses, and prints one
# "<bytes><TAB><name>" line per party. A party's need is twice what it uses and at
# least the floor ($2). A party whose need is under an even share gets that need;
# the parties that need more split the rest evenly. The lines never add up to more
# than the budget, which is the invariant a split exists for, and a budget of 0
# stays 0.
#
# It divides the compilation cache's limit between its stores
# (cas_store_budgets). An even split
# handed Xcode's `generic` store, a few KB on every volume, half the compilation
# cache, capping the `plugin` store the builds use at half of it. A strictly
# proportional split is not the answer either: it would pin a small party near
# zero, so it could never grow once a job starts using it. Twice its use is the
# room a party has to double before the next division gives it more.
split_by_use() {
  local budget="$1" floor="$2"
  local tab used name need sized="" count=0
  tab=$(printf '\t')
  while IFS="${tab}" read -r used name; do
    [ -n "${name}" ] || continue
    case "${used}" in ''|*[!0-9]*) used=0 ;; esac
    sized="${sized}${used}${tab}${name}
"
    count=$((count + 1))
  done
  [ "${count}" -gt 0 ] || return 0

  local even=$((budget / count)) small_total=0 large_count=0
  while IFS="${tab}" read -r used name; do
    [ -n "${name}" ] || continue
    need=$((used * 2))
    [ "${need}" -ge "${floor}" ] || need="${floor}"
    if [ "${need}" -lt "${even}" ]; then
      small_total=$((small_total + need))
    else
      large_count=$((large_count + 1))
    fi
  done <<EOF
${sized}
EOF

  local large_share="${even}"
  [ "${large_count}" -eq 0 ] || large_share=$(((budget - small_total) / large_count))
  while IFS="${tab}" read -r used name; do
    [ -n "${name}" ] || continue
    need=$((used * 2))
    [ "${need}" -ge "${floor}" ] || need="${floor}"
    if [ "${large_count}" -gt 0 ] && [ "${need}" -lt "${even}" ]; then
      printf '%s%s%s\n' "${need}" "${tab}" "${name}"
    else
      printf '%s%s%s\n' "${large_share}" "${tab}" "${name}"
    fi
  done <<EOF
${sized}
EOF
}

# CAS_STORE_BUDGET_FLOOR_BYTES is the least a small store is budgeted, so a store
# a job starts writing to can grow before its next prune gives it more.
CAS_STORE_BUDGET_FLOOR_BYTES=$((256 * 1024 * 1024))

# cas_store_budgets splits the compilation cache's limit ($1) across the stores in
# $2 (one path per line) by what each uses (split_by_use), printing one
# "<bytes><TAB><store>" line per store.
cas_store_budgets() {
  local budget="$1" stores="$2"
  local tab store sized=""
  tab=$(printf '\t')
  while IFS= read -r store; do
    [ -n "${store}" ] || continue
    sized="${sized}$(allocated_bytes "${store}")${tab}${store}
"
  done <<EOF
${stores}
EOF
  printf '%s' "${sized}" | split_by_use "${budget}" "${CAS_STORE_BUDGET_FLOOR_BYTES}"
}

# prune_cas_stores is what actually bounds the compilation cache on its volume.
#
# COMPILATION_CACHE_LIMIT_SIZE does NOT cap the store directory. Measured against
# Xcode 26.5: the limit bounds a GENERATION, and it is enforced by ROTATION — when
# the live chain is over it, closing the store's last handle starts a new primary
# and demotes the old one. Nothing then deletes the generations that fall off the
# end unless `llcas_cas_prune_ondisk_data` is called, and no part of a build ever
# calls it, so the directory grows without bound. This is the call.
#
# It runs at teardown, AFTER drain_cas_publications (a prune deletes objects, and
# deleting one the spool still owed the remote would strand the association
# naming it) and BEFORE the volume is saved, so every job that later attaches it
# starts from a bounded store.
#
# The prune runs through the proxy binary rather than in this shell because the
# per-machine proxy holds its stores open, and only the holder can rotate a
# store. `--prune` asks the running proxy first for exactly that reason, and
# prunes a store no proxy holds itself, on its generation directories, which
# works on a full volume.
#
# Best-effort: a store we could not prune costs the volume space. It never fails
# the job or withholds the volume.
#
# `$1` names the call site and is echoed into every line this emits.
prune_cas_stores() {
  local when="${1:-teardown}"
  [ -n "$(cas_store_root)" ] || return 0
  local stores
  stores=$(cas_store_dirs)
  [ -n "${stores}" ] || return 0

  local client budget store
  client=$(cas_proxy_client) || {
    echo "$(date -u +%FT%TZ) dispatch-poll: WARNING no CAS proxy binary; compilation-cache stores left unbounded"
    return 0
  }
  # The compilation cache's limit, the figure its xcconfig gives the compiler. An
  # empty or non-numeric one leaves it at 0, which prunes against whatever limit
  # the store already carries rather than inventing one.
  budget="${CAS_LIMIT_BYTES}"
  case "${budget}" in ''|*[!0-9]*) budget=0 ;; esac

  # SPLIT across the stores actually present, because the limit is the CAS's
  # allowance as a whole and llcas only takes a per-generation bound per STORE.
  # A job that used both lanes would otherwise get the full allowance twice,
  # which is the over-commit this budget exists to prevent. See cas_store_budgets
  # for how it is divided.
  #
  # This is the enforcement point rather than the build-time setting because it
  # is the only one that can count: COMPILATION_CACHE_LIMIT_SIZE is written
  # before a single lane exists, so it cannot know how many there will be, while
  # what the saved volume carries is settled here.
  local tab store_budget
  tab=$(printf '\t')
  while IFS="${tab}" read -r store_budget store; do
    [ -n "${store}" ] || continue
    # `env -u TUIST_CAS_REMOTE_GRPC_URL` is the version-skew guard the drain uses
    # for the same reason: a proxy binary older than this op does not recognise
    # `--prune` and falls through to its SERVE path, which unlinks the machine's
    # socket and binds its own — killing the live proxy from a teardown script.
    # Without that variable it exits before reaching the bind, every time.
    # Captured rather than left to stream: the client reports the bytes it
    # freed and which route it took, and both belong ON this line. Loose on
    # stderr they land in the runner's own multi-MB log, attributable to
    # neither the store nor the pass that produced them.
    local output reclaimed via
    if output=$(env -u TUIST_CAS_REMOTE_GRPC_URL "${client}" --prune "${store}" \
      --limit-bytes "${store_budget}" --socket "${CAS_PROXY_SOCKET}" 2>&1); then
      # 0 is the ordinary healthy answer — a store inside its budget has no
      # generation to collect — so it must stay distinguishable from "no figure
      # reported", which would mean the client changed under us.
      reclaimed=$(printf '%s\n' "${output}" | sed -n 's/.*reclaiming \([0-9][0-9]*\) bytes.*/\1/p' | tail -1)
      # Which path actually ran. A store the proxy holds can ONLY be rotated
      # through the proxy, so a `local` route on the plugin lane is the shape of
      # a prune that collected nothing while reporting success.
      case "${output}" in
        *"proxy pruned"*) via="proxy" ;;
        *"holds no handle"*) via="local, proxy holds no handle" ;;
        *"could not ask the proxy"*) via="local, no proxy" ;;
        *) via="local" ;;
      esac
      echo "$(date -u +%FT%TZ) dispatch-poll: CAS store pruned (${when}): ${store} (limit ${store_budget}B/generation, reclaimed ${reclaimed:-unknown}B, ${via})"
    else
      echo "$(date -u +%FT%TZ) dispatch-poll: WARNING could not prune CAS store (${when}) ${store}: ${output}"
    fi
  done <<EOF
$(cas_store_budgets "${budget}" "${stores}")
EOF
}

# stage_runner_caches records how this job reaches the caches, before the runner
# starts: `mode`, and each cache's volume and environment, which
# tuist-runner-cache reads when the job activates that cache.
stage_runner_caches() {
  if ! mkdir -p "${RUNNER_CACHES_DIR}" 2>/dev/null; then
    echo "$(date -u +%FT%TZ) dispatch-poll: WARNING cannot stage the caches; this job runs without them"
    return 0
  fi
  stage_managed_cache_volumes
  printf 'opt-in' >"${RUNNER_CACHES_DIR}/mode" 2>/dev/null || true
  echo "$(date -u +%FT%TZ) dispatch-poll: caches staged for tuist/module-cache and tuist/xcode-cache"
}

# stage_managed_cache_volumes stages each cache on its own custom volume: the
# volume tuist-runner-cache attaches (`<cache>.volume`, key and path) and the
# environment that points the cache at it. The compilation cache gets its own
# xcconfig, bounded to its volume, with the store on the volume's path.
stage_managed_cache_volumes() {
  printf 'tuist-module\t%s\n' "${MANAGED_MODULE_CACHE}" >"${RUNNER_CACHES_DIR}/module.volume" 2>/dev/null || true
  {
    printf 'TUIST_XDG_CACHE_HOME=%s\n' "${MANAGED_MODULE_CACHE}"
    printf 'TUIST_CACHE_MAX_BYTES=%s\n' "${MANAGED_MODULE_CACHE_MAX_BYTES}"
  } >"${RUNNER_CACHES_DIR}/module.env" 2>/dev/null || true
  if {
    printf 'COMPILATION_CACHE_CAS_PATH = %s\n' "${MANAGED_XCODE_CACHE}"
    printf 'COMPILATION_CACHE_KEEP_CAS_DIRECTORY = YES\n'
    printf 'COMPILATION_CACHE_LIMIT_SIZE = %s\n' "${MANAGED_XCODE_CACHE_LIMIT_BYTES}"
  } >"${MANAGED_XCCONFIG}" 2>/dev/null; then
    printf 'tuist-xcode\t%s\n' "${MANAGED_XCODE_CACHE}" >"${RUNNER_CACHES_DIR}/xcode.volume" 2>/dev/null || true
    {
      printf 'XCODE_XCCONFIG_FILE=%s\n' "${MANAGED_XCCONFIG}"
      printf 'TUIST_COMPILATION_CACHE_CAS_PATH=%s\n' "${MANAGED_XCODE_CACHE}"
      printf 'TUIST_CAS_DRAINED_STORE=%s\n' "${MANAGED_XCODE_CACHE}"
    } >"${RUNNER_CACHES_DIR}/xcode.env" 2>/dev/null || true
  fi
}

# managed_xcode_cache_limit prints the compilation cache limit the job's xcconfig
# gave the compiler, which tuist-runner-cache derived from the capacity of the
# attached volume, else the default-sized volume's.
managed_xcode_cache_limit() {
  local limit
  limit=$(sed -n 's/^COMPILATION_CACHE_LIMIT_SIZE = \([0-9][0-9]*\)$/\1/p' "${MANAGED_XCCONFIG}" 2>/dev/null | head -n 1)
  printf '%s' "${limit:-${MANAGED_XCODE_CACHE_LIMIT_BYTES}}"
}

# JOB_RESULT_FILE is where the Buildkite pre-exit hook and the GitLab executor
# leave the job's outcome for teardown. The hook's state directory defaults to
# this directory, and the executor is handed the path.
JOB_RESULT_FILE=/var/log/tuist-runner/job-result
RUNNER_DIAG_DIR=/Users/runner/actions-runner/_diag

# read_job_result prints how the job on this machine ended, lowercased
# (succeeded, failed, canceled, ...), or "unknown" when the agent left no
# verdict. `$1` names the agent: github, buildkite or gitlab.
#
# This, and not the runner's exit status, is what gates saving the cache
# volumes. `run.sh` maps every Listener exit code except a restart to 0, and the
# GitLab executor exits 0 for job outcomes by design, so neither exit says how
# the job ended.
# The Buildkite agent's exit does, but only for failures, and only because it
# is started with `--reflect-exit-status`; buildkite_job_result combines the two.
#
# GitHub records its verdict in the Listener's own trace, as `finish job request
# for job <id> with result: <Result>`. The Listener writes that line on both of
# its completion paths (the Worker exited, or the job was cancelled or
# abandoned), with the result it reports to GitHub, and nothing in it comes from
# the job. The match is anchored to the trace header because a later line
# echoes the job's display name, which the workflow chooses. The Worker's "Job
# result after all job steps finish" line is not a substitute: a job that fails
# to initialize, or whose Worker crashes, never writes it. Buildkite and GitLab
# write JOB_RESULT_FILE.
#
# An absent verdict reads as "unknown", which does not save the volumes.
read_job_result() {
  local result=""
  case "${1}" in
    github)
      result=$(cat "${RUNNER_DIAG_DIR}"/Runner_*.log 2>/dev/null |
        sed -n 's/^\[[^]]* JobDispatcher\] finish job request for job [^ ]* with result: \([A-Za-z]*\)[[:space:]]*$/\1/p' |
        tail -n 1)
      ;;
    *)
      result=$(cat "${JOB_RESULT_FILE}" 2>/dev/null)
      ;;
  esac
  result=$(printf '%s' "${result}" | tr -cd 'A-Za-z' | tr '[:upper:]' '[:lower:]' | cut -c1-32)
  printf '%s' "${result:-unknown}"
}

# buildkite_job_result prints the Buildkite job's result from the pre-exit
# hook's verdict and the agent's exit status (`$1`), which
# `--reflect-exit-status` makes the job's final status. The hook alone is not
# enough: the executor settles that status after the global pre-exit hook runs,
# so an automatic artifact upload that fails, or a repository or plugin pre-exit
# hook that fails, turns a job the hook saw pass into a failure. The status
# alone is not enough either: it does not mark a cancel, and a job whose command
# exits 0 after being cancelled reads as a pass.
buildkite_job_result() {
  local result
  result=$(read_job_result buildkite)
  if [ "${result}" = "succeeded" ] && [ "${1}" != "0" ]; then
    result=failed
  fi
  printf '%s' "${result}"
}

# cache_volumes_detached says whether teardown detaches the job's cache volumes,
# given whether they may be saved (`$1`) and the job's result (`$2`). A job that
# failed detaches them too: the server discards a failed job's volumes, and the
# detach is what reports how full each one got, which is how a copy that ran
# out of space clears the saved snapshot it started from.
cache_volumes_detached() {
  [ "$1" = "1" ] || [ "$2" = "failed" ]
}

# 2 s polling interval is the practical floor for "feels live" to
# a customer staring at their CI dashboard without burning the
# dispatch endpoint. Average pickup latency is ~1 s after a
# webhook lands; server-side load is still trivial at this rate
# (a few QPS per warm Pod, multiplied by host count).
interval=2
attempt=0

# Resolve the image's JSON parser independently of launchd's PATH before acquiring a job.
JQ=/opt/homebrew/bin/jq
if [ ! -x "${JQ}" ]; then
  echo "dispatch-poll: GitLab assignment parser is unavailable"
  exit 1
fi

while true; do
  attempt=$((attempt + 1))
  # Beat before the request, not after: this says the loop is running,
  # and a curl that hangs to its --max-time is exactly the stall the
  # beat needs to expose. One iteration is bounded by that timeout, so
  # a healthy warm runner never goes more than ~12s without a beat.
  report_heartbeat "${HEARTBEAT_POLLING}"
  # `-f` is intentionally omitted: with it, curl exits non-zero on
  # 4xx/5xx, the `|| http="000"` clause fires, and the real status
  # never reaches the case statement. We need 401/403/5xx as
  # numeric statuses so the case can branch on them. stderr is
  # redirected so curl's "The requested URL returned error: …" line
  # doesn't end up in the captured %{http_code}. The `|| http="000"`
  # fallback now fires only on transport failure (DNS, TCP, TLS,
  # timeout), where %{http_code} is "000" anyway.
  http=$(curl -sS -o /tmp/dispatch.json -w '%{http_code}' \
    --max-time 10 \
    --request POST \
    --header "Authorization: Bearer ${SA_TOKEN}" \
    --header "Content-Type: application/json" \
    --data "{\"os_version\":\"${os_version}\"}" \
    "${TUIST_RUNNER_DISPATCH_URL}" 2>/dev/null) || http="000"

  case "${http}" in
    200)
      if ! gitlab_job=$("${JQ}" -r 'has("gitlab_job")' /tmp/dispatch.json); then
        echo "dispatch-poll: invalid assignment response; aborting"
        exit 1
      fi
      if [ "${gitlab_job}" = "true" ]; then
        gitlab_tmp=$(umask 077; mktemp /tmp/tuist-gitlab-job.XXXXXX) || exit 1
        if ! { "${JQ}" -e --arg report_url "${TUIST_RUNNER_DISPATCH_URL%/dispatch}/jobs" \
          '.gitlab_job + {report_url: $report_url}' /tmp/dispatch.json >"${gitlab_tmp}" &&
          mv -f "${gitlab_tmp}" /tmp/tuist-gitlab-job.json; }; then
          rm -f "${gitlab_tmp}" 2>/dev/null || true
          echo "dispatch-poll: GitLab assignment could not be staged; aborting"
          exit 1
        fi
      fi
      # GitHub and Buildkite credentials are opaque ASCII, so their extraction
      # below does not need to interpret nested JSON or escape sequences.
      jit=$(sed -n 's/.*"encoded_jit_config"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' /tmp/dispatch.json)
      # Buildkite's counterpart. The server sends one credential set or
      # the other, never both, so which key is present is what selects
      # the agent to launch further down. Same value-safety as the JIT:
      # a `bkjat_` token and a UUID are both opaque ASCII with no quotes.
      bk_token=$(sed -n 's/.*"buildkite_acquisition_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' /tmp/dispatch.json)
      bk_job_uuid=$(sed -n 's/.*"buildkite_job_uuid"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' /tmp/dispatch.json)
      bk_report_token=$(sed -n 's/.*"buildkite_report_token"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' /tmp/dispatch.json)
      if [ -z "${jit}" ] && [ -z "${bk_token}" ] && [ "${gitlab_job}" != "true" ]; then
        echo "$(date -u +%FT%TZ) dispatch-poll: 200 but no runner credential; retrying"
        sleep "${interval}"
        continue
      fi
      printf '%s\n' "$(date -u +%FT%TZ)" >"${SHELL_CLAIM_MARKER}" 2>/dev/null || true
      # Last beat of the warm-standby life. Everything below runs the job,
      # so the loop stops beating here by design and the state — not the
      # age — is what tells the host this Pod is no longer warm.
      report_heartbeat "${HEARTBEAT_CLAIMED}"
      # Optional: route the job's Tuist cache at the account's private
      # runner-cache Kura node (in-cluster, near this runner) when the
      # server includes it. Exported here so the GitHub Actions runner —
      # and therefore every job step — inherits it; the Tuist CLI honors
      # TUIST_CACHE_ENDPOINT as a cache-endpoint override. Same value-
      # safety as the JIT extraction: the URL is a plain http(s) URL
      # with no embedded quotes.
      cache_endpoint=$(sed -n 's/.*"cache_endpoint_url"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' /tmp/dispatch.json)
      if [ -n "${cache_endpoint}" ]; then
        echo "$(date -u +%FT%TZ) dispatch-poll: routing cache to runner-local endpoint ${cache_endpoint}"
        export TUIST_CACHE_ENDPOINT="${cache_endpoint}"
      fi
      # Server-signed cache grant: a short-lived token scoping cache
      # artifact signatures to this account instead of the machine MAC, so a
      # warm volume's binaries validate as local hits across VMs. Same value-
      # safety as the JIT (a base64url token, no embedded quotes). The Tuist EE
      # CLI verifies it offline against a baked-in public key; absent/invalid/
      # expired falls back to the MAC default, so this is purely additive.
      cache_grant=$(sed -n 's/.*"cache_signing_grant"[[:space:]]*:[[:space:]]*"\([^"]*\)".*/\1/p' /tmp/dispatch.json)
      if [ -n "${cache_grant}" ]; then
        echo "$(date -u +%FT%TZ) dispatch-poll: cache signing grant delivered"
        export TUIST_CACHE_SIGNING_GRANT="${cache_grant}"
      fi
      # The GitHub runner inherits this process's environment, so exporting
      # is enough there. The Buildkite agent sanitizes the job environment
      # instead, so anything the build needs has to be re-exported from
      # inside a hook — which can only read what is on disk.
      if [ -n "${bk_token}" ]; then
        # This script runs as `runner`, and a shell redirect into /etc is
        # performed by the shell as that user, not by sudo — so writing
        # the file directly fails with EACCES. It did, silently, and the
        # pre-exit hook then found no credential and skipped reporting
        # while the job itself passed: the run looked fine on Buildkite
        # and arrived on the dashboard with no logs and no conclusion.
        #
        # `sudo tee` puts the privileged process on the writing side, and
        # the outcome is checked rather than discarded.
        job_env_tmp=$(mktemp)
        {
          [ -n "${cache_endpoint}" ] && printf 'TUIST_CACHE_ENDPOINT=%s\n' "${cache_endpoint}"
          [ -n "${cache_grant}" ] && printf 'TUIST_CACHE_SIGNING_GRANT=%s\n' "${cache_grant}"
          # The credential the pre-exit hook reports with. Job-scoped, so
          # unlike the SA token it can only write this job's log and
          # declare this job's outcome — which is why the hook may read it
          # from inside the job at all.
          printf 'TUIST_RUNNER_REPORT_TOKEN=%s\n' "${bk_report_token}"
          printf 'TUIST_RUNNER_REPORT_URL=%s\n' "${TUIST_RUNNER_DISPATCH_URL%/dispatch}"
        } >"${job_env_tmp}"
        if sudo tee /etc/tuist-runner-job.env <"${job_env_tmp}" >/dev/null 2>&1; then
          sudo chmod 0644 /etc/tuist-runner-job.env 2>/dev/null || true
          echo "$(date -u +%FT%TZ) dispatch-poll: staged buildkite job env for the hooks"
        else
          echo "$(date -u +%FT%TZ) dispatch-poll: FAILED to stage /etc/tuist-runner-job.env; the job will run but report no logs or outcome"
        fi
        rm -f "${job_env_tmp}"
      fi
      echo "$(date -u +%FT%TZ) dispatch-poll: dispatched, starting runner"
      # Force an NTP step before the job runs. A golden-base VM can be
      # handed a job within seconds of boot — before macOS `timed` has
      # synced the guest clock, which can start minutes behind. The
      # GitHub runner stamps step times and metrics-poll stamps samples
      # off this clock, so an unsynced VM lands the two on different
      # timelines (the step timeline only drifts into alignment once
      # `timed` catches up mid-job). `sntp -sS` steps a large offset via
      # clock_settime (and slews a sub-50ms one); the network is already
      # up here since dispatch just succeeded. Best-effort: on failure
      # `timed` still converges, just later.
      if sudo /usr/bin/sntp -sS -t 5 time.apple.com >/dev/null 2>&1; then
        echo "$(date -u +%FT%TZ) dispatch-poll: clock stepped to NTP before runner start"
      else
        echo "$(date -u +%FT%TZ) dispatch-poll: WARNING NTP step failed; relying on timed"
      fi
      stage_runner_caches
      # Fork the machine-metrics sampler so it runs for the job's
      # duration and POSTs CPU/memory/network/disk to the server. It
      # dies with the VM when the EXIT trap halts us after the runner
      # exits. Best-effort — never blocks the job from starting.
      if [ -x /opt/tuist/metrics-poll.sh ]; then
        /opt/tuist/metrics-poll.sh &
      fi
      cd /Users/runner/actions-runner
      # Idle watchdog. GitHub assigns a queued job to any label-eligible
      # runner, not necessarily the one the server minted it for, so
      # this runner can register and then wait indefinitely for a job
      # GitHub ran on a sibling, holding the VM and its warm-pool slot
      # idle. The watchdog terminates it after
      # TUIST_RUNNER_IDLE_TIMEOUT_SECONDS; the EXIT trap then halts the
      # VM and the reconciler recycles it. A runner holding a job has
      # written the JOB_STARTED marker (via the runner's own hook) and
      # is never touched. 0 / unset disables the watchdog.
      # The job-start signal must be irreversible: /tmp is writable by
      # the workflow, so a job that removes the marker (a broad
      # `rm -rf /tmp/*` cleanup is enough) must not be able to make
      # itself look idle and get killed mid-run. Two independent
      # latches: the hook cancels the watchdog outright (it runs before
      # any workflow step, so job code never sees a live watchdog), and
      # the watchdog polls and stands down the moment it observes work
      # rather than reading the marker once at the deadline. Neither can
      # be undone from inside the job.
      JOB_STARTED_MARKER=/tmp/tuist-runner-job-started
      JOB_STARTED_HOOK=/tmp/tuist-runner-job-started-hook.sh
      WATCHDOG_PID_FILE=/tmp/tuist-runner-watchdog.pid
      rm -f "${JOB_STARTED_MARKER}" "${WATCHDOG_PID_FILE}"
      # The hook also mounts the job's cached checkout at its workspace before
      # the first step, so a stock actions/checkout reuses it instead of
      # cloning. The host decides whether there is one; any miss leaves the
      # workspace empty and the job checks out exactly as before.
      cat >"${JOB_STARTED_HOOK}" <<HOOK
#!/bin/bash
touch "${JOB_STARTED_MARKER}" 2>/dev/null || true
_wpid="\$(cat "${WATCHDOG_PID_FILE}" 2>/dev/null || true)"
[ -n "\${_wpid}" ] && kill "\${_wpid}" 2>/dev/null || true
if [ -n "\${GITHUB_WORKSPACE:-}" ] && [ -x /usr/local/bin/tuist-cache-volume ] && [ -d "/Volumes/My Shared Files/custom-cache" ]; then
  /usr/local/bin/tuist-cache-volume --checkout "\${GITHUB_WORKSPACE}" || true
fi
exit 0
HOOK
      chmod +x "${JOB_STARTED_HOOK}"
      export ACTIONS_RUNNER_HOOK_JOB_STARTED="${JOB_STARTED_HOOK}"
      idle_timeout="${TUIST_RUNNER_IDLE_TIMEOUT_SECONDS:-0}"

      # RUNNER_PERFLOG makes the Listener append a `MessageReceived_<type>`
      # line to `<dir>/Runner.perf` the instant a message arrives from
      # GitHub, before it acknowledges the assignment and before it fetches
      # the job body. That is seconds ahead of Runner.Worker, and it is the
      # earliest local evidence that this runner has been given work.
      #
      # The Listener's poll loop returns nothing on an idle timeout, so the
      # file stays empty until GitHub actually routes something here. Only
      # the two job-request message types count; a refresh or cancel message
      # is not an assignment.
      RUNNER_PERF_DIR=/Users/runner/actions-runner/_perf
      RUNNER_PERF_FILE="${RUNNER_PERF_DIR}/Runner.perf"
      rm -rf "${RUNNER_PERF_DIR}"
      export RUNNER_PERFLOG="${RUNNER_PERF_DIR}"
      # 404/409/422 on the job fetch make the Listener skip the message and
      # go back to waiting, so a received message does not always become a
      # Worker. Bound how long the watchdog defers on one.
      WORKER_GRACE_SECONDS=60
      job_message_received() {
        grep -q 'MessageReceived_PipelineAgentJobRequest\|MessageReceived_RunnerJobRequest' \
          "${RUNNER_PERF_FILE}" 2>/dev/null
      }

      # The machine is fresh per job, so anything here would be a stray, but the
      # verdict teardown saves the cache volumes on has to be this job's.
      rm -f "${JOB_RESULT_FILE}"

      # `--jitconfig` implies ephemeral: the runner accepts one job
      # and exits. `--disableupdate` pins the runner to whatever
      # version is baked into the image; we bump that via Renovate
      # PRs against `runner_version` in runner.pkr.hcl, which the
      # release-runner-image flow turns into a fresh image + digest
      # bump. Auto-update would self-upgrade the runner mid-VM, which
      # is opaque (the version that ran a job isn't the version we
      # baked in) and can race with GitHub's deprecation message on
      # cold boot. The EXIT trap above halts the VM regardless of
      # rc — the trap is what tart-kubelet ultimately observes, so
      # both clean and crash paths refill the warm pool the same way.
      #
      # Logs are captured server-side from GitHub's Actions Logs
      # API on `workflow_job: completed` (see
      # `Tuist.Runners.Workers.FetchLogsWorker`); the runner VM
      # writes nothing to the ingest path.
      if [ "${gitlab_job}" = "true" ]; then
        /opt/tuist/tuist-gitlab-runner --job-file /tmp/tuist-gitlab-job.json \
          --builds-dir /Users/runner/work --result-file "${JOB_RESULT_FILE}" &
        runner_pid=$!
        wait "${runner_pid}"
        rc=$?
        JOB_RESULT=$(read_job_result gitlab)
      elif [ -n "${bk_token}" ]; then
        # Buildkite needs none of the idle-watchdog machinery below. The
        # acquisition token names one job UUID, so the assignment already
        # happened server-side before this VM was handed anything: the
        # agent either takes that job or exits. There is no window in
        # which a registered agent sits waiting to be given work, which
        # is the whole hazard the GitHub watchdog exists to bound.
        #
        # `--enable-job-log-tmpfile` is what makes the log ours to ship.
        # The agent writes the job's output verbatim to the path it
        # exports as BUILDKITE_JOB_LOG_TMPFILE, and the global pre-exit
        # hook posts it to the server while the file still exists (the
        # agent removes it when the job ends).
        export BUILDKITE_AGENT_TOKEN="${bk_token}"
        export BUILDKITE_AGENT_ACQUIRE_JOB="${bk_job_uuid}"
        echo "$(date -u +%FT%TZ) dispatch-poll: acquiring buildkite job ${bk_job_uuid}"
        /opt/tuist/buildkite-agent start \
          --name "$(hostname)" \
          --hooks-path /opt/tuist/buildkite-hooks \
          --build-path /Users/runner/work \
          --enable-job-log-tmpfile \
          --job-log-path /var/log/tuist-runner \
          --disconnect-after-job \
          --reflect-exit-status &
        runner_pid=$!
        wait "${runner_pid}"
        agent_rc=$?
        JOB_RESULT=$(buildkite_job_result "${agent_rc}")
        # `--reflect-exit-status` exits the agent with a failed job's status, but
        # the runners-controller reads a non-zero runner exit as a runner death
        # and not as a job outcome. A verdict from the hook proves the job ran, so
        # its status stays out of the exit; without one, the agent's own status
        # (a rejected acquisition, or a job that never reached its hooks) is
        # still reported.
        rc=0
        if [ "${JOB_RESULT}" = "unknown" ]; then
          rc="${agent_rc}"
        fi
        echo "$(date -u +%FT%TZ) dispatch-poll: buildkite agent exited ${agent_rc}"
      else
      # The runner prints `.setup_info` as groups in the job's "Set up job"
      # step; the server's group links the job to its Tuist dashboard page.
      # Best-effort: a missing or unwritable file only drops the link.
      if "${JQ}" -e '.setup_info | type == "array"' /tmp/dispatch.json >/dev/null 2>&1; then
        "${JQ}" '.setup_info' /tmp/dispatch.json >.setup_info 2>/dev/null || rm -f .setup_info
      fi
      ./run.sh --jitconfig "${jit}" --disableupdate &
      runner_pid=$!
      if [ "${idle_timeout}" -gt 0 ] 2>/dev/null; then
        (
          waited=0
          while [ "${waited}" -lt "${idle_timeout}" ]; do
            # Latch and stand down for good the first time work is observed.
            [ -e "${JOB_STARTED_MARKER}" ] && exit 0
            kill -0 "${runner_pid}" 2>/dev/null || exit 0
            sleep 1
            waited=$((waited + 1))
          done
          # Both process-level latches trail the assignment. The Listener
          # acknowledges the job, fetches its body over HTTP and only then
          # forks Runner.Worker, with the job-started hook later still, so a
          # check at the deadline reads "idle" for a runner GitHub has
          # already, irrevocably, given work to. Killing it there marks that
          # job failed rather than re-queuing it, and GitHub then spends ten
          # minutes waiting out the job's lock before anyone learns it died.
          #
          # Deferring on the Listener's own record of the inbound message
          # covers that gap, because that record predates the acknowledgment
          # rather than trailing it. What stays exposed is the interval
          # between the last read and the signal below, not the fetch.
          worker_wait=0
          while :; do
            [ -e "${JOB_STARTED_MARKER}" ] && exit 0
            pgrep -f "Runner.Worker" >/dev/null 2>&1 && exit 0
            kill -0 "${runner_pid}" 2>/dev/null || exit 0
            job_message_received || break
            [ "${worker_wait}" -ge "${WORKER_GRACE_SECONDS}" ] && break
            sleep 1
            worker_wait=$((worker_wait + 1))
          done
          echo "$(date -u +%FT%TZ) dispatch-poll: no job assigned within ${idle_timeout}s; terminating idle runner"
          kill -TERM "${runner_pid}" 2>/dev/null || true
        ) &
        watchdog_pid=$!
        printf '%s' "${watchdog_pid}" >"${WATCHDOG_PID_FILE}" 2>/dev/null || true
      fi
      wait "${runner_pid}"
      rc=$?
      # The runner is gone, so the idle watchdog has nothing left to police.
      [ -n "${watchdog_pid:-}" ] && kill "${watchdog_pid}" 2>/dev/null || true
      JOB_RESULT=$(read_job_result github)
      fi
      # Only a job that succeeded may save its cache volumes (see read_job_result
      # for why the exit status cannot say so). A non-zero exit still withholds:
      # it is a runner the idle watchdog killed, or an agent that failed.
      JOB_PASSED=0
      if [ "${rc}" = "0" ] && [ "${JOB_RESULT}" = "succeeded" ]; then
        JOB_PASSED=1
      fi
      echo "$(date -u +%FT%TZ) dispatch-poll: job result=${JOB_RESULT} (rc=${rc}); cache volume saves $([ "${JOB_PASSED}" = "1" ] && echo allowed || echo withheld)"
      # Cache teardown. The order here is load-bearing: the compilation cache's
      # publications reach the remote before the volume holding their store is
      # saved, the store is bounded after the drain and before the volume is
      # measured, and the Tuist launch agents, which the drain and the prune
      # still need, are stopped before anything detaches. The drain runs for
      # every job that used the cache, the prune only for one whose volumes are
      # saved. A drain that cannot finish withholds the job's volumes. A failed
      # job's volumes are detached anyway (cache_volumes_detached).
      custom_volumes_savable="${JOB_PASSED}"
      if [ -e "${RUNNER_CACHES_DIR}/xcode.used" ]; then
        CAS_STORE_ROOT="${MANAGED_XCODE_CACHE}"
        if ! drain_cas_publications; then
          custom_volumes_savable=0
          echo "$(date -u +%FT%TZ) dispatch-poll: WARNING compilation cache publications did not drain; this job's cache volumes will not be saved"
        elif [ "${JOB_PASSED}" = "1" ]; then
          CAS_LIMIT_BYTES=$(managed_xcode_cache_limit)
          prune_cas_stores teardown
        fi
      fi
      stop_tuist_launch_agents
      # Hand the host what the job's checkout added; the host verifies it and
      # builds the next cached checkout from it. Never affects the exit code.
      if [ -x /usr/local/bin/tuist-cache-volume ] && [ -d "/Volumes/My Shared Files/custom-cache" ]; then
        /usr/local/bin/tuist-cache-volume --checkout-export || true
      fi
      if cache_volumes_detached "${custom_volumes_savable}" "${JOB_RESULT}" && [ -x /usr/local/bin/tuist-cache-volume ]; then
        if ! /usr/local/bin/tuist-cache-volume --detach-all; then
          echo "$(date -u +%FT%TZ) dispatch-poll: WARNING custom cache detach failed; affected volumes will not be published" >&2
        fi
      fi
      # Final metrics sample before the EXIT trap halts the VM. The
      # looping sampler is killed mid-sleep by the shutdown, so the last
      # interval — including "Complete job" — otherwise has no data point
      # and the chart stops short of the job's end. One synchronous
      # sample now, while the network is still up, closes that gap.
      # Best-effort; never affects the runner's exit code.
      [ -x /opt/tuist/metrics-poll.sh ] && /opt/tuist/metrics-poll.sh --once || true
      exit "${rc}"
      ;;
    204)
      # Server has nothing for us yet. Keep polling — the VM is
      # booted and registered with the dispatch endpoint via its
      # SA token; when a customer workflow_job arrives, our next
      # poll will return 200 with the JIT bound to that customer.
      # Quiet log every 30th tick (~once per minute at 2 s
      # interval) so the file doesn't balloon while idle.
      [ $((attempt % 30)) -eq 0 ] && echo "$(date -u +%FT%TZ) dispatch-poll: warm standby (attempt=${attempt})"
      sleep "${interval}"
      ;;
    401|403)
      echo "$(date -u +%FT%TZ) dispatch-poll: ${http} unauthorized; aborting"
      exit 1
      ;;
    410)
      # Server signalled drain — this Pod's image no longer matches
      # the RunnerPool's spec.image (chart digest-pin rolled). Exit
      # cleanly so the EXIT trap halts the VM and tart-kubelet flips
      # the Pod to Succeeded; the reconciler then replaces it with
      # one on the current image. The check only runs on idle polls,
      # so in-flight customer work is never interrupted.
      echo "$(date -u +%FT%TZ) dispatch-poll: 410 drain — stale image, exiting cleanly"
      exit 0
      ;;
    *)
      echo "$(date -u +%FT%TZ) dispatch-poll: HTTP ${http} (attempt=${attempt}); retrying"
      sleep "${interval}"
      ;;
  esac
done
