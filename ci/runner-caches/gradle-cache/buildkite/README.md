# Tuist Gradle cache for Buildkite

Keep Gradle's dependency and wrapper caches across jobs on Tuist Linux and
macOS runners. The pre-command hook attaches a cache volume at
`$GRADLE_USER_HOME/caches` and `$GRADLE_USER_HOME/wrapper` (`~/.gradle` when
`GRADLE_USER_HOME` is unset).

```yaml
steps:
  - label: Test
    agents:
      queue: tuist-linux
    plugins:
      - tuist/gradle-cache#v1: ~
    command: ./gradlew test
```

The cache volume starts at `20gb`. Set `size` to give it another capacity, a
whole number of GB from `1gb` to `100gb`:

```yaml
    plugins:
      - tuist/gradle-cache#v1:
          size: 50gb
```

A larger size grows the cache, keeping its contents, from its next job. A
smaller one applies after the volume is next cleared or expires. Sizes above
`20gb` may not be enabled for every account yet. Runner images without size
support keep the current size and warn.

Set `GRADLE_USER_HOME` in the step's `env` if you use one. The directories must
be empty when the hook runs, so remove other caches of them.

Gradle cleans its cache only when its daemon stops, which a CI job rarely
reaches. The hook installs an init script in `$GRADLE_USER_HOME/init.d` that
cleans after every build and removes entries unused for seven days. The plugin
keeps local caches only; the Tuist Gradle plugin shares build outputs through
Tuist's remote cache.

Successful default-branch webhook and scheduled builds save the cache. On
agents that are not Tuist runners the hook does nothing, and if the volume is
unavailable the build runs with an empty cache; it never fails the step.

This plugin's distribution repository is `tuist/gradle-cache-buildkite-plugin`.
`SOURCE_COMMIT` records its monorepo source.
