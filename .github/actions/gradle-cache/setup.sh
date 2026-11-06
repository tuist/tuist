#!/usr/bin/env bash
set -uo pipefail

if command -v tuist-cache-volume >/dev/null 2>&1; then
  client=tuist-cache-volume
elif [ -x /__e/tuist-cache-volume ]; then
  client=/__e/tuist-cache-volume
else
  echo "This runner does not provide Tuist cache volumes; nothing to set up."
  exit 0
fi

gradle_home=${GRADLE_USER_HOME:-$HOME/.gradle}
case "$gradle_home" in
  /*) ;;
  *) gradle_home="$PWD/$gradle_home" ;;
esac

arguments=(--key tuist-gradle --path "$gradle_home/caches" --path "$gradle_home/wrapper")
size=${TUIST_GRADLE_CACHE_SIZE:-}
if [ -n "$size" ]; then
  case "$("$client" -h 2>&1 || true)" in
    *-size*) arguments+=(--size "$size") ;;
    *) echo "::warning::This runner image does not support the size input yet; the Gradle cache keeps its current size." ;;
  esac
fi

status=0
"$client" "${arguments[@]}" || status=$?
if [ "$status" != 0 ]; then
  echo "::warning::Could not attach the Gradle cache (tuist-cache-volume exited $status); the job runs with an empty one."
  exit 0
fi

# Gradle drops only entries unused for seven days, so a busy repository fills the
# volume within hours and the job that reaches the top fails. From three quarters
# full, drop Gradle's local build cache, and start the caches empty if that is not
# enough. Nothing holds these files before Gradle runs.
used=$(df -Pk "$gradle_home/caches" 2>/dev/null | awk 'NR == 2 && $3 + $4 > 0 { print int($3 * 100 / ($3 + $4)) }')
if [ "${used:-0}" -ge 75 ]; then
  rm -rf "$gradle_home/caches/build-cache-1"
  used=$(df -Pk "$gradle_home/caches" 2>/dev/null | awk 'NR == 2 && $3 + $4 > 0 { print int($3 * 100 / ($3 + $4)) }')
  if [ "${used:-0}" -ge 75 ]; then
    find "$gradle_home/caches" -mindepth 1 -maxdepth 1 -exec rm -rf {} +
    echo "::warning::The Gradle cache was nearly full, so this job starts it empty. Raise the size input if this repeats."
  else
    echo "The Gradle cache was nearly full; dropped Gradle's local build cache."
  fi
fi

mkdir -p "$gradle_home/init.d"
cat >"$gradle_home/init.d/tuist-gradle-cache.gradle" <<'GROOVY'
// Written by Tuist's Gradle cache step. Gradle cleans its user home only when
// the daemon stops, which a CI job rarely reaches, so the persisted cache would
// grow until it fills its volume. Clean after every build instead, and drop
// entries unused for seven days. Gradle versions without this API keep their
// own settings.
beforeSettings { settings ->
    try {
        def cleanup = Class.forName('org.gradle.api.cache.Cleanup', true, Settings.classLoader).getField('ALWAYS').get(null)
        settings.caches { caches ->
            caches.cleanup.set(cleanup)
            [caches.releasedWrappers, caches.snapshotWrappers, caches.downloadedResources, caches.createdResources, caches.buildCache].each {
                it.setRemoveUnusedEntriesAfterDays(7)
            }
        }
    } catch (Throwable ignored) {
    }
}
GROOVY
