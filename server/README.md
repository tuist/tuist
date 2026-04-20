# Tuist Server

This repository contains the source code of the server-side application that extends the functionality of the [Tuist](https://tuist.io) CLI.

## Contributing

Contributions to the Tuist Server require signing a Contributor License Agreement (CLA). Please see [CLA.md](./CLA.md) for details before submitting pull requests that modify server components.

## Development

### Requirements

- [Postgres](https://formulae.brew.sh/formula/postgresql@16)
- [Mise](https://mise.jdx.dev/)

### Set up

1. Clone the repository: `git clone https://github.com/tuist/tuist.git`.
1. Open the folder: `cd server`.
1. Install system dependencies with: `mise install`.
1. Start Postgres with: `brew services start postgresql@16`.
1. Start ClickHouse with: `mise run clickhouse:start`
1. Install dependencies: `mise run install`
1. Create and set up the database: `mise run db:setup`
1. Run the server: `mise run dev`
1. Open the local URL for your current clone or worktree in your browser and log in with the pre-made test user account. With `mise activate` enabled, each checkout persists its own numeric suffix through Git metadata when available, while keeping the existing root `.tuist-dev-instance` file as a compatibility fallback. That suffix scopes the local service ports, MinIO ports, and server databases, so developers can choose either standalone clones or linked worktrees. For example, a suffix of `443` yields `http://localhost:8523`. If you need the dev server to be reachable from another machine, set `TUIST_SERVER_BIND_HOST` to the interface or address the server should listen on before `mise activate`. When you bind to all interfaces with `0.0.0.0` or `::`, also set `TUIST_SERVER_PUBLIC_HOST` so generated absolute URLs and OAuth callbacks use a reachable host:

   - `TUIST_SERVER_BIND_HOST=192.168.1.10 mise activate`
   - `TUIST_SERVER_BIND_HOST=0.0.0.0 TUIST_SERVER_PUBLIC_HOST=192.168.1.10 mise activate`

```
Email: tuistrocks@tuist.dev
Pass: tuistrocks
```

> [!NOTE]
> First-party developers can load encrypted secrets from `priv/secrets/dev.key`. External contributors don't need this key — the server runs locally without it. OAuth, Stripe, and other third-party integrations will be disabled, but core functionality works.

#### To run additional features
1. Clone the repository: `https://github.com/tuist/tuist.git`.
1. Go to `tuist/examples/xcode/generated_ios_app_with_frameworks`.
1. Change the url in `Tuist.swift` to the local URL for the current clone or worktree, for example `http://localhost:8523`.
1. Run `tuist auth` to authenticate.
1. You are now connected to the local Tuist Server!  You can try running `tuist cache` and see the binaries being uploaded.
