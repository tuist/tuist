# Module cache action

Source package for the standalone `tuist/module-cache` action. `xcode-cache/` is
its sibling and shares `activate.sh`, `action_test.sh` and `scripts/package.sh`
byte for byte; change both together.

- Keep the action a thin wrapper. The runner image's `tuist-runner-cache`
  (`infra/runner-image/`) owns activation, the xcconfig chaining and the env
  contract; the action only appends what it prints to `$GITHUB_ENV`.
- Never fail the job: a missing helper is a no-op, exit 3 and any other failure
  warn.
- Keep the distribution self-contained: `action.yml`, `activate.sh`, README,
  license and source commit.
- Run `bash .github/actions/module-cache/action_test.sh` and
  `bash infra/runner-image/runner-caches_test.sh`.
- Accounts get these caches through the actions only while the server's
  `:runner_opt_in_caches` flag is on for them; otherwise they stay automatic and
  the action is a no-op. See the "Opt-in caches" section of
  `infra/runner-image/AGENTS.md`.
