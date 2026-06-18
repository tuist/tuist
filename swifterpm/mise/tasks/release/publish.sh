#!/usr/bin/env bash
#MISE description="Publish the GitHub release"
#USAGE flag "--version <version>" help="Version being released"
#USAGE flag "--notes <notes>" help="Path to the rendered release notes file"
#USAGE flag "--dist <dist>" help="Directory containing release artifacts"
set -euo pipefail

version=""
notes=""
dist=""
while (($# > 0)); do
  case "$1" in
    --version)
      version="${2}"
      shift 2
      ;;
    --notes)
      notes="${2}"
      shift 2
      ;;
    --dist)
      dist="${2}"
      shift 2
      ;;
    *)
      echo "unknown argument: $1" >&2
      exit 1
      ;;
  esac
done

if [[ -z "${version}" ]]; then
  echo "--version is required" >&2
  exit 1
fi
if [[ -z "${notes}" ]]; then
  echo "--notes is required" >&2
  exit 1
fi
if [[ -z "${dist}" ]]; then
  echo "--dist is required" >&2
  exit 1
fi

target="$(git rev-parse HEAD)"

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${script_dir}/checksums.sh" --dist "${dist}"

artifacts=()
while IFS= read -r artifact; do
  artifacts+=("${artifact}")
done < <(find "${dist}" -maxdepth 1 -type f -print | sort)

gh release create "${version}" \
  --title "${version}" \
  --notes-file "${notes}" \
  --target "${target}" \
  "${artifacts[@]}"
