if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  SCRIPT_PATH="${BASH_SOURCE[0]}"
elif [[ -n "${ZSH_VERSION:-}" ]]; then
  SCRIPT_PATH="${(%):-%x}"
else
  SCRIPT_PATH="${0}"
fi

SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_PATH}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ROOT_INSTANCE_FILE="${PROJECT_ROOT}/.tuist-dev-instance"
CACHE_ROOT="${XDG_CACHE_HOME:-${HOME}/.cache}/tuist"
CLICKHOUSE_STATE_ROOT="${XDG_STATE_HOME:-${HOME}/.local/state}/tuist"

resolve_git_path() {
  local target_name="$1"
  local fallback_path="$2"
  local git_path=""

  if command -v git >/dev/null 2>&1 && git -C "${PROJECT_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    git_path="$(
      git -C "${PROJECT_ROOT}" rev-parse --path-format=absolute --git-path "${target_name}" 2>/dev/null ||
        git -C "${PROJECT_ROOT}" rev-parse --git-path "${target_name}" 2>/dev/null ||
        true
    )"

    if [[ -n "${git_path}" && "${git_path}" != /* ]]; then
      git_path="${PROJECT_ROOT}/${git_path#./}"
    fi
  fi

  if [[ -n "${git_path}" ]]; then
    printf '%s' "${git_path}"
  else
    printf '%s' "${fallback_path}"
  fi
}

INSTANCE_FILE="$(resolve_git_path "tuist-dev-instance" "${ROOT_INSTANCE_FILE}")"

validate_suffix() {
  local suffix="$1"

  [[ "$suffix" =~ ^[0-9]+$ ]] || return 1
  (( suffix >= 1 && suffix <= 999 ))
}

persist_suffix() {
  local suffix="$1"
  local target="$2"

  mkdir -p "$(dirname "${target}")" 2>/dev/null || return 1
  printf '%s' "${suffix}" | tee "${target}" >/dev/null 2>&1
}

collect_used_suffixes() {
  # Suffixes already assigned to the main checkout and every linked worktree, so
  # a freshly generated one can avoid colliding on ports and database names.
  local common_dir="" f
  if command -v git >/dev/null 2>&1 && git -C "${PROJECT_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    common_dir="$(git -C "${PROJECT_ROOT}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  fi
  [[ -n "${common_dir}" && -d "${common_dir}" ]] || return 0

  for f in "${common_dir}/tuist-dev-instance" "${common_dir}"/worktrees/*/tuist-dev-instance; do
    [[ -s "${f}" ]] || continue
    [[ "${f}" -ef "${INSTANCE_FILE}" ]] 2>/dev/null && continue
    tr -d '[:space:]' < "${f}"
    printf '\n'
  done
}

generate_suffix() {
  # Pick a suffix in [100, 999] not used by any other instance. Seed awk's RNG
  # with the PID so worktrees bootstrapped within the same second diverge instead
  # of sharing awk's default time(0) seed.
  local used
  used="$(collect_used_suffixes | tr '\n' ' ')"
  awk -v used="${used}" -v seed="$$" '
    BEGIN {
      srand(seed)
      n = split(used, list, " ")
      for (i = 1; i <= n; i++) taken[list[i]] = 1
      for (attempt = 0; attempt < 100000; attempt++) {
        candidate = int(100 + rand() * 900)
        if (!(candidate in taken)) { print candidate; exit 0 }
      }
      exit 1
    }
  '
}

ensure_suffix() {
  local suffix=""

  # This instance's own persisted suffix wins over everything else. Worktrees
  # live nested under the main checkout, so mise loads both mise.toml files and
  # runs this script once per project root; the parent run exports its own
  # TUIST_DEV_INSTANCE, which would otherwise leak into the worktree. Reading our
  # own file first keeps each worktree on its distinct suffix regardless of what
  # a parent (or stale env) provides.
  if [[ -s "${INSTANCE_FILE}" ]]; then
    suffix="$(tr -d '[:space:]' < "${INSTANCE_FILE}")"
  # No file yet: trust TUIST_DEV_INSTANCE only when it belongs to THIS project
  # root, or when it was set externally with no provenance marker (an explicit
  # override such as CI's TUIST_DEV_INSTANCE=1). A value carrying a different
  # root leaked from a parent checkout and must be ignored.
  elif [[ -n "${TUIST_DEV_INSTANCE:-}" ]] &&
    { [[ "${TUIST_DEV_INSTANCE_ROOT:-}" == "${PROJECT_ROOT}" ]] || [[ -z "${TUIST_DEV_INSTANCE_ROOT:-}" ]]; }; then
    suffix="${TUIST_DEV_INSTANCE}"
  elif [[ -s "${ROOT_INSTANCE_FILE}" ]]; then
    suffix="$(tr -d '[:space:]' < "${ROOT_INSTANCE_FILE}")"
  else
    suffix="$(generate_suffix)"
  fi

  validate_suffix "${suffix}" || {
    echo "Invalid dev instance suffix '${suffix}'. Expected an integer between 1 and 999." >&2
    return 1
  }

  if ! persist_suffix "${suffix}" "${INSTANCE_FILE}"; then
    if [[ "${INSTANCE_FILE}" != "${ROOT_INSTANCE_FILE}" ]] &&
      persist_suffix "${suffix}" "${ROOT_INSTANCE_FILE}"; then
      INSTANCE_FILE="${ROOT_INSTANCE_FILE}"
    else
      echo "Failed to persist dev instance suffix '${suffix}'." >&2
      return 1
    fi
  fi

  printf '%s' "${suffix}"
}

suffix="$(ensure_suffix)"
test_partition="${MIX_TEST_PARTITION:-}"

# Derive a hostname from the project root directory basename
project_basename="$(basename "${PROJECT_ROOT}")"
# Sanitize: lowercase, replace non-alphanumeric with hyphens, trim leading/trailing hyphens
project_hostname="$(printf '%s' "${project_basename}" | tr '[:upper:]' '[:lower:]' | sed 's/[^a-z0-9-]/-/g; s/^-*//; s/-*$//')"

export TUIST_DEV_INSTANCE="${suffix}"
export TUIST_DEV_INSTANCE_ROOT="${PROJECT_ROOT}"
export TUIST_SERVER_PORT="$((8080 + suffix))"
export TUIST_SERVER_HOSTNAME="${project_hostname}.localhost"
export TUIST_SERVER_URL="http://localhost:${TUIST_SERVER_PORT}"
export TUIST_SERVER_POSTGRES_DB="tuist_development_${suffix}"
export TUIST_SERVER_CLICKHOUSE_DB="tuist_development_${suffix}"
export TUIST_SERVER_CLICKHOUSE_RUNTIME_DIR="${CLICKHOUSE_STATE_ROOT}/clickhouse"
export TUIST_SERVER_CLICKHOUSE_HTTP_PORT="8123"
export TUIST_SERVER_CLICKHOUSE_NATIVE_PORT="9000"
export TUIST_SERVER_CLICKHOUSE_INTERSERVER_HTTP_PORT="9009"
export TUIST_SERVER_CLICKHOUSE_MYSQL_PORT="9004"
export TUIST_SERVER_CLICKHOUSE_POSTGRESQL_PORT="9005"
export TUIST_SERVER_CLICKHOUSE_KEEPER_PORT="9181"
export TUIST_SERVER_CLICKHOUSE_KEEPER_RAFT_PORT="9234"
export TUIST_SERVER_CLICKHOUSE_HTTP_URL="http://127.0.0.1:${TUIST_SERVER_CLICKHOUSE_HTTP_PORT}"
export TUIST_CACHE_PORT="$((8087 + suffix))"
export TUIST_CACHE_SERVER_URL="${TUIST_SERVER_URL}"
export TUIST_MINIO_API_PORT="$((9095 + suffix))"
export TUIST_MINIO_CONSOLE_PORT="$((9098 + suffix))"
export TUIST_SERVER_TEST_PORT="$((4002 + suffix))"
export TUIST_SERVER_TEST_POSTGRES_DB="tuist_test${test_partition}_${suffix}"
export TUIST_SERVER_TEST_CLICKHOUSE_DB="tuist_test${test_partition}_${suffix}"
export TUIST_CACHE_TEST_PORT="$((4003 + suffix))"
export TUIST_CACHE_TEST_POSTGRES_DB="cache_test_${suffix}"
export TUIST_CACHE_TEST_STORAGE_DIR="/tmp/test_cas_${suffix}"

if [[ -z "${CI:-}" && -z "${MIX_OS_DEPS_COMPILE_PARTITION_COUNT:-}" ]]; then
  # Keep faster local dependency compilation without forcing CI into the same setting.
  export MIX_OS_DEPS_COMPILE_PARTITION_COUNT="4"
fi
