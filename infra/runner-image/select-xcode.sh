#!/bin/bash
# Selects the Xcode a job or sandbox asked for, and warms the guest's Xcodes
# while a runner waits idle.
#
#   select-xcode.sh select <catalog-version>
#     Points `xcode-select` and `/Applications/Xcode.app` at the Xcode the
#     runner profile (or the sandbox create) names. dispatch-poll.sh runs it
#     on the claim path, so it never launches `xcodebuild`; measured on a
#     fresh clone, the switch takes about 50 ms. Exits 1 and changes nothing
#     when the image has no such Xcode.
#
#   select-xcode.sh warm [<preferred-version>]
#     Launches each Xcode once while the VM is idle, so a job's first
#     `xcodebuild` takes about 0.1 s instead of about 8 s on a cold boot.
#     Warms every Xcode in an image with up to XCODE_WARM_ALL_MAX (3) of
#     them, and otherwise only the image's default and <preferred-version>:
#     each extra warmed Xcode keeps about 360 MB of clean file cache. Stops
#     before the next Xcode once XCODE_WARM_STOP_FILE exists (the claim).
#
# `DEVELOPER_DIR` is deliberately not set for the job: it overrides
# `xcode-select`, so a workflow that switches Xcode the GitHub-hosted way
# (`sudo xcode-select -s`, setup-xcode, fastlane) would silently keep ours.
#
# Catalog versions are the image's bundle names (`26.4.1` is
# `/Applications/Xcode_26.4.1.app`), except a beta channel (`27.3-beta`),
# whose image holds the exact beta (`Xcode_27.3-beta-2.app`); see
# infra/macos-xcode-image/AGENTS.md.
set -uo pipefail

XCODE_APPS_DIR="${XCODE_APPS_DIR:-/Applications}"
XCODE_WARM_ALL_MAX="${XCODE_WARM_ALL_MAX:-3}"
XCODE_WARM_STOP_FILE="${XCODE_WARM_STOP_FILE:-}"

xcode_log() { echo "$(date -u +%FT%TZ) select-xcode: $*"; }

# resolved prints a path with every symlink resolved, so an alias
# (`Xcode_26.4.app`) and its bundle compare equal.
resolved() { (cd -P "$1" 2>/dev/null && pwd -P); }

# installed_xcodes prints each Xcode bundle once: the real `Xcode_*.app`
# directories, not the major-minor aliases or `Xcode.app`.
installed_xcodes() {
  local app
  for app in "${XCODE_APPS_DIR}"/Xcode_*.app; do
    if [ -d "${app}" ] && [ ! -L "${app}" ]; then printf '%s\n' "${app}"; fi
  done
}

# xcode_app prints the bundle of a catalog version, or fails without one.
xcode_app() {
  local version=$1 app best="" best_n=-1 n
  case "${version}" in "" | */* | *..*) return 1 ;; esac
  if [ -d "${XCODE_APPS_DIR}/Xcode_${version}.app" ]; then
    printf '%s\n' "${XCODE_APPS_DIR}/Xcode_${version}.app"
    return 0
  fi
  # A beta channel names the newest numbered beta the image holds.
  case "${version}" in *-beta) ;; *) return 1 ;; esac
  for app in "${XCODE_APPS_DIR}/Xcode_${version}"-*.app; do
    [ -d "${app}" ] || continue
    n=${app##*-}
    n=${n%.app}
    case "${n}" in "" | *[!0-9]*) continue ;; esac
    if [ "${n}" -gt "${best_n}" ]; then best=${app} best_n=${n}; fi
  done
  [ -n "${best}" ] || return 1
  printf '%s\n' "${best}"
}

select_xcode() {
  local version=$1 app link
  if ! app=$(xcode_app "${version}"); then
    xcode_log "WARNING no Xcode ${version} in ${XCODE_APPS_DIR}; keeping $(xcode-select -p 2>/dev/null)"
    return 1
  fi
  if ! sudo -n xcode-select -s "${app}"; then
    xcode_log "WARNING xcode-select -s ${app} failed; keeping $(xcode-select -p 2>/dev/null)"
    return 1
  fi
  # Scripts that hard-code /Applications/Xcode.app follow the selection. A
  # real bundle at that path is the image's own and is left alone.
  link="${XCODE_APPS_DIR}/Xcode.app"
  if [ -L "${link}" ] || [ ! -e "${link}" ]; then
    sudo -n ln -sfn "${app}" "${link}" || xcode_log "WARNING could not link ${link} to ${app}"
  else
    xcode_log "${link} is not a symlink; left as is"
  fi
  xcode_log "selected Xcode ${version} at ${app}"
}

# warm_one launches one Xcode's tools the way a job's first build does.
warm_one() {
  local developer="$1/Contents/Developer"
  DEVELOPER_DIR="${developer}" xcodebuild -version >/dev/null 2>&1
  DEVELOPER_DIR="${developer}" xcrun --find swift >/dev/null 2>&1
  DEVELOPER_DIR="${developer}" xcrun swift --version >/dev/null 2>&1
}

warm_xcodes() {
  local preferred=${1:-} apps count default preferred_app app real seen="" started
  apps=$(installed_xcodes)
  count=$(printf '%s' "${apps}" | grep -c .)
  if [ "${count}" -gt "${XCODE_WARM_ALL_MAX}" ]; then
    default=$(xcode-select -p 2>/dev/null)
    apps=${default%/Contents/Developer}
    if [ -n "${preferred}" ] && preferred_app=$(xcode_app "${preferred}"); then
      apps=$(printf '%s\n%s' "${apps}" "${preferred_app}")
    fi
  fi
  # The first sudo and xcode-select of a boot took 3.2 s; the claim's switch
  # should not pay it. `-p` warms them without changing the selection, so a
  # claim that switches while this runs is never overwritten.
  sudo -n xcode-select -p >/dev/null 2>&1
  while IFS= read -r app; do
    [ -n "${app}" ] || continue
    if [ -n "${XCODE_WARM_STOP_FILE}" ] && [ -e "${XCODE_WARM_STOP_FILE}" ]; then
      xcode_log "warm-up stopped: claimed"
      return 0
    fi
    real=$(resolved "${app}") || continue
    case "${real}" in *.app) ;; *) continue ;; esac
    case "${seen}" in *"|${real}|"*) continue ;; esac
    seen="${seen}|${real}|"
    started=${SECONDS}
    warm_one "${real}"
    xcode_log "warmed $(basename "${real}") in $((SECONDS - started)) s"
  done <<EOF
${apps}
EOF
}

if [ "${BASH_SOURCE[0]}" = "$0" ]; then
  case "${1:-}" in
    select) select_xcode "${2:-}" ;;
    warm) warm_xcodes "${2:-}" ;;
    *)
      echo "usage: $0 select <version> | warm [<preferred-version>]" >&2
      exit 64
      ;;
  esac
fi
