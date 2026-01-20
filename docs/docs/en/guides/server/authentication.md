---
{
  "title": "Authentication",
  "titleTemplate": ":title | Server | Guides | Tuist",
  "description": "Learn how to authenticate with the Tuist server from the CLI."
}
---
# Authentication {#authentication}

To interact with the server, the CLI needs to authenticate the requests using [bearer authentication](https://swagger.io/docs/specification/authentication/bearer-authentication/). The CLI supports authenticating as a user, as an account, or using an OIDC token.

## As a user {#as-a-user}

When using the CLI locally on your machine, we recommend authenticating as a user. To authenticate as a user, you need to run the following command:

```bash
tuist auth login
```

The command will take you through a web-based authentication flow. Once you authenticate, the CLI will store a long-lived refresh token and a short-lived access token under `~/.config/tuist/credentials`. Each file in the directory represents the domain you authenticated against, which by default should be `tuist.dev.json`. The information stored in that directory is sensitive, so **make sure to keep it safe**.

The CLI will automatically look up the credentials when making requests to the server. If the access token is expired, the CLI will use the refresh token to get a new access token.

## OIDC tokens {#oidc-tokens}

For CI environments that support OpenID Connect (OIDC), Tuist can authenticate automatically without requiring you to manage long-lived secrets. When running in a supported CI environment, the CLI will automatically detect the OIDC token provider and exchange the CI-provided token for a Tuist access token.

### Supported CI providers {#supported-ci-providers}

- GitHub Actions
- CircleCI
- Bitrise

### Setting up OIDC authentication {#setting-up-oidc-authentication}

1. **Connect your repository to Tuist**: Follow the <LocalizedLink href="/guides/integrations/gitforge/github">GitHub integration guide</LocalizedLink> to connect your GitHub repository to your Tuist project.

2. **Run `tuist auth login`**: In your CI workflow, run `tuist auth login` before any commands that require authentication. The CLI will automatically detect the CI environment and authenticate using OIDC.

See the <LocalizedLink href="/guides/integrations/continuous-integration">Continuous Integration guide</LocalizedLink> for provider-specific configuration examples.

### OIDC token scopes {#oidc-token-scopes}

OIDC tokens are granted the `ci` scope group, which provides access to all projects connected to the repository. See [Scope groups](#scope-groups) for details about what the `ci` scope includes.

::: tip SECURITY BENEFITS
<!-- -->
OIDC authentication is more secure than long-lived tokens because:
- No secrets to rotate or manage
- Tokens are short-lived and scoped to individual workflow runs
- Authentication is tied to your repository identity
<!-- -->
:::

## Account tokens {#account-tokens}

For CI environments that don't support OIDC, or when you need fine-grained control over permissions, you can use account tokens. Account tokens allow you to specify exactly which scopes and projects the token can access.

### Creating an account token {#creating-an-account-token}

```bash
tuist account tokens create my-account \
  --scopes project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

The command accepts the following options:

| Option | Description |
| --- | --- |
| `--scopes` | Required. Comma-separated list of scopes to grant the token. |
| `--name` | Required. A unique identifier for the token (1-32 characters, alphanumeric, hyphens, and underscores only). |
| `--expires` | Optional. When the token should expire. Use format like `30d` (days), `6m` (months), or `1y` (years). If not specified, the token never expires. |
| `--projects` | Limit the token to specific project handles. The token has access to all projects if not specified. |

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
| `project:runs:read` | Read command runs |
| `project:runs:write` | Create and update command runs |

### Scope groups {#scope-groups}

Scope groups provide a convenient way to grant multiple related scopes with a single identifier. When you use a scope group, it automatically expands to include all the individual scopes it contains.

| Scope Group | Included Scopes |
| --- | --- |
| `ci` | `project:cache:write`, `project:previews:write`, `project:bundles:write`, `project:tests:write`, `project:builds:write`, `project:runs:write` |

### Continuous Integration {#continuous-integration}

For CI environments that don't support OIDC, you can create an account token with the `ci` scope group to authenticate your CI workflows:

```bash
tuist account tokens create my-account --scopes ci --name ci
```

This creates a token with all the scopes needed for typical CI operations (cache, previews, bundles, tests, builds, and runs). Store the generated token as a secret in your CI environment and set it as the `TUIST_TOKEN` environment variable.

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

Account tokens are expected to be defined as the environment variable `TUIST_TOKEN`:

```bash
export TUIST_TOKEN=your-account-token
```

::: tip WHEN TO USE ACCOUNT TOKENS
<!-- -->
Use account tokens when you need:
- Authentication in CI environments that don't support OIDC
- Fine-grained control over which operations the token can perform
- A token that can access multiple projects within an account
- Time-limited tokens that automatically expire
<!-- -->
:::
