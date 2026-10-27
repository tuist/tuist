# Tuist module cache for Buildkite

Keep Tuist's local cache across jobs on Tuist macOS runners. Every `tuist`
command the step runs reads and writes its cache on storage that Tuist restores
into the next job: module cache binaries, along with compiled manifests, plugins
and selective testing results. Binaries the job finds locally do not have to be
downloaded again.

```yaml
steps:
  - label: Test
    agents:
      queue: tuist-macos
    plugins:
      - tuist/module-cache#v1: ~
    command: |
      tuist generate --no-open
      tuist test
```

The pre-command hook sets `TUIST_XDG_CACHE_HOME` to the restored cache and
`TUIST_CACHE_MAX_BYTES` to its share of the storage, so the Tuist CLI evicts the
least recently used binaries before the cache fills up. Authenticate and
configure the module cache as usual; the plugin only decides where its local
copy lives.

Successful webhook and schedule builds of your pipeline's repository save their
changes, including its pull requests. Fork pull requests, tags and builds started
from the API or the dashboard use the cache but never save. To save only from
some branches, limit them on the runner profile; see
[Choose which branches save](https://tuist.dev/en/docs/guides/features/runners/cache-volumes#choose-which-branches-save).
Directories you keep with the `tuist/cache-volume` plugin are separate.

The cache starts at `20gb`. Set `size` to give it another capacity, a whole
number of GB from `1gb` to `100gb`:

```yaml
    plugins:
      - tuist/module-cache#v1:
          size: 50gb
```

The Tuist CLI keeps the cache within whatever its capacity is. A larger size
grows the cache, keeping its contents, from its next build. A smaller one
applies after the cache is next cleared or expires. Runner images without size
support keep the current size and warn.

On agents that are not Tuist macOS runners the hook does nothing. If the runner
could not restore the cache, the hook warns and the build runs with an empty
one; it never fails the step.

This plugin's distribution repository is `tuist/module-cache-buildkite-plugin`.
`SOURCE_COMMIT` records its monorepo source.
