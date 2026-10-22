# Runner cache entry points for Buildkite and GitLab

Buildkite plugins and GitLab snippets for the managed caches, one directory per
cache (`xcode-cache/`, `module-cache/`, `gradle-cache/`), each with `buildkite/`
and `gitlab/`. The GitHub actions live in `../../.github/actions/<cache>/`.

- Xcode and module entry points are thin wrappers over the runner image's
  `tuist-runner-cache` (`infra/runner-image/`): run `activate <cache>` and export
  the `NAME=VALUE` lines it prints. Activation, trust and saving stay in the
  image and the server. Those two differ only by name; the test enforces it.
- Gradle entry points call `tuist-cache-volume` with key `tuist-gradle` for
  `$GRADLE_USER_HOME/{caches,wrapper}` and install the same cleanup init script
  as `.github/actions/gradle-cache/setup.sh`; the test compares them byte for byte.
  An optional size (`BUILDKITE_PLUGIN_GRADLE_CACHE_SIZE` from the plugin's
  `size`, GitLab `TUIST_GRADLE_CACHE_SIZE`) is passed as `--size` only when
  `tuist-cache-volume -h` lists `-size`; otherwise they warn and attach without it.
- Both providers keep exports only if the entry point runs in the build's shell:
  Buildkite sources the plugin hook, GitLab runs `before_script` and `script`
  in one shell. So never `exit`, never enable errexit, and never fail the job
  on a cache problem. GitLab snippets must stay POSIX `sh`.
- Run `bash ci/runner-caches/integrations_test.sh`.
- Releases: `distributions` lists the nine distribution repositories and the
  package script for each. Relevant pushes to `main` release all nine together
  through the `runner-caches` component (`ci/runner-caches/cliff.toml`,
  `mise/tasks/release/components.json`) and `.github/workflows/runner-cache-actions.yml`:
  `prepare-release.sh` packages them, recovering an incomplete release from its
  original `SOURCE_COMMIT` first, and `ci/cache-volume/publish.sh` pushes each
  with an immutable `vX.Y.Z` tag and a moving major tag. Each repository needs a
  `main` branch and write access for `TUIST_RELEASE_GITHUB_TOKEN`. Run
  `prepare-release_test.sh` and `release_check_test.sh` here when changing this.
