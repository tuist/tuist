#!/usr/bin/env bash
# Select a reachable runner-image release that published every active profile.
# Older releases can predate a newly added Xcode, even when their semver is newer
# than every other release known when the deployment started.
set -euo pipefail

deploy_sha="${1:-HEAD}"
profiles_file="infra/runner-image/profiles.json"
required_profiles="$(jq -ce 'select(type == "array" and length > 0 and all(.[]; type == "string"))' "$profiles_file")"

while IFS= read -r tag; do
  published_profiles="$(git show "${tag}:${profiles_file}" 2>/dev/null)" || continue
  if jq -ne --argjson required "$required_profiles" --argjson published "$published_profiles" \
    '$published | type == "array" and ($required - . | length == 0)' >/dev/null; then
    printf '%s\n' "${tag#runner-image@}"
    exit 0
  fi
done < <(git tag --list 'runner-image@*' --merged "$deploy_sha" | grep -E '^runner-image@[0-9]+\.[0-9]+\.[0-9]+$' | sort -rV)

echo "No reachable runner-image release contains every active profile: ${required_profiles}" >&2
exit 1
