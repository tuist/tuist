#!/usr/bin/env bash
#MISE description="Update release-facing version references"
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

if [[ -z "${version}" ]]; then
  echo "--version is required" >&2
  exit 1
fi

if ! [[ "${version}" =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]]; then
  echo "--version must be a semantic version like 0.3.0" >&2
  exit 1
fi

VERSION="${version}" perl -0pi -e 's/(bazel_dep\(name = "swifterpm", version = ")[^"]+(")/$1$ENV{VERSION}$2/' README.md
VERSION="${version}" perl -0pi -e 's/(module\(\s*\n\s*name = "swifterpm",\s*\n\s*version = ")[^"]+(")/$1$ENV{VERSION}$2/s' MODULE.bazel

if ! grep -q "bazel_dep(name = \"swifterpm\", version = \"${version}\")" README.md; then
  echo "failed to update README.md" >&2
  exit 1
fi
if ! grep -q "version = \"${version}\"" MODULE.bazel; then
  echo "failed to update MODULE.bazel" >&2
  exit 1
fi
