#!/usr/bin/env bash
# Pod-shaped check that cache volumes reach Docker child containers: a
# privileged docker:dind runs the mount broker and dockerd, an unprivileged
# runner shares its network and the work/cache volumes, like a runner pod.
# Usage: cache-volume-docker-e2e.sh /path/to/static/tuist-cache-volume
set -euo pipefail

client=$(cd "$(dirname "$1")" && pwd)/$(basename "$1")
p="cache-volume-e2e-$$"
work=/home/runner/work
cleanup() {
  docker rm -f "$p-dind" "$p-runner" >/dev/null 2>&1 || true
  docker volume rm "$p-work" "$p-cache" >/dev/null 2>&1 || true
}
trap cleanup EXIT
fail() { echo "FAIL: $*" >&2; exit 1; }

docker volume create "$p-work" >/dev/null
docker volume create "$p-cache" >/dev/null
scope=$(docker run --rm alpine sh -c 'printf scope | sha256sum | cut -d" " -f1')
docker run --rm -v "$p-cache:/c" -v "$p-work:/w" alpine sh -c \
  "mkdir -p /c/$scope/data /w/native /w/job && echo warm > /c/$scope/data/warm && printf lease > /c/$scope/.tuist-volume && chmod -R 777 /c /w"

docker run -d --name "$p-dind" --privileged \
  -v "$p-work:$work" -v "$p-cache:$work/_tuist_cache" -v "$client:/ext/tuist-cache-volume:ro" \
  docker:dind sh -c "(/ext/tuist-cache-volume mount-server $work/.tuist-cache-mount.sock $work/_tuist_cache &); exec dockerd --host=unix:///var/run/docker.sock" >/dev/null
for _ in $(seq 1 60); do
  docker exec "$p-dind" sh -c "test -S $work/.tuist-cache-mount.sock && docker info" >/dev/null 2>&1 && break
  sleep 1
done
docker exec "$p-dind" docker pull -q alpine >/dev/null

agent='import http.server,json
class H(http.server.BaseHTTPRequestHandler):
    def do_POST(self):
        self.rfile.read(int(self.headers.get("Content-Length",0)))
        b=json.dumps({"directory":"'"$scope"'","id":"lease","warm":True}).encode()
        self.send_response(200);self.send_header("Content-Length",str(len(b)));self.end_headers();self.wfile.write(b)
http.server.HTTPServer(("127.0.0.1",8090),H).serve_forever()'
docker run -d --name "$p-runner" --network "container:$p-dind" --user 1001:1001 -e HOME=/tmp \
  -e TUIST_CACHE_VOLUME_URL=http://127.0.0.1:8090 \
  -v "$p-work:$work" -v "$p-cache:$work/_tuist_cache" -v "$client:/ext/tuist-cache-volume:ro" \
  python:3.12-alpine python3 -c "$agent" >/dev/null
sleep 2

child() { docker exec "$p-dind" docker run --rm -v "$work/$1:/workspace" -w /workspace alpine sh -c "$2"; }
volume_has() { docker exec "$p-dind" test -f "$work/_tuist_cache/$scope/data/$1"; }

# Native job: the client runs in the runner container.
docker exec -w "$work/native" "$p-runner" /ext/tuist-cache-volume --key deps --path deps
docker exec "$p-runner" awk -v p="$work/native/deps" '$5 == p { found = 1 } END { exit !found }' /proc/self/mountinfo ||
  fail "native target is not a mount"
child native 'test -f deps/warm && touch deps/native-child' || fail "docker child did not see the native volume"
volume_has native-child || fail "docker child write did not reach the volume"
docker exec "$p-runner" test -f "$work/native/deps/native-child" || fail "runner did not see the child's write"

# container: job: the client runs in a container dockerd started with the work
# directory at /__w, then a later child binds the checkout.
docker exec "$p-dind" docker run --rm --network host -e TUIST_CACHE_VOLUME_URL=http://127.0.0.1:8090 \
  -v "$work:/__w" -v /ext/tuist-cache-volume:/__e/tuist-cache-volume:ro -w /__w/job alpine \
  sh -c '/__e/tuist-cache-volume --key deps --path deps && test -f deps/warm && touch deps/job-container'
child job 'test -f deps/job-container && touch deps/job-child' || fail "docker child did not see the job container's volume"
volume_has job-child || fail "docker child write did not reach the volume"

echo "Cache volumes reach Docker child containers"
