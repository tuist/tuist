#!/usr/bin/env bash
# Reports the checkout's branch and revision to the build event stream so a
# Bazel invocation is attributable to a revision in Tuist (Kura reads
# BUILD_SCM_BRANCH / BUILD_SCM_REVISION off the stream).
#
# Both keys are deliberately unprefixed, so Bazel writes them to
# volatile-status.txt rather than stable-status.txt: a new commit or a branch
# switch then never invalidates a cached action. A STABLE_ prefix would put
# the revision into the action key space and cost a full rebuild per commit.
#
# Never fails the build: `git` may be missing, the tree may not be a
# repository, and a detached HEAD has no branch name. Each of those degrades
# to omitting the key, and the script always exits 0.
set -uo pipefail

branch=$(git rev-parse --abbrev-ref HEAD 2>/dev/null) || branch=""
revision=$(git rev-parse HEAD 2>/dev/null) || revision=""

# "HEAD" is what rev-parse reports for a detached checkout, which is not a
# branch, so it is dropped rather than reported as one.
if [ -n "$branch" ] && [ "$branch" != "HEAD" ]; then
  echo "BUILD_SCM_BRANCH $branch"
fi

if [ -n "$revision" ]; then
  echo "BUILD_SCM_REVISION $revision"
fi

exit 0
