#!/usr/bin/env bash
# Regression tests for metrics-sampler.sh's byte-valued metrics.
#
# Must run on the runner image's base (Ubuntu, so `awk` is mawk).
# mawk saturates `printf "%d"` at INT_MAX and renders integers above
# 2^31 through OFMT, so a byte counter formatted either way is wrong
# above 2 GiB while still looking like a plausible number. Running
# these under gawk or BWK awk would pass regardless and prove nothing.

set -uo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
# shellcheck source=metrics-sampler.sh
source ./metrics-sampler.sh

INT32_MAX=2147483647
failures=0

assert_eq() {
  local label="$1" expected="$2" actual="$3"
  if [ "${expected}" = "${actual}" ]; then
    echo "  ok   ${label}"
  else
    echo "  FAIL ${label}: expected ${expected}, got ${actual}"
    failures=$((failures + 1))
  fi
}

assert_ne() {
  local label="$1" unexpected="$2" actual="$3"
  if [ "${unexpected}" != "${actual}" ]; then
    echo "  ok   ${label}"
  else
    echo "  FAIL ${label}: expected anything but ${unexpected}"
    failures=$((failures + 1))
  fi
}

fixtures="$(mktemp -d)"
trap 'rm -rf "${fixtures}"' EXIT

meminfo_fixture() {
  local name="$1" total_kb="$2" avail_kb="$3"
  cat > "${fixtures}/${name}" <<MEM
MemTotal:       ${total_kb} kB
MemFree:        ${avail_kb} kB
MemAvailable:   ${avail_kb} kB
MEM
  echo "${fixtures}/${name}"
}

echo "memory_total_bytes tracks the guest's configured memory"
# One fixture per fleet shape. A total that is constant across these,
# or quantized to OFMT's six significant digits, is the regression.
boot=$(meminfo_fixture boot 1950752 1850000)       # kata sandbox default, pre-hotplug
mem32=$(meminfo_fixture mem32 33554432 27262976)   # 32 GiB shape, 6 GiB in use
mem64=$(meminfo_fixture mem64 67108864 58720256)   # 64 GiB shape, 8 GiB in use

read -r used total <<<"$(mem_totals "${boot}")"
assert_eq "2 GiB sandbox total" 1997570048 "${total}"

read -r used total <<<"$(mem_totals "${mem32}")"
assert_eq "32 GiB shape total" 34359738368 "${total}"
assert_eq "32 GiB shape used" 6442450944 "${used}"

read -r used total <<<"$(mem_totals "${mem64}")"
assert_eq "64 GiB shape total" 68719476736 "${total}"
assert_eq "64 GiB shape used" 8589934592 "${used}"

echo
echo "memory survives kata hot-plugging the sandbox mid-job"
# The sidecar starts while the guest is still at its boot size and the
# guest grows underneath it. Reporting the boot-time total against a
# post-hotplug MemAvailable is what pinned memory_total_bytes at
# 1997570048 and memory_used_bytes at 0.
MEMINFO_PATH="${boot}"
read -r used_before total_before <<<"$(mem_totals)"
MEMINFO_PATH="${mem32}"
read -r used_after total_after <<<"$(mem_totals)"
assert_ne "total is re-read after hotplug" "${total_before}" "${total_after}"
assert_eq "post-hotplug total" 34359738368 "${total_after}"
assert_ne "post-hotplug used is not zeroed" 0 "${used_after}"
assert_ne "pre-hotplug used is not zeroed" 0 "${used_before}"

echo
echo "disk_total_bytes is not clamped at Int32 max"
disk_kb="$(df -k -P / | awk 'NR == 2 { print $2 }')"
expected_disk=$(( disk_kb * 1024 ))
if [ "${expected_disk}" -le "${INT32_MAX}" ]; then
  echo "  FAIL / is ${expected_disk} bytes, too small to exercise the INT_MAX clamp"
  failures=$((failures + 1))
fi
read -r disk_used disk_total <<<"$(disk_totals /)"
assert_eq "total matches df" "${expected_disk}" "${disk_total}"
assert_ne "total is not INT_MAX" "${INT32_MAX}" "${disk_total}"
assert_ne "used is not INT_MAX" "${INT32_MAX}" "${disk_used}"

echo
echo "network counters are not clamped at Int32 max"
cat > "${fixtures}/net_dev" <<'NET'
Inter-|   Receive                                                |  Transmit
 face |bytes    packets errs drop fifo frame compressed multicast|bytes    packets errs drop fifo colls carrier compressed
    lo:     100       1    0    0    0     0          0         0      100       1    0    0    0     0       0          0
  eth0: 9663676416 1000    0    0    0     0          0         0 5368709120 900    0    0    0     0       0          0
NET
read -r rx tx <<<"$(net_totals "${fixtures}/net_dev")"
assert_eq "rx total" 9663676416 "${rx}"
assert_eq "tx total" 5368709120 "${tx}"
assert_eq "delta above 2 GiB" 4294967296 "$(delta 9663676416 5368709120)"
assert_eq "counter reset floors at 0" 0 "$(delta 100 9663676416)"

echo
echo "metrics_payload carries the real byte values"
# Guards the caller as well as the readers: a total hoisted out of the
# sampling loop cannot reach the payload from here.
MEMINFO_PATH="${mem64}"
DISK_PATH=/
payload="$(metrics_payload 1750684800 42.5 1.2 1024 2048)"
echo "  ${payload}"
for field in \
  '"memory_total_bytes":68719476736' \
  '"memory_used_bytes":8589934592' \
  "\"disk_total_bytes\":${expected_disk}"; do
  if [[ "${payload}" == *"${field}"* ]]; then
    echo "  ok   payload has ${field}"
  else
    echo "  FAIL payload missing ${field}"
    failures=$((failures + 1))
  fi
done
if [[ "${payload}" == *"${INT32_MAX}"* ]]; then
  echo "  FAIL payload contains INT_MAX ${INT32_MAX}"
  failures=$((failures + 1))
else
  echo "  ok   payload contains no INT_MAX clamp"
fi
if [[ "${payload}" == *e+* ]]; then
  echo "  FAIL payload contains scientific notation"
  failures=$((failures + 1))
else
  echo "  ok   payload contains no scientific notation"
fi

echo
echo "oom_kill_count reports the guest's OOM kills"
cat > "${fixtures}/vmstat" <<'VMSTAT'
pgfault 123456
oom_kill 3
pgmajfault 7
VMSTAT
printf 'pgfault 1\n' > "${fixtures}/vmstat_old_kernel"
assert_eq "oom_kill counter" 3 "$(oom_kills "${fixtures}/vmstat")"
assert_eq "kernel without the counter" 0 "$(oom_kills "${fixtures}/vmstat_old_kernel")"
assert_eq "unreadable vmstat" 0 "$(oom_kills "${fixtures}/missing")"
payload="$(metrics_payload 1750684800 42.5 1.2 1024 2048 2)"
if [[ "${payload}" == *'"oom_kill_count":2}'* ]]; then
  echo "  ok   payload has the OOM kills since the job started"
else
  echo "  FAIL payload missing \"oom_kill_count\":2: ${payload}"
  failures=$((failures + 1))
fi


echo
echo "a sample with OOM kills names the process killed last"
DIND_MEMORY_PATH="${fixtures}/dind-memory"
printf 'dind.mem.current=1 dind.oom_kill=1 oom.victim=java oom.victim.anon.kb=27262976 oom.victim.container=gradle-build oom.victim.image=gradle:8-jdk21@sha256:ab\n' >"${DIND_MEMORY_PATH}"
payload="$(metrics_payload 1750684800 42.5 1.2 1024 2048 1)"
want=',"oom_kill_count":1,"oom_victim_process":"java","oom_victim_memory_bytes":27917287424,"oom_victim_container":"gradle-build","oom_victim_image":"gradle:8-jdk21@sha256:ab"}]}'
if [[ "${payload}" == *"${want}" ]]; then
  echo "  ok   payload names java in gradle-build, 26 GiB"
else
  echo "  FAIL payload: ${payload}"
  failures=$((failures + 1))
fi
# Before any kill of its own the job's sample names nobody, even if the
# file names a victim from before the job was claimed.
payload="$(metrics_payload 1750684800 42.5 1.2 1024 2048 0)"
if [[ "${payload}" == *oom_victim* ]]; then
  echo "  FAIL a sample without kills names a victim: ${payload}"
  failures=$((failures + 1))
else
  echo "  ok   a sample without kills names no victim"
fi
# The job can write the file: quotes, backslashes and newlines must not
# reach the JSON.
printf 'oom.victim=a"b\\c oom.victim.anon.kb=1e9x oom.victim.container=c"},{"x":1\n' >"${DIND_MEMORY_PATH}"
payload="$(metrics_payload 1750684800 42.5 1.2 1024 2048 1)"
# The test runs in bare Ubuntu images, which have no JSON parser: one sample
# ending in exactly the sanitized fields, and no stray quote or backslash.
if [[ "${payload}" == *'"oom_victim_process":"abc","oom_victim_memory_bytes":19456,"oom_victim_container":"cx:1"}]}' ]] &&
  [[ "$(grep -o '"timestamp"' <<<"${payload}" | wc -l)" -eq 1 ]] &&
  [[ "${payload}" != *'\'* && "${payload}" != *'"x"'* ]]; then
  echo "  ok   a hostile file stays one valid sample"
else
  echo "  FAIL hostile payload: ${payload}"
  failures=$((failures + 1))
fi
rm "${DIND_MEMORY_PATH}"
payload="$(metrics_payload 1750684800 42.5 1.2 1024 2048 1)"
if [[ "${payload}" == *'"oom_kill_count":1}]}' ]]; then
  echo "  ok   a pool without the dind report sends only the count"
else
  echo "  FAIL payload: ${payload}"
  failures=$((failures + 1))
fi

echo
echo "SIGTERM sends a final sample without waiting out the interval"
# Kubelet stops the sidecar right after the runner exits. When the
# kernel killed the runner for memory, only this last sample reports
# it, and it must go out before kubelet's grace period ends.
bin="${fixtures}/bin"
mkdir -p "${bin}"
cat > "${bin}/curl" <<CURL
#!/usr/bin/env bash
while [ \$# -gt 0 ]; do
  if [ "\$1" = "--data" ]; then echo "\$2" >> "${fixtures}/posted"; fi
  shift
done
CURL
chmod +x "${bin}/curl"
echo token > "${fixtures}/token"
touch "${fixtures}/jit"
PATH="${bin}:${PATH}" \
  TUIST_RUNNER_DISPATCH_URL=http://server.invalid/dispatch \
  TUIST_RUNNER_POD_NAME=pod \
  TUIST_RUNNER_TOKEN_PATH="${fixtures}/token" \
  TUIST_RUNNER_JIT_PATH="${fixtures}/jit" \
  TUIST_RUNNER_DISK_PATH=/ \
  TUIST_RUNNER_METRICS_INTERVAL=600 \
  bash ./metrics-sampler.sh > "${fixtures}/sampler.log" 2>&1 &
sampler=$!
for _ in $(seq 50); do
  [ -s "${fixtures}/posted" ] && break
  sleep 0.1
done
kill -TERM "${sampler}"
for _ in $(seq 30); do
  kill -0 "${sampler}" 2>/dev/null || break
  sleep 0.1
done
if kill -0 "${sampler}" 2>/dev/null; then
  echo "  FAIL sampler still running 3s after SIGTERM"
  kill -KILL "${sampler}"
  failures=$((failures + 1))
else
  echo "  ok   sampler exited on SIGTERM"
fi
wait "${sampler}" 2>/dev/null
assert_eq "samples posted (first + final)" 2 "$(grep -c '"oom_kill_count":0}' "${fixtures}/posted" 2>/dev/null || echo 0)"

echo
if [ "${failures}" -ne 0 ]; then
  echo "${failures} assertion(s) failed"
  exit 1
fi
echo "all assertions passed"
