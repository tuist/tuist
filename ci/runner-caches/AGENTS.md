# Runner cache entry points for Buildkite and GitLab

Buildkite plugins and GitLab snippets for the managed caches, one directory per
cache (`xcode-cache/`, `module-cache/`, `gradle-cache/`), each with `buildkite/`
and `gitlab/`. The GitHub actions live in `../../.github/actions/<cache>/`.

- Xcode and module entry points are thin wrappers over the runner image's
  `tuist-runner-cache` (`infra/runner-image/`): run `activate <cache>` and export
  the `NAME=VALUE` lines it prints. Activation, trust and saving stay in the
  image and the server. Those two differ only by name; the test enforces it.
- Gradle entry points call `tuist-cache-volume` with key `gradle` for
  `$GRADLE_USER_HOME/{caches,wrapper}` and install the same cleanup init script
  as `.github/actions/gradle-cache/setup.sh`; the test compares them byte for byte.
- Both providers keep exports only if the entry point runs in the build's shell:
  Buildkite sources the plugin hook, GitLab runs `before_script` and `script`
  in one shell. So never `exit`, never enable errexit, and never fail the job
  on a cache problem. GitLab snippets must stay POSIX `sh`.
- Run `bash ci/runner-caches/integrations_test.sh`.
- Distribution repositories (`tuist/<cache>-buildkite-plugin`,
  `tuist/<cache>-gitlab`) and release wiring do not exist yet.
