#!/usr/bin/env bash
# Run inside the built guest container as root. Replaces amp with a local
# test process; no Amp token, network or workspace access is needed.
set -euo pipefail
cat > /usr/local/bin/amp <<'AMP'
#!/usr/bin/env bash
set -euo pipefail
printf '%s %s %s\n' "$(id -un)" "$HOME" "$AMP_URL" > /home/user/bootstrap-test
[[ -z "${AMP_ORB_PROVIDER_TOKEN:-}" && -z "${TUIST_TOKEN:-}" ]]
echo started >> /home/user/bootstrap-starts
exec sleep 300
AMP
chmod +x /usr/local/bin/amp
export ORB_TOKEN=test-token AMP_URL=https://amp.example.com
export AMP_ORB_PROVIDER_TOKEN=must-not-cross TUIST_TOKEN=must-not-cross
/usr/local/bin/sbx-orb-bootstrap
read -r first _ < /run/tuist-amp/process
[[ "$(cat /home/user/bootstrap-test)" == 'user /home/user https://amp.example.com' ]]
[[ "$(readlink /home/user/workspace)" == /workspace/amp ]]
runuser -u user -- touch /home/user/workspace/preserved
/usr/local/bin/sbx-orb-bootstrap
read -r duplicate _ < /run/tuist-amp/process
[[ "$first" == "$duplicate" ]]
[[ "$(wc -l < /home/user/bootstrap-starts)" == 1 ]]
sleep 300 &
background=$!
export ORB_TOKEN=fresh-token
/usr/local/bin/sbx-orb-bootstrap
read -r refreshed _ < /run/tuist-amp/process
[[ "$refreshed" != "$first" ]]
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
echo 'bootstrap user, environment, duplicate spawn, token rotation and cold-start checks passed'
