#!/bin/bash
# Installs the runner payload tart-kubelet shares at
# /Volumes/My Shared Files/payload over the copies baked into the image.
# Archive paths are guest paths; only /opt/tuist and /usr/local/bin are
# writable through it. A failed install halts the VM so the Pod is replaced.

set -euo pipefail

PAYLOAD_DIR="${TUIST_RUNNER_PAYLOAD_DIR:-/Volumes/My Shared Files/payload}"
DEST_ROOT="${TUIST_RUNNER_PAYLOAD_DEST_ROOT:-}"
HALT="${TUIST_RUNNER_PAYLOAD_HALT:-/sbin/shutdown -h now}"

trap 'echo "install-payload: install failed; halting" >&2; ${HALT}' ERR

if [ ! -d "${PAYLOAD_DIR}" ]; then
  echo "install-payload: no payload at ${PAYLOAD_DIR}; using the image's copies"
  exit 0
fi

version="$(cat "${PAYLOAD_DIR}/VERSION")"

cd "${PAYLOAD_DIR}"
while IFS= read -r -d '' file; do
  path="${file#./}"
  case "${path}" in
    VERSION) continue ;;
    opt/tuist/*|usr/local/bin/*) ;;
    *)
      echo "install-payload: ${path} is outside /opt/tuist and /usr/local/bin" >&2
      false
      ;;
  esac
  mode=0644
  if [ -x "${file}" ]; then
    mode=0755
  fi
  install -d -m 0755 "${DEST_ROOT}/$(dirname "${path}")"
  install -m "${mode}" "${file}" "${DEST_ROOT}/${path}"
done < <(find . -type f -print0)

echo "install-payload: installed runner payload ${version}"
