#!/usr/bin/env bash
# Exercises memory-report.sh, the job-completed hook, against fixture
# /proc/vmstat, vitals low-water and dind sidecar files.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")"
fixtures="$(mktemp -d)"
trap 'rm -rf "${fixtures}"' EXIT
export TUIST_RUNNER_VMSTAT="${fixtures}/vmstat"
export TUIST_RUNNER_MEMORY_LOW_FILE="${fixtures}/low"
export TUIST_RUNNER_DIND_MEMORY_FILE="${fixtures}/dind"

report() { bash ./memory-report.sh >"${fixtures}/out"; }
total=35517284 # a 16x32 runner's MemTotal, 33.9 GB

# A job that kept 4 GB free and killed nothing gets no annotation.
printf 'pgfault 1\noom_kill 0\n' >"${TUIST_RUNNER_VMSTAT}"
printf '4194304 %s\n' "${total}" >"${TUIST_RUNNER_MEMORY_LOW_FILE}"
report
test ! -s "${fixtures}/out"
echo "ok: a job with room to spare is not annotated"

# Within 5% of the VM: a warning that names how close it came.
printf '629146 %s\n' "${total}" >"${TUIST_RUNNER_MEMORY_LOW_FILE}"
report
grep -qx '::warning title=Close to the memory limit::This job came within 0.6 GB of running the runner out of memory (33.9 GB).*' "${fixtures}/out"
test "$(wc -l <"${fixtures}/out")" -eq 1
echo "ok: a job that came within 5% of the limit gets a warning"

# Just above 5%: no warning.
printf '%s %s\n' $((total / 20 + 1)) "${total}" >"${TUIST_RUNNER_MEMORY_LOW_FILE}"
report
test ! -s "${fixtures}/out"
echo "ok: the warning threshold is 5% of the VM"

# One kill the sidecar named: an error naming the process and its size.
printf 'oom_kill 1\n' >"${TUIST_RUNNER_VMSTAT}"
printf 'dind.mem.current=1 dind.oom_kill=1 oom.victim=java oom.victim.anon.kb=27262976\n' >"${TUIST_RUNNER_DIND_MEMORY_FILE}"
report
grep -qx '::error title=Out of memory::This job ran the runner out of memory, and the Linux kernel stopped java (26.0 GB) to free some. The runner has 33.9 GB of memory. To fit, lower .*' "${fixtures}/out"
test "$(wc -l <"${fixtures}/out")" -eq 1
echo "ok: an OOM kill is an error naming the victim"

# Several kills, no sidecar report (a pool without cache volumes).
printf 'oom_kill 3\n' >"${TUIST_RUNNER_VMSTAT}"
rm "${TUIST_RUNNER_DIND_MEMORY_FILE}"
report
grep -q 'the Linux kernel stopped 3 processes to free some' "${fixtures}/out"
printf 'oom.victim=java oom.victim.anon.kb=1048576\n' >"${TUIST_RUNNER_DIND_MEMORY_FILE}"
report
grep -q 'stopped 3 processes, the last one java (1.0 GB), to free some' "${fixtures}/out"
echo "ok: several kills are counted, with or without a named victim"

# The job can write the shared file; it must not start a workflow command or
# break the annotation onto a second line.
printf 'oom.victim=x%%0A::add-mask::y oom.victim.anon.kb=12;rm\n' >"${TUIST_RUNNER_DIND_MEMORY_FILE}"
report
test "$(wc -l <"${fixtures}/out")" -eq 1
grep -q 'stopped 3 processes, the last one x0Aadd-masky (0.0 GB),' "${fixtures}/out"
echo "ok: a hostile victim name stays inside the annotation"

# Nothing readable: no annotation, and never a failing hook.
rm -f "${TUIST_RUNNER_VMSTAT}" "${TUIST_RUNNER_MEMORY_LOW_FILE}" "${TUIST_RUNNER_DIND_MEMORY_FILE}"
report
test ! -s "${fixtures}/out"
echo "ok: missing inputs report nothing and exit 0"
