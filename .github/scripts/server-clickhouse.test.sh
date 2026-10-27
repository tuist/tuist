#!/usr/bin/env bash
# Exercise ClickHouse's inherited file limits without starting a database.

set -euo pipefail

SCRIPT="$(cd "$(dirname "$0")/../../server/mise/tasks/clickhouse" && pwd)/start.sh"
scratch="$(mktemp -d)"
trap 'rm -rf "$scratch"' EXIT
original_soft="$(ulimit -Sn)"
original_hard="$(ulimit -Hn)"

mkdir -p "$scratch/bin"
cat > "$scratch/bin/curl" <<'BASH'
#!/usr/bin/env bash
[[ -f "$CLICKHOUSE_TEST_READY" ]]
BASH
cat > "$scratch/bin/clickhouse" <<'BASH'
#!/usr/bin/env bash
set -euo pipefail
printf '%s\n' "$(ulimit -Sn)" "$(ulimit -Hn)" > "$CLICKHOUSE_TEST_LIMITS"
touch "$CLICKHOUSE_TEST_READY"
BASH
chmod +x "$scratch/bin/curl" "$scratch/bin/clickhouse"
export PATH="$scratch/bin:$PATH"

run_case() {
  local name="$1" soft="$2" hard="$3" expected="$4" mode="${5:-normal}"
  local directory="$scratch/$name"
  mkdir -p "$directory"
  export CLICKHOUSE_TEST_READY="$directory/ready"
  export CLICKHOUSE_TEST_LIMITS="$directory/limits"
  export TUIST_SERVER_CLICKHOUSE_RUNTIME_DIR="$directory/runtime"

  if [[ "$mode" == running ]]; then
    touch "$CLICKHOUSE_TEST_READY"
  fi

  # Limits and the simulated platform restriction stay in this child process.
  bash -c '
    set -euo pipefail
    ulimit -Sn "$1"
    ulimit -Hn "$2"
    if [[ "$4" == blocked ]]; then
      ulimit() {
        if [[ "$#" == 2 && "$1" == -Sn ]]; then
          return 1
        fi
        builtin ulimit "$@"
      }
      export -f ulimit
    fi
    exec bash "$3"
  ' clickhouse-limit-test "$soft" "$hard" "$SCRIPT" "$mode" > "$directory/output" 2>&1

  if [[ "$mode" == running ]]; then
    if [[ -f "$CLICKHOUSE_TEST_LIMITS" ]]; then
      echo 'An already-running ClickHouse must not be relaunched.' >&2
      exit 1
    fi
    grep -q 'ClickHouse already running' "$directory/output"
  else
    local actual_soft actual_hard
    {
      read -r actual_soft
      read -r actual_hard
    } < "$CLICKHOUSE_TEST_LIMITS"
    if [[ "$actual_soft" != "$expected" || "$actual_hard" != "$hard" ]]; then
      echo "$name: expected limits $expected/$hard, got $actual_soft/$actual_hard" >&2
      exit 1
    fi
    grep -q "Starting ClickHouse with open-files limit $expected" "$directory/output"
    grep -q 'ClickHouse ready' "$directory/output"
  fi
}

run_case low-soft-limit 128 4096 4096
run_case already-raised 4096 4096 4096
run_case restricted-hard-limit 128 256 256
run_case unsupported-raise 128 4096 128 blocked
run_case already-running 128 4096 128 running

[[ "$(ulimit -Sn)" == "$original_soft" ]]
[[ "$(ulimit -Hn)" == "$original_hard" ]]
echo 'ClickHouse startup regression tests passed (5 cases).'
