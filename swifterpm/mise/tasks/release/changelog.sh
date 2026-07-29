#!/usr/bin/env bash
#MISE description="Regenerate CHANGELOG.md from conventional commits"
#USAGE flag "--version <version>" help="Version number to write into release-facing files"
set -euo pipefail

version=""
while (($# > 0)); do
  case "$1" in
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

git cliff --config cliff.toml --bump --output CHANGELOG.md

if [[ -n "${version}" ]]; then
  script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
  "${script_dir}/version.sh" --version "${version}"
fi
