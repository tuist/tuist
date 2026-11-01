#!/usr/bin/env bash
#MISE description="Extracts gettext templates without disturbing the dev server"

set -euo pipefail

# `mix gettext.extract` force-recompiles every module of the application. In
# the shared _build/dev it holds the build lock for the whole compilation,
# stalling a running dev server and every other Mix task, and the dev server
# then reloads every module. Its own build path keeps both untouched.
export MIX_BUILD_PATH="${MIX_BUILD_PATH:-_build/gettext_extract}"

mix gettext.extract "$@"
