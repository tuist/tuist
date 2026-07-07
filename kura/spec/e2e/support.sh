# shellcheck shell=bash

PROJECT_ROOT="${KURA_PROJECT_ROOT:?missing KURA_PROJECT_ROOT}"

# Detach stdin (`docker compose exec` attaches the caller's stdin by default, unlike
# raw `docker exec`). Under shellspec the inherited stdin is wired into the
# executor->reporter pipeline, so an attached `compose exec` corrupts the descriptor
# the reporter reads from and crashes it ([reporter: 1]) even when examples pass.
# No `dc` subcommand we use reads stdin, so redirecting from /dev/null is safe.
#
# `--env-file` supplies compose interpolation values and COMPOSE_PROJECT_NAME from a
# per-suite file (populated via `suite_env`) instead of exported variables, so each
# suite stays scoped and never leaks settings into the shell process that shellspec
# shares across spec files.
dc() {
  docker compose --env-file "${COMPOSE_ENV_FILE}" "${COMPOSE_FILES[@]}" "$@" </dev/null
}

dc_container_id() {
  dc ps -q "$1"
}

compose_up() {
  if [ "${KURA_E2E_SKIP_BUILD:-0}" = "1" ]; then
    dc up -d "$@" >/dev/null 2>&1
  else
    dc up --build -d "$@" >/dev/null 2>&1
  fi
}

setup_suite_tmpdir() {
  SUITE_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kura-e2e.XXXXXX")"
  COMPOSE_ENV_FILE="${SUITE_TMP_DIR}/compose.env"
  : >"${COMPOSE_ENV_FILE}"
}

# Set NAME=VALUE as a non-exported shell variable for in-shell use and record it in
# the per-suite env file that `dc` feeds to `docker compose --env-file`. This replaces
# the previous `export`/`unset` pattern: values reach both docker compose and the spec
# body without leaking into the process environment shellspec shares across spec files,
# so suites no longer have to unset state to avoid bleeding into one another.
suite_env() {
  printf -v "$1" '%s' "$2"
  printf '%s=%s\n' "$1" "$2" >>"${COMPOSE_ENV_FILE}"
}

# Request ephemeral host ports for the given compose variables by recording each as 0
# in the suite env file. docker compose then publishes those container ports on a free
# host port chosen by the kernel, so parallel suites (`shellspec -j N`) can never clash
# on `port is already allocated`. Read the actual ports back after startup with
# resolve_http_node / resolve_host_port.
ephemeral_ports() {
  local name
  for name in "$@"; do
    suite_env "$name" 0
  done
}

# Print the host port docker compose published for SERVICE's CONTAINER_PORT.
# `docker compose port` prints e.g. "0.0.0.0:49153"; emit just the port number.
resolve_host_port() {
  dc port "$1" "$2" | head -n1 | sed 's/.*://'
}

# Resolve SERVICE's published client port (CONTAINER_PORT, default 4000 — kura's
# single co-hosted HTTP + h2c gRPC listener, so both cache and REAPI traffic ride
# one endpoint) into the shell vars <PREFIX>_PORT and
# <PREFIX>_URL, e.g. `resolve_http_node KURA_US kura-us` sets KURA_US_PORT and
# KURA_US_URL=http://localhost:<port>. Pass an explicit CONTAINER_PORT (e.g. 4000)
# to reach a dedicated listener instead. Call it after every `dc up`, `dc
# restart`, or `dc stop`+`dc up` of the service: an ephemeral host port is
# re-allocated on each container start (recreate AND plain restart change it).
resolve_http_node() {
  local prefix="$1" service="$2" container_port="${3:-4000}" port
  port="$(resolve_host_port "$service" "$container_port")"
  printf -v "${prefix}_PORT" '%s' "$port"
  printf -v "${prefix}_URL" 'http://localhost:%s' "$port"
}

compose_teardown() {
  if [ -n "${SUITE_TMP_DIR:-}" ] && [ -d "${SUITE_TMP_DIR}" ]; then
    dc logs --no-color >"${SUITE_TMP_DIR}/compose.log" 2>&1 || true
  fi
  dc down -v --remove-orphans >/dev/null 2>&1 || true
  if [ -n "${SUITE_TMP_DIR:-}" ] && [ -d "${SUITE_TMP_DIR}" ]; then
    rm -rf "${SUITE_TMP_DIR}"
  fi
}

capture_into() {
  local __var="$1"
  shift
  local __output
  __output="$("$@" 2>&1)"
  local __status=$?
  printf -v "$__var" '%s' "$__output"
  return "$__status"
}

status_only() {
  curl -sS -o /dev/null -w "%{http_code}" "$@"
}

container_status() {
  docker inspect --format '{{.State.Status}}' "$(dc_container_id "$1")"
}

container_restart_count() {
  docker inspect --format '{{.RestartCount}}' "$(dc_container_id "$1")"
}

container_oom_killed() {
  docker inspect --format '{{.State.OOMKilled}}' "$(dc_container_id "$1")"
}

run_parallel_http_gets() {
  local url="$1"
  local workers="$2"
  local iterations="$3"
  local failures=0
  local pids=()

  for worker in $(seq 1 "$workers"); do
    (
      for _ in $(seq 1 "$iterations"); do
        curl -fsS --max-time 20 -o /dev/null "$url" || exit 1
      done
    ) &
    pids+=("$!")
  done

  for pid in "${pids[@]}"; do
    if ! wait "$pid"; then
      failures=1
    fi
  done

  return "$failures"
}

wait_for_http() {
  local url="$1"
  local attempts="${2:-90}"
  local sleep_seconds="${3:-2}"

  for _ in $(seq 1 "$attempts"); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep "$sleep_seconds"
  done

  printf 'Timed out waiting for %s\n' "$url" >&2
  return 1
}

wait_for_status() {
  local url="$1"
  local expected_status="$2"
  local attempts="${3:-45}"
  local sleep_seconds="${4:-2}"
  local actual_status

  for _ in $(seq 1 "$attempts"); do
    actual_status="$(status_only "$url" 2>/dev/null || true)"
    if [ "$actual_status" = "$expected_status" ]; then
      printf '%s' "$actual_status"
      return 0
    fi
    sleep "$sleep_seconds"
  done

  printf 'Timed out waiting for %s to return %s (last status %s)\n' "$url" "$expected_status" "${actual_status:-unknown}" >&2
  return 1
}

# Like wait_for_status but forwards trailing arguments to status_only (and thus
# curl), so callers can attach an auth header or method. The extension suite needs
# this: every cache request must carry a Bearer token, so the bare wait_for_status
# (which only sends an unauthenticated GET) can never reach a 2xx there.
wait_for_status_with() {
  local url="$1"
  local expected_status="$2"
  shift 2
  local attempts=45
  local sleep_seconds=2
  local actual_status

  for _ in $(seq 1 "$attempts"); do
    actual_status="$(status_only "$url" "$@" 2>/dev/null || true)"
    if [ "$actual_status" = "$expected_status" ]; then
      printf '%s' "$actual_status"
      return 0
    fi
    sleep "$sleep_seconds"
  done

  printf 'Timed out waiting for %s to return %s (last status %s)\n' "$url" "$expected_status" "${actual_status:-unknown}" >&2
  return 1
}

wait_for_head_status() {
  local url="$1"
  local expected_status="$2"
  local attempts="${3:-45}"
  local sleep_seconds="${4:-2}"
  local actual_status

  for _ in $(seq 1 "$attempts"); do
    actual_status="$(status_only -I "$url" 2>/dev/null || true)"
    if [ "$actual_status" = "$expected_status" ]; then
      printf '%s' "$actual_status"
      return 0
    fi
    sleep "$sleep_seconds"
  done

  printf 'Timed out waiting for HEAD %s to return %s (last status %s)\n' "$url" "$expected_status" "${actual_status:-unknown}" >&2
  return 1
}

wait_for_contains() {
  local url="$1"
  local needle="$2"
  local attempts="${3:-45}"
  local sleep_seconds="${4:-2}"
  local body

  for _ in $(seq 1 "$attempts"); do
    body="$(curl -fsS "$url" 2>/dev/null || true)"
    if [[ "$body" == *"$needle"* ]]; then
      printf '%s' "$body"
      return 0
    fi
    sleep "$sleep_seconds"
  done

  printf 'Timed out waiting for [%s] in %s\n' "$needle" "$url" >&2
  return 1
}

wait_for_all_contains() {
  local url="$1"
  shift
  local attempts=45
  local sleep_seconds=2
  local body
  local needle
  local matched

  for _ in $(seq 1 "$attempts"); do
    body="$(curl -fsS "$url" 2>/dev/null || true)"
    matched=1
    for needle in "$@"; do
      if [[ "$body" != *"$needle"* ]]; then
        matched=0
        break
      fi
    done
    if [ -n "$body" ] && [ "$matched" -eq 1 ]; then
      printf '%s' "$body"
      return 0
    fi
    sleep "$sleep_seconds"
  done

  printf 'Timed out waiting for [%s] in %s\n' "$*" "$url" >&2
  return 1
}

new_marker() {
  python3 - <<'PY'
import secrets
print(secrets.token_hex(8))
PY
}

extract_upload_id() {
  printf '%s' "$1" | sed -E 's/.*"upload_id":"([^"]+)".*/\1/'
}

jwt_for_namespace() {
  local namespace_id="$1"
  python3 - "$namespace_id" <<'PY'
import base64
import hashlib
import hmac
import json
import sys

def b64url(data: bytes) -> str:
    return base64.urlsafe_b64encode(data).rstrip(b"=").decode()

namespace_id = sys.argv[1]
header = {"alg": "HS256", "typ": "JWT"}
payload = {"sub": "user-1", "namespace_id": namespace_id, "exp": 4000000000}

header_b64 = b64url(json.dumps(header, separators=(",", ":")).encode())
payload_b64 = b64url(json.dumps(payload, separators=(",", ":")).encode())
signing_input = f"{header_b64}.{payload_b64}".encode()
signature = hmac.new(b"extension-jwt-secret", signing_input, hashlib.sha256).digest()
print(f"{header_b64}.{payload_b64}.{b64url(signature)}")
PY
}

expected_signature() {
  local payload="$1"
  python3 - "$payload" <<'PY'
import base64
import hashlib
import hmac
import sys

payload = sys.argv[1].encode()
signature = hmac.new(b"extension-signing-secret", payload, hashlib.sha256).digest()
print(base64.b64encode(signature).decode())
PY
}

create_bazel_workspace() {
  local dir="$1"
  local marker="$2"

  mkdir -p "$dir"
  cat >"$dir/MODULE.bazel" <<'EOF'
module(name = "kura_bazel_demo")
EOF
  cat >"$dir/BUILD.bazel" <<EOF
genrule(
    name = "hello",
    outs = ["hello.txt"],
    cmd = "echo ${marker} > \$@",
)
EOF
}

bazel_build() {
  local dir="$1"
  local grpc_port="$2"
  local instance_name="$3"
  local bazel_path
  bazel_path="$(mise exec -- which bazel)"

  (
    cd "$dir"
    "$bazel_path" \
      build //:hello \
      --remote_cache="grpc://127.0.0.1:${grpc_port}" \
      --remote_instance_name="${instance_name}" \
      --remote_upload_local_results=true \
      --remote_download_outputs=all \
      --show_result=0 \
      --noshow_loading_progress \
      --noshow_progress
  )
}

create_buck_workspace() {
  local dir="$1"
  local grpc_port="$2"
  local marker="$3"
  local instance_name="$4"
  local buck2_path
  buck2_path="$(mise exec -- which buck2)"

  mkdir -p "$dir"
  (
    cd "$dir"
    "$buck2_path" init --git >/dev/null 2>&1
    mkdir -p platforms
    cat > platforms/defs.bzl <<'EOF'
def _impl(ctx):
    configuration = ConfigurationInfo(constraints = {}, values = {})

    platform = ExecutionPlatformInfo(
        label = ctx.label.raw_target(),
        configuration = configuration,
        executor_config = CommandExecutorConfig(
            local_enabled = True,
            remote_enabled = False,
            remote_cache_enabled = True,
            allow_cache_uploads = True,
            use_limited_hybrid = False,
        ),
    )

    return [DefaultInfo(), ExecutionPlatformRegistrationInfo(platforms = [platform])]

platforms = rule(attrs = {}, impl = _impl)
EOF
    cat > platforms/BUCK <<'EOF'
load(":defs.bzl", "platforms")
platforms(name = "platforms")
EOF
    cat > .buckconfig.local <<EOF
[build]
  execution_platforms = root//platforms:platforms

[buck2_re_client]
  action_cache_address = grpc://127.0.0.1:${grpc_port}
  cas_address = grpc://127.0.0.1:${grpc_port}
  engine_address = grpc://127.0.0.1:${grpc_port}
  tls = false
  instance_name = ${instance_name}
EOF
    cat > BUCK <<EOF
genrule(
    name = "hello_world",
    out = "out.txt",
    cmd = "echo ${marker} > \$OUT",
    cacheable = True,
    labels = ["network_access"],
)
EOF
  )
}

buck_build() {
  local dir="$1"
  local isolation_dir="$2"
  local buck2_path
  buck2_path="$(mise exec -- which buck2)"

  (
    cd "$dir"
    "$buck2_path" build //:hello_world --show-output --console=simple --isolation-dir "${isolation_dir}"
  )
}

kill_buck2() {
  local buck2_path
  buck2_path="$(mise exec -- which buck2 2>/dev/null || true)"
  if [ -n "$buck2_path" ]; then
    "$buck2_path" killall >/dev/null 2>&1 || true
  fi
}

kill_bazel_servers() {
  pkill -f 'bazel\(bazel-' >/dev/null 2>&1 || true
}

generate_peer_tls_material() {
  mkdir -p "${KURA_MTLS_CERT_DIR}"

  cat >"${KURA_MTLS_CERT_DIR}/openssl.cnf" <<'EOF'
[req]
distinguished_name = req_distinguished_name
prompt = no

[req_distinguished_name]
CN = kura-peer

[peer_cert]
basicConstraints = CA:false
keyUsage = critical, digitalSignature, keyEncipherment
extendedKeyUsage = serverAuth, clientAuth
subjectAltName = @alt_names

[alt_names]
DNS.1 = kura-us.kura.internal
DNS.2 = kura-eu.kura.internal
DNS.3 = kura-ap.kura.internal
DNS.4 = kura-ring.kura.internal
EOF

  openssl genrsa -out "${KURA_MTLS_CERT_DIR}/ca.key" 2048 >/dev/null 2>&1
  openssl req -x509 -new -nodes \
    -key "${KURA_MTLS_CERT_DIR}/ca.key" \
    -sha256 \
    -days 3650 \
    -out "${KURA_MTLS_CERT_DIR}/ca.pem" \
    -subj "/CN=kura-peer-ca" >/dev/null 2>&1

  openssl genrsa -out "${KURA_MTLS_CERT_DIR}/peer.key" 2048 >/dev/null 2>&1
  openssl req -new \
    -key "${KURA_MTLS_CERT_DIR}/peer.key" \
    -out "${KURA_MTLS_CERT_DIR}/peer.csr" \
    -config "${KURA_MTLS_CERT_DIR}/openssl.cnf" >/dev/null 2>&1
  openssl x509 -req \
    -in "${KURA_MTLS_CERT_DIR}/peer.csr" \
    -CA "${KURA_MTLS_CERT_DIR}/ca.pem" \
    -CAkey "${KURA_MTLS_CERT_DIR}/ca.key" \
    -CAcreateserial \
    -out "${KURA_MTLS_CERT_DIR}/peer.pem" \
    -days 3650 \
    -sha256 \
    -extfile "${KURA_MTLS_CERT_DIR}/openssl.cnf" \
    -extensions peer_cert >/dev/null 2>&1
}
