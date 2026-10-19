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

Successful builds Tuist can verify as coming from your own repository save their
changes. Builds from forks start empty and never save. The module cache shares
its storage and size budget with the Xcode cache plugin. Directories you keep
with the `tuist/cache-volume` plugin are separate.

On agents that are not Tuist macOS runners the hook does nothing. If the runner
could not restore the cache, the hook warns and the build runs with an empty
one; it never fails the step.

This plugin's distribution repository is `tuist/module-cache-buildkite-plugin`.
`SOURCE_COMMIT` records its monorepo source.
