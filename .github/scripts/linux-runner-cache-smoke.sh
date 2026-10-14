#!/usr/bin/env bash
set -euo pipefail

: "${TUIST_CACHE_ENDPOINT:?Dispatch must supply the private runner-cache endpoint}"
: "${TUIST_TOKEN:?Set TUIST_STAGING_GRADLE_SMOKE_TOKEN for the staging project}"
: "${SMOKE_PROJECT:?Set the staging account/project}"
: "${RUNNER_TEMP:?Run this on the staging GitHub runner}"
: "${GITHUB_WORKSPACE:?Checkout the repository first}"

# Reject public-region ClusterIP fallback as well as public ingress URLs.
python3 - <<'PY'
import os
import re
from urllib.parse import urlsplit

endpoint = urlsplit(os.environ['TUIST_CACHE_ENDPOINT'])
assert endpoint.scheme == 'http', 'Expected the private ClusterIP HTTP endpoint'
assert re.fullmatch(r'kura-[a-z0-9-]+-ovh-gra-runners\.kura\.svc\.cluster\.local', endpoint.hostname or ''), endpoint.hostname
assert endpoint.port == 4000, 'Unexpected Kura service port'
assert not endpoint.username and not endpoint.password and not endpoint.query and not endpoint.fragment
assert endpoint.path in ('', '/')
assert re.fullmatch(r'[a-zA-Z0-9_-]+/[a-zA-Z0-9_-]+', os.environ['SMOKE_PROJECT']), 'Expected account/project'
print('Dispatch selected:', os.environ['TUIST_CACHE_ENDPOINT'])
PY
curl --fail --silent --show-error --max-time 10 "${TUIST_CACHE_ENDPOINT%/}/up"

fixture="$(mktemp -d "${RUNNER_TEMP}/kura-gradle-fixture.XXXXXX")"
evidence="${RUNNER_TEMP}/kura-gradle-smoke"
mkdir -p "$evidence"
trap 'rm -rf "$fixture"' EXIT
export SMOKE_PLUGIN_DIR="${GITHUB_WORKSPACE}/gradle"
SMOKE_NONCE="${GITHUB_RUN_ID:-local}-${GITHUB_RUN_ATTEMPT:-1}-$(date +%s)-${RANDOM}"
export SMOKE_NONCE

cat > "$fixture/settings.gradle" <<'GRADLE'
pluginManagement {
    includeBuild(System.getenv('SMOKE_PLUGIN_DIR'))
}
plugins { id 'dev.tuist' }
rootProject.name = 'kura-gradle-smoke'
tuist {
    project = System.getenv('SMOKE_PROJECT')
    url = 'https://staging.tuist.dev'
    buildCache {
        push = true
        allowInsecureProtocol = true
    }
}
buildCache { local { enabled = false } }
GRADLE
cat > "$fixture/build.gradle" <<'GRADLE'
@CacheableTask
abstract class KuraSmoke extends DefaultTask {
    @Input abstract Property<String> getNonce()
    @OutputFile abstract RegularFileProperty getArtifact()
    @TaskAction void generate() {
        artifact.get().asFile.parentFile.mkdirs()
        artifact.get().asFile.text = nonce.get() + '\n'
    }
}
tasks.register('kuraSmoke', KuraSmoke) {
    nonce = System.getenv('SMOKE_NONCE')
    artifact = layout.buildDirectory.file('smoke.txt')
}
GRADLE

gradle=("${GITHUB_WORKSPACE}/gradle/gradlew" -p "$fixture" --build-cache --no-configuration-cache --no-daemon --console=plain --info kuraSmoke)
"${gradle[@]}" | tee "$evidence/cold.log"
if grep -Eq '^> Task :kuraSmoke (FROM-CACHE|UP-TO-DATE)' "$evidence/cold.log"; then
  echo 'ERROR: unique cold build unexpectedly reused an output' >&2
  exit 1
fi
test "$(cat "$fixture/build/smoke.txt")" = "$SMOKE_NONCE"
rm -rf "$fixture/build"
"${gradle[@]}" | tee "$evidence/warm.log"
grep -Fx '> Task :kuraSmoke FROM-CACHE' "$evidence/warm.log"
test "$(cat "$fixture/build/smoke.txt")" = "$SMOKE_NONCE"
echo 'Gradle restored the artifact from the dispatched OVH private Kura service, with local build cache disabled.'
echo 'Confirm matching traffic on the hosts private NICs before declaring the physical vRack path verified.'
