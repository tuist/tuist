#!/usr/bin/env bash
# Run inside the built guest container as root. Replaces amp with a local
# test process; no Amp token, network or workspace access is needed.
set -euo pipefail
cat > /usr/local/bin/amp <<'AMP'
#!/usr/bin/env bash
set -euo pipefail
printf '%s %s %s\n' "$(id -un)" "$HOME" "$AMP_URL" > /home/user/bootstrap-test
printf '%s|%s|%s\n' "${TUIST_TOKEN-unset}" "${TUIST_URL-unset}" "${TUIST_CACHE_ENDPOINT-unset}" > /home/user/bootstrap-tuist
[[ -z "${AMP_ORB_PROVIDER_TOKEN:-}" && -z "${UNRELATED_SECRET:-}" ]]
echo started >> /home/user/bootstrap-starts
exec sleep 300
AMP
chmod +x /usr/local/bin/amp
export ORB_TOKEN=test-token AMP_URL=https://amp.example.com
export AMP_ORB_PROVIDER_TOKEN=must-not-cross UNRELATED_SECRET=must-not-cross
export TUIST_TOKEN=cache-read-token TUIST_URL=https://tuist.example.com
export TUIST_CACHE_ENDPOINT=http://kura.example.svc.cluster.local:4000
/usr/local/bin/sbx-orb-bootstrap
read -r first _ < /run/tuist-amp/process
[[ "$(cat /home/user/bootstrap-test)" == 'user /home/user https://amp.example.com' ]]
[[ "$(cat /home/user/bootstrap-tuist)" == 'cache-read-token|https://tuist.example.com|http://kura.example.svc.cluster.local:4000' ]]
[[ "$(readlink /home/user/workspace)" == /workspace/amp ]]
runuser -u user -- touch /home/user/workspace/preserved
# A retried spawn mints a new cache credential without restarting bootstrap.
export TUIST_TOKEN=retried-cache-read-token
/usr/local/bin/sbx-orb-bootstrap
read -r duplicate _ < /run/tuist-amp/process
[[ "$first" == "$duplicate" ]]
[[ "$(cut -d '|' -f 1 /home/user/bootstrap-tuist)" == cache-read-token ]]
[[ "$(wc -l < /home/user/bootstrap-starts)" == 1 ]]
sleep 300 &
background=$!
export ORB_TOKEN=fresh-token
unset TUIST_TOKEN TUIST_URL TUIST_CACHE_ENDPOINT
/usr/local/bin/sbx-orb-bootstrap
read -r refreshed _ < /run/tuist-amp/process
[[ "$refreshed" != "$first" ]]
[[ "$(cat /home/user/bootstrap-tuist)" == 'unset|unset|unset' ]]
[[ -f /workspace/amp/preserved ]]
kill -0 "$refreshed"
kill -0 "$background"
# Simulate cold boot: the saved PID no longer exists, but disk persists.
kill -KILL "$refreshed"
rm /run/tuist-amp/process
/usr/local/bin/sbx-orb-bootstrap
read -r recovered _ < /run/tuist-amp/process
[[ "$recovered" != "$refreshed" && -f /workspace/amp/preserved ]]
[[ "$(wc -l < /home/user/bootstrap-starts)" == 3 ]]
kill "$background"
kill -KILL "$recovered"
echo 'bootstrap user, environment, cache credential, duplicate spawn, token rotation and cold-start checks passed'
