# shellcheck shell=bash

PROJECT_ROOT="${KURA_PROJECT_ROOT:?missing KURA_PROJECT_ROOT}"

dc() {
  docker compose "${COMPOSE_FILES[@]}" "$@"
}

dc_container_id() {
  dc ps -q "$1"
}

setup_suite_tmpdir() {
  SUITE_TMP_DIR="$(mktemp -d "${TMPDIR:-/tmp}/kura-e2e.XXXXXX")"
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
    "$buck2_path" init --git >/dev/null
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

create_nx_workspace() {
  local dir="$1"
  local marker="$2"

  mkdir -p "$dir/apps/demo"
  cat >"$dir/package.json" <<'EOF'
{
  "name": "kura-nx-demo",
  "private": true,
  "devDependencies": {
    "nx": "22.6.5"
  }
}
EOF
  cat >"$dir/nx.json" <<'EOF'
{
  "$schema": "./node_modules/nx/schemas/nx-schema.json",
  "targetDefaults": {
    "build": {
      "cache": true,
      "outputs": ["{workspaceRoot}/dist/{projectRoot}"]
    }
  }
}
EOF
  cat >"$dir/apps/demo/project.json" <<EOF
{
  "name": "demo",
  "\$schema": "../../node_modules/nx/schemas/project-schema.json",
  "targets": {
    "build": {
      "executor": "nx:run-commands",
      "options": {
        "command": "mkdir -p dist/apps/demo && echo ${marker} > dist/apps/demo/out.txt"
      }
    }
  }
}
EOF
  (
    cd "$dir"
    npm install --silent --no-audit --no-fund >/dev/null
  )
}

nx_build() {
  local dir="$1"
  local server_url="$2"

  (
    cd "$dir"
    NX_DAEMON=false NX_SELF_HOSTED_REMOTE_CACHE_SERVER="$server_url" npx nx run demo:build --outputStyle=static
  )
}

create_metro_workspace() {
  local dir="$1"

  mkdir -p "$dir"
  cat >"$dir/package.json" <<'EOF'
{
  "name": "kura-metro-demo",
  "private": true,
  "dependencies": {
    "metro-cache": "0.84.3"
  }
}
EOF
  (
    cd "$dir"
    npm install --silent --no-audit --no-fund >/dev/null
  )
}

metro_put() {
  local dir="$1"
  local endpoint="$2"
  local key_hex="$3"
  local payload="$4"

  (
    cd "$dir"
    ENDPOINT="$endpoint" KEY_HEX="$key_hex" PAYLOAD="$payload" node - <<'EOF'
const { HttpStore } = require('metro-cache');

(async () => {
  const store = new HttpStore({ endpoint: process.env.ENDPOINT });
  await store.set(Buffer.from(process.env.KEY_HEX, 'hex'), Buffer.from(process.env.PAYLOAD));
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
EOF
  )
}

metro_get() {
  local dir="$1"
  local endpoint="$2"
  local key_hex="$3"

  (
    cd "$dir"
    ENDPOINT="$endpoint" KEY_HEX="$key_hex" node - <<'EOF'
const { HttpGetStore } = require('metro-cache');

(async () => {
  const store = new HttpGetStore({ endpoint: process.env.ENDPOINT });
  const value = await store.get(Buffer.from(process.env.KEY_HEX, 'hex'));
  if (!value) {
    process.exit(2);
  }
  process.stdout.write(Buffer.isBuffer(value) ? value : Buffer.from(JSON.stringify(value)));
})().catch((error) => {
  console.error(error);
  process.exit(1);
});
EOF
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
