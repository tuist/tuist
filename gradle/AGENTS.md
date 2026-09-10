# Tuist Gradle plugin

Settings plugin written in Kotlin. `TuistBuildInsights` uploads build reports; `BuildExecutionTelemetry` collects execution and cache operations.

- Register the build insights service only through the configuration-cache-aware `onOperationCompletion` registry. A single service provider cannot hold both task and operation subscriptions. Keep it an operation-only listener so configuration reuse restores the correct subscription.
- Completion events are ordered. Propagate nested cache metadata to parents until the owning task finishes; do not depend on start events from this registry.
- Internal Gradle APIs can change. Catch unavailable operations without failing the build, and mark incomplete telemetry honestly. Integration tests must exercise real builds and configuration-cache reuse.
- Exclude machine counter reads from configuration input tracking and restore tracking in a finally block. Linux `/proc` counters are telemetry, not configuration inputs, and change between builds.
- Cacheability is task capability, not global build-cache availability. Fall back to `@CacheableTask` for disabled-cache or skipped lookups, while honoring observed task-specific disabled reasons.
- Run tests with `./gradlew test --no-build-cache --no-watch-fs`. When validating source changed outside Gradle's file watcher, force compilation with `--rerun-tasks`.

Related: `server/lib/tuist/gradle/AGENTS.md`.

- Initialize local end-to-end demo projects as Git repositories and commit their fixture sources before recording builds, so branch and commit metadata is present in dashboard examples.

- Build reports include `started_at` using the same origin as `duration_ms`, including configuration-cache reuse, so the server can align operations with machine samples.

- Machine monitoring takes initial and final samples, including builds shorter than the periodic interval. Network and disk counters are normalized by actual elapsed sampling time. Never backdate samples to cover operations before monitoring began.

- `TuistMachineMetricsService` is eagerly started when the settings plugin is applied and passed as a managed service provider to build insights. Keep collector state out of configuration-cache parameters; every restored build needs fresh samples. Preserve the report service’s operation-only subscription.

- Timestamp machine samples and report fallbacks with Gradle’s operation clock (`Time.currentTimeMillis`), not the system wall clock; long-lived daemons can have different offsets between those clocks.

- Report time bounds cover the recorded operations and machine measurements, rather than unrelated internal callbacks. Keep earlier recorded operations intact, and include the final measurement in the reported duration. The reporter owns the early collector until its completion queue drains; the sampler’s independent Gradle close hook must not stop it prematurely.

- After a periodic reading, omit a stop-time sample less than 200 ms later to avoid unstable rates from a tiny final interval. Preserve start/stop readings when no periodic sample was collected, including short builds.
