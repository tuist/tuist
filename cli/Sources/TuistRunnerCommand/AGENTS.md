# Runner commands

`tuist runner` owns interactive shells and account-scoped volume management.

- Volume commands use the generated TuistServer client and authenticated transport.
  Change the server schemas and regenerate OpenAPI; never edit generated files.
- Keep list, show, jobs, for-job, analytics and clear aligned with the public API
  and MCP contract in `server/lib/tuist/runners/cache_volumes/query.ex`.
- `--account` overrides the project full-handle account; `--path` selects config.
  Preserve the configured server URL and normal CLI authentication.
- Bound pagination and analytics periods before requesting the server. Clearing
  requires explicit `--yes`, and the server independently enforces account update
  permission and account ownership. Do not implement host block operations here.
- Preserve unknown metrics rather than converting them to zero. The generated
  Swift encoder omits nil fields in JSON output; pagination remains included.
- Test through the generated Xcode workspace and Swift Testing, not SwiftPM.
