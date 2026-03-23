if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  SCRIPT_PATH="${BASH_SOURCE[0]}"
elif [[ -n "${ZSH_VERSION:-}" ]]; then
  SCRIPT_PATH="${(%):-%x}"
else
  SCRIPT_PATH="${0}"
fi

SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_PATH}")" && pwd)"
PROJECT_ROOT="${MISE_PROJECT_ROOT:-$(cd "${SCRIPT_DIR}/../.." && pwd)}"
INSTANCE_FILE="${PROJECT_ROOT}/.tuist-dev-instance"

validate_suffix() {
  local suffix="$1"

  [[ "$suffix" =~ ^[0-9]+$ ]] || return 1
  (( suffix >= 1 && suffix <= 999 ))
}

ensure_suffix() {
  local suffix=""

  if [[ -n "${TUIST_DEV_INSTANCE:-}" ]]; then
    suffix="${TUIST_DEV_INSTANCE}"
  elif [[ -s "${INSTANCE_FILE}" ]]; then
    suffix="$(tr -d '[:space:]' < "${INSTANCE_FILE}")"
  else
    suffix="$(awk 'BEGIN { srand(); print int(100 + rand() * 900) }')"
  fi

  validate_suffix "${suffix}" || {
    echo "Invalid dev instance suffix '${suffix}'. Expected an integer between 1 and 999." >&2
    return 1
  }

  printf '%s' "${suffix}" > "${INSTANCE_FILE}"
  printf '%s' "${suffix}"
}

suffix="$(ensure_suffix)"
test_partition="${MIX_TEST_PARTITION:-}"

export TUIST_DEV_INSTANCE="${suffix}"
export TUIST_SERVER_PORT="$((8080 + suffix))"
export TUIST_SERVER_URL="http://localhost:${TUIST_SERVER_PORT}"
export TUIST_SERVER_POSTGRES_DB="tuist_development_${suffix}"
export TUIST_SERVER_CLICKHOUSE_DB="tuist_development_${suffix}"
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
