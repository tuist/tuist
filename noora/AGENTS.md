# Noora Web (Elixir/Phoenix Component Library)

## Overview

Noora is a Phoenix LiveView component library published to hex.pm. It provides reusable UI components (buttons, modals, tables, forms, etc.) for Phoenix applications.

## Structure

- `lib/` - Elixir component modules
- `js/` - JavaScript hooks and behaviors
- `css/` - Component stylesheets
- `priv/static/` - Built assets (noora.js, noora.css)
- `storybook/` - Phoenix Storybook app for component previews, deployed to Render at storybook.noora.tuist.dev

## Development Commands

- `mise run noora:build` - Install JS dependencies, build JS/CSS assets, and compile Elixir
- `mise run noora:test` - Run vitest JS tests
- `mise run noora:lint` - Check formatting (Elixir + Prettier)
- `mise run noora:lint --fix` - Auto-fix formatting

## Publishing

Noora is published to hex.pm. Version is tracked in `mix.exs`. Releases are automated via the monorepo release workflow using `noora/cliff.toml` for changelog generation.

## Conventions

- Use `noora` as the conventional commit scope for changes in this directory
- The Tuist server depends on noora via a local path dependency (`{:noora, path: "../noora"}`)
