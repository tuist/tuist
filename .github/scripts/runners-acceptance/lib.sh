# shellcheck shell=bash disable=SC2034
# Sourced by the runners acceptance scripts. Every failure names the layer that
# broke, as the annotation title and in the job summary, so a red gate reads as
# "Kura auth" or "Cache hits" without opening the log.

fail() {
  local layer="$1"
  shift
  echo "::error title=${layer}::$*"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf '### %s failed\n\n%s\n\n' "${layer}" "$*" >> "${GITHUB_STEP_SUMMARY}"
  fi
  exit 1
}

pass() {
  echo "$*"
  if [ -n "${GITHUB_STEP_SUMMARY:-}" ]; then
    printf -- '- %s\n' "$*" >> "${GITHUB_STEP_SUMMARY}"
  fi
}

# The log lines a broken Kura leaves in client output while builds still
# "succeed": the cas-proxy's degraded lookups, Xcode's non-fatal CAS warnings,
# and the module cache falling back to local.
CACHE_ERROR_PATTERN='Authentication backend unavailable|CAS operation failed|CAS error:|Remote module caching is unavailable|kura\.auth\.backend_unavailable'

cache_endpoint_host() {
  local host="${1#*://}"
  host="${host%%/*}"
  echo "${host%%:*}"
}
