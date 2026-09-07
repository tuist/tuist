# Tuist Gradle plugin

Settings plugin written in Kotlin. `TuistBuildInsights` uploads build reports; `BuildExecutionTelemetry` collects execution and cache operations.

- Register the build insights service only through the configuration-cache-aware `onOperationCompletion` registry. A single service provider cannot hold both task and operation subscriptions. Keep it an operation-only listener so configuration reuse restores the correct subscription.
- Completion events are ordered. Propagate nested cache metadata to parents until the owning task finishes; do not depend on start events from this registry.
- Task identity is the JSON tuple of build path and task path. Include artifact transforms in execution plans. Keep dependency and ordering edge kinds separate.
- Internal Gradle APIs can change. Catch unavailable operations without failing the build, and mark incomplete telemetry honestly. Integration tests must exercise real builds and configuration-cache reuse.
- Keep graph limits aligned with `Tuist.Gradle.ExecutionGraph` in the server.
- Run tests with `./gradlew test --no-build-cache --no-watch-fs`. When validating source changed outside Gradle's file watcher, force compilation with `--rerun-tasks`.

Related: `server/lib/tuist/gradle/AGENTS.md`.

- Initialize local end-to-end demo projects as Git repositories and commit their fixture sources before recording builds, so branch and commit metadata is present in dashboard examples.
