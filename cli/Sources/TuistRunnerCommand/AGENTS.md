# Runner commands

`tuist runner` owns interactive shells and account-scoped volume management.

- Define each command in its own file and delegate to its corresponding command
  service. Inject API service protocols from TuistServer; keep authenticated client
  construction, OpenAPI requests and HTTP response mapping in TuistServer services.
  Change server schemas and regenerate OpenAPI; never edit generated files.
- Resolve account and server configuration through the injectable volume context
  service. Pass plain argument values into services, not ParsableArguments wrappers.
- Keep list, show, jobs, analytics and clear aligned with the public API
  and MCP contract in `server/lib/tuist/runners/cache_volumes/query.ex`.
- `--account` overrides the project full-handle account; `--path` selects config.
  Preserve the configured server URL and normal CLI authentication.
- Inventory uses explicit exact-match `--name` and `--repository` filters, combined
  with AND. Keep their counts and pagination consistent across API and MCP.
- Bound pagination and analytics periods before requesting the server. Clearing
  requires explicit `--yes`, and the server independently enforces account update
  permission and account ownership. Do not implement host block operations here.
- Preserve unknown metrics rather than converting them to zero. The generated
  Swift encoder omits nil fields in JSON output; pagination remains included.
- Test through the generated Xcode workspace and Swift Testing, not SwiftPM.

- Human output uses Noora paginated tables for inventory/jobs and labeled summaries
  for details/analytics, with shared byte/date formatters and explicit unknowns.
  Preserve structured response envelopes for `--json`. There is no CLI `for-job`
  command; mounted-volume lookup remains available through API and MCP.
