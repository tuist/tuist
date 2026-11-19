#!/usr/bin/env bash
set -euo pipefail

test "${TUIST_URL:?}" = https://staging.tuist.dev
if [[ "${TUIST_CACHE_ENDPOINT:?}" != http://kura-tuist-ovh-gra-runners.kura.svc.cluster.local:4000 &&
      ! "$TUIST_CACHE_ENDPOINT" =~ ^http://kura-[a-z0-9-]+-eu-west-1(-m)?\.kura\.svc\.cluster\.local:4000$ ]]; then
    echo 'Expected the staging private runner cache or an EU-West regional cache endpoint.' >&2
    exit 1
fi
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="${RUNNER_TEMP:?}/gradle-real-cache-smoke"
mkdir -p "$fixture"
cp "$repo_root/gradle/settings.gradle.kts" "$repo_root/gradle/build.gradle.kts" "$fixture/"
cp -R "$repo_root/gradle/src" "$fixture/"
cd "$fixture"
export GRADLE_USER_HOME="$fixture/gradle-home"
SMOKE_NONCE="${GITHUB_RUN_ID:?}-${GITHUB_RUN_ATTEMPT:?}-$(od -An -N16 -tx1 /dev/urandom | tr -d ' \n')"
export SMOKE_NONCE
printf 'project = "%s"\n' "${SMOKE_PROJECT:?}" > tuist.toml
cat >> build.gradle.kts <<'GRADLE'

tasks.matching { it.name == "compileKotlin" || it.name == "compileTestKotlin" }.configureEach {
    inputs.property("regionalSmokeNonce", providers.environmentVariable("SMOKE_NONCE"))
}
GRADLE
cat > gradle.properties <<'PROPERTIES'
org.gradle.jvmargs=-Xmx2g -XX:MaxMetaspaceSize=1g
org.gradle.workers.max=2
kotlin.compiler.execution.strategy=in-process
PROPERTIES
git init --quiet
git add .
git -c user.name='Tuist CI' -c user.email='ci@tuist.dev' commit --quiet -m 'Initialize real Gradle cache validation'
args=(compileKotlin compileTestKotlin --build-cache --no-configuration-cache --no-daemon --info --console=plain)
"$repo_root/gradle/gradlew" "${args[@]}" 2>&1 | tee first.log
for task in compileKotlin compileTestKotlin; do
    grep -Fq "Stored cache entry for task ':$task'" first.log
done
if grep -Eq 'Could not (load|store).*cache|FROM-CACHE' first.log; then exit 1; fi
find build/classes -type f -print0 | sort -z | xargs -0 sha256sum > classes.sha256
rm -rf build
"$repo_root/gradle/gradlew" "${args[@]}" 2>&1 | tee second.log
for task in compileKotlin compileTestKotlin; do
    grep -Fq "Loaded cache entry for task ':$task'" second.log
    grep -Fq "> Task :$task FROM-CACHE" second.log
done
if grep -Eq 'Could not (load|store).*cache' second.log; then exit 1; fi
sha256sum --check classes.sha256
echo 'Real production and test Kotlin sources restored with matching class checksums.'
