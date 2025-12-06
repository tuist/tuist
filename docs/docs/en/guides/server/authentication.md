---
{
  "title": "Authentication",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to authenticate with the Tuist server from the CLI."
}
---
# Authentication {#authentication}

To interact with the server, the CLI needs to authenticate the requests using [bearer authentication](https://swagger.io/docs/specification/authentication/bearer-authentication/). The CLI supports authenticating as a user or as a project.

## As a user {#as-a-user}

When using the CLI locally on your machine, we recommend authenticating as a user. To authenticate as a user, you need to run the following command:

```bash
tuist auth login
```

The command will take you through a web-based authentication flow. Once you authenticate, the CLI will store a long-lived refresh token and a short-lived access token under `~/.config/tuist/credentials`. Each file in the directory represents the domain you authenticated against, which by default should be `tuist.dev.json`. The information stored in that directory is sensitive, so **make sure to keep it safe**.

The CLI will automatically look up the credentials when making requests to the server. If the access token is expired, the CLI will use the refresh token to get a new access token.

## As a project {#as-a-project}

In non-interactive environments like continuous integrations', you can't authenticate through an interactive flow. For those environments, we recommend authenticating as a project by using a project-scoped token:

```bash
tuist project tokens create
```

The CLI expects the token to be defined as the environment variable `TUIST_TOKEN`, and the `CI=1` environment variable to be set. The CLI will use the token to authenticate the requests.

::: warning LIMITED SCOPE
<!-- -->
The permissions of the project-scoped token are limited to the actions that we consider safe for projects to perform from a CI environment. We plan to document the permissions that the token has in the future.
<!-- -->
:::

## Account tokens {#account-tokens}

For more fine-grained control over permissions in CI environments, you can use account tokens. Unlike project tokens, account tokens allow you to specify exactly which scopes and projects the token can access.

### Creating an account token {#creating-an-account-token}

```bash
tuist account tokens create my-account \
  --scopes project:cache:read,project:cache:write \
  --name ci-cache-token \
  --expires 1y \
  --all-projects
```

The command accepts the following options:

| Option | Description |
| --- | --- |
| `--scopes` | Required. Comma-separated list of scopes to grant the token. |
| `--name` | Required. A unique identifier for the token (1-32 characters, alphanumeric, hyphens, and underscores only). |
| `--expires` | Optional. When the token should expire. Use format like `30d` (days), `6m` (months), or `1y` (years). If not specified, the token never expires. |
| `--all-projects` | Grant the token access to all projects in the account. |
| `--projects` | Limit the token to specific project handles (only used when `--all-projects` is not set). |

### Available scopes {#available-scopes}

| Scope | Description |
| --- | --- |
| `account:members:read` | Read account members |
| `account:members:write` | Manage account members |
| `account:registry:read` | Read from the Swift package registry |
| `account:registry:write` | Publish to the Swift package registry |
| `project:previews:read` | Download previews |
| `project:previews:write` | Upload previews |
| `project:admin:read` | Read project settings |
| `project:admin:write` | Manage project settings |
| `project:cache:read` | Download cached binaries |
| `project:cache:write` | Upload cached binaries |
| `project:bundles:read` | View bundles |
| `project:bundles:write` | Upload bundles |
| `project:tests:read` | Read test results |
| `project:tests:write` | Upload test results |
| `project:builds:read` | Read build analytics |
| `project:builds:write` | Upload build analytics |

### Managing account tokens {#managing-account-tokens}

To list all tokens for an account:

```bash
tuist account tokens list my-account
```

To revoke a token by name:

```bash
tuist account tokens revoke my-account ci-cache-token
```

### Using account tokens {#using-account-tokens}

Like project tokens, account tokens are expected to be defined as the environment variable `TUIST_TOKEN`:

```bash
export TUIST_TOKEN=your-account-token
```

::: tip WHEN TO USE ACCOUNT TOKENS
<!-- -->
Use account tokens when you need:
- Fine-grained control over which operations the token can perform
- A token that can access multiple projects within an account
- Time-limited tokens that automatically expire
<!-- -->
:::
