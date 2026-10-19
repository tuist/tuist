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

status=0
"$client" --key tuist-gradle --path "$gradle_home/caches" --path "$gradle_home/wrapper" || status=$?
if [ "$status" != 0 ]; then
  echo "::warning::Could not attach the Gradle cache (tuist-cache-volume exited $status); the job runs with an empty one."
  exit 0
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
