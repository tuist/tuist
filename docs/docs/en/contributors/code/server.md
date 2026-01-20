---
{
  "title": "Server",
  "titleTemplate": ":title · Code · Contributors · Tuist",
  "description": "Contribute to the Tuist Server."
}
---
# Server {#server}

Source: [github.com/tuist/tuist/tree/main/server](https://github.com/tuist/tuist/tree/main/server)

## What it is for {#what-it-is-for}

The server powers Tuist’s server-side features like authentication, accounts and projects, cache storage, insights, previews, registry, and integrations (GitHub, Slack, and SSO). It is a Phoenix/Elixir application with Postgres and ClickHouse.

::: warning TIMESCALEDB DEPRECATION
<!-- -->
TimescaleDB is deprecated and will be removed. For now, if you need it for local setup or migrations, use the [TimescaleDB installation docs](https://docs.timescale.com/self-hosted/latest/install/installation-macos/).
<!-- -->
:::

## How to contribute {#how-to-contribute}

Contributions to the server require signing the CLA (`server/CLA.md`).

### Set up locally {#set-up-locally}

```bash
cd server
mise install

# Dependencies
brew services start postgresql@16
mise run clickhouse:start

# Minimal secrets
export TUIST_SECRET_KEY_BASE="$(mix phx.gen.secret)"

# Install dependencies + set up the database
mise run install

# Run the server
mise run dev
```

> [!NOTE]
> First-party developers load encrypted secrets from `priv/secrets/dev.key`. External contributors won't have that key, and that's fine. The server still runs locally with `TUIST_SECRET_KEY_BASE`, but OAuth, Stripe, and other integrations remain disabled.

### Tests and formatting {#tests-and-formatting}

- Tests: `mix test`
- Format: `mise run format`
