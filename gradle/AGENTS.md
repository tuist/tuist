# Tuist Gradle plugin

Settings plugin written in Kotlin. `TuistBuildInsights` uploads build reports; `BuildExecutionTelemetry` collects execution and cache operations.

- Register the build insights service only through the configuration-cache-aware `onOperationCompletion` registry. A single service provider cannot hold both task and operation subscriptions. Keep it an operation-only listener so configuration reuse restores the correct subscription.
- Completion events are ordered. Propagate nested cache metadata to parents until the owning task finishes; do not depend on start events from this registry.
- Internal Gradle APIs can change. Catch unavailable operations without failing the build, and mark incomplete telemetry honestly. Integration tests must exercise real builds and configuration-cache reuse.
- Exclude machine counter reads from configuration input tracking and restore tracking in a finally block. Linux `/proc` counters are telemetry, not configuration inputs, and change between builds.
- Cacheability is task capability, not global build-cache availability. Fall back to `@CacheableTask` for disabled-cache or skipped lookups, while honoring observed task-specific disabled reasons.
- Run tests with `./gradlew test --no-build-cache --no-watch-fs`. When validating source changed outside Gradle's file watcher, force compilation with `--rerun-tasks`.
- Chunked uploads require the server's exact supported capability; old or mixed-version servers keep whole uploads. Independent gzip members must remain readable by the built-in Gradle cache reader. `ChunkedGradleBuildTest` covers real builds, configuration reuse, and legacy reader compatibility against a local Kura.
- Chunked downloads additionally require `download_version: 1`. Keep local transfer storage bounded across projects, verify each chunk and the complete staged artifact before invoking Gradle's reader, preserve token refresh and whole-read fallback, and close the bounded download worker pool with the cache service. Uploads seed the same local chunks; tests must isolate writer and reader caches when measuring network savings.

Related: `server/lib/tuist/gradle/AGENTS.md`.

- Initialize local end-to-end demo projects as Git repositories and commit their fixture sources before recording builds, so branch and commit metadata is present in dashboard examples.
