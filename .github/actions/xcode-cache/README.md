# Tuist Xcode Cache

Keep Xcode's compilation cache across jobs on Tuist macOS runners. Every
`xcodebuild` that runs after this step stores its compilation cache on storage
that Tuist restores into the next job, so a fresh runner starts warm.

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: tuist/xcode-cache@v1
  - run: xcodebuild build -scheme App COMPILATION_CACHE_ENABLE_CACHING=YES
```

The action only decides where the cache lives. Turning compilation caching on
stays with your project: set `COMPILATION_CACHE_ENABLE_CACHING`, or run
`tuist setup cache` to share it with your team through Tuist's remote cache.

The action points `XCODE_XCCONFIG_FILE` at a file that sets the cache's location
and size limit. If your workflow sets `XCODE_XCCONFIG_FILE` before this step,
that file is included last, so its settings win. Setting it after this step
replaces the runner's file and the cache runs on the runner's own disk.

## Saving

Successful jobs from your repository save their changes. Jobs from forks start
empty and never save. The Xcode cache shares its storage and size budget with
the [module cache](https://github.com/tuist/module-cache), and Tuist prunes it
to fit, so there is nothing to size or clear. Directories you keep with
[`tuist/cache-volume`](https://github.com/tuist/cache-volume) are separate.

## Other runners

On runners that are not Tuist macOS runners, the action does nothing. If the
runner could not restore the cache, the action warns and the job builds with an
empty one.

The `SOURCE_COMMIT` file records the monorepo source.
