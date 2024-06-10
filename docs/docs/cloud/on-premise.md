---
title: On premise
titleTemplate: ':title - Tuist Cloud'
description: Learn how to host Tuist Cloud on your own infrastructure.
---

# On premise

We offer a self-hosted version of Tuist Cloud for organizations that require more control over their infrastructure. This version allows you to host Tuist Cloud on your own infrastructure, ensuring that your data remains secure and private.

If you signed an agreement with us to use Tuist Cloud on-premise, you can follow the instructions below to set up your environment.

## Release cadence

Tuist Cloud is **released every Monday** and the version name follows the convention name `{MAJOR}.YY.MM.DD`. The date component is used to warn the CLI user if their hosted version is 60 days older than the release date of the CLI. It's crucial that on-premise organizations keep up with Tuist Cloud updates to ensure their developers benefit from the most recent improvements and that we can drop deprecated features with the confidence that we are not breaking any of the on-premise setups.

The major component of the CLI is used to flag breaking changes in Tuist Cloud that will require coordination with the on-premise users. You should not expect us to use it, and in case we needed, rest asure we'll work with you in making the transition smooth.

> [!NOTE] RELEASE NOTES
> You'll be given access to a `tuist/cloud-on-premise` repository associated with the registry where images are published. Every new released will be published in that repository as a GitHub release and will contain release notes to inform you about what changes come with it.

## Runtime requirements

This section outlines the requirements for hosting Tuist Cloud on your infrastructure.

### Running Docker-virtualized images

We distribute Tuist Cloud as a [Docker](https://www.docker.com/) image via [GitHub’s Container Registry](https://docs.github.com/en/packages/working-with-a-github-packages-registry/working-with-the-container-registry). 

<!-- We utilize GitHub’s Container Registry to synchronize the authorization for registry access with access to this repository. In essence, if you have access to this repository, you can download the Tuist Cloud Enterprise images. -->

To run it, your infrastructure must support running Docker images. Note that most infrastructure providers support it because it’s become the standard container for distributing and running software in production environments.

### Postgres database

In addition to running the Docker images, you’ll need a [Postgres database](https://www.postgresql.org/) to store relational data. Most infrastructure providers include Posgres databases in their offering (e.g., [AWS](https://aws.amazon.com/rds/postgresql/) & [Google Cloud](https://cloud.google.com/sql/docs/postgres)).

For performant analytics, we use a [Timescale Postgres extension](https://www.timescale.com/). You need to make sure that TimescaleDB is installed on the machine running the Postgres database. Follow the installation instructions [here](https://docs.timescale.com/self-hosted/latest/install/) to learn more. If you are unable to install the Timescale extension, you can set up your own dashboard using the Prometheus metrics.

> [!INFO] MIGRATIONS
> The Docker image's entrypoint automatically runs any pending schema migrations before starting the service.

### Storage

You’ll also need a solution to store files (e.g. framework and library binaries). Currently we support any storage that's S3-compliant.

## Configuration

The configuration of the service is done at runtime through environment variables. Given the sensitive nature of these variables, we advise encrypting and storing them in secure password management solutions. Rest assured, Tuist Cloud handles these variables with utmost care, ensuring they are never displayed in logs.

> [!NOTE] LAUNCH CHECKS
> The necessary variables are verified at startup. If any are missing, the launch will fail and the error message will detail the absent variables.

### License configuration

As an on-premise user, you'll receive a license key that you'll need to expose as an environment variable. This key is used to validate the license and ensure that the service is running within the terms of the agreement.

| Environment variable | Description | Required | Default | Example |
| --- | --- | --- | --- | --- |
| `TUIST_LICENSE` | The license provided after signing the service level agreement | Yes | | `******` |

> [!IMPORTANT] EXPIRATION DATE
> Licenses have an expiration date. Users will receive a warning while using Tuist commands that interact with Tuist Cloud if the license expires in less than 30 days. If you are interested in renewing your license, please reach out to [contact@tuist.io](mailto:contact@tuist.io).

### Base environment configuration

| Environment variable | Description | Required | Default | Example |
| --- | --- | --- | --- | --- |
| `DATABASE_URL` | The URL to access the Postgres database. Note that the URL should contain the authentication information | Yes | | `postgres://username:password@cloud.us-east-2.aws.test.com/production` |
| `TUIST_USE_SSL_FOR_DATABASE` | When true, it uses [SSL](https://en.wikipedia.org/wiki/Transport_Layer_Security) to connect to the database | No | `1` | `1` |
| `TUIST_APP_URL` | The base URL to access the instance from the Internet | Yes | | https://cloud.tuist.io |
| `TUIST_SECRET_KEY_BASE` | The key to use to encrypt information (e.g. sessions in a cookie) | Yes | | | `c5786d9f869239cbddeca645575349a570ffebb332b64400c37256e1c9cb7ec831345d03dc0188edd129d09580d8cbf3ceaf17768e2048c037d9c31da5dcacfa` |
| `TUIST_SECRET_KEY_PASSWORD` | Pepper to generate hashed passwords | No | `$TUIST_SECRET_KEY_BASE` | |
| `TUIST_SECRET_KEY_TOKENS` | Secret key to generate random tokens | No | `$TUIST_SECRET_KEY_BASE` | |        
| `TUIST_USE_IPV6` | When `1` it configures the app to use IPv6 addresses | No | `0` | `1`|

### Authentication environment configuration

We facilitate authentication through [identity providers (IdP)](https://en.wikipedia.org/wiki/Identity_provider). To utilize this, ensure all necessary environment variables for the chosen provider are present in the Tuist Cloud’s operating environment. **Missing variables** will result in Tuist Cloud bypassing that provider.

#### GitHub
        
We recommend authenticating using a [GitHub App](https://docs.github.com/en/apps/creating-github-apps/about-creating-github-apps/about-creating-github-apps) but you can also use the [OAuth App](https://docs.github.com/en/apps/oauth-apps/building-oauth-apps/creating-an-oauth-app). Make sure to include all essential environment variables specified by GitHub in the Tuist Cloud environment. Absent variables will cause Tuist Cloud to overlook the GitHub authentication. To properly set up the GitHub app:
- In the GitHub app's general settings:
    - Copy the `Client ID` and set it as `TUIST_GITHUB_OAUTH_ID`
    - Create and copy a new `client secret` and set it as `TUIST_GITHUB_OAUTH_SECRET`
    - Set the `Callback URL` as `http://YOUR_APP_URL/users/auth/github/callback`. `YOUR_APP_URL` can also be your server's IP address.
- In the `Permissions and events`'s `Account permissions` section, set the `Email addresses` permission to `Read-only`.

You'll then need to expose the following environment variables in the environment where Tuist Cloud runs:

| Environment variable | Description | Required | Default | Example |
| --- | --- | --- | --- | --- |
| `TUIST_GITHUB_OAUTH_ID` | The client ID of the application | Yes | | `Iv1.a629723000043722` |
| `TUIST_GITHUB_OAUTH_SECRET` | The client secret of the application | Yes | | `232f972951033b89799b0fd24566a04d83f44ccc` |

#### Google

You can set up authentication with Google using [OAuth 2](https://developers.google.com/identity/protocols/oauth2). For that, you'll need to [create a new credential](https://console.cloud.google.com/apis/credentials?project=tuist-cloud-staging) of type OAuth client ID. When creating the credentials, select "Web Application" as application type, name it `Tuist Cloud`, and set the redirect URI to `{base_url}/users/auth/google/callback` where `base_url` is the URL your hosted-service is running at. Once you create the app, copy the client ID and secret and set them as environment variables `GOOGLE_CLIENT_ID` and `GOOGLE_CLIENT_SECRET` respectively.

> [!NOTE] CONSENT SCREEN SCOPES
> You might need to create a consent screen. When you do so, make sure to add the `userinfo.email` and `openid` scopes and mark the app as internal.

#### Okta

You can enable authentication with Okta through the [OAuth 2.0](https://oauth.net/2/) protocol. You'll have to [create an app](https://developer.okta.com/docs/guides/implement-oauth-for-okta/main/#create-an-oauth-2-0-app-in-okta) on Okta with the following configuration:
        
- **App integration name:** `Tuist Cloud`
- **Grant type:** Enable *Authorization Code* for *Client acting on behalf of a user*
- **Sign-in redirect URL:** `{url}/users/auth/github/callback` where `url` is the public URL your service is accessed through.
- **Assignments:** This configuration will depend on your security team requirements.

If you'd like Tuist Cloud to detect when a user is removed from the application, you'll have to configure an [event hook](https://help.okta.com/en-us/content/topics/automation-hooks/event-hooks-main.htm). In your Okta organization, go to **Workflow > Event Hooks** and create a new event hook with the following data:

- **Name:**  Notify memberhip removal to Tuist Cloud
- **URL:** `{url}/webhooks/okta` where `url` is the public URL your service is accessed through.
- **Authentication field:** `Authorization`
- **Authentication secret:** A token that Tuist Cloud uses to validate the webhooks.
- **Subscribe to events** Include *User unassigned from app*

Once the app is created you'll need to set the following environment variables:

| Environment variable | Description | Required | Default | Example |
| --- | --- | --- | --- | --- |
| `TUIST_OKTA_SITE` | The URL of your Okta organization | Yes | | `https://your-org.okta.com` |
| `TUIST_OKTA_CLIENT_ID` | The client ID to authenticate against Okta | Yes | | |
| `TUIST_OKTA_CLIENT_SECRET` | The client secret to authenticate against Okta | Yes | | |
| `TUIST_OKTA_AUTHORIZE_URL` | The authorize URL | No | `{OKTA_SITE}/oauth2/<authorization_server>/v1/authorize` | |
| `TUIST_OKTA_TOKEN_URL` | The token URL | No | `{OKTA_SITE}/oauth2/<authorization_server>/v1/token` | |
| `TUIST_OKTA_USER_INFO_URL` | The token URL | No | `{OKTA_SITE}/oauth2/<authorization_server>/v1/userinfo` | |
| `TUIST_OKTA_EVENT_HOOK_SECRET` | A secret to validat event hooks delivered by Okta | No | |

### Storage environment configuration

 Tuist Cloud needs storage to house artifacts uploaded through the API. It's **essential to configure one of the supported storage solutions** for Tuist Cloud to operate effectively.

#### S3-compliant storages

The environment variables required to authenticate against S3-compliant storages aligns with the [conventions set by AWS](https://docs.aws.amazon.com/cli/v1/userguide/cli-configure-envvars.html) (e.g. `AWS_ACCESS_KEY_ID`, `AWS_SECRET_ACCESS_KEY`, `AWS_REGION`, `AWS_ENDPOINT`). Additionally, you need to set the `TUIST_S3_BUCKET_NAME` environment variable to indicate the bucket where the artifacts will be stored.

> [!NOTE] RUST SDK
> Tuist uses this [Rust SDK](https://github.com/durch/rust-s3), which you can use as a reference to understand how the environment variables are used. 

### Google Cloud Storage
For Google Cloud Storage, follow [these docs](https://cloud.google.com/storage/docs/authentication/managing-hmackeys) to get the `AWS_ACCESS_KEY_ID` and `AWS_SECRET_ACCESS_KEY` pair. The `AWS_ENDPOINT` should be set to `https://storage.googleapis.com`. Other environment variables are the same as for any other S3-compliant storage.

## Deployment

On-premise users are granted access to the repository located at [tuist/cloud-on-premise](https://github.com/cloud/cloud-on-premise) which has a linked container registry for pulling images. Currently, the container registry allows authentication only as an individual user. Therefore, users with repository access must generate a **personal access token** within the Tuist organization, ensuring they have the necessary permissions to read packages. After submission, we will promptly approve this token.
        
> [!IMPORTANT] USER VS ORGANIZATION-SCOPED TOKENS
> Using a personal access token presents a challenge because it's associated with an individual who might eventually depart from the enterprise organization. GitHub recognizes this limitation and is actively developing a solution to allow GitHub apps to authenticate with app-generated tokens.
        
### Pulling the Docker image

After generating the token, you can retrieve the image by executing the following command:

```bash
echo $TOKEN | docker login ghcr.io -u USERNAME --password-stdin
docker pull ghcr.io/tuist/cloud-on-premise:latest
```

### Deploying the Docker image

The deployment process for the Docker image will differ based on your chosen cloud provider and your organization's continuous deployment approach. Since most cloud solutions and tools, like [Kubernetes](https://kubernetes.io/), utilize Docker images as fundamental units, the examples in this section should align well with your existing setup.
        
We recommend establishing a deployment pipeline that that runs **every Tuesday**, pulling and deploying fresh images. This ensures you consistently benefit from the latest improvements.

> [!IMPORTANT]
> If your deployment pipeline needs to validate that the server is up and running, you can send a `GET` HTTP request to `/ready` and assert a `200` status code in the response. 

#### Fly
        
To deploy the app on [Fly](https://fly.io/), you'll require a `fly.toml` configuration file. Consider generating it dynamically within your Continuous Deployment (CD) pipeline. Below is a reference example for your use:

```toml
app = "tuist-cloud"
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

### Docker Compose

Below is an example of a `docker-compose.yml` file that you can use as a reference to deploy the service:

```yaml
version: '3.8'
services:
  db:
    image: timescale/timescaledb-ha:pg16
    restart: always
    environment:
      - POSTGRES_USER=postgres
      - POSTGRES_PASSWORD=postgres
    ports:
      - '5432:5432'
    volumes: 
      - db:/var/lib/postgresql/data
    healthcheck:
      test: ["CMD-SHELL", "pg_isready -U postgres"]
      interval: 5s
      timeout: 5s
      retries: 5

  pgweb:
    container_name: pgweb  
    restart: always  
    image: sosedoff/pgweb
    ports:
      - "8081:8081"
    links:
      - db:db  
    environment:
      PGWEB_DATABASE_URL: postgres://postgres:postgres@db:5432/postgres?sslmode=disable
    depends_on:
      - db 

  tuist:
    image: ghcr.io/tuist/cloud-on-premise:latest
    container_name: tuist_cloud
    depends_on:
      - db
    ports:
      - "80:80"
      - "8080:8080"
      - "443:443"
    expose:
      - "80"
      - "8080"
      - "443:443"
    environment:
      # Base Tuist Env - https://docs.tuist.io/cloud/on-premise#base-environment-configuration
      TUIST_USE_SSL_FOR_DATABASE: "0"
      TUIST_LICENSE:  # ...
      TUIST_CLOUD_HOSTED: "0"
      DATABASE_URL: postgres://postgres:postgres@db:5432/postgres?sslmode=disable
      TUIST_APP_URL: https://localhost:8080
      TUIST_SECRET_KEY_BASE: # ...
      WEB_CONCURRENCY: 80
      
      # Auth - one method
      # GitHub Auth - https://docs.tuist.io/cloud/on-premise#github
      TUIST_GITHUB_OAUTH_ID: 
      TUIST_GITHUB_OAUTH_SECRET: 

      # Okta Auth - https://docs.tuist.io/cloud/on-premise#okta
      TUIST_OKTA_SITE:
      TUIST_OKTA_CLIENT_ID:
      TUIST_OKTA_CLIENT_SECRET:
      TUIST_OKTA_AUTHORIZE_URL: # Optional
      TUIST_OKTA_TOKEN_URL: # Optional
      TUIST_OKTA_USER_INFO_URL: # Optional
      TUIST_OKTA_EVENT_HOOK_SECRET: # Optional

      # Storage
      AWS_ACCESS_KEY_ID: # ...
      AWS_SECRET_ACCESS_KEY: # ...
      AWS_S3_REGION: # ...
      AWS_ENDPOINT: # https://amazonaws.com
      TUIST_S3_BUCKET_NAME: # ...
    
      # Other

volumes:
  db:
    driver: local
```

## Metrics

You can ingest metrics gathered by the Tuist server using [Prometheus](https://prometheus.io/) and a visualization tool such as [Grafana](https://grafana.com/) to create a custom dashboard tailored to your needs. The Prometheus metrics are served via the `/metrics` endpoint. The Prometheus' [scrape_interval](https://prometheus.io/docs/introduction/first_steps/#configuring-prometheus) should be set as less than 10_000 seconds (we recommend keeping the default of 15 seconds).

### Runs metrics

A set of metrics related to Tuist Runs.

#### `tuist_runs_total` (counter)

The total number of Tuist Runs.

**Tags:**
- `name` – name of the `tuist` command that was run, such as `build`, `test`, etc.
- `is_ci` – a boolean indicating if the executor was a CI or a developer's machine.
- `status` – `0` in case of `success`, `1` in case of `failure`

#### `tuist_runs_duration_milliseconds` (histogram)

The total duration of each tuist run in milliseconds.

**Tags:**
- `name` – name of the `tuist` command that was run, such as `build`, `test`, etc.
- `is_ci` – a boolean indicating if the executor was a CI or a developer's machine.
- `status` – `0` in case of `success`, `1` in case of `failure`

### Cache metrics

A set of metrics related to the Tuist Cache.

#### `tuist_cache_events_total` (counter)

The total number of Tuist Binary Cache events.

**Tags:**
- `event_type`: Can be either of `local_hit`, `remote_hit`, or `miss`.
