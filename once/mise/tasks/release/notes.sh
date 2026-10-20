#!/usr/bin/env bash
#MISE description="Generate release notes for the next release"
#USAGE flag "--version <version>" help="Version number to render into the generated notes"
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

if [[ -z "${version}" ]]; then
  echo "--version is required" >&2
  exit 1
fi

latest_version="$(git tag -l | grep -E '^once@[0-9]+\.[0-9]+\.[0-9]+$' | sort -V | tail -n1 || true)"

repo_root="$(git rev-parse --show-toplevel)"

if [[ -n "${latest_version}" ]]; then
  rendered="$(git cliff --include-path 'once/**/*' --config cliff.toml --repository "${repo_root}" --tag "${version}" -- "${latest_version}..HEAD")"
else
  rendered="$(git cliff --include-path 'once/**/*' --config cliff.toml --repository "${repo_root}" --tag "${version}")"
fi

# GitHub release pages already display the version and a "Changelog"
# heading, so drop everything up to the marker that the cliff template
# emits right after those titles.
awk '
  !found && /<!-- RELEASE NOTES START -->/ { found = 1; next }
  found
' <<<"${rendered}"
