# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

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