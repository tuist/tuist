# Tuist Xcode cache for GitLab CI

Keep Xcode's compilation cache across jobs on Tuist macOS runners. Include the
template and reference its snippet before your build commands:

```yaml
include:
  - remote: https://raw.githubusercontent.com/tuist/xcode-cache-gitlab/v1/xcode-cache.yml

build:
  tags: [tuist-macos]
  before_script:
    - !reference [.tuist-xcode-cache, before_script]
  script:
    - xcodebuild build -scheme App COMPILATION_CACHE_ENABLE_CACHING=YES
```

Use `!reference` rather than `extends`: `extends` replaces `before_script`, so
it cannot combine this snippet with the module cache's or your own. You can also
vendor `xcode-cache.yml` and use `include:local`.

The snippet only decides where the cache lives. Turning compilation caching on
stays with your project: set `COMPILATION_CACHE_ENABLE_CACHING`, or run
`tuist setup cache` to share it through Tuist's remote cache. It points
`XCODE_XCCONFIG_FILE` at a file with the cache's location and size limit; a
`XCODE_XCCONFIG_FILE` the job already sets is included last, so its settings
win.

Tuist does not yet verify GitLab jobs for its built-in caches, so on GitLab the
cache starts empty and is not saved. Once Tuist verifies GitLab jobs, the same
snippet starts saving with no pipeline change.

On runners that are not Tuist macOS runners the snippet does nothing. If the
runner could not restore the cache, it warns and the job runs with an empty
one; it never fails the job. `SOURCE_COMMIT` records its monorepo source.
