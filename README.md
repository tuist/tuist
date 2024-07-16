# Tuist Server

This repository contains the source code of the server-side application that extends the functionality of the [Tuist](https://tuist.io) CLI.

## Development

### Requirements

- [Posgres](https://formulae.brew.sh/formula/postgresql@16)
- [TimescaleDB](https://docs.timescale.com/self-hosted/latest/install/installation-macos/)
- [Mise](https://mise.jdx.dev/)

### Set up

1. Clone the repository: `git clone https://github.com/tuist/server.git`.
2. Install additional system dependencies with: `mise install`.
3. Install the project dependencies with: `mise run install`
3. Run `mise run dev`

> [!IMPORTANT]
> If the execution of database migrations fails because the TimescaleDB extension is not installed, you'll have to [install the extension](https://docs.timescale.com/self-hosted/latest/install/installation-macos/#set-up-the-timescaledb-extension) in the `tuist_development` database.
