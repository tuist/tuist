# Per-worktree port and instance suffix scoping. Sourced by mise so every
# `mise` invocation inside this project (or a linked worktree) exports a
# stable instance suffix and a set of ports derived from it.
#
# Adapted from tuist/tuist. The persisted suffix lives inside git's per-
# worktree state directory, so two worktrees pointing at the same repo get
# distinct suffixes and never collide on Phoenix, RustFS, or console ports.

if [[ -n "${BASH_SOURCE[0]:-}" ]]; then
  SCRIPT_PATH="${BASH_SOURCE[0]}"
elif [[ -n "${ZSH_VERSION:-}" ]]; then
  SCRIPT_PATH="${(%):-%x}"
else
  SCRIPT_PATH="${0}"
fi

SCRIPT_DIR="$(cd "$(dirname "${SCRIPT_PATH}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../.." && pwd)"
ROOT_INSTANCE_FILE="${PROJECT_ROOT}/.pulse-dev-instance"

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

INSTANCE_FILE="$(resolve_git_path "pulse-dev-instance" "${ROOT_INSTANCE_FILE}")"

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
  # Suffixes already claimed by the main checkout and every linked worktree,
  # so a freshly generated one can dodge collisions.
  local common_dir="" f
  if command -v git >/dev/null 2>&1 && git -C "${PROJECT_ROOT}" rev-parse --is-inside-work-tree >/dev/null 2>&1; then
    common_dir="$(git -C "${PROJECT_ROOT}" rev-parse --path-format=absolute --git-common-dir 2>/dev/null || true)"
  fi
  [[ -n "${common_dir}" && -d "${common_dir}" ]] || return 0

  for f in "${common_dir}/pulse-dev-instance" "${common_dir}"/worktrees/*/pulse-dev-instance; do
    [[ -s "${f}" ]] || continue
    [[ "${f}" -ef "${INSTANCE_FILE}" ]] 2>/dev/null && continue
    tr -d '[:space:]' < "${f}"
    printf '\n'
  done
}

generate_suffix() {
  # Pick a suffix in [100, 999] not used by any other instance. Seed awk's RNG
  # with the PID so worktrees bootstrapped within the same second diverge
  # instead of sharing awk's default time(0) seed.
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

  # This instance's own persisted suffix wins over everything else. Nested
  # worktrees would otherwise inherit the parent's PULSE_DEV_INSTANCE.
  if [[ -s "${INSTANCE_FILE}" ]]; then
    suffix="$(tr -d '[:space:]' < "${INSTANCE_FILE}")"
  elif [[ -n "${PULSE_DEV_INSTANCE:-}" ]] &&
    { [[ "${PULSE_DEV_INSTANCE_ROOT:-}" == "${PROJECT_ROOT}" ]] || [[ -z "${PULSE_DEV_INSTANCE_ROOT:-}" ]]; }; then
    suffix="${PULSE_DEV_INSTANCE}"
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

export PULSE_DEV_INSTANCE="${suffix}"
export PULSE_DEV_INSTANCE_ROOT="${PROJECT_ROOT}"

# Phoenix endpoint. 4100..4999 — clear of the default Phoenix dev port (4000)
# and the ExUnit port (4002).
export PORT="$((4000 + suffix))"

# RustFS via docker-compose. Ranges are 1000 apart so two suffixes N and
# N+3 cannot accidentally claim the same TCP port. Bases picked to avoid
# common developer defaults on macOS: ClickHouse (9000), Node.js debugger
# (9229), Prometheus (9090), Grafana (3000), gRPC dev (50051).
#     API:      11100..11999
#     Console:  12100..12999
export PULSE_RUSTFS_API_PORT="$((11000 + suffix))"
export PULSE_RUSTFS_CONSOLE_PORT="$((12000 + suffix))"

# What the Elixir app reads. runtime.exs reads PULSE_S3_ENDPOINT verbatim.
export PULSE_S3_ENDPOINT="http://localhost:${PULSE_RUSTFS_API_PORT}"

# Compile the Rust NIF from source in this checkout instead of trying to
# fetch a precompiled artifact from GitHub Releases (which is what
# `mix deps.get` of Pulse as a hex package does). This is what proves
# every branch keeps building the source; consumers who install Pulse
# elsewhere leave this unset and download the release artifact.
export PULSE_NIF_FORCE_BUILD="1"
