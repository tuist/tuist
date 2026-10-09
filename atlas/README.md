# Atlas

Atlas is a Phoenix application for bringing account, customer, billing, product, finance, integration, and workflow context into one place.

## Development

```bash
mise install
mix deps.get
mix ecto.setup
mix phx.server
```

## Self-hosting

Use the [self-hosting guide](priv/docs/self-hosting.md) for Docker Compose and Helm installation, administrator bootstrap, upgrades, and backups. Each Atlas release publishes the image, a matching chart, and a Compose bundle.
