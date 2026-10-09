#!/usr/bin/env bash
#MISE description="Build and package a release archive for a target triple"
#USAGE flag "--target <target>" help="Rust target triple to compile"
#USAGE flag "--version <version>" help="Version number to embed in the binary and asset name"
set -euo pipefail

target=""
version=""
while (($# > 0)); do
  case "$1" in
    --target)
      target="${2}"
      shift 2
      ;;
    --version)
      version="${2}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${target}" || -z "${version}" ]]; then
  echo "--target and --version are required" >&2
  exit 1
fi

mkdir -p dist
ONCE_VERSION="${version}" cargo build --locked --release --target "${target}"

# Windows uses the .exe suffix; everything else ships a bare binary.
case "${target}" in
  *-windows-*)
    bin_name="once.exe"
    ;;
  *)
    bin_name="once"
    ;;
esac

stage_dir="$(mktemp -d)"
trap 'rm -rf "${stage_dir}"' EXIT
cp "target/${target}/release/${bin_name}" "${stage_dir}/${bin_name}"

# tar.gz everywhere — modern Windows ships tar(1) and `mise install`'s
# ubi backend handles either format. Keeping one extension across
# platforms makes the asset-naming pattern downstream tools key off
# (mise/aqua/ubi) trivially predictable.
asset="once-${version}-${target}.tar.gz"
tar -C "${stage_dir}" -czf "dist/${asset}" "${bin_name}"

# sha256: sha256sum on Linux and Git-Bash-on-Windows; shasum -a 256 on macOS.
if command -v sha256sum >/dev/null 2>&1; then
  (cd dist && sha256sum "${asset}" > "${asset}.sha256")
else
  (cd dist && shasum -a 256 "${asset}" > "${asset}.sha256")
fi
