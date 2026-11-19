#!/bin/bash

# Copyright 2026 The Kubernetes Authors.
#
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
#
#     http://www.apache.org/licenses/LICENSE-2.0
#
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

# Runs nginx-tests against the binary built by build-nginx.sh.
# Adapted from chainguard-forks/ingress-nginx images/nginx/tests/run.sh
# (commit 29e7c87140a9d88ffd3cf26ff07852bb81dc0a4a); our Test::Nginx scripts
# are the *.t files next to this script.
#
#   run.sh              the whole pinned suite plus our tests (*.t here)
#   run.sh FILE.t ...   only the given files, verbosely: upstream file names
#                       such as proxy.t, or t/NAME.t for ours
#
# The patched build has no root or alias directive (00_drop-alias-root.patch).
# When the binary rejects root, this script sets TEST_NGINX_NO_ROOT, so that
# Test::Nginx (nginx-tests-no-root.patch) stops putting "root <testdir>" into
# every HTTP configuration.  Whole-suite runs then skip two kinds of files:
#   - on such a binary, every upstream file whose own configuration uses root
#     or alias, since nginx cannot load it,
#   - the files listed in skip.txt, for the reason given there.
# Files that fail are re-run once, verbosely; the run fails if any of them
# fails again.

set -o errexit
set -o nounset
set -o pipefail

SUITE=${SUITE:-/opt/nginx-tests}
TUIST_TESTS=${TUIST_TESTS:-$(dirname "$0")}
SKIP_LIST=${SKIP_LIST:-$(dirname "$0")/skip.txt}
# more parallel files means more port collisions between them (each one
# fails with "Address already in use"), so use at most 16 by default
JOBS=${JOBS:-$(( $(nproc) < 16 ? $(nproc) : 16 ))}
export TEST_NGINX_BINARY=${TEST_NGINX_BINARY:-/opt/nginx/sbin/nginx}
# leak reports would fail every file: nginx does not free all memory at exit
export ASAN_OPTIONS=${ASAN_OPTIONS:-detect_leaks=0}

cd "${SUITE}"

# Does the binary accept the root directive?  The patched build does not.
probe=$(mktemp -d)
printf 'events {}\nhttp { root html; }\n' > "${probe}/nginx.conf"
if out=$("${TEST_NGINX_BINARY}" -t -q -p "${probe}/" -c nginx.conf \
    -e "${probe}/error.log" -g "pid ${probe}/nginx.pid;" 2>&1); then
  skip_root=no
elif [[ "${out}" == *'unknown directive "root"'* ]]; then
  skip_root=yes
  # nginx-tests-no-root.patch: Test::Nginx then leaves "root" out of its configs
  export TEST_NGINX_NO_ROOT=1
else
  echo "nginx -t failed on a minimal configuration: ${out}" >&2
  exit 4
fi
rm -rf "${probe}"

if [[ $# -gt 0 ]]; then
  files=()
  for f in "$@"; do
    case "${f}" in
      t/*) files+=("${TUIST_TESTS}/${f#t/}") ;;
      *) files+=("${f}") ;;
    esac
  done
  exec prove -v -I "${SUITE}/lib" "${files[@]}"
fi

"${TEST_NGINX_BINARY}" -V

shopt -s nullglob
declare -A skip=()
if [[ "${skip_root}" == "yes" ]]; then
  echo "root directive rejected by this binary: skipping files that use root or alias"
  # shellcheck disable=SC2013 # nginx-tests file names have no spaces
  for f in $(grep -lE '^\s+(root|alias)\s' ./*.t); do
    skip["${f#./}"]="uses root or alias"
  done
fi
while read -r f reason; do
  skip["${f}"]="${reason}"
done < <(grep -vE '^\s*(#|$)' "${SKIP_LIST}")

files=()
for f in *.t; do
  if [[ -n "${skip[${f}]:-}" ]]; then
    echo "skip ${f}: ${skip[${f}]}"
  else
    files+=("${f}")
  fi
done
files+=("${TUIST_TESTS}"/*.t)
echo "running ${#files[@]} files, skipping ${#skip[@]}"

state=$(mktemp)
if prove -I "${SUITE}/lib" -j "${JOBS}" --statefile="${state}" --state=save "${files[@]}"; then
  exit 0
fi

echo "re-running the failed files once, verbosely"
prove -v -I "${SUITE}/lib" --statefile="${state}" --state=failed
