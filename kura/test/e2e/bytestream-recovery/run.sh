#!/usr/bin/env bash
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
TARGET="${1:?pass the Kura gRPC target as host:port}"
SCRATCH="$(mktemp -d)"
trap 'rm -rf "${SCRATCH}"' EXIT

INSTALL="${BAZEL_RECOVERY_INSTALL_BASE:-${SCRATCH}/install}"
if [ ! -f "${INSTALL}/A-server.jar" ]; then
  bazel --ignore_all_rc_files --batch --install_base="${INSTALL}" \
    --output_user_root="${SCRATCH}/bazel" version >"${SCRATCH}/version.log"
  if ! grep -q '^Build label: 9.1.1$' "${SCRATCH}/version.log"; then
    printf 'The recovery fixture uses Bazel 9.1.1 internals; update it with the pinned toolchain.\n' >&2
    exit 1
  fi
fi

mkdir "${SCRATCH}/classes"
javac --release 21 -cp "${INSTALL}/A-server.jar" -d "${SCRATCH}/classes" "${HERE}/UploadRecovery.java"
for compressed in false true; do
  "${INSTALL}/embedded_tools/jdk/bin/java" \
    -cp "${SCRATCH}/classes:${INSTALL}/A-server.jar" \
    com.google.devtools.build.lib.remote.UploadRecovery "${TARGET}" "${compressed}"
done
