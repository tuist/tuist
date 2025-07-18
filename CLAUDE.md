# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

# Tuist CLI (Swift)

## Code style
- Do not add one-line comments unless you think they are really useful.

## Workflow
- The Xcode project is generated with Tuist running `tuist generate --no-open`
- When compiling Swift changes, use `xcodebuild build -workspace Tuist.xcworkspace -scheme Tuist-Workspace` instead of `swift build`
- When testing Swift changes, use `xcodebuild test -workspace Tuist.xcworkspace -scheme Tuist-Workspace -only-testing MyTests/SuiteTests` instead of `swift test`.
- Prefer running test suites or individual test cases, and not the whole test target, for performance

## Testing
- Use Swift Testing framework with custom traits for tests that need temporary directories
- For tests requiring temporary directories, use `@Test(.inTemporaryDirectory)` and access the directory via `FileSystem.temporaryTestDirectory`
- Import `FileSystemTesting` when using the `.inTemporaryDirectory` trait
- Example pattern:
  ```swift
  import FileSystemTesting
  import Testing

  @Test(.inTemporaryDirectory) func test_example() async throws {
      let temporaryDirectory = try #require(FileSystem.temporaryTestDirectory)
      // Test implementation
  }
  ```
- Do not modify CHANGELOG.md as it is auto-generated

## Linting
- To check for linting issues: `mise run lint`
- To automatically fix fixable linting issues: `mise run lint --fix`

# Tuist Server (Elixir/Phoenix)

## Project Architecture

Tuist Server is an Elixir/Phoenix web application that extends the functionality of the Tuist CLI for iOS/macOS development. It provides binary caching, app preview deployment, build analytics, and Swift package registry services.

**Key Technologies:**
- **Backend**: Elixir 1.18.3 with Phoenix 1.7.12 framework
- **Databases**: PostgreSQL with TimescaleDB extension (primary), ClickHouse (analytics)
- **Frontend**: Phoenix LiveView with JavaScript/TypeScript and esbuild
- **Package Management**: pnpm for JavaScript dependencies

**Core Architecture Components:**
- `lib/tuist/` - Core business logic modules (accounts, billing, bundles, projects, registry, etc.)
- `lib/tuist_web/` - Web interface (controllers, LiveView components, marketing site)
- `priv/repo/migrations/` - Database schema migrations
- `assets/` - Frontend source files (JS/CSS)
- `config/` - Application configuration

**Main Business Domains:**
- **Accounts** - User authentication, organizations, billing management
- **Projects** - Project management, tokens, permissions
- **Bundles** - Binary cache management for build optimization
- **Previews** - iOS app preview generation and deployment
- **Registry** - Swift package registry implementation
- **Command Events** - CLI interaction tracking and analytics

## Development Setup

**Prerequisites:**
- PostgreSQL 16 with TimescaleDB extension
- Mise development environment manager
- Private key from 1Password for `priv/secrets/dev.key`

**Setup Commands:**
```bash
mise install                    # Install system dependencies
brew services start postgresql@16
mise run clickhouse:start      # Start ClickHouse
mise run db:create             # Create database
mise run db:load               # Load database schema
mise run db:seed               # Seed with development data
mise run dev                   # Start development server
```

**Test User Account:**
- Email: `tuistrocks@tuist.io`
- Password: `tuistrocks`

## Common Development Commands

**Database Management:**
- `mise run db:setup` - Complete database setup (create, migrate, seed)
- `mise run db:reset` - Drop, recreate, and migrate database
- `mix ecto.migrate` - Run pending migrations
- `mix ecto.rollback` - Rollback last migration

**Development Server:**
- `mise run dev` - Start Phoenix development server
- `mix phx.server` - Alternative way to start server
- `iex -S mix phx.server` - Start server with interactive shell

**Testing:**
- `mix test` - Run full test suite (includes database setup)
- `mix test test/path/to/specific_test.exs` - Run specific test file
- `mix test test/path/to/test_file.exs:line_number_of_test` - Test single case
- `mix test --only tag_name` - Run tests with specific tag

**Code Quality:**
- `mix credo` - Run code analysis and linting
- `mix format` - Format Elixir code
- `mise run format` - Format all code (Elixir + JS)
- `mix sobelow` - Security analysis
- `mise run security` - Run security static checks

**Frontend Assets:**
- `mix assets.setup` - Install esbuild
- `mix assets.build` - Build all assets (app, marketing, apidocs)
- `mix assets.deploy` - Build and minify assets for production

**Database Utilities:**
- `mix ecto.dump` - Export database structure
- `mix ecto.load` - Import database structure
- `mix excellent_migrations.check_safety` - Check migration safety

## Key Configuration Files

- `.mise.toml` - Development environment and tool versions
- `mix.exs` - Elixir project configuration and dependencies
- `package.json` - JavaScript dependencies managed by pnpm
- `config/` directory - Phoenix application configuration
- `priv/secrets/dev.key` - Development secrets encryption key (not in repo)

## Testing Patterns

The codebase uses ExUnit for testing. Test files follow the pattern `test/**/module_name_test.exs`. Tests automatically set up a clean database before running.

**Running Specific Tests:**
```bash
mix test test/tuist/accounts_test.exs
mix test test/tuist_web/live/dashboard_live_test.exs
```

**Testing Guidelines:**
- **Never modify System environment variables** in tests as they are shared state and can cause flaky tests
- Use mocks, stubs, or dependency injection to test environment-dependent behavior
- If environment testing is absolutely necessary, use process-scoped alternatives or test tags to isolate tests

## Code Style Guidelines (Elixir)
- **Formatting:** Follow standard Elixir and Phoenix conventions. Consider using an Elixir formatter.
- **Imports/Aliases:** Use `alias` for modules used multiple times. Avoid `import` unless for specific DSLs (e.g., Ecto.Query).
- **Modules Aliases:** Always declare module aliases at the module level in files, not within individual functions. This improves readability and avoids repetition.
- **Mocking:** Copy the modules for mocking in @server/test/test_helper.exs not in the individual functions.
- **Types:** Utilize typespecs (`@spec`) for public functions.
- **Naming Conventions:**
    - Modules: PascalCase (e.g., `MyModule`)
    - Functions: snake_case (e.g., `my_function`)
    - Variables: snake_case (e.g., `my_variable`)
- **Error Handling:** Prefer tagged tuples `{:ok, value}` and `{:error, reason}` for functions that can fail. Use exceptions for unrecoverable errors.
- **Credo:** Adhere to rules in `.credo.exs`.
    - Timestamps in migrations should be `:timestamptz`.
    - Timestamps in `lib/` should be `:utc_datetime`.
- **Comments:** Add comments for complex logic or non-obvious code. Remove `TODO` comments once addressed.

## Deployment

The application deploys to Fly.io with different environments:
- `mise run deploy:staging` - Deploy to staging
- `mise run deploy:canary` - Deploy to canary
- `mise run deploy:production` - Deploy to production

**Remote Console Access:**
- `mise run fly:console:staging`
- `mise run fly:console:production`

## Important Notes

- Always run `mix ecto.migrate` after pulling database migrations
- Use `mise run install` after pulling dependency changes
- The application requires TimescaleDB extension - install it if migrations fail
- Local development connects to `http://localhost:8080` for Tuist CLI integration
