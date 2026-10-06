# Tuist Gradle plugin

Settings plugin written in Kotlin. `TuistBuildInsights` uploads build reports; `BuildExecutionTelemetry` collects execution and cache operations.

- Register the build insights service only through the configuration-cache-aware `onOperationCompletion` registry. A single service provider cannot hold both task and operation subscriptions. Keep it an operation-only listener so configuration reuse restores the correct subscription.
- Completion events are ordered. Propagate nested cache metadata to parents until the owning task finishes; do not depend on start events from this registry.
- Internal Gradle APIs can change. Catch unavailable operations without failing the build, and mark incomplete telemetry honestly. Integration tests must exercise real builds and configuration-cache reuse.
- Exclude machine counter reads from configuration input tracking and restore tracking in a finally block. Linux `/proc` counters are telemetry, not configuration inputs, and change between builds.
- Cacheability is task capability, not global build-cache availability. Fall back to `@CacheableTask` for disabled-cache or skipped lookups, while honoring observed task-specific disabled reasons.
- The build cache declares `tuist-checksum-sha256` (lowercase hex SHA-256 of the exact body) on every store. It hashes Gradle's entry writer in a separate pass before sending, because `HttpURLConnection` already buffers the body; the writer copies from a packed file and is repeatable. A 422 refusal retries the store once with a fresh checksum. On load, a well-formed `tuist-checksum-sha256` response header is verified when the body reaches end of stream; a mismatch, including a truncated body, is logged and returned as a miss. Gradle only unpacks an entry whose `readFrom` completed, so the partial download is discarded and the task runs. Responses without the header are not verified.
- Run tests with `./gradlew test --no-build-cache --no-watch-fs`. When validating source changed outside Gradle's file watcher, force compilation with `--rerun-tasks`.

Related: `server/lib/tuist/gradle/AGENTS.md`.

- Initialize local end-to-end demo projects as Git repositories and commit their fixture sources before recording builds, so branch and commit metadata is present in dashboard examples.

- Build reports include `started_at` using the same origin as `duration_ms`, including configuration-cache reuse, so the server can align operations with machine samples.

- Machine monitoring takes initial and final samples, including builds shorter than the periodic interval. Network and disk counters are normalized by actual elapsed sampling time. Never backdate samples to cover operations before monitoring began.

- `TuistMachineMetricsService` is eagerly started when the settings plugin is applied and passed as a managed service provider to build insights. Keep collector state out of configuration-cache parameters; every restored build needs fresh samples. Preserve the report service’s operation-only subscription.

- Timestamp machine samples and report fallbacks with Gradle’s operation clock (`Time.currentTimeMillis`), not the system wall clock; long-lived daemons can have different offsets between those clocks.

- Report time bounds cover the recorded operations and machine measurements, rather than unrelated internal callbacks. Keep earlier recorded operations intact, and include the final measurement in the reported duration. The reporter owns the early collector until its completion queue drains; the sampler’s independent Gradle close hook must not stop it prematurely.

- A stop-time reading less than 200 ms after a periodic reading replaces that periodic reading, with rates measured from the reading before it, to avoid unstable rates from a tiny final interval. Do not omit the stop-time reading instead: the last task can finish after the periodic reading, and monitoring must cover the reported build end. Preserve start/stop readings when no periodic sample was collected, including short builds. Downsampling keeps the first and last samples.

- `tuistPrepareTestShards` sends the module names of the projects that have the sharded test tasks, with suite granularity, and the server resolves each module's suites from test insights history. It does not depend on compiled test classes, so planning never compiles. The module list is a provider over each project's test task names, resolved when the task graph is built, after every project is configured. The prepare task calls `evaluationDependsOn` for every subproject when it is configured, because configuration on demand leaves subprojects unconfigured when `:tuistPrepareTestShards` is requested by path. Keep that in the task configuration, not in `apply`, so other builds keep configuration on demand.

- Modules are named as test insights reports them (`testModuleName`), so the server matches them against historical suites. A shard configures each test task's filter from its project's assigned suites and skips test tasks with none. Shards request the plan's final shard as a catch-all (`catch_all=true`): it has no modules, runs every test task, and excludes the suites listed in `skip`, so suites without history still run. A plan without history has a single catch-all shard. Test insights records a nested class (`Outer$Inner`) as its own suite, and the server folds it into its top-level class when planning, because a filter on a class also includes or excludes its nested classes. Set the filter during configuration, never in `doFirst`: the filter is then part of the test task's cache key, and shards cannot load each other's results from the remote cache.

- `tuistPrepareTestShards` supports the configuration cache: its action never reads `project`. The root directory, the shard matrix output directory, and the `tuistBuildInsights` service (declared with `usesService`) are task properties set when the task is configured.
