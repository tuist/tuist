# Runner cache entry points for Buildkite and GitLab

Buildkite plugins and GitLab snippets for the built-in caches, one per cache:
`xcode-cache/` and `module-cache/`, each with `buildkite/` and `gitlab/`. The
GitHub actions live in `../../.github/actions/{xcode,module}-cache/`.

- Keep every entry point a thin wrapper over the runner image's
  `tuist-runner-cache` (`infra/runner-image/`): run `activate <cache>` and export
  the `NAME=VALUE` lines it prints. Activation, trust and saving stay in the
  image and the server.
- Both providers keep exports only if the entry point runs in the build's shell:
  Buildkite sources the plugin hook, GitLab runs `before_script` and `script`
  in one shell. So never `exit`, never enable errexit, and never fail the job
  on a cache problem. GitLab's snippet must stay POSIX `sh`.
- The two caches differ only by name; `integrations_test.sh` enforces it.
  Change both together and run `bash ci/runner-caches/integrations_test.sh`.
- Distribution repositories (`tuist/{xcode,module}-cache-buildkite-plugin`,
  `tuist/{xcode,module}-cache-gitlab`) and release wiring do not exist yet.
