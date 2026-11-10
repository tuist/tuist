#!/bin/bash
set -euo pipefail

# Load only the production discovery function, never the dispatch loop.
root=$(cd "$(dirname "$0")/.." && pwd)
eval "$(awk '/^cas_proxy_client\(\)/ { copying=1 } copying { print } copying && /^}/ { exit }' "${root}/dispatch-poll.sh")"
fixture=$(mktemp -d)
trap 'rm -rf "${fixture}"' EXIT
export HOME="${fixture}/home"
export PATH="${fixture}/path:/usr/bin:/bin:/usr/sbin:/sbin"
unset TUIST_CAS_PROXY_PATH
mkdir -p "${HOME}/Library/LaunchAgents" "${fixture}/configured bundle" "${fixture}/path"
plist="${HOME}/Library/LaunchAgents/tuist.cas-proxy.plist"
configured="${fixture}/configured bundle/tuist-cas-proxy"
fallback="${fixture}/path/tuist-cas-proxy"
printf '#!/bin/sh\nexit 0\n' > "${configured}"
cp "${configured}" "${fallback}"
chmod +x "${configured}" "${fallback}"

write_plist() {
  python3 - "$plist" "$@" <<'PY'
import json, plistlib, sys
with open(sys.argv[1], "wb") as output:
    plistlib.dump(json.loads(sys.argv[2]), output)
PY
}
expect_client() {
  actual=$(cas_proxy_client)
  if [ "${actual}" != "$1" ]; then
    printf 'Expected %s, got %s\n' "$1" "${actual}" >&2
    exit 1
  fi
}

# Legacy agent discovery must win over an unrelated PATH installation.
write_plist "{\"Program\":\"${fixture}/configured bundle/tuist\"}"
expect_client "${configured}"

# Stable agents include argv[0] (/bin/sh), launcher, then the JSON pointer.
target="${fixture}/cas-launch-target.json"
printf '{"executable":"%s","tuistVersion":"4.214.0"}' "${fixture}/configured bundle/tuist" > "${target}"
write_plist "{\"Program\":\"/bin/sh\",\"ProgramArguments\":[\"/bin/sh\",\"${fixture}/cas-launcher.sh\",\"${target}\",\"cache-proxy\"]}"
expect_client "${configured}"

# A custom/source-built setup directly execs its own CLI.
write_plist "{\"Program\":\"/bin/sh\",\"ProgramArguments\":[\"/bin/sh\",\"-c\",\"exec \\\"\u0024@\\\"\",\"tuist-cas-launcher\",\"${fixture}/configured bundle/tuist\",\"cache-proxy\"]}"
expect_client "${configured}"

# The configured proxy override wins even when the CLI bundle has another copy.
write_plist "{\"Program\":\"${fixture}/configured bundle/tuist\",\"EnvironmentVariables\":{\"TUIST_CAS_PROXY_PATH\":\"${fallback}\"}}"
expect_client "${fallback}"
TUIST_CAS_PROXY_PATH="${configured}" expect_client "${configured}"

# Missing installations still use the PATH fallback.
rm "${plist}"
expect_client "${fallback}"
printf 'CAS proxy client discovery tests passed\n'
