## Run the published image

Atlas is distributed as a container image at [`ghcr.io/tuist/atlas`](https://github.com/tuist/tuist/pkgs/container/atlas). Run that image with your own PostgreSQL database, application keys, storage, and sign-in configuration. You do not need a source checkout or Elixir installed on the host.

Use `latest` to evaluate Atlas. For production, select a published version and pin that tag so an upgrade is deliberate.

Follow [Deploy with Docker](/docs/installation) for the starting deployment, then [grant your first administrator access](/docs/first-administrator).

## What you operate

Your installation needs persistent PostgreSQL storage, a public hostname, and a reverse proxy that terminates encrypted browser connections. Atlas currently uses Google sign-in, so you also need a Google application configured for your own hostname and email domain.

Production file workflows need compatible object storage. Communication, payments, document extraction, and assisted workflows each require their own provider configuration. Review the [configuration reference](/docs/configuration) and [integrations](/docs/integrations) before enabling them.

## Installation lifecycle

Start the database, run migrations through the image's release command, and start Atlas behind your reverse proxy. Sign in once, then run the first-administrator command from the deployment.

Before upgrading, back up the database, file storage, and encryption keys. Pin the new image version and run its migrations before replacing the running application. Never run demo seeds against a real installation.

## Current limitations

> [!WARNING]
> Atlas emerged from Tuist's operations, and self-hosting is still being generalized. Some defaults refer to Tuist, and optional integrations and background jobs are not yet uniformly gated. Review configuration and delivery destinations before enabling them. Missing credentials do not reliably disable every integration.
>
> The published image is the recommended deployment artifact. The Docker guide is a starting configuration, not yet a verified minimal standalone deployment contract.
