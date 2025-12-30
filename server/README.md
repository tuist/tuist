# Tuist Server

This repository contains the source code of the server-side application that extends the functionality of the [Tuist](https://tuist.io) CLI.

## Contributing

Contributions to the Tuist Server require signing a Contributor License Agreement (CLA). Please see [CLA.md](./CLA.md) for details before submitting pull requests that modify server components.

## Development

### Requirements

- [Postgres](https://formulae.brew.sh/formula/postgresql@16)
- [TimescaleDB](https://docs.timescale.com/self-hosted/latest/install/installation-macos/)
- [Mise](https://mise.jdx.dev/)

### Set up

1. Clone the repository: `git clone https://github.com/tuist/server.git`.
1. Open the folder: `cd server`.
1. Get the private key from 1Password.
1. Create a `priv/secrets/dev.key` file and add the key to decrypt the secrets needed for development.
1. Install additional system dependencies with: `mise install`.
1. Start Postgres with: `brew services start postgresql@16`.
1. Start ClickHouse with: `mise run clickhouse:start`
1. Create a new database with: `mise run db:create`.
1. Load the data into database with: `mise run db:load`.
1. Seed your database with data: `mise run db:seed`.
1. Run the server: `mise run dev`
1. We already have a pre-made user account that you can use to test the server:

```
Email: tuistrocks@tuist.dev
Pass: tuistrocks
```

#### To run additional features
1. Clone the repository: `https://github.com/tuist/tuist.git`.
1. Go to `tuist/examples/xcode/generated_ios_app_with_frameworks`.
1. Change the url in `Tuist/Config.swift` to `http://localhost:8080`.
1. Run `tuist auth` to authenticate.
1. You are now connected to the local Tuist Server!  You can try running `tuist cache` and see the binaries being uploaded.

> [!IMPORTANT]
> If the execution of database migrations fails because the TimescaleDB extension is not installed, you'll have to [install the extension](https://docs.timescale.com/self-hosted/latest/install/installation-macos/#set-up-the-timescaledb-extension) in the `tuist_development` database.
