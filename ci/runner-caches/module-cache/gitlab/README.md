# Tuist module cache for GitLab CI

Keep Tuist's local cache across jobs on Tuist macOS runners: module cache
binaries, along with compiled manifests, plugins and selective testing results.
Include the template and reference its snippet before your `tuist` commands:

```yaml
include:
  - remote: https://raw.githubusercontent.com/tuist/module-cache-gitlab/v1/module-cache.yml

test:
  tags: [tuist-macos]
  before_script:
    - !reference [.tuist-module-cache, before_script]
  script:
    - tuist generate --no-open
    - tuist test
```

Use `!reference` rather than `extends`: `extends` replaces `before_script`, so
it cannot combine this snippet with the Xcode cache's or your own. You can also
vendor `module-cache.yml` and use `include:local`.

The snippet sets `TUIST_XDG_CACHE_HOME` to the cache and `TUIST_CACHE_MAX_BYTES`
to its share of the storage, so the Tuist CLI evicts the least recently used
binaries before the cache fills up.

Tuist does not yet verify GitLab jobs for its built-in caches, so on GitLab the
cache starts empty and is not saved. Once Tuist verifies GitLab jobs, the same
snippet starts saving with no pipeline change.

On runners that are not Tuist macOS runners the snippet does nothing. If the
runner could not restore the cache, it warns and the job runs with an empty
one; it never fails the job. `SOURCE_COMMIT` records its monorepo source.
