#!/usr/bin/env bash
#MISE description="Compute the next CLI version for a release channel (canary | rc-new | rc | promote)"
set -euo pipefail

# Resolve the next CLI version for one of the release channels and emit it (with
# the SHA to build and the changelog base) to GITHUB_OUTPUT, falling back to
# stdout when run locally.
#
# The "cut lines" that anchor the scheme are the stable tags (X.Y.Z) and the RC
# tags (X.Y.0-rc.N). Canary tags are deliberately NOT counted as cut lines: they
# track unreleased work for the *next* minor, so counting them would make canary
# chase its own tail. Because rc-new creates the release branch and publishes
# rc.1 atomically, a line is "cut" the moment its first RC tag exists — there is
# never a release branch without a matching tag to scan.
#
# Usage:
#   channel-version.sh canary               # next X.Y.0-canary.N off main
#   channel-version.sh rc-new               # cut next minor: X.Y.0-rc.1 (+ branch)
#   channel-version.sh rc      <branch>     # iterate X.Y.0-rc.(N+1) on a branch
#   channel-version.sh promote <branch>     # promote X.Y.0 stable from a branch

CHANNEL="${1:-}"
BRANCH="${2:-}"

REPO_ROOT="$(git rev-parse --show-toplevel)"
cd "$REPO_ROOT"

emit() {
  local key=$1 value=$2
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    printf '%s=%s\n' "$key" "$value" >> "$GITHUB_OUTPUT"
  fi
  printf '%s=%s\n' "$key" "$value"
}

# Escape a literal version string for use inside a grep -E pattern.
# shellcheck disable=SC2016  # the sed program is a literal, nothing to expand
escape_re() { printf '%s' "$1" | sed 's/[.[\*^$()+?{|]/\\&/g'; }

stable_tags() { git tag -l | grep -E '^[0-9]+\.[0-9]+\.[0-9]+$' || true; }

latest_stable_tag() { stable_tags | sort -V | tail -n1; }

# Highest minor line that has been cut, as "X.Y" (over stable and rc tags).
highest_cut_line() {
  {
    stable_tags | sed -E 's/^([0-9]+\.[0-9]+)\..*$/\1/'
    git tag -l | grep -E '^[0-9]+\.[0-9]+\.0-rc\.[0-9]+$' | sed -E 's/^([0-9]+\.[0-9]+)\..*$/\1/' || true
  } | sort -u | sort -V | tail -n1
}

next_minor() {
  local line=$1 major minor
  major=${line%.*}
  minor=${line#*.}
  printf '%s.%s' "$major" "$((minor + 1))"
}

# Highest N among tags matching <target>-<channel>.N. Prints nothing when none
# exist; callers default to 0.
highest_prerelease_n() {
  local target=$1 channel=$2 target_re
  target_re=$(escape_re "$target")
  git tag -l \
    | { grep -E "^${target_re}-${channel}\.[0-9]+$" || true; } \
    | sed -E "s/.*-${channel}\.([0-9]+)$/\1/" \
    | sort -n | tail -n1
}

line_from_branch() {
  local branch=$1
  if ! printf '%s' "$branch" | grep -qE '^releases/[0-9]+\.[0-9]+\.x$'; then
    echo "::error::Branch must be named releases/<major>.<minor>.x (got '${branch:-<empty>}')." >&2
    exit 1
  fi
  local line=${branch#releases/}
  printf '%s' "${line%.x}"
}

SHA=$(git rev-parse HEAD)

case "$CHANNEL" in
  canary)
    line=$(highest_cut_line)
    if [[ -z "$line" ]]; then
      echo "::error::No stable or RC tags found to anchor the canary line." >&2
      exit 1
    fi
    target="$(next_minor "$line").0"
    latest_n=$(highest_prerelease_n "$target" canary)
    emit version "${target}-canary.$(( ${latest_n:-0} + 1 ))"
    emit sha "$SHA"
    emit changelog_from "$(latest_stable_tag)"
    ;;

  rc-new)
    line=$(highest_cut_line)
    if [[ -z "$line" ]]; then
      echo "::error::No stable or RC tags found to anchor the next RC line." >&2
      exit 1
    fi
    next="$(next_minor "$line")"
    target="${next}.0"
    branch="releases/${next}.x"

    if git ls-remote --exit-code --heads origin "refs/heads/${branch}" >/dev/null 2>&1; then
      echo "::error::Branch ${branch} already exists. Use the 'rc' channel with branch=${branch} to iterate its RC." >&2
      exit 1
    fi
    if [[ -n "$(highest_prerelease_n "$target" rc)" ]]; then
      echo "::error::An RC already exists for ${target}. Use the 'rc' channel to iterate it." >&2
      exit 1
    fi
    if git rev-parse --verify --quiet "refs/tags/${target}" >/dev/null; then
      echo "::error::Stable tag ${target} already exists; cannot start a new RC line for it." >&2
      exit 1
    fi

    emit version "${target}-rc.1"
    emit branch "$branch"
    emit sha "$SHA"
    emit changelog_from "$(latest_stable_tag)"
    ;;

  rc)
    line=$(line_from_branch "$BRANCH")
    target="${line}.0"
    if git rev-parse --verify --quiet "refs/tags/${target}" >/dev/null; then
      echo "::error::${target} is already stable; the RC line is closed." >&2
      exit 1
    fi
    latest_n=$(highest_prerelease_n "$target" rc)
    if [[ -z "$latest_n" ]]; then
      echo "::error::No existing RC for ${target}. Cut the line first via the 'rc-new' channel." >&2
      exit 1
    fi
    emit version "${target}-rc.$((latest_n + 1))"
    emit sha "$SHA"
    emit changelog_from "$(latest_stable_tag)"
    ;;

  promote)
    line=$(line_from_branch "$BRANCH")
    target="${line}.0"
    if git rev-parse --verify --quiet "refs/tags/${target}" >/dev/null; then
      echo "::error::${target} has already been promoted to stable." >&2
      exit 1
    fi
    if [[ -z "$(highest_prerelease_n "$target" rc)" ]]; then
      echo "::error::No RC has been published for ${target}; promote only after at least one RC has soaked." >&2
      exit 1
    fi
    emit version "$target"
    emit sha "$SHA"
    emit changelog_from "$(latest_stable_tag)"
    ;;

  *)
    echo "::error::Unknown channel '${CHANNEL:-<empty>}'. Expected one of: canary | rc-new | rc | promote." >&2
    exit 1
    ;;
esac
