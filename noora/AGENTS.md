# Noora Web (Elixir/Phoenix Component Library)

## Overview

Noora is a Phoenix LiveView component library published to hex.pm. It provides reusable UI components (buttons, modals, tables, forms, etc.) for Phoenix applications.

## Structure

- `lib/` - Elixir component modules
- `js/` - JavaScript hooks and behaviors
- `js/web-components/` - Lit-based custom elements
- `css/` - Component stylesheets
- `components/` - Shared component contracts consumed by Elixir and JavaScript
- `docs/` - Generated web component guides and references
- `scripts/` - Web component artifact generation
- `types/` - Generated TypeScript declarations
- `priv/static/` - Built assets (noora.js, noora.css)
- `storybook/` - Phoenix Storybook app for component previews, deployed to the production cluster at storybook.noora.tuist.dev via `infra/helm/noora-storybook` and `.github/workflows/noora-storybook-deployment.yml`

## Development Commands

- `mise run noora:build` - Install JS dependencies, build JS/CSS assets, and compile Elixir
- `mise run noora:test` - Run vitest JS tests
- `mise run noora:lint` - Check formatting (Elixir + Prettier)
- `mise run noora:lint --fix` - Auto-fix formatting

## Publishing

Noora is published to [Hex](https://hex.pm/) for Phoenix LiveView consumers and to the [npm package registry](https://www.npmjs.com/) as `@tuist/noora` for JavaScript consumers. The shared version is tracked in `mix.exs` and `package.json`. Releases are automated via the monorepo release workflow using `noora/cliff.toml` for changelog generation.

Web component metadata and documentation are generated from `components/*.json` with `aube run generate:web-components`. Run `aube run check:generated` when changing a component contract.

The first npm package registry release requires a granular access token with permission to publish under the `@tuist` scope, exposed to GitHub Actions as `NPM_TOKEN`. After the package exists, configure its trusted publisher for the `tuist/tuist` repository and `server-production-deployment.yml` workflow, allow `npm publish`, verify a release, and remove the long-lived token.

## Conventions

- Use `noora` as the conventional commit scope for changes in this directory
- The Tuist server depends on noora via a local path dependency (`{:noora, path: "../noora"}`)
