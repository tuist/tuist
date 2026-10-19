#!/usr/bin/env bash
set -euo pipefail

fail() { echo "::error::$*" >&2; exit 1; }
single_line() {
  [[ "$1" != *[$'\r\n']* ]] || fail 'Paths and cache keys must be single-line values.'
}

single_line "${TUIST_INSTALL_PATH:-.}"
single_line "${TUIST_INSTALL_CACHE_KEY:-}"
single_line "${GITHUB_WORKSPACE:?GITHUB_WORKSPACE is required}"
workspace=$(cd "$GITHUB_WORKSPACE" && pwd -P)
cd "$workspace"
project=$(cd "${TUIST_INSTALL_PATH:-.}" && pwd -P)
[[ "$project" == "$workspace" || "$project" == "$workspace/"* ]] || fail 'path must be inside GITHUB_WORKSPACE.'

# Match RootDirectoryLocator, then ManifestFilesLocator's Tuist/ precedence.
root=$project
while [[ ! -d "$root/Tuist" && ! -f "$root/Tuist.swift" && ! -f "$root/tuist.toml" && ! -e "$root/Plugin.swift" && ! -d "$root/.git" ]]; do
  if [[ "$root" == "$workspace" ]]; then
    root=$project
    break
  fi
  root=$(dirname "$root")
done
if [[ -f "$root/Tuist/Package.swift" ]]; then
  package=$(cd "$root/Tuist" && pwd -P)
elif [[ -f "$root/Package.swift" ]]; then
  package=$root
else
  fail 'No Tuist/Package.swift or Package.swift found at the project root.'
fi
[[ "$package" == "$workspace" || "$package" == "$workspace/"* ]] || fail 'Package directory must be inside GITHUB_WORKSPACE.'
[[ -f "$package/Package.resolved" ]] || fail 'Commit Package.resolved before using forced dependency installation.'
[[ -z "${SWIFTPM_BUILD_DIR:-}" ]] || fail 'Unset SWIFTPM_BUILD_DIR; this action retains the package .build directory.'
command -v tuist >/dev/null || fail 'Install the pinned Tuist CLI before running this action (4.214.0-canary.36 or newer).'

single_line "$project"
single_line "$package"
version=$(tuist version)
if [[ "$version" =~ ^([0-9]+)\.([0-9]+)\.([0-9]+)(-.*)?$ ]]; then
  major=$((10#${BASH_REMATCH[1]}))
  minor=$((10#${BASH_REMATCH[2]}))
  patch=$((10#${BASH_REMATCH[3]}))
  prerelease=${BASH_REMATCH[4]:-}
else
  fail 'Cannot identify the Tuist version; use 4.214.0-canary.36 or newer.'
fi
if (( major < 4 || (major == 4 && minor < 214) )); then
  fail 'Tuist 4.214.0-canary.36 or newer is required for consolidated manifest caches.'
fi
if (( major == 4 && minor == 214 && patch == 0 )) && [[ -n "$prerelease" ]]; then
  [[ "$prerelease" =~ ^-canary\.([0-9]+)$ ]] || fail 'Use Tuist 4.214.0-canary.36 or newer.'
  (( 10#${BASH_REMATCH[1]} >= 36 )) || fail 'Use Tuist 4.214.0-canary.36 or newer.'
fi

scratch="$package/.build"
package_relative=${package#"$workspace"}
key=${TUIST_INSTALL_CACHE_KEY:-}
if [[ -z "$key" ]]; then
  toolchain=$(swift --version)
  if [[ $(uname -s) == Darwin ]]; then
    toolchain+=$'\n'$(xcodebuild -version)
  fi

  digest=$({
    printf '%s\0' "${GITHUB_JOB:?GITHUB_JOB is required}" "$toolchain" "$package_relative"
    cat "$package/Package.swift"
  } | shasum -a 256)
  key="tuist-install-v1-${digest%% *}"
fi
[[ "$key" =~ ^[a-zA-Z0-9][a-zA-Z0-9_./-]*$ && ${#key} -le 200 ]] || fail 'cache-key must be 1–200 characters: letters, numbers, _, ., /, or -, starting with a letter or number.'
backend=github
materialization=copy
if command -v tuist-cache-volume >/dev/null 2>&1 || [[ -x /__e/tuist-cache-volume ]]; then
  backend=volume
  materialization=symlink
fi
archive_path=$(printf '%s' ".${package_relative}/.build" | sed 's/[][?*]/[&]/g')
archive_prefix=""
archive_key=""
if [[ "$backend" == github ]]; then
  platform=${RUNNER_OS:?RUNNER_OS is required for GitHub caching}
  architecture=${RUNNER_ARCH:?RUNNER_ARCH is required for GitHub caching}
  [[ "$platform" =~ ^[a-zA-Z0-9_-]+$ && "$architecture" =~ ^[a-zA-Z0-9_-]+$ ]] || fail 'Invalid runner platform or architecture.'
  lock_hash=$(shasum -a 256 < "$package/Package.resolved")
  archive_prefix="tuist-install-github-v1-$platform-$architecture-$key-"
  archive_key="$archive_prefix${lock_hash%% *}"
fi
{
  printf 'project-path=%s\n' "$project"
  printf 'scratch-path=%s\n' "$scratch"
  printf 'cache-path=%s\n' "$scratch/dependency-cache"
  printf 'key=%s\n' "$key"
  printf 'backend=%s\n' "$backend"
  printf 'materialization=%s\n' "$materialization"
  printf 'archive-path=%s\n' "$archive_path"
  printf 'archive-key=%s\n' "$archive_key"
  printf 'archive-prefix=%s\n' "$archive_prefix"
} >> "${GITHUB_OUTPUT:?GITHUB_OUTPUT is required}"
