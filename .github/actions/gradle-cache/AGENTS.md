# Gradle cache action

Source package for the standalone `tuist/gradle-cache` action. Its Buildkite and
GitLab entry points are in `ci/runner-caches/gradle-cache/`.

- Unlike the Xcode and module caches, this one is a custom cache volume: it
  calls the installed `tuist-cache-volume` client (Linux and macOS images) with
  key `gradle` and `$GRADLE_USER_HOME/{caches,wrapper}`. No server flag gates it.
- The init script it writes must stay byte-identical across `setup.sh`, the
  Buildkite hook and the GitLab snippet; `ci/runner-caches/integrations_test.sh`
  enforces it. It must never fail a build: look the cleanup API up dynamically
  and catch everything, because Gradle changed that API between versions and
  older versions lack it. Check changes against real Gradle 8 and 9.
- Never fail the job: a missing client is a no-op and a client failure warns.
- Keep the distribution self-contained: `action.yml`, `setup.sh`, README,
  license and source commit. Run `bash .github/actions/gradle-cache/action_test.sh`.
