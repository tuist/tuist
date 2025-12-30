# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Git and Pull Requests

When creating commits and pull requests, use these conventional commit scopes:
- `app` - Changes to the Tuist iOS app
- `server` - Changes to the Tuist server (Elixir/Phoenix)
- `cache` - Changes to the Tuist cache service (Elixir/Phoenix)
- `cli` - Changes to the Tuist CLI (Swift)
- `docs` - Changes to documentation
- `handbook` - Changes to the handbook/guides

Examples:
- `feat(server): add new telemetry sanitizer module`
- `fix(cli): resolve cache artifact upload issue`
- `feat(cache): add new S3 transfer worker`
- `docs(handbook): update project setup guide`

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
- **Databases**: 
  - PostgreSQL with TimescaleDB extension (primary database)
  - ClickHouse (analytics database, write-only through IngestRepo)
- **Frontend**: Phoenix LiveView with JavaScript/TypeScript and esbuild
- **Package Management**: pnpm for JavaScript dependencies

**Core Architecture Components:**
- `lib/tuist/` - Core business logic modules (accounts, billing, bundles, projects, registry, etc.)
- `lib/tuist_web/` - Web interface (controllers, LiveView components, marketing site)
- `priv/repo/migrations/` - PostgreSQL database schema migrations
- `priv/ingest_repo/migrations/` - ClickHouse database schema migrations (analytics, write-only)
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
- Email: `tuistrocks@tuist.dev`
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

## Translation Management (Gettext)

**Important:** Translations are managed through Weblate. Do not manually edit translation files.

**Translation File Types:**
- `.pot` files (templates) - **CAN be modified** by developers when adding/changing translatable strings
- `.po` files (translations) - **MUST NOT be modified** by developers
- Only the `tuistit` bot should modify `.po` files

**Workflow:**
1. Add translatable strings using `dgettext/2` in your code
2. Run `mix gettext.extract` to update the `.pot` template files
3. Commit only the `.pot` files (and your code changes)
4. Weblate will automatically sync the `.pot` changes and create translation PRs via the `tuistit` bot
5. **Never run `mix gettext.extract --merge`** in your PRs as this modifies `.po` files

**Key Principles:**
- Currency symbols and monetary amounts should NOT be wrapped in `dgettext/2` - they must remain consistent across languages
- Descriptive text around prices (like "and up", "per unit") SHOULD be translatable
- Example: `"0€ " <> dgettext("marketing", "and up")` ✅
- Anti-example: `dgettext("marketing", "0€ and up")` ❌

**CI Protection:**
The CI pipeline will fail if any `.po` files are modified by anyone other than `tuistit`.

## Deployment

The application deploys to Render with different environments:
- `mise run deploy:staging` - Deploy to staging
- `mise run deploy:canary` - Deploy to canary
- `mise run deploy:production` - Deploy to production

## Important Notes

- Always run `mix ecto.migrate` after pulling database migrations
- Use `mise run install` after pulling dependency changes
- The application requires TimescaleDB extension - install it if migrations fail
- Local development connects to `http://localhost:8080` for Tuist CLI integration

# Tuist Handbook

## Overview

The Tuist handbook is a VitePress-based documentation site that contains company policies, procedures, and guidelines. It's organized into several main sections:

- **Company**: Mission, vision, principles, and leadership information
- **Security**: Comprehensive security policies and procedures
- **Engineering**: Technical standards, practices, and technologies
- **People**: Benefits, values, code of conduct, and how we work
- **Marketing**: Guidelines and case studies
- **Product**: Product development processes
- **Support**: Support processes and procedures
- **Community**: Community-related content

## Technical Details

### Building and Testing

- **Build command**: `mise run handbook:build` (can be run from any directory)
  - This command also verifies that there are no dead links
- **Development server**: `mise run handbook:dev` (from the handbook directory)
- **Deployment**: The handbook is automatically deployed to Cloudflare Pages at handbook.tuist.io

### Directory Structure

```
handbook/
├── .vitepress/
│   └── config.mjs    # Navigation and site configuration
├── handbook/         # Content directory
│   ├── company/
│   ├── security/
│   ├── engineering/
│   ├── people/
│   ├── marketing/
│   ├── product/
│   ├── support/
│   └── community/
└── package.json
```

## Working with Security Policies

When creating or modifying security policies:

1. **Follow the standard format**:
   - Include frontmatter with title, titleTemplate, and description
   - Start with policy owner and effective date
   - Use consistent section structure

2. **Standard policy sections**:
   - Purpose
   - Scope
   - Policy Statement
   - Requirements (numbered subsections)
   - Roles and Responsibilities
   - Exceptions
   - Compliance Monitoring
   - Policy Review
   - Version History

3. **Key considerations**:
   - Keep policies practical for a 4-person company
   - Reference the [shared responsibility model](/security/shared-responsibility-model) when discussing infrastructure
   - Infrastructure providers (Render, Supabase, Tigris, Cloudflare) handle their own layer security
   - Focus on application-layer responsibilities

## Navigation Configuration

The site navigation is configured in `.vitepress/config.mjs`:

- The sidebar structure should match the directory structure
- When adding new pages, ensure they're included in the navigation
- Redirects for moved pages are handled in the buildEnd hook

## Content Guidelines

### Writing Style

- Use clear, concise language
- Write for a small, technical team
- Avoid overly bureaucratic language
- Focus on practical implementation

### Frontmatter Format

```yaml
---
title: Page Title
titleTemplate: :title | Section | Tuist Handbook
description: Brief description of the page content
---
```

### Markdown Conventions

- Use standard GitHub-flavored markdown
- Include anchors for major sections
- Use numbered lists for sequential steps
- Use bullet points for non-sequential items

## Handbook Important Reminders

1. **Always verify builds**: Run `mise run handbook:build` before committing to ensure:
   - The handbook builds successfully
   - There are no broken links
   - Navigation is properly configured

2. **Security policy updates**: When updating security policies, consider:
   - Impact on the small team size
   - Alignment with shared responsibility model
   - Practical implementation requirements

3. **Infrastructure responsibilities**: Remember that Tuist relies on:
   - Render for application hosting
   - Supabase for database services
   - Tigris for data storage
   - Cloudflare for CDN and edge services

Each provider handles security at their infrastructure layer, while Tuist focuses on application-layer security.

## Common Handbook Tasks

### Adding a new page

1. Create the markdown file in the appropriate directory
2. Add proper frontmatter
3. Update `.vitepress/config.mjs` to include it in navigation
4. Run `mise run handbook:build` to verify
5. Commit and create a PR with @tuist/company team as reviewer

### Updating Existing Content

1. Make changes to the markdown file
2. Verify internal links are still valid
3. Run `mise run handbook:build` to test
4. Commit with a descriptive message
5. Create a PR with @tuist/company team as reviewer

### Moving or Renaming Pages

1. Move/rename the file
2. Update navigation in `.vitepress/config.mjs`
3. Add a redirect in the buildEnd hook if needed
4. Update any internal links to the page
5. Run `mise run handbook:build` to verify all links
6. Create a PR with @tuist/company team as reviewer

# Data Export Documentation Maintenance

## Important: Keep server/data-export.md Up to Date

The `server/data-export.md` file documents all personal and organizational data that Tuist stores and can export for customers upon legal request. **This file must be kept current whenever database schema changes or new data storage is introduced.**

### When to Update server/data-export.md

You **MUST** update `server/data-export.md` when making any of the following changes:

#### Database Schema Changes
- Adding new tables to PostgreSQL or ClickHouse
- Adding new columns that store customer/user data
- Modifying data relationships between tables
- Adding new Ecto schemas or models
- Changes to data retention policies

#### File Storage Changes
- Adding new types of files stored in S3
- Changing S3 storage path structures
- Adding new file categories or storage buckets
- Modifying file upload/download processes

#### New Data Collection
- Adding new user data fields
- Implementing new analytics or tracking
- Adding new integrations that store customer data
- New features that generate customer-owned content

### How to Update server/data-export.md

When making qualifying changes:

1. **Review the change**: Identify what new data is being stored or how existing data storage is modified
2. **Update the documentation**: Add or modify the relevant sections in `server/data-export.md`
3. **Be comprehensive**: Include:
   - Data type and purpose
   - Storage location (database table, S3 path structure, etc.)
   - Data relationships
   - Retention policies
   - Export capabilities
4. **Maintain format**: Follow the existing documentation structure and style
5. **Test documentation**: Verify that the export process could actually retrieve the documented data

### Legal Compliance

This documentation is critical for:
- GDPR Article 20 (Right to data portability)
- CCPA data export requirements  
- General customer data transparency
- Incident response and data breach notifications

**Failure to keep this documentation current could result in incomplete data exports for legal requests, potentially leading to compliance violations.**
- Don't modify content in languages other than English (source language)
