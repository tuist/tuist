#!/usr/bin/env bash
set -euo pipefail

: "${RUNNER_TEMP:?}" "${SMOKE_PROJECT:?}" "${TUIST_CACHE_ENDPOINT:?}" "${BENCH_WAN_ENDPOINT:?}"
case "$TUIST_CACHE_ENDPOINT" in
  http://kura-*-ovh-gra-runners.kura.svc.cluster.local:4000) ;;
  *) echo 'Expected dispatch to select the OVH private Kura instance' >&2; exit 1 ;;
esac
case "$BENCH_WAN_ENDPOINT" in
  http://kura-*.kura.svc.cluster.local:4000) ;;
  *) echo 'Expected an explicitly selected staging public-region Service' >&2; exit 1 ;;
esac
pn_endpoint="$TUIST_CACHE_ENDPOINT"
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
fixture="$RUNNER_TEMP/gradle-pn-benchmark"
mkdir -p "$fixture"
printf 'logs=%s\n' "$fixture" >> "${GITHUB_OUTPUT:?}"
cd "$fixture"
export GRADLE_USER_HOME="$fixture/gradle-home"
printf 'project = "%s"\n' "$SMOKE_PROJECT" > tuist.toml
cat > settings.gradle <<'GRADLE'
plugins { id 'dev.tuist' version '0.10.0' }
rootProject.name = 'pn-kura-gradle-benchmark'
buildCache { local { enabled = false } }
GRADLE
cat > build.gradle <<'GRADLE'
@CacheableTask
abstract class CacheProbe extends DefaultTask {
    @Input abstract Property<String> getNonce()
    @Input abstract Property<Integer> getSizeMiB()
    @OutputFile abstract RegularFileProperty getResult()
    @TaskAction void generate() {
        def random = new Random(20261026L)
        def block = new byte[1024 * 1024]
        result.get().asFile.withOutputStream { stream ->
            sizeMiB.get().times { random.nextBytes(block); stream.write(block) }
        }
    }
}
tasks.register('cacheProbe', CacheProbe) {
    nonce = providers.environmentVariable('BENCH_NONCE')
    sizeMiB = providers.environmentVariable('BENCH_SIZE_MIB').map { it.toInteger() }
    result = layout.buildDirectory.file('payload.bin')
}
gradle.taskGraph.beforeTask { task ->
    if (task.name == 'cacheProbe') task.ext.benchmarkStarted = System.nanoTime()
}
gradle.taskGraph.afterTask { task, state ->
    if (task.name == 'cacheProbe') {
        println('BENCH_TASK_MS=' + Math.round((System.nanoTime() - task.ext.benchmarkStarted) / 1_000_000.0))
    }
}
GRADLE
git init --quiet
git add settings.gradle build.gradle tuist.toml
git -c user.name='Tuist CI' -c user.email='ci@tuist.dev' commit --quiet -m 'Initialize controlled Gradle cache benchmark'
printf 'mode,size_mib,round,phase,wall_ms,task_ms,sha256\n' > results.csv
printf 'PN=%s\nWAN=%s\nRUNNER=%s\n' "$pn_endpoint" "$BENCH_WAN_ENDPOINT" "${RUNNER_NAME:-unknown}" > environment.txt
java -version >> environment.txt 2>&1
"$repo_root/gradle/gradlew" --version >> environment.txt
export BENCH_NONCE=warmup BENCH_SIZE_MIB=1
# Resolve plugins and warm the same daemon before any recorded measurement.
for mode in wan pn; do
  if [ "$mode" = pn ]; then export TUIST_CACHE_ENDPOINT="$pn_endpoint"; else export TUIST_CACHE_ENDPOINT="$BENCH_WAN_ENDPOINT"; fi
  curl --fail --silent --show-error --max-time 15 "${TUIST_CACHE_ENDPOINT}/up"
  "$repo_root/gradle/gradlew" help --daemon --no-configuration-cache --console=plain > "warmup-$mode.log" 2>&1
done
# Stay below Kura's 100 MiB Gradle artifact limit, including archive overhead.
for size in 1 64; do
  export BENCH_SIZE_MIB="$size"
  for round in 1 2 3 4 5; do
    if (( round % 2 )); then modes='wan pn'; else modes='pn wan'; fi
    for mode in $modes; do
      if [ "$mode" = pn ]; then export TUIST_CACHE_ENDPOINT="$pn_endpoint"; else export TUIST_CACHE_ENDPOINT="$BENCH_WAN_ENDPOINT"; fi
      BENCH_NONCE="${GITHUB_RUN_ID:?}-${GITHUB_RUN_ATTEMPT:?}-$mode-$size-$round-$(od -An -N8 -tx1 /dev/urandom | tr -d ' \n')"
      export BENCH_NONCE
      expected=''
      for phase in cold warm; do
        rm -rf build
        log="$mode-$size-$round-$phase.log"
        start="$(date +%s%N)"
        "$repo_root/gradle/gradlew" cacheProbe --build-cache --no-configuration-cache --daemon --info --console=plain > "$log" 2>&1 || { cat "$log"; exit 1; }
        end="$(date +%s%N)"
        if grep -Eq 'Could not (load|store).*cache|Failed to (load|store).*cache' "$log"; then cat "$log"; exit 1; fi
        if [ "$phase" = cold ]; then
          grep -Fq "Stored cache entry for task ':cacheProbe'" "$log"
          if grep -Fq '> Task :cacheProbe FROM-CACHE' "$log"; then
            echo 'Fresh cache key unexpectedly hit during cold measurement' >&2
            exit 1
          fi
          expected="$(sha256sum build/payload.bin | cut -d ' ' -f 1)"
        else
          grep -Fq "Loaded cache entry for task ':cacheProbe'" "$log"
          grep -Fq '> Task :cacheProbe FROM-CACHE' "$log"
        fi
        checksum="$(sha256sum build/payload.bin | cut -d ' ' -f 1)"
        test "$checksum" = "$expected"
        task_ms="$(sed -n 's/^BENCH_TASK_MS=//p' "$log")"
        [[ "$task_ms" =~ ^[0-9]+$ ]]
        printf '%s,%s,%s,%s,%s,%s,%s\n' "$mode" "$size" "$round" "$phase" "$(((end-start)/1000000))" "$task_ms" "$checksum" | tee -a results.csv
      done
    done
  done
done
"$repo_root/gradle/gradlew" --stop > daemon-stop.log 2>&1
