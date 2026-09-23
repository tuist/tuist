#!/usr/bin/env bash
set -euo pipefail

test "${TUIST_URL:?}" = https://staging.tuist.dev
test "${SMOKE_PROJECT:?}" = kura-spec95-e2e/probe
: "${TUIST_TOKEN:?Temporary staging fixture token is missing}"
unset TUIST_CACHE_ENDPOINT
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="${RUNNER_TEMP:?}/gradle-cache-smoke"
mkdir -p "$fixture"
cd "$fixture"
export GRADLE_USER_HOME="$fixture/gradle-home"
SMOKE_NONCE="${GITHUB_RUN_ID:?}-${GITHUB_RUN_ATTEMPT:?}-$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
export SMOKE_NONCE

printf 'project = "%s"\nurl = "%s"\n' "$SMOKE_PROJECT" "$TUIST_URL" > tuist.toml
cat > settings.gradle <<'GRADLE'
plugins { id 'dev.tuist' version '0.16.0' }
rootProject.name = 'spec95-staging-cache-soak'
tuist { buildCache { enabled = true; push = true } }
buildCache { local { enabled = false } }
GRADLE
cat > build.gradle <<'GRADLE'
@CacheableTask
abstract class CacheProbe extends DefaultTask {
    @Input abstract Property<String> getNonce()
    @OutputFile abstract RegularFileProperty getResult()
    @TaskAction void generate() { result.get().asFile.text = nonce.get() }
}
tasks.register('cacheProbe', CacheProbe) {
    nonce = providers.environmentVariable('SMOKE_NONCE')
    result = layout.buildDirectory.file('cache-probe.txt')
}
GRADLE
git init --quiet
git add settings.gradle build.gradle tuist.toml
git -c user.name='Tuist CI' -c user.email='ci@tuist.dev' commit --quiet -m 'Initialize spec95 staging fixture'

check_endpoint() {
    printf 'Authorization: Bearer %s\n' "$TUIST_TOKEN" |
        curl --fail --silent --show-error --max-time 30 -H @- \
            -H 'x-tuist-cli-version: x.y.z' \
            "$TUIST_URL/api/cache/endpoints?account_handle=kura-spec95-e2e" > endpoint.json
    jq -e '.provisioning == false and .endpoints == ["https://kura-spec95-e2e-staging.cache.tuist.dev"]' endpoint.json >/dev/null
    printf '%s endpoint=%s\n' "$(date -u +%FT%TZ)" "$(cat endpoint.json)" >> endpoints.log
}

check_endpoint
"$repo_root/gradle/gradlew" cacheProbe --build-cache --no-configuration-cache --no-daemon --info --console=plain 2>&1 | tee first.log
grep -Fq "Stored cache entry for task ':cacheProbe'" first.log
if grep -Eq 'Could not (load|store).*cache|FROM-CACHE' first.log; then
    echo 'ERROR: first build must upload a fresh remote entry without cache errors'
    exit 1
fi
test "$(cat build/cache-probe.txt)" = "$SMOKE_NONCE"
for attempt in $(seq 1 12); do
    sleep 30
    check_endpoint
    rm -rf "$fixture/build"
    "$repo_root/gradle/gradlew" cacheProbe --build-cache --no-configuration-cache --no-daemon --info --console=plain 2>&1 | tee "hit-$attempt.log"
    grep -Fq '> Task :cacheProbe FROM-CACHE' "hit-$attempt.log"
    grep -Fq "Loaded cache entry for task ':cacheProbe'" "hit-$attempt.log"
    if grep -Eq 'Could not (load|store).*cache' "hit-$attempt.log"; then exit 1; fi
    test "$(cat build/cache-probe.txt)" = "$SMOKE_NONCE"
done
echo 'PASS: stable API hand-out, remote upload, and 12 fresh-process remote hits with local caching disabled.'
