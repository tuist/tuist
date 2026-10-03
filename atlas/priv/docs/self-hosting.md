Atlas runs on your infrastructure with PostgreSQL, your own application keys, and Google sign-in. Choose Docker Compose for a single host or Helm for Kubernetes. Both use the same published Atlas image.

> [!NOTE]
> Atlas is still being decoupled from Tuist's operations. The deployment defaults below do not require Tuist's cluster, secret manager, or internal server access. Some application workflows still have organization-specific defaults; review integrations and delivery destinations before enabling them.

## Requirements

Provide a hostname, PostgreSQL 18, and encrypted browser connections through a reverse proxy. Reserve memory for the database and operating system in addition to Atlas: the deployment examples allow up to 4 gibibytes for the application and migrations, with two Erlang schedulers by default. Google sign-in requires a Google application, with an authorized redirect address of `https://atlas.example.org/auth/google/callback` and credentials for your organization. Set `ATLAS_ALLOWED_EMAIL_DOMAIN` to your organization's email domain; it limits admission but does not grant administrator access.

Production file workflows require compatible object storage. Document search needs a vector service and an embedding provider. Engineering error analytics needs ClickHouse. These dependencies are optional in the base deployment; configure them before using those features. Never load the development demo seeds into an installation containing real data.

## Release artifacts

Select a version from the [Atlas releases](https://github.com/tuist/tuist/releases?q=atlas%40). Each release publishes:

- `ghcr.io/tuist/atlas:VERSION`, the application image.
- `oci://ghcr.io/tuist/charts/atlas` at the same version, the Helm chart.
- A chart archive and `atlas-compose-VERSION.tar.gz` attached to the release. The Compose bundle pins the matching image version.

The chart's application version supplies the default image tag. Pin a release for production rather than following `latest`. The registry uses the [Open Container Initiative distribution format](https://helm.sh/docs/topics/registries/).

## Docker Compose

Install [Docker Compose](https://docs.docker.com/compose/install/), download the Compose bundle from your chosen release, and unpack it. From its `atlas-compose` directory:

```sh
cp .env.example .env
openssl rand -hex 32
openssl rand -hex 64
openssl rand -hex 64
openssl rand -base64 32
```

Use the outputs for `POSTGRES_PASSWORD`, `SECRET_KEY_BASE`, `GUARDIAN_SECRET_KEY`, and `ENCRYPTION_KEY`, respectively. Keep the database password hexadecimal so it can safely appear in the database connection address. Set `ATLAS_HOST`, `ATLAS_ALLOWED_EMAIL_DOMAIN`, `GOOGLE_CLIENT_ID`, and `GOOGLE_CLIENT_SECRET` in `.env`. Keep `.env` private.

```sh
docker compose config --quiet
docker compose up -d
docker compose ps -a
```

Compose waits for PostgreSQL to become healthy and for migrations to complete before starting Atlas. Caddy terminates encrypted connections and forwards requests to Atlas. For a public hostname, point its address records at the host and allow inbound ports 80 and 443. The `localhost` default is for evaluation and uses a locally issued certificate; your browser may require you to trust it. Public documentation can be evaluated without Google credentials, but signing in requires them.

Database data and proxy certificates persist in named volumes. `docker compose down` preserves these volumes; adding `--volumes` deletes them. Optional provider variables can be added to `.env`, which is read by both Atlas and its migration service. Upstream tools start disabled through `MCP_PROXY_SERVERS=[]`.

## Kubernetes with Helm

The base chart needs an existing PostgreSQL database and a Kubernetes Secret. It does not install a database operator or a secret manager. Create the keys locally as above and put them in a private `atlas.env` file:

```sh
DATABASE_URL=ecto://atlas:HEX_PASSWORD@postgres.example.org:5432/atlas
SECRET_KEY_BASE=YOUR_FIRST_SIGNING_KEY
GUARDIAN_SECRET_KEY=YOUR_SECOND_SIGNING_KEY
ENCRYPTION_KEY=YOUR_BASE64_ENCRYPTION_KEY
GOOGLE_CLIENT_ID=YOUR_GOOGLE_CLIENT_ID
GOOGLE_CLIENT_SECRET=YOUR_GOOGLE_CLIENT_SECRET
```

Create a namespace and Secret, then install the matching chart version:

```sh
kubectl create namespace atlas
kubectl --namespace atlas create secret generic atlas-app --from-env-file=atlas.env
helm upgrade --install atlas oci://ghcr.io/tuist/charts/atlas \
  --version VERSION --namespace atlas --values values.yaml --wait --timeout 10m
```

The chart archive attached to the same release is also installable directly. If you use that download, replace `oci://ghcr.io/tuist/charts/atlas` with the local `atlas-VERSION.tgz` path.

Use your own hostname and admission domain in `values.yaml`:

```yaml
host: atlas.example.org
appSecretName: atlas-app
env:
  ATLAS_ALLOWED_EMAIL_DOMAIN: example.org
  DATABASE_SSL: "true"
ingress:
  enabled: true
  className: nginx
  tlsSecretName: atlas-tls
```

Provision the named certificate Secret and an ingress controller separately. If you use cert-manager, set `ingress.clusterIssuer` to an existing issuer instead of provisioning the certificate yourself. Database encryption is disabled by default for local networks; enable it for a remote database. Atlas currently encrypts database connections without verifying the server certificate, so restrict database network access as well.

Migrations run in an initialization container before each Atlas replica starts. For optional services, inspect `helm show values oci://ghcr.io/tuist/charts/atlas --version VERSION`. Enabling the bundled PostgreSQL service requires [CloudNativePG](https://cloudnative-pg.io/documentation/); enabling the chart's managed secret synchronization requires [External Secrets Operator](https://external-secrets.io/). The base installation needs neither. Vector storage and bundled backup secret synchronization currently use that operator too; external services can instead be configured through the application Secret and environment values.

## First administrator

Sign in once with the intended administrator's Google account. Then run the operator-only bootstrap command. For Compose:

```sh
docker compose exec -e ATLAS_BOOTSTRAP_ADMIN_EMAIL=person@example.org atlas /app/bin/bootstrap-admin
```

For Helm, find the running Atlas pod and run:

```sh
kubectl --namespace atlas get pods
kubectl --namespace atlas exec POD_NAME -- env \
  ATLAS_BOOTSTRAP_ADMIN_EMAIL=person@example.org /app/bin/bootstrap-admin
```

Bootstrap grants access to an existing user and refuses to run after initialization. It never creates a user or demo data. Removing an administrator does not reopen bootstrap.

## Upgrades and backups

Back up PostgreSQL, object storage, and the encryption key before upgrading. Losing `ENCRYPTION_KEY` prevents decryption of saved integration credentials. Store signing keys and Google credentials securely with the deployment configuration. Test restoring backups into an isolated installation.

For Compose, stop Atlas, change `ATLAS_VERSION` in `.env`, pull the images, and rerun the migration service before starting the application:

```sh
docker compose stop atlas
docker compose pull
docker compose run --rm migrate
docker compose up -d --force-recreate migrate atlas
```

For Helm, repeat `helm upgrade --install` with the new release version. Review migration compatibility before rolling back an image: a Helm rollback does not undo database migrations.

## Operational checks

`/ready` returns success when the web server answers and bypasses the production encrypted-connection redirect so private container probes can reach it directly. Migrations must succeed before Atlas starts in both deployments. Monitor database connectivity separately: this endpoint does not query the database. Do not expose port 4000 directly to the internet; use the proxy or ingress.

Monitor background job failures and database capacity. Configure your own edge rate limits for public documentation and application endpoints. The response classification header used by Tuist does not itself provide rate limiting on your infrastructure.
