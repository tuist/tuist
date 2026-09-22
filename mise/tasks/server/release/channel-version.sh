#!/usr/bin/env bash
#MISE description="Compute the next Server version for a release channel (canary | rc-new | rc | promote)"
set -euo pipefail

# Resolve the next Server version for one of the release channels and emit it,
# with the SHA to build and the changelog base, to GITHUB_OUTPUT (and stdout).
# Run by the release workflows as
# `mise run server:release:channel-version -- <channel>`:
#
#   canary            server-release.yml   next X.Y.0-canary.N off main
#   rc-new            server-rc.yml        cut next minor: X.Y.0-rc.1 (+ branch to create)
#   rc      <branch>  server-rc.yml        iterate X.Y.0-rc.(N+1) on a release branch
#   promote <branch>  server-promote.yml   promote X.Y.0 stable from a release branch
#   promote           server-promote.yml   promote the newest cut line not yet stable
#                                          (should_publish=false when there is none)
#
# Cloned from mise/tasks/cli/release/channel-version.sh; the only differences
# are the git-tag prefix (server@) and the emitted `version` staying bare
# (matching how release:check emits server-next-version-number). See the CLI
# script for the design rationale on canary vs rc vs promote.

CHANNEL="${1:-}"
BRANCH="${2:-}"

TAG_PREFIX="server@"

cd "$(git rev-parse --show-toplevel)"
SHA=$(git rev-parse HEAD)

changelog_from=""

emit() {
  [[ -n "${GITHUB_OUTPUT:-}" ]] && printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
  printf '%s=%s\n' "$1" "$2"
}

die() { echo "::error::$1" >&2; exit 1; }

# All tag helpers below list git tags with the server@ prefix and strip it
# before comparing, so the rest of the script works in bare X.Y.Z space.
stable_tags() {
  git tag -l "${TAG_PREFIX}*" | sed "s|^${TAG_PREFIX}||" | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' || true
}
latest_stable_tag() { stable_tags | sort -V | tail -n1; }
canary_tags() {
  git tag -l "${TAG_PREFIX}*" | sed "s|^${TAG_PREFIX}||" | grep -E '^[0-9]+\.[0-9]+\.0-canary\.[0-9]+$' || true
}
latest_canary_tag() { canary_tags | sort -V | tail -n1; }
tag_exists() { git rev-parse --verify --quiet "refs/tags/${TAG_PREFIX}$1" >/dev/null; }

# Highest N among existing <target>-<channel>.N tags; empty when none exist.
highest_prerelease_n() {
  local target_re=${1//./\\.} channel=$2
  git tag -l "${TAG_PREFIX}*" \
    | sed "s|^${TAG_PREFIX}||" \
    | { grep -E "^${target_re}-${channel}\.[0-9]+$" || true; } \
    | sed -E 's/.*\.([0-9]+)$/\1/' | sort -n | tail -n1
}

# Next minor ("X.Y") above the highest cut line, over stable and RC tags.
next_target_minor() {
  local line
  line=$(
    {
      stable_tags
      git tag -l "${TAG_PREFIX}*" | sed "s|^${TAG_PREFIX}||" | { grep -E '^[0-9]+\.[0-9]+\.0-rc\.[0-9]+$' || true; }
    } | sed -E 's/^([0-9]+\.[0-9]+)\..*/\1/' | sort -V | tail -n1
  )
  [[ -z "$line" ]] && die "No stable or RC tags found to anchor the next minor."
  printf '%s.%s' "${line%.*}" "$(( ${line#*.} + 1 ))"
}

# The newest cut line not yet promoted; empty when that line already shipped.
pending_rc_line() {
  local stable rc
  stable=$(stable_tags | sed -E 's/^([0-9]+\.[0-9]+)\..*/\1/' | sort -V | tail -n1)
  rc=$(
    git tag -l "${TAG_PREFIX}*" | sed "s|^${TAG_PREFIX}||" \
      | { grep -E '^[0-9]+\.[0-9]+\.0-rc\.[0-9]+$' || true; } \
      | sed -E 's/^([0-9]+\.[0-9]+)\..*/\1/' | sort -V | tail -n1
  )
  if [[ -n "$rc" && "$rc" != "$stable" && "$(printf '%s\n%s\n' "$stable" "$rc" | sort -V | tail -n1)" == "$rc" ]]; then
    printf '%s' "$rc"
  fi
}

# Validate a releases/server-<major>.<minor>.x branch and echo its "X.Y" line.
# Server release branches are prefixed to keep them distinct from CLI release
# branches, which share the same origin.
line_from_branch() {
  [[ "$1" =~ ^releases/server-([0-9]+\.[0-9]+)\.x$ ]] ||
    die "Branch must be named releases/server-<major>.<minor>.x (got '${1:-<empty>}')."
  printf '%s' "${BASH_REMATCH[1]}"
}

case "$CHANNEL" in
  canary)
    target="$(next_target_minor).0"
    n=$(highest_prerelease_n "$target" canary)
    emit version "${target}-canary.$(( ${n:-0} + 1 ))"
    changelog_from="$(latest_canary_tag)"
    [[ -n "$changelog_from" ]] && changelog_from="${TAG_PREFIX}${changelog_from}"
    ;;

  rc-new)
    minor="$(next_target_minor)"
    target="${minor}.0"
    branch="releases/server-${minor}.x"
    if git ls-remote --exit-code --heads origin "refs/heads/${branch}" >/dev/null 2>&1; then
      die "Branch ${branch} already exists. Use the 'rc' channel with branch=${branch} to iterate its RC."
    fi
    [[ -n "$(highest_prerelease_n "$target" rc)" ]] &&
      die "An RC already exists for ${target}. Use the 'rc' channel to iterate it."
    tag_exists "$target" &&
      die "Stable tag ${TAG_PREFIX}${target} already exists; cannot start a new RC line for it."
    emit version "${target}-rc.1"
    emit branch "$branch"
    ;;

  rc)
    target="$(line_from_branch "$BRANCH").0"
    tag_exists "$target" && die "${TAG_PREFIX}${target} is already stable; the RC line is closed."
    n=$(highest_prerelease_n "$target" rc)
    [[ -z "$n" ]] && die "No existing RC for ${target}. Cut the line first via the 'rc-new' channel."
    emit version "${target}-rc.$(( n + 1 ))"
    ;;

  promote)
    if [[ -z "$BRANCH" ]]; then
      line="$(pending_rc_line)"
      if [[ -z "$line" ]]; then
        echo "::notice::No release candidate is waiting for promotion; nothing to promote."
        emit should_publish false
        exit 0
      fi
      BRANCH="releases/server-${line}.x"
    fi
    target="$(line_from_branch "$BRANCH").0"
    SHA=$(git ls-remote --exit-code --heads origin "refs/heads/${BRANCH}" | cut -f1) ||
      die "${target} cannot be promoted: its release branch ${BRANCH} does not exist."
    tag_exists "$target" && die "${TAG_PREFIX}${target} has already been promoted to stable."
    n=$(highest_prerelease_n "$target" rc)
    [[ -z "$n" ]] && die "No RC has been published for ${target}; promote only after at least one RC has soaked."
    rc_commit=$(git rev-list -n1 "${TAG_PREFIX}${target}-rc.${n}")
    [[ "$rc_commit" == "$SHA" ]] ||
      die "Branch HEAD (${SHA}) is ahead of the latest RC ${TAG_PREFIX}${target}-rc.${n} (${rc_commit}). Cut a new RC with the 'rc' channel and let it soak before promoting."
    emit version "$target"
    emit branch "$BRANCH"
    emit should_publish true
    ;;

  *)
    die "Unknown channel '${CHANNEL:-<empty>}'. Expected one of: canary | rc-new | rc | promote."
    ;;
esac

emit sha "$SHA"
if [[ -z "$changelog_from" ]]; then
  fallback="$(latest_stable_tag)"
  [[ -n "$fallback" ]] && changelog_from="${TAG_PREFIX}${fallback}"
fi
emit changelog_from "${changelog_from:-}"
