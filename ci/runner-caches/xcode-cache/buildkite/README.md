# Tuist Xcode cache for Buildkite

Keep Xcode's compilation cache across jobs on Tuist macOS runners. Every
`xcodebuild` the step runs stores its compilation cache on storage that Tuist
restores into the next job, so a fresh runner starts warm.

```yaml
steps:
  - label: Build
    agents:
      queue: tuist-macos
    plugins:
      - tuist/xcode-cache#v1: ~
    command: xcodebuild build -scheme App COMPILATION_CACHE_ENABLE_CACHING=YES
```

The plugin only decides where the cache lives. Turning compilation caching on
stays with your project: set `COMPILATION_CACHE_ENABLE_CACHING`, or run
`tuist setup cache` to share it with your team through Tuist's remote cache.

The pre-command hook runs after checkout and points `XCODE_XCCONFIG_FILE` at a
file that sets the cache's location and size limit. If the step's environment
already sets `XCODE_XCCONFIG_FILE`, that file is included last, so its settings
win; a relative path is resolved against the checkout.

Successful webhook and schedule builds of your pipeline's repository save their
changes, including its pull requests. Fork pull requests, tags and builds started
from the API or the dashboard use the cache but never save. To save only from
some branches, limit them on the runner profile; see
[Choose which branches save](https://tuist.dev/en/docs/guides/features/runners/cache-volumes#choose-which-branches-save). The cache
holds up to 30 GB and Tuist prunes it to fit. Directories you keep with the `tuist/cache-volume` plugin are separate.

On agents that are not Tuist macOS runners the hook does nothing. If the runner
could not restore the cache, the hook warns and the build runs with an empty
one; it never fails the step.

This plugin's distribution repository is `tuist/xcode-cache-buildkite-plugin`.
`SOURCE_COMMIT` records its monorepo source.
