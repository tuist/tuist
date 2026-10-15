#!/usr/bin/env bash
#
# Assembles the runner payload archive from the runner-image sources and the
# binaries `.github/actions/build-runner-image-binaries` built into
# infra/runner-image/build/. Paths inside the archive are the guest paths
# install-payload.sh installs them to.
#
# Usage: build.sh <version> <output.tar.gz>
set -euo pipefail

version="${1:?usage: build.sh <version> <output.tar.gz>}"
output="${2:?usage: build.sh <version> <output.tar.gz>}"

here="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
image="$(cd "$here/../runner-image" && pwd)"
# shellcheck source=/dev/null
source "$here/buildkite-agent.env"

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
root="$work/root"

install -d "$root/opt/tuist/buildkite-hooks" "$root/usr/local/bin"
install -m 0755 \
  "$image/dispatch-poll.sh" \
  "$image/metrics-poll.sh" \
  "$image/build/runner-shell-agent" \
  "$image/build/tuist-gitlab-runner" \
  "$image/build/tuist-cas-proxy" \
  "$root/opt/tuist/"
install -m 0755 \
  "$image/buildkite-hooks/environment" \
  "$image/buildkite-hooks/post-command" \
  "$image/buildkite-hooks/pre-exit" \
  "$root/opt/tuist/buildkite-hooks/"
install -m 0755 "$image/build/tuist-cache-volume" "$root/usr/local/bin/"

agent_archive="$work/buildkite-agent.tar.gz"
curl --fail --silent --show-error --location --retry 3 -o "$agent_archive" \
  "https://github.com/buildkite/agent/releases/download/v${BUILDKITE_AGENT_VERSION}/buildkite-agent-darwin-arm64-${BUILDKITE_AGENT_VERSION}.tar.gz"
echo "${BUILDKITE_AGENT_SHA256_DARWIN_ARM64}  ${agent_archive}" | shasum -a 256 -c -
mkdir "$work/buildkite-agent"
tar -xzf "$agent_archive" -C "$work/buildkite-agent"
install -m 0755 "$work/buildkite-agent/buildkite-agent" "$root/opt/tuist/"

printf '%s\n' "$version" > "$root/VERSION"

COPYFILE_DISABLE=1 tar -C "$root" -czf "$output" .
echo "Built runner payload ${version} at ${output}"
tar -tzvf "$output"
