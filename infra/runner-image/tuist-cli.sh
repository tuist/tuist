#!/bin/sh
# /opt/tuist/cli/bin/tuist: runs the Tuist a repository pins through mise,
# else the one preinstalled in the image. The preinstall lives outside
# runner's mise data directory, which stays empty so cache volumes can mount
# over it, so mise has no tuist shim until a repository installs one.
# `mise exec` installs a pinned version on first use. The guard variable stops
# a loop back into this wrapper when mise cannot provide the pin.
if [ -z "${TUIST_CLI_WRAPPED:-}" ] && command -v mise >/dev/null 2>&1 &&
  [ -n "$(mise current tuist 2>/dev/null)" ]; then
  export TUIST_CLI_WRAPPED=1
  exec mise exec -- tuist "$@"
fi
# Tuist finds ProjectDescription.framework next to its executable.
exec /opt/tuist/cli/current/tuist "$@"
