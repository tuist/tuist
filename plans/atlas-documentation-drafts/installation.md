## Choose an image

Use the published [`ghcr.io/tuist/atlas`](https://github.com/tuist/tuist/pkgs/container/atlas) image. The examples use `latest` for evaluation; replace it with a published version tag before a production deployment.

```sh
docker pull ghcr.io/tuist/atlas:latest
```

## Prepare configuration

Create a private `.env` file alongside your `compose.yaml`. Replace every placeholder with your own value. Use the same PostgreSQL password in `POSTGRES_PASSWORD` and `DATABASE_URL`.

```dotenv
ATLAS_IMAGE=ghcr.io/tuist/atlas:latest
POSTGRES_PASSWORD=replace-with-your-database-password
DATABASE_URL=ecto://atlas:replace-with-your-database-password@postgres/atlas
PHX_HOST=atlas.example.org
SECRET_KEY_BASE=replace-with-an-independent-session-secret
GUARDIAN_SECRET_KEY=replace-with-an-independent-token-secret
ENCRYPTION_KEY=replace-with-a-base64-encoded-32-byte-key
GOOGLE_CLIENT_ID=replace-with-your-google-client-identifier
GOOGLE_CLIENT_SECRET=replace-with-your-google-client-secret
ATLAS_ALLOWED_EMAIL_DOMAIN=example.org
ATLAS_CLICKHOUSE_ENABLED=false
MCP_PROXY_SERVERS=[]
```

Generate independent secrets with a local cryptographic tool. For example, run `openssl rand -base64 64` separately for the session and token secrets, and `openssl rand -base64 32` for the encryption key. Keep these values private and preserve the encryption key with your backups.

Set up a Google sign-in application whose callback is `https://atlas.example.org/auth/google/callback`, replacing the hostname with your own. `ATLAS_ALLOWED_EMAIL_DOMAIN` controls admission and Google's account-picker hint; it does not grant roles.

## Start PostgreSQL

This Compose example uses PostgreSQL 16, matching the version used for the empty-database migration check. It persists database files in a named volume and exposes Atlas only on the host's loopback interface.

```yaml
services:
  postgres:
    image: postgres:16
    environment:
      POSTGRES_USER: atlas
      POSTGRES_DB: atlas
      POSTGRES_PASSWORD: ${POSTGRES_PASSWORD}
    volumes:
      - atlas-postgres:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U atlas -d atlas"]
      interval: 5s
      timeout: 5s
      retries: 10

  atlas:
    image: ${ATLAS_IMAGE}
    env_file: .env
    ports:
      - "127.0.0.1:4000:4000"
    depends_on:
      postgres:
        condition: service_healthy

volumes:
  atlas-postgres:
```

```sh
docker compose up -d postgres
```

## Run migrations

The image contains the release commands. Run migrations against the database before starting or upgrading Atlas:

```sh
docker compose run --rm atlas /app/bin/migrate
```

PostgreSQL creates the database during its first initialization. The release migration command creates the schema without running demo seeds or starting Atlas's background workers.

## Start Atlas

```sh
docker compose up -d atlas
```

Place an encrypted reverse proxy in front of `127.0.0.1:4000`. Serve the hostname configured in `PHX_HOST` and forward `X-Forwarded-Proto: https` for requests received over encrypted connections. The production image redirects ordinary browser requests to the encrypted site; port 4000 is the origin behind the proxy.

Open your public hostname, sign in, and follow [First administrator](/docs/first-administrator). Configure object storage and the providers required by your workflows before using them.

## Current limitations

> [!WARNING]
> Self-hosting is still being generalized. Optional integrations and background jobs are not yet uniformly gated, and some defaults still refer to Tuist. Review configuration before enabling workers or delivery providers. Do not assume that omitting credentials disables every integration.
>
> This example documents the existing image and release commands. It has not yet been verified as a complete standalone deployment with every optional dependency disabled.

For source development, use [Run from source](/docs/development).
