#!/usr/bin/env bash
set -euo pipefail
script="$(cd "$(dirname "$0")" && pwd)/ghcr-manifest-digest.sh"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
cat > "$work/curl" <<'STUB'
#!/usr/bin/env bash
set -euo pipefail
if [[ "$*" == *'ghcr.io/token?'* ]]; then
  echo '{"token":"fake-pull-token"}'
else
  # GHCR returns 404 for an index unless the Accept header includes it.
  case "$MANIFEST_KIND" in
    index) [[ "$*" == *'application/vnd.oci.image.index.v1+json'* ]] || exit 22 ;;
    image) [[ "$*" == *'application/vnd.oci.image.manifest.v1+json'* ]] || exit 22 ;;
    missing) exit 22 ;;
  esac
  printf 'HTTP/2 200\r\nDocker-Content-Digest: %s\r\n' "$MANIFEST_DIGEST"
fi
STUB
chmod +x "$work/curl"
export PATH="$work:$PATH"
MANIFEST_DIGEST="sha256:$(printf 'a%.0s' {1..64})"
export MANIFEST_DIGEST
for kind in index image; do
  actual="$(MANIFEST_KIND="$kind" bash "$script" tuist/runner v1)"
  [[ "$actual" == "$MANIFEST_DIGEST" ]]
done
if MANIFEST_KIND=missing bash "$script" tuist/runner v1 > "$work/out" 2>&1; then
  echo 'Accepted missing image' >&2; exit 1
fi
if MANIFEST_KIND=index MANIFEST_DIGEST=invalid bash "$script" tuist/runner v1 > "$work/out" 2>&1; then
  echo 'Accepted invalid digest' >&2; exit 1
fi
echo 'GHCR digest resolution accepts image/index manifests and rejects missing/invalid digests.'
