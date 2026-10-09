# Standalone server verification

- These scripts run in dedicated Erlang processes outside ExUnit. They may configure their own application environment before booting; do not move that configuration into ordinary tests or disable the shared-state mutation guard for `test/`.
- Keep this directory included in `.credo.exs` and `.formatter.exs` so standalone scripts retain code-analysis and formatting coverage.
- `cluster_scale_out.exs` verifies distributed components without starting databases. [`cluster_e2e/`](cluster_e2e/AGENTS.md) boots complete servers against dedicated real services; follow its setup instructions and cleanup requirements.
- `bcrypt_load.exs` is a database-free production-cost guard: 2,000 concurrent proof lookups must perform exactly one bcrypt verification at 12 rounds. It runs in CI in its own VM, because ordinary ExUnit uses reduced bcrypt rounds. Never count this as a full API load test.
- Changes must preserve real request paths and document local-networking and production-profile limits. Do not replace the full-server checks with mocks.
