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

ensure_suffix() {
  local suffix=""

  if [[ -n "${TUIST_DEV_INSTANCE:-}" ]]; then
    suffix="${TUIST_DEV_INSTANCE}"
  elif [[ -s "${INSTANCE_FILE}" ]]; then
    suffix="$(tr -d '[:space:]' < "${INSTANCE_FILE}")"
  elif [[ -s "${ROOT_INSTANCE_FILE}" ]]; then
    suffix="$(tr -d '[:space:]' < "${ROOT_INSTANCE_FILE}")"
  else
    suffix="$(awk 'BEGIN { srand(); print int(100 + rand() * 900) }')"
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
