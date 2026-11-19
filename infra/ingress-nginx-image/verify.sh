#!/usr/bin/env bash
# Checks the images build.sh produced and compares them with the images they
# would replace.
#
#   verify.sh WORK_DIR
#
# WORK_DIR is the directory build.sh wrote images.env to. Writes report.md
# there (and to the job summary on GitHub Actions).
#
# Fatal: the controller runs nginx 1.27.1 from our nginx image with the fork's
# patch stack and ours, its modules load and link, and the binaries run.
# Reported only: how image configuration, user and filesystem differ from the
# official images and from the Chainguard-fork build we run today. These images
# are not drop-in replacements for either (README.md, "Contract").

set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source-path=SCRIPTDIR source=fork.env
source "$here/fork.env"
work=$(cd "${1:?usage: verify.sh WORK_DIR}" && pwd)
# shellcheck disable=SC1091
source "$work/images.env"
report="$work/report.md"
version=$FORK_TAG

fail() {
  echo "error: $*" >&2
  echo "**Failed:** $*" >> "$report"
  [[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && cat "$report" >> "$GITHUB_STEP_SUMMARY"
  exit 1
}
run() { docker run --rm --network none --entrypoint "$@"; }

for image in "$UPSTREAM_CONTROLLER_IMAGE" "$UPSTREAM_CERTGEN_IMAGE" "$CURRENT_CONTROLLER_IMAGE" "$CURRENT_CERTGEN_IMAGE"; do
  docker pull -q "$image" >/dev/null
done

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
# one from the unpatched upstream image the fork's NGINX_BASE names.
binary_sum() { run sha256sum "$1" /usr/local/nginx/sbin/nginx | cut -d' ' -f1; }
[[ "$(binary_sum "$NGINX_IMAGE")" == "$(binary_sum "$CONTROLLER_IMAGE")" ]] || fail "controller nginx binary differs from $NGINX_IMAGE"

# Messages only the fork's CVE backports add: CVE-2026-97205 (per-request
# pending operation limit) and CVE-2026-42533 (script buffer overrun checks).
# The official image's stock 1.27.1 has neither, which shows the probe can tell
# patched from stock nginx.
markers=("too many operations pending" "no buffer space in script copy")
for marker in "${markers[@]}"; do
  run grep "$CONTROLLER_IMAGE" -qaF "$marker" /usr/local/nginx/sbin/nginx || fail "controller nginx lacks \"$marker\": the fork's patches are not applied"
  if run grep "$UPSTREAM_CONTROLLER_IMAGE" -qaF "$marker" /usr/local/nginx/sbin/nginx; then
    fail "the official nginx contains \"$marker\" too, so this probe cannot tell patched from stock nginx"
  fi
done

# Every dynamic module the image ships must load with HTTP/2 on: the patches
# change core struct layouts, so a module built against other headers would
# fail or crash here.
probe() {
  run sh "$1" -c '
    set -e
    d=$(mktemp -d)
    { for m in /etc/nginx/modules/*.so; do echo "load_module $m;"; done
      echo "pid $d/nginx.pid; events {}"
      echo "http { http2 on; server { listen 8080; } }"
    } > "$d/nginx.conf"
    nginx -t -p "$d/" -c "$d/nginx.conf" -e stderr' 2>&1
}
probe "$CONTROLLER_IMAGE" > "$work/probe-modules.txt" || fail "nginx -t with all dynamic modules failed: $(cat "$work/probe-modules.txt")"

# The fork's scripts/validate-modules: nothing nginx loads may miss a library.
# The image is glibc-based, so this is what catches a SUSE runtime package the
# fork's packages.txt forgot.
run bash "$CONTROLLER_IMAGE" -c '
  shopt -s nullglob globstar
  for target in /usr/local/nginx/sbin/nginx /etc/nginx/modules/* /usr/local/lib/*.so* \
      /usr/local/lib64/*.so* /usr/local/lib/lua/**/*.so /usr/lib64/libopentelemetry*.so* \
      /usr/lib64/libbrotli*.so* /opt/**/*.so*; do
    [[ -e $target ]] || continue
    echo "=== $target"
    ldd "$target"
  done' > "$work/ldd.txt" 2>&1 || fail "ldd failed: $(tail -5 "$work/ldd.txt")"
if grep -q 'not found' "$work/ldd.txt"; then
  fail "missing libraries: $(awk '/^=== /{t=$2} /not found/{print t": "$1}' "$work/ldd.txt" | tr '\n' ' ')"
fi

# patches/0001: an access_log path with variables keeps its last character.
# nginx only logs to a variable path when the request's root exists: the
# default <prefix>/html, since the fork removes the root directive.
run sh "$CONTROLLER_IMAGE" -c '
  set -e
  d=$(mktemp -d)
  mkdir "$d/html"
  echo "pid $d/nginx.pid; events {} http { access_log $d/access-\$host.log; server { listen 8080; location / { return 204; } } }" > "$d/nginx.conf"
  nginx -p "$d/" -c "$d/nginx.conf" -e "$d/error.log"
  curl -s -o /dev/null -H "Host: tuist" http://127.0.0.1:8080/
  nginx -p "$d/" -c "$d/nginx.conf" -e "$d/error.log" -s quit
  while [ -e "$d/nginx.pid" ]; do sleep 0.1; done
  ls "$d"' > "$work/probe-access-log.txt" 2>&1 || fail "access log probe failed: $(cat "$work/probe-access-log.txt")"
grep -qx 'access-tuist.log' "$work/probe-access-log.txt" || fail "access_log with variables wrote $(grep access- "$work/probe-access-log.txt"), not access-tuist.log"

# Controller binary version.
run /nginx-ingress-controller "$CONTROLLER_IMAGE" --version > "$work/controller-version.txt" 2>&1
grep -q "Release:[[:space:]]*$version" "$work/controller-version.txt" || fail "controller reports $(cat "$work/controller-version.txt")"
run /kube-webhook-certgen "$CERTGEN_IMAGE" --help > /dev/null || fail "kube-webhook-certgen --help failed"
{
  echo "- Controller: \`$(grep -E 'Release|Build' "$work/controller-version.txt" | tr -s ' ' | tr '\n' ' ')\`"
  echo "- nginx binary identical to the one in \`$NGINX_IMAGE\`; contains the fork's CVE backport messages (the official image does not); all dynamic modules load with HTTP/2; ldd finds every library; \`access_log\` paths with variables are intact (patches/0001)"
  echo
} >> "$report"

# Comparisons with the images these would replace: reported, not fatal.
config() { docker image inspect "$1" --format '{{json .Config}}' | jq -S "{User, Entrypoint, Cmd, WorkingDir, ExposedPorts${2:+, $2}}"; }
export_fs() { local c; c=$(docker create "$1"); docker export "$c" > "$2"; docker rm "$c" > /dev/null; }
export_fs "$CONTROLLER_IMAGE" "$work/ours.tar"
compare() {
  local name=$1 controller=$2 certgen=$3 slug=$4
  {
    echo "### Compared with $name"
    echo
    echo "Controller \`$controller\`, kube-webhook-certgen \`$certgen\`."
    echo
    echo "- \`id\`: theirs \`$(run id "$controller")\`, ours \`$(run id "$CONTROLLER_IMAGE")\`"
  } >> "$report"
  local d
  for d in controller certgen; do
    local theirs ours extra
    if [[ $d == controller ]]; then theirs=$controller ours=$CONTROLLER_IMAGE extra=Env; else theirs=$certgen ours=$CERTGEN_IMAGE extra=; fi
    if diff -u <(config "$theirs" ${extra:+"$extra"}) <(config "$ours" ${extra:+"$extra"}) > "$work/$slug-$d-config.diff"; then
      echo "- $d image config (user, entrypoint, command, working directory, ports${extra:+, env}): same" >> "$report"
    else
      { echo "- $d image config differs:"; echo; echo '```diff'; tail -n +3 "$work/$slug-$d-config.diff"; echo '```'; } >> "$report"
    fi
  done
  echo >> "$report"
  export_fs "$controller" "$work/theirs.tar"
  python3 -I "$here/compare-layout.py" "$work/theirs.tar" "$work/ours.tar" "$name" >> "$report" || true
  rm -f "$work/theirs.tar"
}
compare "the official v1.15.1 images" "$UPSTREAM_CONTROLLER_IMAGE" "$UPSTREAM_CERTGEN_IMAGE" upstream
compare "our Chainguard-fork build (v1.15.16-tuist.1)" "$CURRENT_CONTROLLER_IMAGE" "$CURRENT_CERTGEN_IMAGE" current
rm -f "$work/ours.tar"

[[ -n "${GITHUB_STEP_SUMMARY:-}" ]] && cat "$report" >> "$GITHUB_STEP_SUMMARY"
cat "$report"
