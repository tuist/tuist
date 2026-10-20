# Tuist Gradle Cache

Keep Gradle's dependency and wrapper caches across jobs on Tuist Linux and
macOS runners. The action attaches a
[cache volume](https://github.com/tuist/cache-volume) at
`$GRADLE_USER_HOME/caches` and `$GRADLE_USER_HOME/wrapper` (`~/.gradle` when
`GRADLE_USER_HOME` is unset), so downloaded dependencies, transformed jars,
compiled build scripts and Gradle distributions don't have to be fetched or
built again.

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: actions/setup-java@v4
    with:
      distribution: temurin
      java-version: '21'
  - uses: tuist/gradle-cache@v1
  - run: ./gradlew test
```

Set `GRADLE_USER_HOME` before this step if you use one. Turn off other caches
of the same directories, such as `cache: gradle` on `actions/setup-java` or the
caching of `gradle/actions/setup-gradle`: the directories must be empty when
the action runs.

Gradle cleans its cache only when its daemon stops, which a CI job rarely
reaches. The action installs an init script in `$GRADLE_USER_HOME/init.d` that
cleans after every build and removes entries unused for seven days, so the
cache stays within its volume. Gradle versions without this API keep their own
cleanup settings.

The action keeps local caches only. Use the
[Tuist Gradle plugin](https://tuist.dev/en/docs/guides/features/cache/gradle-cache)
to share build outputs through Tuist's remote cache.

Saving follows the cache volume rules: by default every successful job from
the repository saves, fork pull requests never do, and the runner profile's
**Save cache from** setting can limit it to specific branches. The `cache-hit`
output is `true` when the job attached a saved cache. On runners that are not Tuist runners the action does nothing, and if
the volume is unavailable it warns and the job runs with an empty cache.

The `SOURCE_COMMIT` file records the monorepo source.
