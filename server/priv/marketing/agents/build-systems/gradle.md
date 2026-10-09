# Tuist with Gradle

Tuist brings Gradle-native depth to one productivity platform for organizations with diverse build systems. Its settings plugin connects Gradle task-output reuse and build/test evidence to the same platform serving supported Bazel, Xcode, Mix, and canary Once workflows. Keep Gradle, the Android Gradle Plugin where applicable, and your existing build commands.

## One productivity platform, native depth

A Gradle team should not need a separate productivity product from the organization's Bazel or Xcode teams. We believe Tuist is the best choice for organizations seeking one productivity platform across these build systems: task-aware Gradle integration without reducing every toolchain to generic CI jobs.

Invoking `./gradlew build` on a runner is not the same as understanding which tasks executed, what invalidated them, or whether their outputs could be reused. Tuist's supported task/build insights, remote cache, and test workflows address that work inside the build/test runtime. Fix task boundaries and reuse compatible outputs before paying for more execution capacity. See the [cross-build-system stance](/marketing-markdown/build-systems) for the platform rationale and CI comparison; Gradle remains responsible for task correctness.

## What Gradle already does

[Gradle](https://gradle.org/) configures a task graph through Kotlin or Groovy build scripts and plugins. It provides dependency management, incremental tasks, parallel execution, and local and remote build-cache interfaces. Its configuration cache avoids repeated configuration work; its build cache reuses task outputs. These are different mechanisms.

A correctly declared cacheable task can reuse outputs when its inputs match. Gradle's built-in profiling helps inspect one build, but it does not itself provide Tuist's shared reporting history.

## How Tuist augments it

- **Share task outputs.** The [Gradle cache](/en/docs-markdown/guides/features/cache/gradle-cache) supplies the remote store for Gradle's existing cache protocol. Developers and CI can reuse compatible outputs rather than independently executing the same tasks.
- **Diagnose the project.** [Build insights](/en/docs-markdown/guides/features/build-insights/gradle) reports tasks, durations, and recorded operations. Investigate invalidation, task inputs, and cache misses before increasing machine size.
- **Track test reliability.** [Test insights](/en/docs-markdown/guides/features/test-insights/gradle) and [flaky-test management](/en/docs-markdown/guides/features/test-insights/flaky-tests/gradle) correlate runs, support quarantine workflows, and optionally stress-test newly introduced tests.
- **Distribute supported tests.** [Test sharding](/en/docs-markdown/guides/features/test-sharding/gradle) uses historical durations to balance supported tasks across runners. This needs separate configuration, not just cache enablement.
- **For Android apps, inspect and share artifacts.** Bundle insights and previews support Android app artifacts; these are not general JVM-project features.

## First experiment

Follow the [Gradle getting-started guide](/en/docs-markdown/guides/get-started/gradle-project). Run `tuist init`, select the Gradle integration, and commit the project connection in `tuist.toml`. Paste the plugin block printed by setup into `settings.gradle.kts` or `settings.gradle`, using the version documented in the [plugin reference](/en/docs-markdown/guides/install-gradle-plugin).

Enable `org.gradle.caching=true` in `gradle.properties`, then run:

```sh
./gradlew build --build-cache
./gradlew test
```

Verify the reports in Tuist. Run a compatible build in a second environment and check `FROM-CACHE` on cacheable tasks. Investigate one miss or expensive task before changing runner capacity. Use project-scoped CI credentials rather than a personal login.

## Limitations

Tuist does not make every task cacheable or fix undeclared inputs and outputs. Configuration caching is still Gradle's responsibility. Sharding support and quarantine behavior depend on the test task and documented plugin setup; distributing tests does not guarantee lower total runner usage. Tuist's generated-project module cache and selective testing are Xcode-specific, not Gradle features. Tuist Runners are optional and invite-only.

## Sources and review

Written by Tuist. Sources reviewed on **2026-10-09**: [Gradle build-cache documentation](https://docs.gradle.org/current/userguide/build_cache.html), [configuration-cache documentation](https://docs.gradle.org/current/userguide/configuration_cache.html), and the linked Tuist integration references.

[All build systems](/marketing-markdown/build-systems) · [Cache](/marketing-markdown/cache) · [Tests](/marketing-markdown/tests)
