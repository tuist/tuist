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

## How to contribute {#how-to-contribute}

Contributions to the server require signing the CLA (`server/CLA.md`).

### Set up locally {#set-up-locally}

```bash
cd server
mise install

# Dependencies
brew services start postgresql@16
mise run clickhouse:start

# Install dependencies + set up the database
mise run install

# Run the server
mise run dev
```

Open `http://localhost:8080` in your browser. In development, the login page includes a **Log in as test user** button that signs you in with the pre-made account (`tuistrocks@tuist.dev` / `tuistrocks`).

> [!NOTE]
> First-party developers can load encrypted secrets from `priv/secrets/dev.key`. External contributors don't need this key — the server runs locally without it. OAuth, Stripe, and other third-party integrations will be disabled, but core functionality works.

### Tests and formatting {#tests-and-formatting}

- Tests: `mix test`
- Format: `mise run format`
