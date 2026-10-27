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

Successful jobs from your repository save their changes. Fork pull requests use
the cache but never save. To save only from some branches, limit them on the
runner profile; see
[Choose which branches save](https://tuist.dev/en/docs/guides/features/runners/cache-volumes#choose-which-branches-save).
Directories you keep with
[`tuist/cache-volume`](https://github.com/tuist/cache-volume) are separate.

## Size

The cache starts at `30gb`. Set `size` to give it another capacity, a whole
number of GB from `1gb` to `100gb`:

```yaml
  - uses: tuist/xcode-cache@v1
    with:
      size: 50gb
```

Tuist prunes the cache to fit whatever its capacity is, so there is nothing to
clear. A larger size grows the cache, keeping its contents, from its next job.
A smaller one applies after the cache is next cleared or expires. Runner images
without size support keep the current size and warn.

## Other runners

On runners that are not Tuist macOS runners, the action does nothing. If the
runner could not restore the cache, the action warns and the job builds with an
empty one.

The `SOURCE_COMMIT` file records the monorepo source.
