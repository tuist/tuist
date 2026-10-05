You can run Atlas on a single host with [Docker Compose](https://docs.docker.com/compose/) or in an existing [Kubernetes](https://kubernetes.io/docs/concepts/overview/) cluster with [Helm](https://helm.sh/docs/). If you're starting from scratch, Compose gives you the shortest path: it includes the database and reverse proxy. The Helm chart fits an environment where you already manage those services.

This guide takes you from an empty installation to your first administrator account, then covers the backups and upgrades you'll need to keep it running. Both deployment options use the same Atlas image, so you can choose based on the infrastructure you're comfortable operating.

> [!NOTE]
> We're still adapting Atlas for use outside Tuist. You can deploy it without access to our infrastructure, but some application workflows still carry defaults from our operations. Review an integration's configuration and delivery destinations before enabling it for your organization.

## Before you begin

For a production installation, choose a hostname such as `atlas.example.org`. People will use this address to sign in, so it needs encrypted browser connections. [Compose](https://docs.docker.com/compose/) sets up [Caddy](https://caddyserver.com/docs/) for that purpose; with [Kubernetes](https://kubernetes.io/docs/concepts/overview/), you'll use your cluster's ingress controller and certificate.

Atlas stores its data in [PostgreSQL 18](https://www.postgresql.org/docs/18/index.html). Compose includes it, while the [Helm](https://helm.sh/docs/) chart connects to a database you provide. When sizing the host or cluster, leave room for the database and operating system as well as Atlas. The examples allow the application and migration containers up to 4 gibibytes of memory each. [Erlang](https://www.erlang.org/doc/apps/erts/erl_cmd.html) chooses the active scheduler count from the available processors and container processor quotas automatically.

Sign-in uses Google. Before inviting anyone, create a [Google application](https://developers.google.com/identity/openid-connect/openid-connect) for your organization and register `https://atlas.example.org/auth/google/callback` as an authorized redirect address, replacing the hostname with yours. Keep its client identifier and secret handy for the installation steps below. You'll also set `ATLAS_ALLOWED_EMAIL_DOMAIN` to decide who can sign in. Someone with an allowed address can create an account, but you'll grant the first administrator access separately.

You can try the public documentation without Google credentials. For a local Compose evaluation, keep the default `localhost` hostname; Caddy will use a locally issued certificate that your browser may ask you to trust.

## Choose a release

Start with an [Atlas release](https://github.com/tuist/tuist/releases?q=atlas%40) and keep its version for the rest of this guide. Wherever a command says `VERSION`, substitute that release number. Pinning a version lets you decide when to upgrade rather than taking new changes through `latest`.

Each release contains the image `ghcr.io/tuist/atlas:VERSION`, a matching [Helm](https://helm.sh/docs/) chart, and a downloadable [Compose](https://docs.docker.com/compose/) bundle. For Compose, download `atlas-compose-VERSION.tar.gz` and unpack it. Its configuration already points to the matching image.

For Helm, you can install `oci://ghcr.io/tuist/charts/atlas` from the registry or download `atlas-VERSION.tgz` from the same release. The chart's application version selects the image tag by default. The registry path uses the [Open Container Initiative distribution format](https://helm.sh/docs/topics/registries/).

## Run with Docker Compose

Once you've [installed Docker Compose](https://docs.docker.com/compose/install/) and unpacked the release bundle, open its `atlas-compose` directory. Copy the example configuration so you have a place to save your own settings:

```sh
cp .env.example .env
```

Atlas needs a database password, two signing keys, and an encryption key. Generate a fresh value for each with the commands below, and paste the results into the corresponding entries in `.env`:

```sh
openssl rand -hex 32     # POSTGRES_PASSWORD
openssl rand -hex 64     # SECRET_KEY_BASE
openssl rand -hex 64     # GUARDIAN_SECRET_KEY
openssl rand -base64 32  # ENCRYPTION_KEY
```

Keep the database password hexadecimal, as generated here, so it can safely appear in the database connection address. Treat `.env` as a secret: it holds the credentials for your installation.

In the same file, set `ATLAS_HOST` to your hostname and `ATLAS_ALLOWED_EMAIL_DOMAIN` to your organization's email domain. Add your [Google application](https://developers.google.com/identity/openid-connect/openid-connect)'s credentials as `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET`. For a public hostname, point its address records at this host and allow inbound connections on ports 80 and 443 so [Caddy](https://caddyserver.com/docs/) can obtain a certificate and serve Atlas.

You're now ready to check the configuration and start the services:

```sh
docker compose config --quiet
docker compose up -d
docker compose ps -a
```

On the first start, Compose waits for [PostgreSQL](https://www.postgresql.org/docs/18/index.html) to become healthy, runs the database migrations, and then starts Atlas. The migration service exits when it finishes; that's expected. Caddy receives browser traffic and forwards it to Atlas. Once the application is running, open your hostname and continue to [create the first administrator](#create-the-first-administrator).

The database and Caddy's certificates live in named volumes, so stopping the stack with `docker compose down` preserves them. Adding `--volumes` deletes them; use that option only when you intend to discard the installation's data.

## Run on Kubernetes

The [Helm](https://helm.sh/docs/) chart starts Atlas against an existing [PostgreSQL](https://www.postgresql.org/docs/18/index.html) database. Its default configuration uses an ordinary [Kubernetes Secret](https://kubernetes.io/docs/concepts/configuration/secret/) for application credentials, so you can install it without adding a database operator or secret manager to your cluster.

Generate the signing and encryption keys with the commands in the [Compose](https://docs.docker.com/compose/) section, then save them alongside your database connection and Google credentials in a private `atlas.env` file:

```sh
DATABASE_URL=ecto://atlas:HEX_PASSWORD@postgres.example.org:5432/atlas
SECRET_KEY_BASE=YOUR_FIRST_SIGNING_KEY
GUARDIAN_SECRET_KEY=YOUR_SECOND_SIGNING_KEY
ENCRYPTION_KEY=YOUR_BASE64_ENCRYPTION_KEY
GOOGLE_CLIENT_ID=YOUR_GOOGLE_CLIENT_ID
GOOGLE_CLIENT_SECRET=YOUR_GOOGLE_CLIENT_SECRET
```

Next, create a `values.yaml` file to tell the chart where people will reach Atlas. This example assumes you have an ingress controller named `nginx` and a certificate Secret named `atlas-tls`; replace those values with your cluster's configuration:

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

Provision the certificate Secret before installing. If you use [cert-manager](https://cert-manager.io/docs/) to issue certificates, you can set `ingress.clusterIssuer` to an existing issuer instead. The chart doesn't install an ingress controller for you.

The example enables encryption for the database connection. It is disabled in the chart's defaults for local networks, so enable it when connecting to a remote database. Atlas currently does not verify the database server's certificate; keep database access restricted to trusted networks as well.

With both files ready, create the namespace and application Secret, then install your chosen release:

```sh
kubectl create namespace atlas
kubectl --namespace atlas create secret generic atlas-app --from-env-file=atlas.env
helm upgrade --install atlas oci://ghcr.io/tuist/charts/atlas \
  --version VERSION --namespace atlas --values values.yaml --wait --timeout 10m
```

If you downloaded the chart archive, use its local `atlas-VERSION.tgz` path in place of the registry address. Each Atlas replica runs migrations in an initialization container before starting the application. When the installation completes, open your hostname and sign in to set up the first administrator.

## Create the first administrator

First, sign in with the Google account you want to use as the administrator. This creates the user that the bootstrap command will promote. Then, from the host or cluster where you installed Atlas, run the command for your deployment, replacing `person@example.org` with that user's address.

For [Compose](https://docs.docker.com/compose/):

```sh
docker compose exec -e ATLAS_BOOTSTRAP_ADMIN_EMAIL=person@example.org atlas /app/bin/bootstrap-admin
```

For [Kubernetes](https://kubernetes.io/docs/concepts/overview/), find the running Atlas pod and use its name in the second command:

```sh
kubectl --namespace atlas get pods
kubectl --namespace atlas exec POD_NAME -- env \
  ATLAS_BOOTSTRAP_ADMIN_EMAIL=person@example.org /app/bin/bootstrap-admin
```

Bootstrap is a one-time setup step available to the operator of the installation. It grants access to the existing user without creating accounts or loading demo data, and refuses to run once Atlas has been initialized. Removing an administrator later does not reopen it.

## Add services as you need them

You don't need to configure every integration to get Atlas running. Start with the workspace, then add the services required by the features you want to use. File workflows need compatible object storage; document search also needs a vector service and an embedding provider. Engineering error analytics uses [ClickHouse](https://clickhouse.com/docs).

With [Compose](https://docs.docker.com/compose/), put optional provider settings in `.env`, which is read by both the application and migration service. `MCP_PROXY_SERVERS=[]` starts with no deployment-configured upstream tool servers; you can add your own after signing in. Keep the development demo seeds out of an installation containing real data.

With [Helm](https://helm.sh/docs/), inspect the available settings for the version you're running:

```sh
helm show values oci://ghcr.io/tuist/charts/atlas --version VERSION
```

You can configure external services through the application Secret and environment values. If you'd prefer the chart to manage [PostgreSQL](https://www.postgresql.org/docs/18/index.html), its bundled database configuration requires [CloudNativePG](https://cloudnative-pg.io/documentation/). Managed secret synchronization requires [External Secrets Operator](https://external-secrets.io/), as do the chart's bundled vector storage and backup secret synchronization. These are choices you can make later; they're not prerequisites for the base installation.

## Connect upstream tool servers

Atlas can expose tools from upstream [Model Context Protocol servers](https://modelcontextprotocol.io/docs/learn/architecture) through its own authenticated `/mcp` endpoint. A fresh installation has no upstream servers. An administrator with `admin:write` access can add one at `/admin/mcps`: select **Add server**, enter a name and the server's public `https://` address, then provide its authorization and token endpoint addresses. The registration endpoint and requested authorization scopes are optional. Choose **Add server** to save it; the new server appears immediately, without restarting Atlas.

Each person who needs that server selects **Connect** on the same page and completes the upstream's [Open Authorization 2.0](https://oauth.net/2/) flow. Atlas keeps each person's authorization session separately. When a session expires or is revoked, the page offers **Reconnect**. Only tools that the upstream marks as read-only are exposed from servers added in Atlas. A server that does not mark any tools as read-only will expose none, and Atlas relies on the upstream's own classification.

The `create_mcp_server` and `delete_mcp_server` tools provide the same add and remove operations to authenticated tool clients with `admin:write` access. Creation takes the same addresses and an optional array of scopes; deletion takes the server name. Administrators with `admin:read` access can inspect the page but cannot add or remove servers, and these management tools are not available to them.

Removing a server from the page or with `delete_mcp_server` removes its saved authorization sessions for all users. Re-adding it requires each user to connect again. Names supplied by deployment configuration cannot be removed through the page or tools. Shared credentials, custom request headers, and privileged identity headers remain deployment settings rather than administrator-managed options.

If you are upgrading an installation that relied on Atlas implicitly loading Tuist's upstream servers when `MCP_PROXY_SERVERS` was unset, set `MCP_PROXY_SERVERS=tuist-managed` before upgrading to preserve those servers. Tuist's managed production deployment already sets this value explicitly. Other installations can keep `MCP_PROXY_SERVERS=[]` and add servers at runtime, or supply a server list through deployment configuration when they need options that the page does not offer.

## Backups and upgrades

Before putting real data into Atlas, decide how you'll back up [PostgreSQL](https://www.postgresql.org/docs/18/index.html) and any object storage you enable, and test restoring them into an isolated installation. Save the deployment configuration and credentials securely too. In particular, keep `ENCRYPTION_KEY` with your backups: without it, Atlas cannot decrypt saved integration credentials, even if you restore the database.

Before an upgrade, take a fresh backup and read the release's migration notes. For [Compose](https://docs.docker.com/compose/), stop the application, change `ATLAS_VERSION` in `.env` to the new release, then pull the images and run migrations before starting it again:

```sh
docker compose stop atlas
docker compose pull
docker compose run --rm migrate
docker compose up -d --force-recreate migrate atlas
```

For [Helm](https://helm.sh/docs/), repeat the installation command with the new `--version`. Keep in mind that returning to an older image does not reverse database migrations. Check their compatibility before using a Helm rollback.

## Keep the installation healthy

If you need to override Erlang's automatic scheduler sizing, set `ERL_FLAGS` in Compose's `.env` or `env.ERL_FLAGS` in Helm values. For example, `+S 2:2` selects two schedulers. Leave the setting unset to use the resources available to the container.

Use `/ready` to check that the web server is answering. Private container probes can reach it directly because it bypasses the production redirect to an encrypted connection. That check doesn't query [PostgreSQL](https://www.postgresql.org/docs/18/index.html), so monitor database connectivity and capacity separately, along with background job failures.

Keep browser traffic behind [Caddy](https://caddyserver.com/docs/) or your ingress controller rather than exposing Atlas's port 4000 to the internet. Configure rate limits at that edge for the application and public documentation. Atlas emits a response classification header that Tuist uses for its own rate limits, but the header alone does not apply limits to your installation.
