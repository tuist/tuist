---
{
  "title": "Installation",
  "titleTemplate": ":title | Self-hosting | Server | Guides | Tuist",
  "description": "Learn how to install Tuist on your infrastructure."
}
---
# Self-host installation {#self-host-installation}

We offer a self-hosted version of the Tuist server for organizations that require more control over their infrastructure. This version allows you to host Tuist on your own infrastructure, ensuring that your data remains secure and private.

> [!WARNING]
> **License Required**
>
> Self-hosting Tuist requires a legally valid paid license. The on-premise version of Tuist is available only for organizations on the Enterprise plan. If you are interested in this version, please reach out to [contact@tuist.dev](mailto:contact@tuist.dev).


## Release cadence {#release-cadence}

We release new versions of Tuist continuously as new releasable changes land on main. We follow [semantic versioning](https://semver.org/) to ensure predictable versioning and compatibility.

The major component is used to flag breaking changes in the Tuist server that will require coordination with the on-premise users. You should not expect us to use it, and in case we needed, rest assured we'll work with you in making the transition smooth.

## Continuous deployment {#continuous-deployment}

We strongly recommend setting up a continuous deployment pipeline that automatically deploys the latest version of Tuist every day. This ensures you always have access to the latest features, improvements, and security updates.

Here's an example GitHub Actions workflow that checks for and deploys new versions daily:

```yaml
name: Update Tuist Server
on:
  schedule:
    - cron: '0 3 * * *' # Run daily at 3 AM UTC
  workflow_dispatch: # Allow manual runs

jobs:
  update:
    runs-on: ubuntu-latest
    steps:
      - name: Check and deploy latest version
        run: |
          # Your deployment commands here
          # Example: docker pull ghcr.io/tuist/tuist:latest
          # Deploy to your infrastructure
```

## Runtime requirements {#runtime-requirements}

This section outlines the requirements for hosting the Tuist server on your infrastructure.

### Compatibility matrix {#compatibility-matrix}

Tuist server has been tested and is compatible with the following minimum versions:

| Component | Minimum Version | Notes |
| --- | --- | --- |
| PostgreSQL | 15 | |
| ClickHouse | 25 | Required for analytics |

### Running Docker-virtualized images {#running-dockervirtualized-images}

We distribute the server as a [Docker](https://www.docker.com/) image via [GitHub’s Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry).

To run it, your infrastructure must support running Docker images. Note that most infrastructure providers support it because it’s become the standard container for distributing and running software in production environments.

### Postgres database {#postgres-database}

In addition to running the Docker images, you'll need a [Postgres database](https://www.postgresql.org/) to store relational data. Most infrastructure providers include Postgres databases in their offering (e.g., [AWS](https://aws.amazon.com/rds/postgresql/) & [Google Cloud](https://cloud.google.com/sql/docs/postgres)).

> [!NOTE]
> **Migrations**
>
> The Docker image's entrypoint automatically runs any pending schema migrations before starting the service.


### ClickHouse database {#clickhouse-database}

Tuist uses [ClickHouse](https://clickhouse.com/) for storing and querying large amounts of analytics data. ClickHouse is **required** for features like build insights. You can choose whether to self-host ClickHouse or use their hosted service.

> [!NOTE]
> **Migrations**
>
> The Docker image's entrypoint automatically runs any pending ClickHouse schema migrations before starting the service.


### Storage {#storage}

You’ll also need a solution to store files (e.g. framework and library binaries). Currently we support any storage that's S3-compliant.

> [!TIP]
> **Optimized Caching**
>
> If your goal is primarily to bring your own bucket for storing binaries and reduce cache latency, you might not need to self-host the whole server. You can self-host cache nodes and connect them to the hosted Tuist server or your self-hosted server.
>
> See the <.localized_link href="/guides/cache/self-host">cache self-hosting guide</.localized_link>.


### Self-hosted cache nodes {#self-hosted-cache-nodes}

To use self-hosted cache nodes with a self-hosted Tuist server:

1. Deploy your cache nodes following the <.localized_link href="/guides/cache/self-host">cache self-hosting guide</.localized_link>.
2. Set `TUIST_CACHE_ENDPOINTS` to a comma-separated list of cache node URLs (for example, `https://cache-1.example.com,https://cache-2.example.com`).

## Configuration {#configuration}

The configuration of the service is done at runtime through environment variables. Given the sensitive nature of these variables, we advise encrypting and storing them in secure password management solutions. Rest assured, Tuist handles these variables with utmost care, ensuring they are never displayed in logs.

> [!NOTE]
> **Launch Checks**
>
> The necessary variables are verified at startup. If any are missing, the launch will fail and the error message will detail the absent variables.


### License configuration {#license-configuration}

As an on-premise user, you'll receive a license key that you'll need to expose as an environment variable. This key is used to validate the license and ensure that the service is running within the terms of the agreement.

| Environment variable | Description | Required | Default | Example |
| --- | --- | --- | --- | --- |
| `TUIST_LICENSE` | The license provided after signing the service level agreement | Yes* | | `******` |
| `TUIST_LICENSE_CERTIFICATE_BASE64` | **Exceptional alternative to `TUIST_LICENSE`**. Base64-encoded public certificate for offline license validation in air-gapped environments where the server cannot contact external services. Only use when `TUIST_LICENSE` cannot be used | Yes* | | `LS0tLS1CRUdJTiBDRVJUSUZJQ0FURS0tLS0t...` |

\* Either `TUIST_LICENSE` or `TUIST_LICENSE_CERTIFICATE_BASE64` must be provided, but not both. Use `TUIST_LICENSE` for standard deployments.

> [!WARNING]
> **Expiration Date**
>
> Licenses have an expiration date. Users will receive a warning while using Tuist commands that interact with the server if the license expires in less than 30 days. If you are interested in renewing your license, please reach out to [contact@tuist.dev](mailto:contact@tuist.dev).


### Base environment configuration {#base-environment-configuration}

| Environment variable | Description | Required | Default | Example |
| --- | --- | --- | --- | --- |
| `TUIST_APP_URL` | The base URL to access the instance from the Internet | Yes | | https://tuist.dev |
| `TUIST_SECRET_KEY_BASE` | The key to use to encrypt information (e.g. sessions in a cookie) | Yes | | | `c5786d9f869239cbddeca645575349a570ffebb332b64400c37256e1c9cb7ec831345d03dc0188edd129d09580d8cbf3ceaf17768e2048c037d9c31da5dcacfa` |
| `TUIST_SECRET_KEY_PASSWORD` | Pepper to generate hashed passwords | No | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_TOKENS` | Secret key to generate random tokens | No | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_ENCRYPTION` | 32-byte key for AES-GCM encryption of sensitive data | No | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_USE_IPV6` | When `1` it configures the app to use IPv6 addresses | No | `0` | `1`|
| `TUIST_LOG_LEVEL` | The log level to use for the app | No | `info` | [Log levels](https://hexdocs.pm/logger/1.12.3/Logger.html#module-levels) |
| `TUIST_GITHUB_APP_NAME` | The URL version of your GitHub app name | No | | `my-app` |
| `TUIST_GITHUB_APP_PRIVATE_KEY_BASE64` | The base64-encoded private key used for the GitHub app to unlock extra functionality such as posting automatic PR comments | No | `LS0tLS1CRUdJTiBSU0EgUFJJVkFUR...` | |
| `TUIST_GITHUB_APP_PRIVATE_KEY` | The private key used for the GitHub app to unlock extra functionality such as posting automatic PR comments. **We recommend using the base64-encoded version instead to avoid issues with special characters** | No | `-----BEGIN RSA...` | |
| `TUIST_OPS_USER_HANDLES` | A comma-separated list of user handles that have access to the operations URLs | No | | `user1,user2` |
| `TUIST_SERVER_VERSION_IDENTIFIER` | A label displayed as a badge in the dashboard navbar to identify the server instance (e.g. a version number or branch name) | No | Git branch in dev | `v1.2.3` |
| `TUIST_WEB` | Enable the web server endpoint | No | `1` | `1` or `0` |
| `TUIST_OTEL_EXPORTER_OTLP_ENDPOINT` | The gRPC endpoint of an OpenTelemetry Collector to send traces to | No | | `http://localhost:4317` |
| `TUIST_LOKI_URL` | The base URL of a Loki-compatible endpoint to push logs to (e.g. Grafana Alloy or Loki) | No | | `http://localhost:3100` |

### Database configuration {#database-configuration}

The following environment variables are used to configure the database connection:

| Environment variable | Description | Required | Default | Example |
| --- | --- | --- | --- | --- |
| `DATABASE_URL` | The URL to access the Postgres database. Note that the URL should contain the authentication information | Yes | | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_CLICKHOUSE_URL` | The URL to access the ClickHouse database. Note that the URL should contain the authentication information | No | | `http://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_USE_SSL_FOR_DATABASE` | When true, it uses [SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security) to connect to the database | No | `1` | `1` |
| `TUIST_DATABASE_POOL_SIZE` | The number of connections to keep open in the connection pool | No | `10` | `10` |
| `TUIST_DATABASE_QUEUE_TARGET` | The interval (in miliseconds) for checking if all the connections checked out from the pool took more than the queue interval [(More information)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | No | `300` | `300` |
| `TUIST_DATABASE_QUEUE_INTERVAL` | The threshold time (in miliseconds) in the queue that the pool uses to determine if it should start dropping new connections [(More information)](https://hexdocs.pm/db_connection/DBConnection.html#start_link/2-queue-config) | No | `1000` | `1000` |
| `TUIST_CLICKHOUSE_FLUSH_INTERVAL_MS` | Time interval in milliseconds between ClickHouse buffer flushes | No | `5000` | `5000` |
| `TUIST_CLICKHOUSE_MAX_BUFFER_SIZE` | Maximum ClickHouse buffer size in bytes before forcing a flush | No | `1000000` | `1000000` |
| `TUIST_CLICKHOUSE_BUFFER_POOL_SIZE` | Number of ClickHouse buffer processes to run | No | `5` | `5` |

### Authentication environment configuration {#authentication-environment-configuration}

We facilitate authentication through [identity providers (IdP)](https://en.wikipedia.org/wiki/Identity_provider). To utilize this, ensure all necessary environment variables for the chosen provider are present in the server's environment. **Missing variables** will result in Tuist bypassing that provider.

#### GitHub {#github}

We recommend authenticating using a [GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps) but you can also use the [OAuth App](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app). Make sure to include all essential environment variables specified by GitHub in the server environment. Absent variables will cause Tuist to overlook the GitHub authentication. To properly set up the GitHub app:
- In the GitHub app's general settings:
    - Copy the `Client ID` and set it as `TUIST_GITHUB_APP_CLIENT_ID`
    - Create and copy a new `client secret` and set it as `TUIST_GITHUB_APP_CLIENT_SECRET`
    - Set the `Callback URL` as `http://YOUR_APP_URL/users/auth/github/callback`. `YOUR_APP_URL` can also be your server's IP address.
- The following permissions are required:
  - Repositories:
    - Pull requests: Read and write
  - Accounts:
    - Email addresses: Read-only

In the `Permissions and events`'s `Account permissions` section, set the `Email addresses` permission to `Read-only`.

You'll then need to expose the following environment variables in the environment where the Tuist server runs:

| Environment variable | Description | Required | Default | Example |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_APP_CLIENT_ID` | The client ID of the GitHub application | Yes | | `Iv1.a629723000043722` |
| `TUIST_GITHUB_APP_CLIENT_SECRET` | The client secret of the application | Yes | | `232f972951033b89799b0fd24566a04d83f44ccc` |

#### Google {#google}

You can set up authentication with Google using [OAuth 2](https://developers.google.com/identity/protocols/oauth2). For that, you'll need to create a new credential of type OAuth client ID. When creating the credentials, select "Web Application" as application type, name it `Tuist`, and set the redirect URI to `{base_url}/users/auth/google/callback` where `base_url` is the URL your hosted-service is running at. Once you create the app, copy the client ID and secret and set them as environment variables `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` respectively.

> [!NOTE]
> **Consent Screen Scopes**
>
> You might need to create a consent screen. When you do so, make sure to add the `userinfo.email` and `openid` scopes and mark the app as internal.


#### Okta {#okta}

You can enable authentication with Okta through the [OAuth 2.0](https://oauth.net/2/) protocol. You'll have to [create an app](https://developer.okta.com/docs/en/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta) on Okta following <.localized_link href="/guides/integrations/sso#okta">these instructions</.localized_link>.

You will need to set the following environment variables once you obtain the client id and secret during the set up of the Okta application:

| Environment variable | Description | Required | Default | Example |
| --- | --- | --- | --- | --- |
| `TUIST_OKTA_1_CLIENT_ID` | The client ID to authenticate against Okta. The number should be your organization ID | Yes | | |
| `TUIST_OKTA_1_CLIENT_SECRET` | The client secret to authenticate against Okta | Yes | | |

The number `1` needs to be replaced with your organization ID. This will typically be 1, but check in your database.

### Storage environment configuration {#storage-environment-configuration}

 Tuist needs storage to house artifacts uploaded through the API. It's **essential to configure one of the supported storage solutions** for Tuist to operate effectively.

#### S3-compliant storages {#s3compliant-storages}

You can use any S3-compliant storage provider to store artifacts. The following environment variables are required to authenticate and configure the integration with the storage provider:

| Environment variable | Description | Required | Default | Example |
| --- | --- | --- | --- | --- |
| `TUIST_S3_ACCESS_KEY_ID` or `AWS_ACCESS_KEY_ID` | The access key ID to authenticate against the storage provider | Yes | | `AKIAIOSFOD` |
| `TUIST_S3_SECRET_ACCESS_KEY` or `AWS_SECRET_ACCESS_KEY` | The secret access key to authenticate against the storage provider | Yes | | `wJalrXUtnFEMI/K7MDENG/bPxRfiCYEXAMPLEKEY` |
| `TUIST_S3_REGION` or `AWS_REGION` | The region where the bucket is located | No | `auto` | `us-west-2` |
| `TUIST_S3_ENDPOINT` or `AWS_ENDPOINT` | The endpoint of the storage provider | Yes | | `https://s3.us-west-2.amazonaws.com` |
| `TUIST_S3_BUCKET_NAME` | The name of the bucket where the artifacts will be stored | Yes | | `tuist-artifacts` |
| `TUIST_S3_CA_CERT_PEM` | PEM-encoded CA certificate for verifying S3 HTTPS connections. Useful for air-gapped environments with self-signed certificates or internal Certificate Authorities. | No | System CA bundle | `-----BEGIN CERTIFICATE-----\n...\n-----END CERTIFICATE-----` |
| `TUIST_S3_CONNECT_TIMEOUT` | The timeout (in milliseconds) for establishing a connection to the storage provider | No | `3000` | `3000` |
| `TUIST_S3_RECEIVE_TIMEOUT` | The timeout (in milliseconds) for receiving data from the storage provider | No | `5000` | `5000` |
| `TUIST_S3_POOL_TIMEOUT` | The timeout (in milliseconds) for the connection pool to the storage provider. Use `infinity` for no timeout | No | `5000` | `5000` |
| `TUIST_S3_POOL_MAX_IDLE_TIME` | The maximum idle time (in milliseconds) for connections in the pool. Use `infinity` to keep connections alive indefinitely | No | `infinity` | `60000` |
| `TUIST_S3_POOL_SIZE` | The maximum number of connections per pool | No | `500` | `500` |
| `TUIST_S3_POOL_COUNT` | The number of connection pools to use | No | Number of system schedulers | `4` |
| `TUIST_S3_PROTOCOL` | The protocol to use when connecting to the storage provider (`http1` or `http2`) | No | `http1` | `http1` |
| `TUIST_S3_VIRTUAL_HOST` | Whether the URL should be constructed with the bucket name as a sub-domain (virtual host) | No | `false` | `1` |

> [!NOTE]
> **Aws Authentication With Web Identity Token From Environment Variables**
>
> If your storage provider is AWS and you'd like to authenticate using a web identity token, you can set the environment variable `TUIST_S3_AUTHENTICATION_METHOD` to `aws_web_identity_token_from_env_vars`, and Tuist will use that method using the conventional AWS environment variables.


#### Google Cloud Storage {#google-cloud-storage}
For Google Cloud Storage, follow [these docs](https://cloud.google.com/storage/docs/authentication/managing-hmackeys) to get the `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` pair. The `AWS_ENDPOINT` should be set to `https://storage.googleapis.com`. Other environment variables are the same as for any other S3-compliant storage.

### Email configuration {#email-configuration}

Tuist requires email functionality for user authentication and transactional notifications (e.g., password resets, account notifications). Currently, **only Mailgun is supported** as the email provider.

| Environment variable | Description | Required | Default | Example |
| --- | --- | --- | --- | --- |
| `TUIST_MAILGUN_API_KEY` | The API key for authenticating with Mailgun | Yes* | | `key-1234567890abcdef` |
| `TUIST_MAILING_DOMAIN` | The domain from which emails will be sent | Yes* | | `mg.tuist.io` |
| `TUIST_MAILING_FROM_ADDRESS` | The email address that will appear in the "From" field | Yes* | | `noreply@tuist.io` |
| `TUIST_MAILING_REPLY_TO_ADDRESS` | Optional reply-to address for user replies | No | | `support@tuist.dev` |
| `TUIST_SKIP_EMAIL_CONFIRMATION` | Skip email confirmation for new user registrations. When enabled, users are automatically confirmed and can log in immediately after registration | No | `true` if email not configured, `false` if email is configured | `true`, `false`, `1`, `0` |

\* Email configuration variables are required only if you want to send emails. If not configured, email confirmation is automatically skipped

> [!NOTE]
> **Smtp Support**
>
> Generic SMTP support is not currently available. If you need SMTP support for your on-premise deployment, please reach out to [contact@tuist.dev](mailto:contact@tuist.dev) to discuss your requirements.


> [!NOTE]
> **Air-gapped Deployments**
>
> For on-premise installations without internet access or email provider configuration, email confirmation is automatically skipped by default. Users can log in immediately after registration. If you have email configured but still want to skip confirmation, set `TUIST_SKIP_EMAIL_CONFIRMATION=true`. To require email confirmation when email is configured, set `TUIST_SKIP_EMAIL_CONFIRMATION=false`.


### Git platform configuration {#git-platform-configuration}

Tuist can <.localized_link href="/guides/server/authentication">integrate with Git platforms</.localized_link> to provide extra features such as automatically posting comments in your pull requests.

#### GitHub {#platform-github}

You will need to [create a GitHub app](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps). You can reuse the one you created for authentication, unless you created an OAuth GitHub app. In the `Permissions and events`'s `Repository permissions` section, you will need to additionally set the `Pull requests` permission to `Read and write`.

On top of the `TUIST_GITHUB_APP_CLIENT_ID` and `TUIST_GITHUB_APP_CLIENT_SECRET`, you will need the following environment variables:

| Environment variable | Description | Required | Default | Example |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_APP_PRIVATE_KEY` | The private key of the GitHub application | Yes | | `-----BEGIN RSA PRIVATE KEY-----...` |

## Testing Locally {#testing-locally}

We provide a comprehensive Docker Compose configuration that includes all required dependencies for testing Tuist server on your local machine before deploying to your infrastructure:

- PostgreSQL 15
- ClickHouse 25 for analytics
- ClickHouse Keeper for coordination
- MinIO for S3-compatible storage
- Redis for persistent KV storage across deploys (optional)
- pgweb for database administration

> [!CAUTION]
> **License Required**
>
> A valid `TUIST_LICENSE` environment variable is legally required to run the Tuist server, including local development instances. If you need a license, please reach out to [contact@tuist.dev](mailto:contact@tuist.dev).


**Quick Start:**

1. Download the configuration files:
   ```bash
   curl -O https://docs.tuist.io/server/self-host/docker-compose.yml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-config.xml
   curl -O https://docs.tuist.io/server/self-host/clickhouse-keeper-config.xml
   curl -O https://docs.tuist.io/server/self-host/.env.example
   ```

2. Configure environment variables:
   ```bash
   cp .env.example .env
   # Edit .env and add your TUIST_LICENSE and authentication credentials
   ```

3. Start all services:
   ```bash
   docker compose up -d
   # or with podman:
   podman compose up -d
   ```

4. Access the server at http://localhost:8080

**Service Endpoints:**
- Tuist Server: http://localhost:8080
- MinIO Console: http://localhost:9003 (credentials: `tuist` / `tuist_dev_password`)
- MinIO API: http://localhost:9002
- pgweb (PostgreSQL UI): http://localhost:8081
- Prometheus Metrics: http://localhost:9091/metrics
- ClickHouse HTTP: http://localhost:8124

**Common Commands:**

Check service status:
```bash
docker compose ps
# or: podman compose ps
```

View logs:
```bash
docker compose logs -f tuist
```

Stop services:
```bash
docker compose down
```

Reset everything (deletes all data):
```bash
docker compose down -v
```

**Configuration Files:**
- [docker-compose.yml](/server/self-host/docker-compose.yml) - Complete Docker Compose configuration
- [clickhouse-config.xml](/server/self-host/clickhouse-config.xml) - ClickHouse configuration
- [clickhouse-keeper-config.xml](/server/self-host/clickhouse-keeper-config.xml) - ClickHouse Keeper configuration
- [.env.example](/server/self-host/.env.example) - Example environment variables file

## Kubernetes with Helm {#kubernetes-with-helm}

Tuist provides an official Helm chart for deploying on Kubernetes. The chart packages the Tuist server and cache service, along with embedded infrastructure dependencies that you can swap for external providers as needed.

### Installing the chart {#installing-the-chart}

```bash
helm install tuist oci://ghcr.io/tuist/charts/tuist \
  --set server.license.key="YOUR_LICENSE_KEY"
```

To pin a specific chart version:

```bash
helm install tuist oci://ghcr.io/tuist/charts/tuist \
  --set server.license.key="YOUR_LICENSE_KEY" \
  --version 0.1.0
```

### Infrastructure dependencies {#helm-infrastructure-dependencies}

The chart manages three infrastructure dependencies: `postgresql`, `clickhouse`, and `objectStorage`. Each defaults to **embedded** mode, meaning the chart deploys them inside the cluster. To point at your own external instances instead, set the dependency's `mode` to `external` and fill in the connection details in your `values.yaml`. For example, to use an external PostgreSQL database:

```yaml
# values.yaml
postgresql:
  mode: external
  external:
    host: your-db-host
    port: 5432
    database: tuist
    username: tuist
    password: your-password
```

The same pattern applies to `clickhouse` and `objectStorage`. See the `external` block under each section in the chart's `values.yaml` for the full set of configurable fields.

### Shared scheduling and labels {#helm-shared-scheduling-and-labels}

The chart exposes a small set of shared pod settings under `global` so operators can adapt the deployment to their cluster without repeating the same values for every workload:

```yaml
global:
  podLabels:
    environment: production
  imagePullSecrets:
    - name: ghcr-pull-secret
  nodeSelector:
    nodepool: apps
  tolerations:
    - key: dedicated
      operator: Equal
      value: apps
      effect: NoSchedule
```

Use these settings when you need to:

- add cluster-specific labels to every pod
- pull mirrored images from a private registry
- target a dedicated node pool
- allow pods onto tainted nodes reserved for Tuist workloads

### Workload identity and service accounts {#helm-workload-identity}

The chart scopes service accounts per application workload so you can grant identity only where it is needed:

- `server.serviceAccount` applies to the Tuist server deployment and migration job
- `cache.serviceAccount` applies to the cache deployment

For example, when the cache uses an external S3 bucket on EKS, you can enable IRSA for the cache workload without also attaching the same IAM role to the embedded databases:

```yaml
cache:
  serviceAccount:
    create: true
    annotations:
      eks.amazonaws.com/role-arn: arn:aws:iam::123456789012:role/tuist-cache
```

### Compatibility overrides {#helm-compatibility-overrides}

The chart keeps storage- and mesh-specific tweaks opt-in so the defaults stay portable:

```yaml
cache:
  podSecurityContext:
    fsGroup: 990

clickhouse:
  embedded:
    service:
      nativePort: 9100
```

Use these overrides only when your cluster requires them:

- `cache.podSecurityContext` is empty by default. Set `fsGroup` if your storage class or CSI driver needs shared group ownership on mounted volumes.
- `clickhouse.embedded.service.nativePort` defaults to ClickHouse's standard `9000` native service port and can be changed when a service mesh or platform reserve conflicts with that port.

### Observability {#helm-observability}

The chart includes an optional observability stack (OpenTelemetry Collector, Prometheus, Grafana, Loki, and Tempo). It is **disabled by default**. To enable it in your `values.yaml`:

```yaml
# values.yaml
observability:
  enabled: true
```

When enabled, Grafana is available with Logs, Traces, and Metrics drilldowns pre-configured. For external observability, keep this disabled and configure the endpoints via `server.extraEnv`:

```yaml
# values.yaml
server:
  extraEnv:
    - name: TUIST_OTEL_EXPORTER_OTLP_ENDPOINT
      value: "http://your-otel-collector:4317"
    - name: TUIST_LOKI_URL
      value: "http://your-loki:3100"
```

### Values reference {#helm-values-reference}

For the full list of configurable values, see the chart's [`values.yaml`](https://github.com/tuist/tuist/blob/main/infra/helm/tuist/values.yaml).

## Deployment {#deployment}

The official Tuist Docker image is available at:
```
ghcr.io/tuist/tuist
```

The published image includes embedded Linux build processing for `.xcactivitylog` archives, so self-hosted deployments can process builds without running any additional service — the `ProcessBuildWorker` Oban job runs in-process on each server pod. If you want to offload build processing to a dedicated replica set (for example, to scale parse throughput independently of the web tier), set `processor.enabled: true` in the Helm chart: the chart deploys the same image as a queue-only consumer (`TUIST_PROCESSOR_MODE=true`). See [`values.yaml`](https://github.com/tuist/tuist/blob/main/infra/helm/tuist/values.yaml) for the full set of knobs.

> [!NOTE]
> `.xcresult` parsing leans on `xcresulttool` from Xcode, so the worker that consumes `:process_xcresult` only runs on macOS. On a self-hosted deployment running on Linux nothing claims the queue and `tuist test` results aren't ingested. To enable test result ingestion, run a macOS host that boots the same `tuist` release with `TUIST_XCRESULT_PROCESSOR_MODE=1`, points at the same Postgres, and consumes the `:process_xcresult` queue — that pod becomes the dedicated xcresult processor. The managed cloud deploys this on Scaleway Mac minis (Hetzner has no macOS workers); see [`xcode_processor/`](https://github.com/tuist/tuist/tree/main/xcode_processor) for the deploy tooling.

### Pulling the Docker image {#pulling-the-docker-image}

You can retrieve the image by executing the following command:

```bash
docker pull ghcr.io/tuist/tuist:latest
```

Or pull a specific version:
```bash
docker pull ghcr.io/tuist/tuist:0.1.0
```

### Deploying the Docker image {#deploying-the-docker-image}

The deployment process for the Docker image will differ based on your chosen cloud provider and your organization's continuous deployment approach. Since most cloud solutions and tools, like [Kubernetes](https://kubernetes.io/), utilize Docker images as fundamental units, the examples in this section should align well with your existing setup.

> [!WARNING]
> If your deployment pipeline needs to validate that the server is up and running, you can send a `GET` HTTP request to `/ready` and assert a `200` status code in the response.


#### Fly {#fly}

To deploy the app on [Fly](https://fly.io/), you'll require a `fly.toml` configuration file. Consider generating it dynamically within your Continuous Deployment (CD) pipeline. Below is a reference example for your use:

```toml
app = "tuist"
primary_region = "fra"
kill_signal = "SIGINT"
kill_timeout = "5s"

[experimental]
  auto_rollback = true

[env]
  # Your environment configuration goes here
  # Or exposed through Fly secrets

[processes]
  app = "/usr/local/bin/hivemind /app/Procfile"

[[services]]
  protocol = "tcp"
  internal_port = 8080
  auto_stop_machines = false
  auto_start_machines = false
  processes = ["app"]
  http_options = { h2_backend = true }

  [[services.ports]]
    port = 80
    handlers = ["http"]
    force_https = true

  [[services.ports]]
    port = 443
    handlers = ["tls", "http"]
  [services.concurrency]
    type = "connections"
    hard_limit = 100
    soft_limit = 80

  [[services.http_checks]]
    interval = 10000
    grace_period = "10s"
    method = "get"
    path = "/ready"
    protocol = "http"
    timeout = 2000
    tls_skip_verify = false
    [services.http_checks.headers]

[[statics]]
  guest_path = "/app/public"
  url_prefix = "/"
```

Then you can run `fly launch --local-only --no-deploy` to launch the app. On subsequent deploys, instead of running `fly launch --local-only`, you will need to run `fly deploy --local-only`. Fly.io doesn't allow to pull private Docker images, which is why we need to use the `--local-only` flag.


## Prometheus metrics {#prometheus-metrics}

Tuist exposes Prometheus metrics at `/metrics` to help you monitor your self-hosted instance. These metrics include:

### Finch HTTP client metrics {#finch-metrics}

Tuist uses [Finch](https://github.com/sneako/finch) as its HTTP client and exposes detailed metrics about HTTP requests:

#### Request metrics
- `tuist_prom_ex_finch_request_count_total` - Total number of Finch requests (counter)
  - Labels: `finch_name`, `method`, `scheme`, `host`, `port`, `status`
- `tuist_prom_ex_finch_request_duration_milliseconds` - Duration of HTTP requests (histogram)
  - Labels: `finch_name`, `method`, `scheme`, `host`, `port`, `status`
  - Buckets: 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s, 10s
- `tuist_prom_ex_finch_request_exception_count_total` - Total number of Finch request exceptions (counter)
  - Labels: `finch_name`, `method`, `scheme`, `host`, `port`, `kind`, `reason`

#### Connection pool queue metrics
- `tuist_prom_ex_finch_queue_duration_milliseconds` - Time spent waiting in the connection pool queue (histogram)
  - Labels: `finch_name`, `scheme`, `host`, `port`, `pool`
  - Buckets: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s
- `tuist_prom_ex_finch_queue_idle_time_milliseconds` - Time the connection spent idle before being used (histogram)
  - Labels: `finch_name`, `scheme`, `host`, `port`, `pool`
  - Buckets: 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 5s, 10s
- `tuist_prom_ex_finch_queue_exception_count_total` - Total number of Finch queue exceptions (counter)
  - Labels: `finch_name`, `scheme`, `host`, `port`, `kind`, `reason`

#### Connection metrics
- `tuist_prom_ex_finch_connect_duration_milliseconds` - Time spent establishing a connection (histogram)
  - Labels: `finch_name`, `scheme`, `host`, `port`, `error`
  - Buckets: 10ms, 50ms, 100ms, 250ms, 500ms, 1s, 2.5s, 5s
- `tuist_prom_ex_finch_connect_count_total` - Total number of connection attempts (counter)
  - Labels: `finch_name`, `scheme`, `host`, `port`

#### Send metrics
- `tuist_prom_ex_finch_send_duration_milliseconds` - Time spent sending the request (histogram)
  - Labels: `finch_name`, `method`, `scheme`, `host`, `port`, `error`
  - Buckets: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms, 1s
- `tuist_prom_ex_finch_send_idle_time_milliseconds` - Time the connection spent idle before sending (histogram)
  - Labels: `finch_name`, `method`, `scheme`, `host`, `port`, `error`
  - Buckets: 1ms, 5ms, 10ms, 25ms, 50ms, 100ms, 250ms, 500ms

All histogram metrics provide `_bucket`, `_sum`, and `_count` variants for detailed analysis.

### Other metrics

In addition to Finch metrics, Tuist exposes metrics for:
- BEAM virtual machine performance
- Custom business logic metrics (storage, accounts, projects, etc.)
- Database performance (when using Tuist-hosted infrastructure)

## Operations {#operations}

Tuist provides a set of utilities under `/ops/` that you can use to manage your instance.

> [!WARNING]
> **Authorization**
>
> Only people whose handles are listed in the `TUIST_OPS_USER_HANDLES` environment variable can access the `/ops/` endpoints.


- **Errors (`/ops/errors`):** You can view unexpected errors that ocurred in the application. This is useful for debugging and understanding what went wrong and we might ask you to share this information with us if you're facing issues.
- **Dashboard (`/ops/dashboard`):** You can view a dashboard that provides insights into the application's performance and health (e.g. memory consumption, processes running, number of requests). This dashboard can be quite useful to understand if the hardware you're using is enough to handle the load.
