#!/usr/bin/env bash
# Checkout-relative cache binds on real Firecracker guests, on a disposable
# GitHub-hosted KVM VM.
#
# A CI job that caches `server/deps` with tuist-cache-volume leaves a volume
# whose `.tuist-paths` is {"server/deps":"data"}: the path is relative to the
# job's checkout. This builds such a volume as an ext4 image (the layout seen
# on a production master, data owned by the runner's UID 1000), attaches it
# to a sandbox cloned from a disk snapshot, and runs, as root inside the guest,
# internal/guest's TestBindCheckoutCacheEndToEnd against the drive the guest
# agent's configure mounted: the same BindCheckoutCache sbx-worker calls after
# seeding a Claude Code session's checkout. It checks the bind, its ownership,
# an empty target, a second call, a checkout's own deps kept and a symlinked
# parent refused, then the mount after a pause and resume. It then archives the
# disk snapshot to a local object store (archive_disks, as the server does for
# a project snapshot) and runs the same test in a sandbox created from that
# object alone with the cache image: how a session starts when no node holds
# the snapshot any more.
#
# NOT COVERED: sbx-worker's call site (it needs a Claude Code work order), the
# runner-cache agent's copy, the server's grant and S3 (the store is a local
# HTTP server answering UploadPart and ranged GETs).
set -euo pipefail
[[ "${GITHUB_ACTIONS:-}" == true && "${RUNNER_ENVIRONMENT:-}" == github-hosted ]] || {
  echo 'Run this only on a disposable GitHub-hosted Linux runner.' >&2
  exit 1
}
[[ $(uname -sm) == 'Linux x86_64' ]]
test -c /dev/kvm
repo=$(git rev-parse --show-toplevel)
work=$(mktemp -d "${RUNNER_TEMP:?}/checkout-cache.XXXXXX")
evidence="$RUNNER_TEMP/checkout-cache-evidence"
mkdir -p "$evidence" "$work/data"
daemon="checkout-cache-${GITHUB_RUN_ID:?}-${GITHUB_RUN_ATTEMPT:-1}"
go_version=$(awk '$1 == "go" { print $2 }' "$repo/infra/sandbox-image/go.mod")
go_url="https://go.dev/dl/go${go_version}.linux-amd64.tar.gz"
loop=''
store_pid=''
cleanup() {
  local rc=$?
  trap - EXIT
  if [[ -n "$store_pid" ]]; then kill "$store_pid" 2>/dev/null || true; fi
  docker logs "$daemon" > "$evidence/sandboxd.log" 2>&1 || true
  docker rm -f "$daemon" >/dev/null 2>&1 || true
  if mountpoint -q "$work/data"; then sudo umount "$work/data" || rc=1; fi
  if [[ -n "$loop" ]] && ! mountpoint -q "$work/data"; then sudo losetup -d "$loop" || rc=1; fi
  if ! mountpoint -q "$work/data"; then sudo rm -rf "$work"; fi
  exit "$rc"
}
trap cleanup EXIT
exec > >(tee "$evidence/checkout-cache.log") 2>&1

truncate -s 40G "$work/data.xfs"
loop=$(sudo losetup --find --show "$work/data.xfs")
sudo mkfs.xfs -q -m reflink=1 "$loop"
sudo mount "$loop" "$work/data"
docker run --rm -v "$work/data:/host" -e TEMPLATE_TAG=validation sandbox-orbs-template:validation

# The volume a CI job caching `server/deps` saves (tuist-cache-volume's
# single-path layout).
mkdir -p "$work/volume/data/phoenix/lib"
printf '{"version":1,"paths":{"server/deps":"data"}}\n' > "$work/volume/.tuist-paths"
echo cached > "$work/volume/data/mix.lock.cached"
echo 'defmodule Phoenix do end' > "$work/volume/data/phoenix/lib/phoenix.ex"
sudo chown -R 1000:1000 "$work/volume"
sudo mkdir -p "$work/data/cache-images"
sudo mkfs.ext4 -q -F -d "$work/volume" "$work/data/cache-images/checkout-cache" 1G

# The object store archives go to: UploadPart PUTs (?partNumber=N, answering
# an ETag) and GETs of the parts joined, ranged or whole.
cat > "$work/store.py" <<'PY'
import http.server, os, re, sys
root, port = sys.argv[1], int(sys.argv[2])
os.makedirs(root, exist_ok=True)

def parts():
    names = sorted(n for n in os.listdir(root) if not n.startswith('.'))
    return [(os.path.join(root, n), os.path.getsize(os.path.join(root, n))) for n in names]

class Store(http.server.BaseHTTPRequestHandler):
    protocol_version = 'HTTP/1.1'

    def do_PUT(self):
        number = int(re.search(r'partNumber=(\d+)', self.path).group(1))
        left = int(self.headers['Content-Length'])
        tmp = os.path.join(root, '.%d.tmp' % number)
        with open(tmp, 'wb') as f:
            while left:
                chunk = self.rfile.read(min(left, 1 << 20))
                if not chunk:
                    raise ConnectionError('short part')
                f.write(chunk)
                left -= len(chunk)
        os.replace(tmp, os.path.join(root, '%05d' % number))
        self.send_response(200)
        self.send_header('ETag', '"etag-%d"' % number)
        self.send_header('Content-Length', '0')
        self.end_headers()

    def do_GET(self):
        files = parts()
        total = sum(size for _, size in files)
        start, end, status = 0, total - 1, 200
        ranged = re.fullmatch(r'bytes=(\d+)-(\d+)', self.headers.get('Range', ''))
        if ranged:
            start, end, status = int(ranged.group(1)), min(int(ranged.group(2)), total - 1), 206
        self.send_response(status)
        self.send_header('Content-Length', str(max(end - start + 1, 0)))
        if ranged:
            self.send_header('Content-Range', 'bytes %d-%d/%d' % (start, end, total))
        self.end_headers()
        offset = 0
        for path, size in files:
            lo, hi = max(start, offset), min(end + 1, offset + size)
            if lo < hi:
                with open(path, 'rb') as f:
                    f.seek(lo - offset)
                    left = hi - lo
                    while left:
                        chunk = f.read(min(left, 1 << 20))
                        self.wfile.write(chunk)
                        left -= len(chunk)
            offset += size

http.server.ThreadingHTTPServer(('0.0.0.0', port), Store).serve_forever()
PY
python3 -I "$work/store.py" "$work/store" 9472 > "$evidence/store.log" 2>&1 &
store_pid=$!

docker run -d --name "$daemon" --privileged --cgroupns=host --dns 1.1.1.1 --dns 8.8.8.8 \
  --add-host objstore:host-gateway \
  -v "$work/data:/data/sandboxes" -p 127.0.0.1:9471:9471 \
  -e ADMIN_ADDR=:9471 -e TEMPLATE_TAG=validation -e CACHE_IMAGE_DIR=/data/sandboxes/cache-images \
  -e BOOT_TIMEOUT=120s -e TEMPLATE_BOOT_TIMEOUT=180s -e SHUTDOWN_TIMEOUT=60s \
  sandbox-orbs-daemon:validation >/dev/null
for _ in {1..60}; do
  curl --silent --fail http://127.0.0.1:9471/healthz >/dev/null && break
  sleep 1
done
api() {
  local method=$1 path=$2
  shift 2
  curl --silent --show-error --fail-with-body --max-time 900 \
    -H 'content-type: application/json' -X "$method" "http://127.0.0.1:9471$path" "$@"
}
# guest ID SCRIPT: runs as root in the guest, prints stdout, fails on a
# non-zero exit.
guest() {
  local response
  response=$(printf '%s' "$2" | jq -Rsc '{cmd:["/bin/bash","-euc",.],timeout_ms:840000}' \
    | api POST "/v1/sandboxes/$1/exec" --data-binary @-)
  jq -r '.stdout, .stderr' <<< "$response"
  jq -e '.exit_code == 0' <<< "$response" >/dev/null
}

# A disk snapshot with Go and the guest module, so the test runs offline.
tar -C "$repo/infra/sandbox-image" -czf "$work/src.tgz" go.mod go.sum internal
src_sha=$(sha256sum "$work/src.tgz" | cut -d' ' -f1)
api POST /v1/sandboxes --data '{"id":"base","template":"default","vcpus":2,"memory_mb":4096,"workspace_gb":2}' > "$evidence/create-base.json"
base64 -w0 "$work/src.tgz" | split -b 96K - "$work/src.b64."
for part in "$work"/src.b64.*; do
  guest base "printf '%s' '$(cat "$part")' >> /tmp/src.b64" >/dev/null
done
guest base 'for _ in $(seq 60); do getent hosts go.dev proxy.golang.org >/dev/null && exit 0; sleep 1; done; exit 1'
guest base "curl --fail --silent --show-error --location --retry 3 -o /tmp/go.tgz '$go_url'
rm -rf /usr/local/go && tar -C /usr/local -xzf /tmp/go.tgz
base64 -d /tmp/src.b64 > /tmp/src.tgz && echo '$src_sha  /tmp/src.tgz' | sha256sum -c -
mkdir -p /opt/sandbox-image && tar -C /opt/sandbox-image -xzf /tmp/src.tgz
cd /opt/sandbox-image && GOTOOLCHAIN=local CGO_ENABLED=0 /usr/local/go/bin/go test -c -o /opt/guest.test ./internal/guest
rm /tmp/go.tgz /tmp/src.tgz /tmp/src.b64"
api POST /v1/sandboxes/base/pause --data '{"sync_disks":true}' >/dev/null
api POST /v1/sandboxes/base/save_disks --data '{"snapshot_id":"guest-test"}' >/dev/null
api POST /v1/sandboxes/base/delete >/dev/null

api POST /v1/sandboxes --data '{"id":"cached","template":"default","vcpus":2,"memory_mb":4096,"workspace_gb":2,"from_disk_snapshot":"guest-test","cache_image":"checkout-cache"}' \
  | tee "$evidence/create-cached.json"
echo
check='findmnt -n -o TARGET,SOURCE,FSTYPE,OPTIONS --mountpoint /mnt/tuist-cache
cat /mnt/tuist-cache/.tuist-paths
SBX_CACHE_E2E_MOUNT=/mnt/tuist-cache /opt/guest.test -test.run TestBindCheckoutCacheEndToEnd -test.v -test.count=1'
guest cached "$check" | tee "$evidence/bind.txt"
api POST /v1/sandboxes/cached/pause --data '{}' > "$evidence/pause.json"
api POST /v1/sandboxes/cached/resume --data '{}' > "$evidence/resume.json"
guest cached "$check" | tee "$evidence/bind-resumed.txt"
api POST /v1/sandboxes/cached/delete >/dev/null

# The same snapshot through its archive: no memory image, so the create cold
# boots it with the cache drive.
part_urls=$(jq -nc '[range(1; 65) | "http://objstore:9472/archive?partNumber=\(.)"]')
jq -nc --argjson urls "$part_urls" '{part_size: 134217728, part_urls: $urls}' \
  | api POST /v1/disk_snapshots/guest-test/archive --data-binary @- | tee "$evidence/archive.json"
echo
jq -e '.disks_synced == true and (.tail_offset // 0) == 0 and .bytes > 0' "$evidence/archive.json" >/dev/null
jq -c '{id: "archived", template: "default", vcpus: 2, memory_mb: 4096, workspace_gb: 2,
  cache_image: "checkout-cache", from_archive: {url: "http://objstore:9472/archive", bytes, sha256}}' \
  "$evidence/archive.json" | api POST /v1/sandboxes --data-binary @- | tee "$evidence/create-archived.json"
echo
guest archived "$check" | tee "$evidence/bind-archive.txt"
api POST /v1/sandboxes/archived/delete >/dev/null
grep -q '"GET /archive HTTP' "$evidence/store.log"

for f in bind bind-resumed bind-archive; do
  grep -q '^/mnt/tuist-cache /dev/vdc ext4 .*noatime' "$evidence/$f.txt"
  grep -q -- '--- PASS: TestBindCheckoutCacheEndToEnd' "$evidence/$f.txt"
  if grep -q -- '--- SKIP' "$evidence/$f.txt"; then exit 1; fi
  [[ $(grep -c -- '    --- PASS:' "$evidence/$f.txt") == 4 ]]
done
echo 'DONE: checkout-relative cache paths bound into a checkout inside real Firecracker guests, from a disk snapshot and from its archive.'
