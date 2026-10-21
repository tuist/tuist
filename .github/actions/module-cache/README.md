# Tuist Module Cache

Keep Tuist's local cache across jobs on Tuist macOS runners. Every `tuist`
command that runs after this step reads and writes its cache on storage that
Tuist restores into the next job: module cache binaries, along with compiled
manifests, plugins and selective testing results. Binaries the job finds
locally do not have to be downloaded again.

```yaml
steps:
  - uses: actions/checkout@v4
  - uses: jdx/mise-action@v2
  - uses: tuist/module-cache@v1
  - run: tuist generate --no-open
  - run: tuist test
```

The action sets `TUIST_XDG_CACHE_HOME` to the restored cache and
`TUIST_CACHE_MAX_BYTES` to its share of the storage, so the Tuist CLI evicts the
least recently used binaries before the cache fills up. Authenticate and
configure the module cache as usual; the action only decides where its local
copy lives.

## Saving

Successful jobs from your repository save their changes. Fork pull requests use
the cache but never save. To save only from some branches, limit them on the
runner profile; see
[Choose which branches save](https://tuist.dev/en/docs/guides/features/runners/cache-volumes#choose-which-branches-save).
The cache holds up to 20 GB and the Tuist CLI keeps it within that size, so there
is nothing to size or clear. Directories you keep with
[`tuist/cache-volume`](https://github.com/tuist/cache-volume) are separate.

## Other runners

On runners that are not Tuist macOS runners, the action does nothing. If the
runner could not restore the cache, the action warns and the job runs with an
empty one.

The `SOURCE_COMMIT` file records the monorepo source.
