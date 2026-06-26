#!/usr/bin/env bash
#MISE description="Compute the next CLI version for a release channel (canary | rc-new | rc | promote)"
set -euo pipefail

# Resolve the next CLI version for one of the release channels and emit it, with
# the SHA to build and the changelog base, to GITHUB_OUTPUT (and stdout). Run by
# the release workflows as `mise run cli:release:channel-version -- <channel>`:
#
#   canary            cli-release.yml   next X.Y.0-canary.N off main
#   rc-new            cli-rc.yml        cut next minor: X.Y.0-rc.1 (+ branch to create)
#   rc      <branch>  cli-rc.yml        iterate X.Y.0-rc.(N+1) on a release branch
#   promote <branch>  cli-promote.yml   promote X.Y.0 stable from a release branch
#
# The "cut lines" that anchor the scheme are the stable tags (X.Y.Z) and the RC
# tags (X.Y.0-rc.N). Canary tags are deliberately NOT counted: they track the
# *next* minor, so counting them would make canary chase its own tail. rc-new
# creates the release branch and publishes rc.1 atomically, so a line is "cut"
# the moment its first RC tag exists.
#
# The emitted `changelog_from` is the base the changelog is generated against.
# For canary it is the previous canary tag, so each canary lists only what
# landed since the last canary — not the whole backlog since the last stable
# (it falls back to the latest stable only when no canary exists yet). RC and
# promote keep the full changelog since the latest stable, since those are the
# release notes for the upcoming X.Y.0.

CHANNEL="${1:-}"
BRANCH="${2:-}"

cd "$(git rev-parse --show-toplevel)"
SHA=$(git rev-parse HEAD)

# Changelog base. Defaults to the latest stable; the canary case narrows it to
# the previous canary below.
changelog_from=""

emit() {
  [[ -n "${GITHUB_OUTPUT:-}" ]] && printf '%s=%s\n' "$1" "$2" >> "$GITHUB_OUTPUT"
  printf '%s=%s\n' "$1" "$2"
}

die() { echo "::error::$1" >&2; exit 1; }

stable_tags() { git tag -l | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' || true; }
latest_stable_tag() { stable_tags | sort -V | tail -n1; }
# Canaries are always X.Y.0-canary.N. The version sort dominates on the minor
# first and the canary N second, so the tail is the chronologically newest
# canary even across a minor bump (a line cut advances canary to the next minor).
canary_tags() { git tag -l | grep -E '^[0-9]+\.[0-9]+\.0-canary\.[0-9]+$' || true; }
latest_canary_tag() { canary_tags | sort -V | tail -n1; }
tag_exists() { git rev-parse --verify --quiet "refs/tags/$1" >/dev/null; }

# Highest N among existing <target>-<channel>.N tags; empty when none exist.
highest_prerelease_n() {
  local target_re=${1//./\\.} channel=$2
  git tag -l | { grep -E "^${target_re}-${channel}\.[0-9]+$" || true; } \
    | sed -E 's/.*\.([0-9]+)$/\1/' | sort -n | tail -n1
}

# Next minor ("X.Y") above the highest cut line, over stable and RC tags.
next_target_minor() {
  local line
  line=$(
    {
      stable_tags
      git tag -l | { grep -E '^[0-9]+\.[0-9]+\.0-rc\.[0-9]+$' || true; }
    } | sed -E 's/^([0-9]+\.[0-9]+)\..*/\1/' | sort -V | tail -n1
  )
  [[ -z "$line" ]] && die "No stable or RC tags found to anchor the next minor."
  printf '%s.%s' "${line%.*}" "$(( ${line#*.} + 1 ))"
}

# Validate a releases/<major>.<minor>.x branch and echo its "X.Y" line.
line_from_branch() {
  [[ "$1" =~ ^releases/([0-9]+\.[0-9]+)\.x$ ]] ||
    die "Branch must be named releases/<major>.<minor>.x (got '${1:-<empty>}')."
  printf '%s' "${BASH_REMATCH[1]}"
}

case "$CHANNEL" in
  canary)
    target="$(next_target_minor).0"
    n=$(highest_prerelease_n "$target" canary)
    emit version "${target}-canary.$(( ${n:-0} + 1 ))"
    # Base the changelog on the previous canary, not the last stable, so it
    # lists only what landed since the last canary. Falls back to the latest
    # stable (handled by the final emit) when no canary has been cut yet.
    changelog_from="$(latest_canary_tag)"
    ;;

  rc-new)
    minor="$(next_target_minor)"
    target="${minor}.0"
    branch="releases/${minor}.x"
    if git ls-remote --exit-code --heads origin "refs/heads/${branch}" >/dev/null 2>&1; then
      die "Branch ${branch} already exists. Use the 'rc' channel with branch=${branch} to iterate its RC."
    fi
    [[ -n "$(highest_prerelease_n "$target" rc)" ]] &&
      die "An RC already exists for ${target}. Use the 'rc' channel to iterate it."
    tag_exists "$target" &&
      die "Stable tag ${target} already exists; cannot start a new RC line for it."
    emit version "${target}-rc.1"
    emit branch "$branch"
    ;;

  rc)
    target="$(line_from_branch "$BRANCH").0"
    tag_exists "$target" && die "${target} is already stable; the RC line is closed."
    n=$(highest_prerelease_n "$target" rc)
    [[ -z "$n" ]] && die "No existing RC for ${target}. Cut the line first via the 'rc-new' channel."
    emit version "${target}-rc.$(( n + 1 ))"
    ;;

  promote)
    target="$(line_from_branch "$BRANCH").0"
    tag_exists "$target" && die "${target} has already been promoted to stable."
    n=$(highest_prerelease_n "$target" rc)
    [[ -z "$n" ]] && die "No RC has been published for ${target}; promote only after at least one RC has soaked."
    # Promote exactly what soaked: the branch HEAD must be the commit the latest
    # RC points at. Fixes landed after the last RC have not soaked, so a new RC
    # must be cut (and soak) first.
    rc_commit=$(git rev-list -n1 "${target}-rc.${n}")
    [[ "$rc_commit" == "$SHA" ]] ||
      die "Branch HEAD (${SHA}) is ahead of the latest RC ${target}-rc.${n} (${rc_commit}). Cut a new RC with the 'rc' channel and let it soak before promoting."
    emit version "$target"
    ;;

  *)
    die "Unknown channel '${CHANNEL:-<empty>}'. Expected one of: canary | rc-new | rc | promote."
    ;;
esac

emit sha "$SHA"
emit changelog_from "${changelog_from:-$(latest_stable_tag)}"
