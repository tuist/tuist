#!/bin/bash
# Exercises dispatch-poll.sh's compilation-cache drain and prune against fakes of
# launchctl, the proxy a job installs with `tuist setup cache`, and the image's
# own proxy binary. The functions are extracted rather than the script sourced,
# since sourcing it starts the dispatch loop. macOS only: the launch agent's plist
# is read with PlistBuddy.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
fixtures="$(mktemp -d)"

stop_fixture_proxy() {
  if [ -f "${fixtures}/proxy.pid" ]; then
    kill "$(cat "${fixtures}/proxy.pid")" 2>/dev/null || true
  fi
}
trap 'stop_fixture_proxy; rm -rf "${fixtures}"' EXIT

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

{
  grep -E '^CAS_[A-Z_]+=' dispatch-poll.sh
  awk '/^[a-z_][a-z0-9_]*\(\) \{$/ { copying = 1 }
       copying { print }
       copying && /^\}$/ { copying = 0 }' dispatch-poll.sh
} > "${fixtures}/functions.sh"
bash -n "${fixtures}/functions.sh"

mkdir -p "${fixtures}/bin" "${fixtures}/job" "${fixtures}/image"

# Only the agent `tuist setup cache` installs is ever loaded. A bootout signals
# its process the way launchd does, unless the fixture's proxy ignores it.
cat > "${fixtures}/bin/launchctl" <<'EOF'
#!/bin/bash
echo "$*" >> "${FIXTURES}/launchctl.log"
[ -f "${FIXTURES}/agent-loaded" ] || exit 113
case "$1 $2" in
  "print gui/"*"/tuist.cas-proxy")
    printf 'gui/%s/tuist.cas-proxy = {\n\tstate = running\n\tpid = %s\n\tpid-local endpoints = {\n\t}\n}\n' \
      "$(id -u)" "$(cat "${FIXTURES}/proxy.pid")"
    ;;
  "bootout gui/"*"/tuist.cas-proxy")
    rm -f "${FIXTURES}/agent-loaded"
    [ -f "${FIXTURES}/proxy-ignores-bootout" ] || kill "$(cat "${FIXTURES}/proxy.pid")"
    ;;
  *) exit 113 ;;
esac
EOF

# A tuist-cas-proxy released before `--prune`, like 4.207.0's: it knows `--drain`,
# and any other invocation falls through to its serve path, which refuses to
# start without a remote.
cat > "${fixtures}/job/tuist-cas-proxy" <<'EOF'
#!/bin/bash
echo "$*" >> "${FIXTURES}/job-proxy.log"
if [ "$1" = "--drain" ]; then
  echo "cas publications drained for $2" >&2
  exit 0
fi
if [ -z "${TUIST_CAS_REMOTE_GRPC_URL+set}" ]; then
  echo "TUIST_CAS_REMOTE_GRPC_URL is required" >&2
  exit 2
fi
touch "${FIXTURES}/serve-path-reached"
exit 2
EOF
printf '#!/bin/bash\n' > "${fixtures}/job/tuist"

# The image's binary: it asks the running proxy first, which answers `bad op`
# because it predates the op, and then prunes in-process. While that proxy runs
# it holds the plugin lane open, so the in-process prune rotates nothing there.
# With nothing holding a store, every generation but the two newest is collected.
cat > "${fixtures}/image/tuist-cas-proxy" <<'EOF'
#!/bin/bash
echo "$*" >> "${FIXTURES}/image-proxy.log"
store="$2"
held=0
if kill -0 "$(cat "${FIXTURES}/proxy.pid" 2>/dev/null)" 2>/dev/null; then
  echo "cas prune could not ask the proxy (proxy error: bad op)" >&2
  [ "$(basename "${store}")" = plugin ] && held=1
else
  echo "cas prune could not ask the proxy (proxy connect: Connection refused (os error 61))" >&2
fi
reclaimed=0
if [ "${held}" = 0 ]; then
  for generation in $(ls -1 "${store}" | grep '^v1\.' | sort -t. -k2 -n | sed '$d' | sed '$d'); do
    reclaimed=$((reclaimed + $(wc -c < "${store}/${generation}/data")))
    rm -rf "${store:?}/${generation}"
  done
fi
echo "pruned ${store} directly (the proxy could not be asked), reclaiming ${reclaimed} bytes" >&2
EOF
chmod +x "${fixtures}/bin/launchctl" "${fixtures}/job/tuist-cas-proxy" "${fixtures}/job/tuist" "${fixtures}/image/tuist-cas-proxy"

volume="${fixtures}/volume"
store_root="${volume}/CompilationCache.noindex"

# A mounted image holding both lanes, each one generation past what a prune
# keeps, and an empty publication spool.
reset_fixture() {
  stop_fixture_proxy
  rm -rf "${volume:?}" "${fixtures:?}/home" "${fixtures}/status" "${fixtures}"/*.log \
    "${fixtures}/proxy.pid" "${fixtures}/agent-loaded" "${fixtures}/proxy-ignores-bootout" \
    "${fixtures}/serve-path-reached"
  local lane generation
  for lane in plugin generic; do
    for generation in 1 2 3; do
      mkdir -p "${store_root}/${lane}/v1.${generation}"
      head -c 1000 /dev/zero > "${store_root}/${lane}/v1.${generation}/data"
    done
  done
  mkdir -p "${store_root}/plugin/tuist-spool" "${fixtures}/status" "${fixtures}/home"
  printf '4000' > "${fixtures}/status/cas-enabled"
}

# What `tuist setup cache` leaves running: the launch agent, pointing at the
# job's tuist, and the proxy process it started.
install_job_proxy() {
  mkdir -p "${fixtures}/home/Library/LaunchAgents"
  cat > "${fixtures}/home/Library/LaunchAgents/tuist.cas-proxy.plist" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>Label</key>
    <string>tuist.cas-proxy</string>
    <key>Program</key>
    <string>${fixtures}/job/tuist</string>
</dict>
</plist>
EOF
  # Detached, so the process is reaped as soon as it exits rather than
  # lingering as this shell's zombie.
  (sleep 600 > /dev/null 2>&1 & echo $! > "${fixtures}/proxy.pid")
  touch "${fixtures}/agent-loaded"
}

# Runs `$1` against the extracted functions, with an environment holding
# nothing the fixture does not set.
run_dispatch_poll() {
  env -i HOME="${fixtures}/home" PATH="${fixtures}/bin:/usr/bin:/bin:/usr/sbin:/sbin" FIXTURES="${fixtures}" \
    /bin/bash -c '
      set -uo pipefail
      source "${FIXTURES}/functions.sh"
      CACHE_MOUNT="${FIXTURES}/volume"
      STATUS_SHARE="${FIXTURES}/status"
      CAS_IMAGE_PROXY="${FIXTURES}/image/tuist-cas-proxy"
      eval "$1"
    ' run_dispatch_poll "$1" > "${fixtures}/output" 2>&1
}

expect_output() {
  grep -qF -- "$1" "${fixtures}/output" || { cat "${fixtures}/output" >&2; fail "expected output to contain: $1"; }
}

expect_no_output() {
  if grep -qF -- "$1" "${fixtures}/output"; then
    cat "${fixtures}/output" >&2
    fail "expected output not to contain: $1"
  fi
}

expect_pruned() {
  [ ! -e "${store_root}/$1/v1.1" ] || fail "expected $1's oldest generation to be collected"
  [ -d "${store_root}/$1/v1.2" ] && [ -d "${store_root}/$1/v1.3" ] || fail "expected $1's two newest generations to remain"
}

proxy_running() {
  kill -0 "$(cat "${fixtures}/proxy.pid")" 2>/dev/null
}

reset_fixture
install_job_proxy
run_dispatch_poll 'drain_cas_publications'
expect_output "CAS publications drained for ${store_root}/plugin"
grep -qF -- "--drain ${store_root}/plugin" "${fixtures}/job-proxy.log" || fail "expected the drain to ask the job's own proxy"
proxy_running || fail "expected the drain to leave the job's proxy running"
echo "ok: the drain asks the job's own proxy and leaves it running"

run_dispatch_poll 'prune_cas_stores teardown'
expect_no_output "could not prune CAS store"
expect_output "CAS store pruned (teardown): ${store_root}/generic (limit 2000B/generation, reclaimed 1000B, local, no proxy)"
expect_output "CAS store pruned (teardown): ${store_root}/plugin (limit 2000B/generation, reclaimed 1000B, local, no proxy)"
expect_pruned generic
expect_pruned plugin
if grep -qF -- "--prune" "${fixtures}/job-proxy.log"; then
  fail "expected the prune not to run the job's proxy binary, which predates --prune"
fi
[ ! -e "${fixtures}/serve-path-reached" ] || fail "expected no proxy binary to reach its serve path"
! proxy_running || fail "expected teardown to stop the job's proxy before pruning the store it holds"
echo "ok: teardown prunes both lanes when the job's proxy predates --prune"

reset_fixture
run_dispatch_poll 'prune_cas_stores attach'
expect_output "CAS store pruned (attach): ${store_root}/generic (limit 2000B/generation, reclaimed 1000B, local, no proxy)"
expect_output "CAS store pruned (attach): ${store_root}/plugin (limit 2000B/generation, reclaimed 1000B, local, no proxy)"
expect_pruned generic
expect_pruned plugin
expect_no_output "CAS proxy (pid"
echo "ok: attach, before any proxy exists, prunes both lanes"

reset_fixture
install_job_proxy
touch "${fixtures}/proxy-ignores-bootout"
run_dispatch_poll 'CAS_PROXY_STOP_TIMEOUT=1; prune_cas_stores teardown'
expect_output "WARNING CAS proxy (pid $(cat "${fixtures}/proxy.pid")) still running 1s after bootout"
expect_output "CAS store pruned (teardown): ${store_root}/plugin (limit 2000B/generation, reclaimed 0B, local, proxy refused)"
[ -d "${store_root}/plugin/v1.1" ] || fail "expected the store the proxy still holds to keep its generations"
expect_pruned generic
echo "ok: a proxy that outlives its bootout is reported, not passed off as no proxy"
