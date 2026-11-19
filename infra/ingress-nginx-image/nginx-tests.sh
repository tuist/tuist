#!/usr/bin/env bash
# Runs the nginx-tests suite (tests/) against nginx built with AddressSanitizer
# from the pinned fork's nginx version and patch stack, ours included.
#
#   nginx-tests.sh WORK_DIR             the whole suite
#   nginx-tests.sh WORK_DIR FILE.t ...  only these files, verbosely
#
# Fetches the fork into WORK_DIR with source.sh. Needs Docker with buildx.

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
work=${1:?usage: nginx-tests.sh WORK_DIR [FILE.t ...]}
shift
bash "$here/source.sh" "$work"
work=$(cd "$work" && pwd)

image=tuist-ingress-nginx-tests:local
docker buildx build --builder default --load --pull --progress=plain \
  --file "$here/tests/Dockerfile" --build-context harness="$here/tests" \
  --tag "$image" "$work/src/images/nginx"
docker run --rm --sysctl net.ipv6.conf.all.disable_ipv6=0 "$image" "$@"
