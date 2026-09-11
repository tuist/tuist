#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="${RUNNER_TEMP:?}/gradle-cache-smoke"
mkdir -p "${fixture}"
cd "${fixture}"
export GRADLE_USER_HOME="${fixture}/gradle-home"
# A unique task input guarantees a cold remote key, including on reruns.
SMOKE_NONCE="${GITHUB_RUN_ID:?}-${GITHUB_RUN_ATTEMPT:?}-$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
export SMOKE_NONCE

printf 'project = "%s"\n' "${SMOKE_PROJECT:?}" > tuist.toml
cat > settings.gradle <<'GRADLE'
plugins {
    id 'dev.tuist' version '0.10.0'
}
rootProject.name = 'runner-container-cache-smoke'
buildCache {
    local { enabled = false }
}
GRADLE
cat > build.gradle <<'GRADLE'
@CacheableTask
abstract class CacheProbe extends DefaultTask {
    @Input abstract Property<String> getNonce()
    @OutputFile abstract RegularFileProperty getResult()

    @TaskAction
    void generate() {
        result.get().asFile.text = nonce.get()
    }
}

tasks.register('cacheProbe', CacheProbe) {
    nonce = providers.environmentVariable('SMOKE_NONCE')
    result = layout.buildDirectory.file('cache-probe.txt')
}
GRADLE
git init --quiet
git add settings.gradle build.gradle tuist.toml
git -c user.name='Tuist CI' -c user.email='ci@tuist.dev' commit --quiet -m 'Initialize cache smoke fixture'

"${repo_root}/gradle/gradlew" cacheProbe --build-cache --no-configuration-cache --no-daemon --info --console=plain 2>&1 | tee first.log
grep -Fq "Stored cache entry for task ':cacheProbe'" first.log
if grep -Eq 'Could not (load|store).*cache|FROM-CACHE' first.log; then
    echo "ERROR: the first build must upload a fresh cache entry without errors"
    exit 1
fi
test "$(cat build/cache-probe.txt)" = "${SMOKE_NONCE}"

rm -rf build
"${repo_root}/gradle/gradlew" cacheProbe --build-cache --no-configuration-cache --no-daemon --info --console=plain 2>&1 | tee second.log
grep -Fq "Loaded cache entry for task ':cacheProbe'" second.log
grep -Fq '> Task :cacheProbe FROM-CACHE' second.log
test "$(cat build/cache-probe.txt)" = "${SMOKE_NONCE}"
echo "Remote upload and hit verified with local caching disabled."
