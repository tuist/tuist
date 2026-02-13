# Tuist Server (Elixir/Phoenix)

This node covers the Tuist Server application under `server/`. Follow downlinks for subsystem boundaries.

## Project Architecture
Tuist Server is an Elixir/Phoenix web application that extends the Tuist CLI. It provides binary caching, app preview deployment, build analytics, and Swift package registry services.

**Key Technologies**
- Backend: Elixir 1.18.3 with Phoenix 1.7.12
- Databases: PostgreSQL (primary), ClickHouse (analytics; write via IngestRepo, read via ClickHouseRepo)
- Frontend: Phoenix LiveView with JavaScript/TypeScript and esbuild
- Package management: pnpm for JavaScript dependencies

**Core Components**
- `lib/tuist/` - Business logic modules (accounts, billing, bundles, projects, registry, etc.)
- `lib/tuist_web/` - Web interface (controllers, LiveView, marketing site)
- `priv/repo/migrations/` - PostgreSQL migrations
- `priv/ingest_repo/migrations/` - ClickHouse migrations (analytics)
- `assets/` - Frontend assets (JS/CSS)
- `config/` - Application configuration

## Main Business Domains
- Accounts (auth, orgs, billing)
- Projects (tokens, permissions)
- Bundles (binary cache)
- Previews (iOS app preview deployment)
- Registry (Swift package registry)
- Command Events (CLI analytics)

## Development Setup
**Prerequisites**
- PostgreSQL 16
- Mise development environment manager
- Private key from 1Password for `priv/secrets/dev.key`

**Setup Commands**
```bash
mise install
brew install postgresql@16
brew services start postgresql@16
mise run clickhouse:start
mise run db:create
mise run db:load
mise run db:seed
mise run dev
```

**Test User Account**
- Email: `tuistrocks@tuist.dev`
- Password: `tuistrocks`

## Common Commands
**Database**
- `mise run db:setup`
- `mise run db:reset`
- `mix ecto.migrate`
- `mix ecto.rollback`

**Server**
- `mise run dev`
- `mix phx.server`
- `iex -S mix phx.server`

**Testing**
- `mix test`
- `mix test test/path/to/specific_test.exs`
- `mix test test/path/to/test_file.exs:line_number_of_test`
- `mix test --only tag_name`

**Code Quality**
- `mix credo`
- `mise run format`
- `mix sobelow`
- `mise run security`

**Assets**
- `mix assets.setup`
- `mix assets.build`
- `mix assets.deploy`

**Database Utilities**
- `mix ecto.dump`
- `mix ecto.load`
- `mix excellent_migrations.check_safety`

## Key Configuration Files
- `.mise.toml` - Tool versions
- `mix.exs` - Elixir project configuration
- `package.json` - JS dependencies (pnpm)
- `config/` - Phoenix configuration
- `priv/secrets/dev.key` - Development secrets (not in repo)

## Testing Guidelines
- Tests use ExUnit; files follow `test/**/module_name_test.exs`.
- Tests run with a clean database.
- Never modify System environment variables in tests (shared state).
- Use mocks/stubs/DI for environment-dependent behavior.

## Code Style Guidelines
- Use `alias` for modules used multiple times; avoid `import` unless using DSLs (e.g., Ecto.Query).
- Declare aliases at the module level, not inside functions.
- Copy modules for mocking in `server/test/test_helper.exs`, not inside functions.
- Prefer `{:ok, value}` / `{:error, reason}` for recoverable failures.
- Credo rules:
  - Timestamps in migrations: `:timestamptz`
  - Timestamps in `lib/`: `:utc_datetime`
- Add comments for complex logic; remove `TODO` once addressed.

## Translation Management (Gettext)
- Translations are managed through Weblate. Do not edit `.po` files.
- Only update `.pot` templates when adding/changing strings.
- Do not run `mix gettext.extract --merge` (modifies `.po`).
- Currency symbols/amounts are not translatable; surrounding text is.
- CI will fail if `.po` files are modified by anyone other than `tuistit`.

## Important Notes
- Run `mix ecto.migrate` after pulling migrations.
- Use `mise run install` after dependency changes.
- Local development connects to `http://localhost:8080` for Tuist CLI integration.

## Data Export Documentation
Update `server/data-export.md` whenever you change stored customer data (schema, storage, retention, or new data collection). This is required for legal compliance.

## Related Context (Downlinks)
- Business logic: `server/lib/tuist/AGENTS.md`
- Web/UI layer: `server/lib/tuist_web/AGENTS.md`
- Assets pipeline: `server/assets/AGENTS.md`
- Configuration: `server/config/AGENTS.md`
- Migrations and seeds: `server/priv/AGENTS.md`
- Test conventions: `server/test/AGENTS.md`
