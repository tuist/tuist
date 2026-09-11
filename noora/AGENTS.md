# Noora Web (Elixir/Phoenix Component Library)

## Overview

Noora is a Phoenix LiveView component library published to hex.pm. It provides reusable UI components (buttons, modals, tables, forms, etc.) for Phoenix applications.

## Structure

- `lib/` - Elixir component modules
- `js/` - JavaScript hooks and behaviors. `ScrollIndicator.js` provides shared thumb sizing and dragging for table and chart scrollbars, styled by `css/scroll_indicator.css`. Tables drive indicator updates explicitly so hidden overlays do not measure on scroll.
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

Noora is published to [Hex](https://hex.pm/) for Phoenix LiveView consumers and to the [npm package registry](https://www.npmjs.com/) as `@tuist/noora` for JavaScript consumers. The shared version is tracked in `mix.exs` and `package.json`. Releases are automated by `.github/workflows/noora-release.yml` using `noora/cliff.toml` for changelog generation. The workflow validates Noora on `tuist-linux`, then builds and publishes both registry artifacts on a GitHub-hosted runner so the npm package includes provenance.

Web component metadata and documentation are generated from `components/*.json` with `aube run generate:web-components`. Run `aube run check:generated` when changing a component contract.

Do not bootstrap the npm package from a local machine. The first automated release reads a granular access token with permission to publish under the `@tuist` scope from `op://tuist/NPM_TOKEN/password` using `OP_SERVICE_ACCOUNT_TOKEN`. After the package exists, configure its trusted publisher for the `tuist/tuist` repository and `noora-release.yml` workflow, allow `npm publish`, verify a release, revoke the long-lived token, and remove its 1Password item.

## Conventions
- Icon transition hooks restore their visual state after LiveView patches, including patches that leave the watched ancestor's state unchanged.
- Phoenix table disclosure buttons support an optional `row_toggle` JS callback for server-managed lazy loading. Callers then own `expanded_rows`; tables without a callback retain client-side expansion.

- Brand icons use monochrome `currentColor` SVGs in `lib/noora/icons/`; `brand-gitlab.svg` comes from Simple Icons and is exposed as `brand_gitlab/1`.

- Use `noora` as the conventional commit scope for changes in this directory
- The Tuist server depends on noora via a local path dependency (`{:noora, path: "../noora"}`)
- Delegate date-picker month navigation from the hook root so LiveView can replace
  calendar controls without losing their click handlers.
- The LiveView chart hook supports opt-in `data-lazy="true"` initialization near
  the viewport. Keep offscreen updates and destruction safe, and register resize
  listeners once per hook lifetime rather than once per render.

- Charts humanize plain numeric tooltip values and value-axis labels from 10,000 upward using `formatNumber` (K/M/B/T, up to one decimal). Explicit unit formatters and category/time axes retain their formats; series values remain numeric.
