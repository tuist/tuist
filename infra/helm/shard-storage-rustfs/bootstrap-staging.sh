#!/usr/bin/env bash
# Human-local bootstrap only. Never run in an agent/orb: reads operator credentials.
# Requires op, kubectl, jq, curl and shasum. Downloads a temporary mc if absent.
# No repository checkout needed.
# Default: the four-member Hetzner release. For the single-member OVH release:
#   RUSTFS_RELEASE=rustfs-ovh RUSTFS_HOST=shards-ovh-staging.tuist.dev RUSTFS_TARGET=rustfs-staging-ovh-v1
set -euo pipefail
set +x
umask 077
release=${RUSTFS_RELEASE:-rustfs}
host=${RUSTFS_HOST:-shards-staging.tuist.dev}
target_id=${RUSTFS_TARGET:-rustfs-staging-v1}
case "$release:$host:$target_id" in
  rustfs:shards-staging.tuist.dev:rustfs-staging-v1) ;;
  rustfs-ovh:shards-ovh-staging.tuist.dev:rustfs-staging-ovh-v1) ;;
  *) echo 'Unknown release/host/target combination; stop for review.' >&2; exit 1;;
esac
for command in op kubectl jq curl shasum; do
  command -v "$command" >/dev/null || { echo "Missing command: $command" >&2; exit 1; }
done
work=$(mktemp -d)
forward_pid=
phase=preflight
cleanup() {
  if [ -n "$forward_pid" ]; then kill "$forward_pid" 2>/dev/null || true; wait "$forward_pid" 2>/dev/null || true; fi
  rm -rf "$work"
}
trap cleanup EXIT
trap 'echo "Bootstrap failed during: $phase. Do not paste credentials or raw debug logs." >&2' ERR
export MC_CONFIG_DIR="$work/mc"
if ! command -v mc >/dev/null; then
  phase='temporary MinIO client download'
  case "$(uname -s)-$(uname -m)" in
    Darwin-arm64) platform=darwin-arm64;;
    Darwin-x86_64) platform=darwin-amd64;;
    Linux-x86_64) platform=linux-amd64;;
    Linux-aarch64) platform=linux-arm64;;
    *) echo 'Install MinIO mc for this platform first.' >&2; exit 1;;
  esac
  mc_release=RELEASE.2025-08-13T08-35-41Z
  asset="mc.$platform.$mc_release"
  url="https://github.com/minio/mc/releases/download/$mc_release/$asset"
  mkdir "$work/bin"
  curl -fsSL "$url" -o "$work/bin/$asset"
  curl -fsSL "$url.sha256sum" -o "$work/bin/$asset.sha256sum"
  expected=$(awk '{print $1}' "$work/bin/$asset.sha256sum")
  actual=$(shasum -a 256 "$work/bin/$asset" | awk '{print $1}')
  test "$actual" = "$expected"
  mv "$work/bin/$asset" "$work/bin/mc"
  chmod 700 "$work/bin/mc"
  export PATH="$work/bin:$PATH"
fi
phase='operator credentials and cluster preflight'
op document get 'kubeconfig: tuist-staging' --account tuist.1password.com \
  --vault tuist-k8s-staging >"$work/kubeconfig"
k() { kubectl --kubeconfig "$work/kubeconfig" "$@"; }
m() { mc "$@" >"$work/mc-output" 2>&1; }
k -n rustfs-staging wait --for=condition=Ready pod -l app="$release" --timeout=60s
k -n rustfs-staging wait --for=condition=Ready certificate/"$release-public-tls" --timeout=60s
test "$(curl -sS --max-time 20 -o /dev/null -w '%{http_code}' "https://$host/shards")" = 403

# Discover the live reference rather than assuming a Secret key or overwriting Garage.
k -n tuist-staging get deploy tuist-tuist-server -o json >"$work/deployment.json"
jq -er '[.spec.template.spec.containers[].env[]? |
  select(.name == "TUIST_SHARD_STORAGE_TARGETS") | .valueFrom.secretKeyRef] |
  if length == 1 then .[0] else error("Expected one storage-target reference") end' \
  "$work/deployment.json" >"$work/reference.json"
secret_name=$(jq -er .name "$work/reference.json")
secret_key=$(jq -er .key "$work/reference.json")
test "$secret_name" = shard-storage-targets
case "$secret_key" in targets|targets.json) ;; *) echo 'Unexpected storage-target key; stop for review.' >&2; exit 1;; esac
k -n tuist-staging get secret "$secret_name" -o json >"$work/secret.json"
jq -er --arg key "$secret_key" '.data[$key] | @base64d | fromjson |
  if type == "object" then . else error("Expected target map") end' \
  "$work/secret.json" >"$work/targets.json"

phase='service credential provisioning'
op item list --account tuist.1password.com --vault tuist-k8s-staging --format json >"$work/items.json"
count=$(jq '[.[] | select(.title == "RUSTFS_STAGING_SHARDS")] | length' "$work/items.json")
case "$count" in
  0)
    op item create --account tuist.1password.com --vault tuist-k8s-staging \
      --category Password --title RUSTFS_STAGING_SHARDS \
      --generate-password='letters,digits,64' 'access-key[text]=rustfs-staging-shards' >/dev/null
    ;;
  1) ;;
  *) echo 'Duplicate RUSTFS_STAGING_SHARDS items; stop for review.' >&2; exit 1;;
esac
op read 'op://tuist-k8s-staging/RUSTFS_STAGING_ROOT/root-user' --account tuist.1password.com >"$work/root-user"
op read 'op://tuist-k8s-staging/RUSTFS_STAGING_ROOT/password' --account tuist.1password.com >"$work/root-password"
op read 'op://tuist-k8s-staging/RUSTFS_STAGING_SHARDS/access-key' --account tuist.1password.com >"$work/service-user"
op read 'op://tuist-k8s-staging/RUSTFS_STAGING_SHARDS/password' --account tuist.1password.com >"$work/service-password"
service_user=$(cat "$work/service-user")
test "$service_user" = rustfs-staging-shards

phase='loopback admin connection'
# Let kubectl choose a free local port; refuse stale/unrelated port-forwards.
k -n rustfs-staging port-forward --address 127.0.0.1 pod/"$release-0" :9000 >"$work/forward.log" 2>&1 &
forward_pid=$!
for attempt in $(seq 1 30); do
  kill -0 "$forward_pid"
  port=$(sed -n 's/^Forwarding from 127.0.0.1:\([0-9]*\) -> 9000$/\1/p' "$work/forward.log")
  if [ -n "$port" ]; then break; fi
  sleep 1
done
test -n "$port"
MC_HOST_admin=$(jq -nr --rawfile user "$work/root-user" --rawfile password "$work/root-password" \
  --arg port "$port" '"http://" + ($user | rtrimstr("\n") | @uri) + ":" +
  ($password | rtrimstr("\n") | @uri) + "@127.0.0.1:" + $port')
MC_HOST_service=$(jq -nr --rawfile user "$work/service-user" --rawfile password "$work/service-password" --arg host "$host" \
  '"https://" + ($user | rtrimstr("\n") | @uri) + ":" +
  ($password | rtrimstr("\n") | @uri) + "@" + $host')
export MC_HOST_admin MC_HOST_service

phase='bucket, lifecycle and restricted user'
cat >"$work/lifecycle.json" <<'JSON'
{"Rules":[{"ID":"disposable-staging-shards","Status":"Enabled","Filter":{"Prefix":""},"Expiration":{"Days":3},"AbortIncompleteMultipartUpload":{"DaysAfterInitiation":1}}]}
JSON
cat >"$work/policy.json" <<'JSON'
{"Version":"2012-10-17","Statement":[{"Effect":"Allow","Action":["s3:GetBucketLocation","s3:ListBucket","s3:ListBucketMultipartUploads"],"Resource":"arn:aws:s3:::shards"},{"Effect":"Allow","Action":["s3:GetObject","s3:PutObject","s3:DeleteObject","s3:AbortMultipartUpload","s3:ListMultipartUploadParts"],"Resource":"arn:aws:s3:::shards/*"}]}
JSON
m mb --ignore-existing admin/shards
m ilm import admin/shards <"$work/lifecycle.json"
mc ilm export admin/shards >"$work/lifecycle-readback.json" 2>"$work/mc-output"
jq -e 'any(.Rules[]; .ID == "disposable-staging-shards" and .Status == "Enabled" and
  .Expiration.Days == 3 and .AbortIncompleteMultipartUpload.DaysAfterInitiation == 1)' \
  "$work/lifecycle-readback.json" >/dev/null
m admin policy create admin shard-artifacts "$work/policy.json"
# mc accepts keys on stdin; neither credential is put in process arguments.
printf '%s\n%s\n' "$service_user" "$(cat "$work/service-password")" | m admin user add admin
m admin policy attach admin shard-artifacts --user "$service_user"

phase='authenticated public transfer and private admin denial'
object="operator-bootstrap-$(date +%s)-$$"
printf 'RustFS staging public HTTPS qualification %s\n' "$object" >"$work/input"
m cp "$work/input" "service/shards/$object"
mc cat "service/shards/$object" >"$work/output" 2>"$work/mc-output"
cmp "$work/input" "$work/output"
m rm "service/shards/$object"
export MC_HOST_limited="${MC_HOST_service%@*}@127.0.0.1:$port"
export MC_HOST_limited="${MC_HOST_limited/https:/http:}"
m stat limited/shards
m admin info admin
if m admin info limited; then
  echo 'FAIL: service credential can administer RustFS; target not published.' >&2
  exit 1
fi
grep -Eqi 'Access.?Denied|not allowed|insufficient permissions' "$work/mc-output"

phase='publishing target while preserving existing entries'
jq -n --arg endpoint "https://$host" --rawfile user "$work/service-user" --rawfile password "$work/service-password" \
  '{access:"public", site:"staging", enabled:true, private_network_ready:false,
    endpoint:$endpoint, region:"us-east-1", bucket:"shards",
    access_key_id:($user | rtrimstr("\n")), secret_access_key:($password | rtrimstr("\n"))}' \
  < /dev/null >"$work/target.json"
# A rerun may reuse this exact target, but must never repoint a persisted target ID.
jq -e --arg id "$target_id" --slurpfile target "$work/target.json" '
  .[$id] == null or .[$id] == $target[0]' "$work/targets.json" >/dev/null
jq --arg id "$target_id" --slurpfile target "$work/target.json" '.[$id] = $target[0]' \
  "$work/targets.json" >"$work/merged.json"
jq --arg key "$secret_key" --rawfile targets "$work/merged.json" '
  [{op:"test",path:"/metadata/resourceVersion",value:.metadata.resourceVersion},
   {op:"replace",path:("/data/" + $key),value:($targets | @base64)}]' \
  "$work/secret.json" >"$work/patch.json"
k -n tuist-staging patch secret "$secret_name" --type=json --patch-file "$work/patch.json" >/dev/null
echo 'PASS: bucket/lifecycle/user ready; public PUT/GET/DELETE verified; service admin denied.'
echo "PASS: $target_id published; existing targets preserved. No server restart or account enrollment."
