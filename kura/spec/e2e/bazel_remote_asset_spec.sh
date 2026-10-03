# shellcheck shell=bash

Describe 'Bazel Remote Asset downloads'
  Skip if 'KURA_REMOTE_ASSET_BINARY is not configured' test -z "${KURA_REMOTE_ASSET_BINARY:-}"

  setup_remote_asset() {
    asset_dir="$(mktemp -d)" || return 1
    read -r asset_port asset_internal_port < <(python3 - <<'PY'
import socket
sockets = [socket.socket(), socket.socket()]
for sock in sockets:
    sock.bind(('127.0.0.1', 0))
print(*(sock.getsockname()[1] for sock in sockets))
PY
    )
    KURA_PORT="$asset_port" KURA_INTERNAL_PORT="$asset_internal_port" \
      KURA_TENANT_ID=asset-test KURA_REGION=test KURA_PEERS='' \
      KURA_NODE_URL="http://127.0.0.1:$asset_internal_port" \
      KURA_OTEL_SERVICE_NAME=remote-asset-test KURA_OTEL_DEPLOYMENT_ENVIRONMENT=test \
      KURA_DATA_DIR="$asset_dir/data" KURA_TMP_DIR="$asset_dir/tmp" \
      RUST_LOG=kura::reapi::asset=debug \
      "$KURA_REMOTE_ASSET_BINARY" >"$asset_dir/kura.log" 2>&1 &
    asset_pid=$!
    for ((i = 0; i < 100; i++)); do
      if curl -fsS "http://127.0.0.1:$asset_port/ready" >/dev/null 2>&1; then return 0; fi
      kill -0 "$asset_pid" 2>/dev/null || { cat "$asset_dir/kura.log"; return 1; }
      sleep 0.1
    done
    cat "$asset_dir/kura.log"
    return 1
  }

  teardown_remote_asset() {
    if [ -n "${asset_pid:-}" ]; then
      kill "$asset_pid" 2>/dev/null || true
      wait "$asset_pid" 2>/dev/null || true
    fi
    if [ -n "${asset_dir:-}" ]; then rm -rf "$asset_dir"; fi
  }

  BeforeAll 'setup_remote_asset'
  AfterAll 'teardown_remote_asset'

  download_with_fresh_bazel() {
    local name="$1" workspace="$asset_dir/$1"
    mkdir -p "$workspace"
    cat >"$workspace/MODULE.bazel" <<'MODULE'
module(name = "remote_asset_verification")
asset = use_repo_rule("//:assets.bzl", "asset")
asset(name = "dependency")
MODULE
    touch "$workspace/BUILD.bazel"
    cat >"$workspace/assets.bzl" <<'STARLARK'
def _asset(ctx):
    ctx.download(
        url = "https://github.com/bazel-contrib/supply-chain/releases/download/v0.0.7/supply-chain-v0.0.7.tar.gz",
        integrity = "sha256-jyfcc5Pj873Hk73EujbWemPCLMnTjMZdMgRlSXTqRWM=",
        canonical_id = "kura-remote-asset-e2e",
        output = "archive",
    )
    ctx.file("BUILD.bazel", 'exports_files(["archive"])')
asset = repository_rule(implementation = _asset)
STARLARK
    (cd "$workspace" && bazel --batch --ignore_all_rc_files --output_user_root="$asset_dir/output-$name" \
      build @dependency//:archive \
      --repository_cache="$asset_dir/repositories-$name" \
      --repo_contents_cache="$asset_dir/contents-$name" \
      --experimental_remote_downloader="grpc://127.0.0.1:$asset_port" \
      --remote_cache="grpc://127.0.0.1:$asset_port" \
      --remote_instance_name=asset-test \
      --noexperimental_remote_downloader_local_fallback) >"$asset_dir/$name.log" 2>&1 || {
        cat "$asset_dir/$name.log" "$asset_dir/kura.log"
        return 1
      }
  }

  verify_remote_asset() {
    download_with_fresh_bazel first || return 1
    download_with_fresh_bazel second || return 1
    python3 - "$asset_dir/kura.log" <<'PY'
import base64, pathlib, sys
digest = base64.b64decode('jyfcc5Pj873Hk73EujbWemPCLMnTjMZdMgRlSXTqRWM=').hex()
lines = [line for line in pathlib.Path(sys.argv[1]).read_text().splitlines() if digest in line]
assert sum('remote asset fetched and cached' in line for line in lines) == 1, lines
assert any('remote asset cache hit' in line for line in lines), lines
PY
  }

  It 'downloads through FetchBlob and CAS, then reuses Kura from an empty repository cache'
    When call verify_remote_asset
    The status should be success
    The output should equal ''
  End
End
