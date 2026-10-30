#!/usr/bin/env bash
set -euo pipefail
: "${ORB_TOKEN:?ORB_TOKEN is required}"
export AMP_URL="${AMP_URL:-https://ampcode.com}"
test -x /usr/local/bin/amp
id user >/dev/null

# Root-owned runtime state survives memory snapshots but disappears on a
# cold boot. A process start time fences PID reuse. Never persist the token.
install -d -m 0700 /run/tuist-amp
exec 9>/run/tuist-amp/lock
flock -x -w 10 9
fingerprint=$(printf '%s\0%s' "$ORB_TOKEN" "$AMP_URL" | sha256sum | cut -d ' ' -f 1)
start_time() { awk '{sub(/^.*\) /, ""); print $20}' "/proc/$1/stat" 2>/dev/null; }
if [[ -f /run/tuist-amp/process ]]; then
    read -r pid started previous < /run/tuist-amp/process
    if [[ "$pid" =~ ^[0-9]+$ && "$(start_time "$pid")" == "$started" ]] && kill -0 "$pid" 2>/dev/null; then
        [[ "$fingerprint" != "$previous" ]] || exit 0
        # A resumed Orb receives a fresh token. Replace only bootstrap, not
        # its process group: unrelated tools/background work must survive.
        kill "$pid"
        for _ in {1..30}; do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.1
        done
        if [[ "$(start_time "$pid")" == "$started" ]]; then
            kill -KILL "$pid" 2>/dev/null || true
        fi
    fi
    rm -f /run/tuist-amp/process
fi

# Amp uses /home/user/workspace/repo. Keep checkouts on the separately
# budgeted workspace disk, while home and tool caches live in rootfs.
install -d -o user -g user /workspace/amp
if [[ ! -e /home/user/workspace && ! -L /home/user/workspace ]]; then
    ln -s /workspace/amp /home/user/workspace
fi

# The read-only Tuist cache credential and endpoint reach Amp's processes
# when dispatch supplies them. They stay out of the fingerprint: a retried
# spawn mints a new credential but must not restart a running bootstrap.
tuist_env=()
for name in TUIST_TOKEN TUIST_URL TUIST_CACHE_ENDPOINT; do
    [[ -z "${!name:-}" ]] || tuist_env+=("$name=${!name}")
done

# exec preserves this child's PID across privilege drop and launch. Open
# logs as user, detach all streams, and do not inherit the dispatch lock.
nohup setpriv --reuid=user --regid=user --init-groups \
    env -i PATH=/usr/local/bin:/usr/bin:/bin HOME=/home/user USER=user LOGNAME=user LANG=C.UTF-8 \
    ORB_TOKEN="$ORB_TOKEN" AMP_URL="$AMP_URL" "${tuist_env[@]}" \
    bash -c 'cd /home/user; exec /usr/local/bin/amp orb bootstrap >.amp-bootstrap.log 2>&1' \
    </dev/null >/dev/null 2>&1 9>&- &
pid=$!
started=$(start_time "$pid")
printf '%s %s %s\n' "$pid" "$started" "$fingerprint" > /run/tuist-amp/process.new
mv /run/tuist-amp/process.new /run/tuist-amp/process
sleep 0.2
kill -0 "$pid" 2>/dev/null || { echo 'Amp bootstrap exited during startup.' >&2; exit 1; }
