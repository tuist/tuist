#!/usr/bin/env bash
# Checks the images build.sh produced against the official images they replace.
#
#   verify.sh WORK_DIR
#
# WORK_DIR is the directory build.sh wrote images.env to. Writes report.md
# there (and to the job summary on GitHub Actions) and exits non-zero on the
# first contract violation.

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR source=fork.env
source "$here/fork.env"
work=$(cd "${1:?usage: verify.sh WORK_DIR}" && pwd)
# shellcheck disable=SC1091
source "$work/images.env"
report="$work/report.md"
version=${FORK_TAG#controller-}

fail() {
  echo "error: $*" >&2
  echo "**Failed:** $*" >> "$report"
  [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && cat "$report" >> "$GITHUB_STEP_SUMMARY"
  exit 1
}
run() { docker run --rm --network none --entrypoint "$@"; }

docker pull -q "$UPSTREAM_CONTROLLER_IMAGE" >/dev/null
docker pull -q "$UPSTREAM_CERTGEN_IMAGE" >/dev/null

{
  echo "## ingress-nginx $IMAGE_TAG"
  echo
  echo "Fork: $FORK_REPOSITORY \`$FORK_TAG\` at \`$FORK_COMMIT\`"
  echo
} > "$report"

# nginx version and build flags, from the controller image itself.
run nginx "$CONTROLLER_IMAGE" -V > "$work/nginx-V.txt" 2>&1
grep -qx 'nginx version: nginx/1.27.1' "$work/nginx-V.txt" || fail "controller image does not run nginx 1.27.1: $(head -1 "$work/nginx-V.txt")"
{ echo '```'; cat "$work/nginx-V.txt"; echo '```'; echo; } >> "$report"

# The controller must ship the nginx binary compiled in our base image, not
# one from the upstream registry.k8s.io base.
binary_sum() { run sha256sum "$1" /usr/local/nginx/sbin/nginx | cut -d' ' -f1; }
[[ "$(binary_sum "$NGINX_IMAGE")" == "$(binary_sum "$CONTROLLER_IMAGE")" ]] || fail "controller nginx binary differs from $NGINX_IMAGE"

# The patched binary accepts max_headers (CVE-2026-49975 backport, patch 37);
# stock 1.27.1 in the official image does not. Both must load every dynamic
# module the image ships with HTTP/2 on: the patches change core struct layouts,
# so a module built against other headers would fail or crash here.
probe() {
  local image=$1 extra=$2
  run sh "$image" -c '
    set -e
    d=$(mktemp -d)
    { for m in /etc/nginx/modules/*.so; do echo "load_module $m;"; done
      echo "pid $d/nginx.pid; events {}"
      echo "http { http2 on; '"$extra"' server { listen 8080; } }"
    } > "$d/nginx.conf"
    nginx -t -p "$d/" -c "$d/nginx.conf" -e stderr' 2>&1
}
probe "$CONTROLLER_IMAGE" "" > "$work/probe-modules.txt" || fail "nginx -t with all dynamic modules failed: $(cat "$work/probe-modules.txt")"
probe "$UPSTREAM_CONTROLLER_IMAGE" "" > /dev/null || fail "module probe fails on the official image too; the probe itself is broken"
probe "$CONTROLLER_IMAGE" "max_headers 100;" > "$work/probe-patched.txt" || fail "max_headers rejected: the controller's nginx lacks the fork's patches"
if out=$(probe "$UPSTREAM_CONTROLLER_IMAGE" "max_headers 100;"); then
  fail "the official image accepts max_headers, so this probe cannot tell patched from stock nginx"
fi
[[ "$out" == *'unknown directive "max_headers"'* ]] || fail "unexpected official-image probe output: $out"

# Controller binary version, user and group.
run /nginx-ingress-controller "$CONTROLLER_IMAGE" --version > "$work/controller-version.txt" 2>&1
grep -q "Release:[[:space:]]*$version" "$work/controller-version.txt" || fail "controller reports $(cat "$work/controller-version.txt")"
[[ "$(run id "$CONTROLLER_IMAGE")" == "$(run id "$UPSTREAM_CONTROLLER_IMAGE")" ]] || fail "user/group differ: $(run id "$CONTROLLER_IMAGE")"
{
  echo "- Controller: \`$(grep -E 'Release|Build' "$work/controller-version.txt" | tr -s ' ' | tr '\n' ' ')\`"
  echo "- User: \`$(run id "$CONTROLLER_IMAGE")\` (same as the official image)"
  echo "- nginx binary identical to the one in \`$NGINX_IMAGE\`; all dynamic modules load with HTTP/2; \`max_headers\` accepted (official image: unknown directive)"
} >> "$report"

# Image configuration: entrypoint, command, user, working directory, ports, env.
config() { docker image inspect "$1" --format '{{json .Config}}' | jq -S "{User, Entrypoint, Cmd, WorkingDir, ExposedPorts${2:+, $2}}"; }
diff -u <(config "$UPSTREAM_CONTROLLER_IMAGE" Env) <(config "$CONTROLLER_IMAGE" Env) > "$work/controller-config.diff" \
  || fail "controller image config differs: $(cat "$work/controller-config.diff")"
diff -u <(config "$UPSTREAM_CERTGEN_IMAGE") <(config "$CERTGEN_IMAGE") > "$work/certgen-config.diff" \
  || fail "kube-webhook-certgen image config differs: $(cat "$work/certgen-config.diff")"
run /kube-webhook-certgen "$CERTGEN_IMAGE" --help > /dev/null || fail "kube-webhook-certgen --help failed"
echo "- Entrypoint, command, user, working directory, ports and env match the official controller and kube-webhook-certgen images" >> "$report"
echo >> "$report"

# Filesystem layout, ownership, modes and file capabilities.
export_fs() { local c; c=$(docker create "$1"); docker export "$c" > "$2"; docker rm "$c" > /dev/null; }
export_fs "$UPSTREAM_CONTROLLER_IMAGE" "$work/official.tar"
export_fs "$CONTROLLER_IMAGE" "$work/ours.tar"
status=0
python3 -I "$here/compare-layout.py" "$work/official.tar" "$work/ours.tar" >> "$report" || status=$?
rm -f "$work/official.tar" "$work/ours.tar"
(( status == 0 )) || fail "filesystem layout differs from the official image (see the report)"

[[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && cat "$report" >> "$GITHUB_STEP_SUMMARY"
cat "$report"
