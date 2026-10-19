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

> [!NOTE]
> If your organization uses single sign-on, choose the enterprise login option in the browser and enter your work email address. Tuist can find the provider from your existing organization membership or a <.localized_link href="/guides/integrations/authentication/sso#verify-a-login-email-domain">verified login email domain</.localized_link>.

## OIDC tokens {#oidc-tokens}

For CI environments that support OpenID Connect (OIDC), Tuist can authenticate automatically without requiring you to manage long-lived secrets. When running in a supported CI environment, the CLI will automatically detect the OIDC token provider and exchange the CI-provided token for a Tuist access token.

### Supported CI providers {#supported-ci-providers}

- GitHub Actions
- CircleCI
- Bitrise
- Fly.io Machines (using an explicit workload trust policy)

### Setting up OIDC authentication {#setting-up-oidc-authentication}

For GitHub Actions, CircleCI, and Bitrise:

1. **Connect your repository to Tuist**: Follow the <.localized_link href="/guides/integrations/gitforge/github">GitHub integration guide</.localized_link> to connect your GitHub repository to your Tuist project.

2. **Run `tuist auth login`**: In your CI workflow, run `tuist auth login` before any commands that require authentication. The CLI will automatically detect the CI environment and authenticate using OIDC.

See the <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link> for provider-specific configuration examples.

### Fly.io Machines {#flyio-machines}

[Fly.io supports OIDC workload identity](https://docs.fly.io/reference/openid-connect/). A Machine can request a short-lived, signed identity token from its local `/.fly/api` Unix socket, without a Fly API token or a long-lived Tuist secret.

Fly tokens identify an organization and application, not a source repository. Configure trust explicitly instead of connecting a GitHub repository:

1. Obtain the issuer (`iss`), organization ID (`org_id`), and application ID (`app_id`) from an identity token issued inside your Fly Machine. The issuer is `https://oidc.fly.io/<organization-slug>`. Use the numeric IDs, not organization or app names.
2. In the Tuist dashboard, open your project's **Settings** > **Authentication**. Under **Workload identities** > **Fly.io**, add the issuer URL, organization ID, and application ID. You must have permission to update the project.
3. Inside the Machine, set `TUIST_OIDC_ACCOUNT` to the Tuist account handle that owns the project (not the Fly organization slug). This selects the destination without granting access: a matching trust policy is still required. Request a token with audience `tuist` and pass it to `tuist auth login` using `TUIST_OIDC_TOKEN`:

```bash
set -euo pipefail
export TUIST_OIDC_ACCOUNT="my-tuist-account"

TUIST_OIDC_TOKEN="$(curl --fail --silent --show-error \
  --unix-socket /.fly/api \
  -X POST http://localhost/v1/tokens/oidc \
  -H 'Content-Type: application/json' \
  --data '{"aud":"tuist"}')"
export TUIST_OIDC_TOKEN

tuist auth login
unset TUIST_OIDC_TOKEN
```

For the initial setup, you can inspect only the identity fields locally, after exporting the token and before unsetting it. This decodes claims for configuration; Tuist separately verifies the signature during authentication:

```bash
python3 - <<'PY'
import base64, json, os
payload = os.environ["TUIST_OIDC_TOKEN"].split(".")[1]
claims = json.loads(base64.urlsafe_b64decode(payload + "=" * (-len(payload) % 4)))
print(json.dumps({key: claims[key] for key in ("iss", "org_id", "app_id")}, indent=2))
PY
```

For Elixir projects, you can replace `tuist auth login` with `mix tuist.login` using the same `TUIST_OIDC_TOKEN`. The Elixir integration can also exchange a freshly minted identity token automatically when no `TUIST_TOKEN` or valid stored credentials are available. Both clients forward `TUIST_OIDC_ACCOUNT` to select the target account.

Do not print or commit the token itself. Run the token request and login before each job; setting `CI` is not required. Commands after login use the stored short-lived Tuist access token as usual, including for projects configured in `tuist.toml`.

Every Machine in the authorized Fly app can authenticate to the project. Add a separate policy for each additional app or project that needs access. The exchange grants the `ci` scope group only for projects that explicitly trust the exact issuer, organization ID, and application ID. Setting `TUIST_OIDC_ACCOUNT` limits the exchange to that account, so another account's policies cannot block your login or add projects to your token. Without an explicit account, a workload trusted by multiple Tuist accounts is rejected rather than selecting one implicitly.

Remove a policy in project settings to prevent new token exchanges. Already-issued Tuist access tokens remain valid until they expire, currently after one hour. These sessions have no refresh token. Fly identity tokens expire after approximately ten minutes, so keeping an old `TUIST_OIDC_TOKEN` is not a renewal strategy. For jobs or Machines running longer than an hour, request a new Fly identity token and run `tuist auth login` or `mix tuist.login` again before the Tuist session expires. No GitHub repository connection is required for Fly authentication.

> [!NOTE]
> `TUIST_OIDC_TOKEN` is a generic CLI token input, not a way to bypass server trust. It takes precedence over CI provider detection, and the server still accepts only supported providers and authorized identities. Do not put a Fly identity token in `TUIST_TOKEN`, which expects a Tuist credential.

If authentication reports **OIDC token signature verification failed**, check that the policy exactly matches the token's `iss`, `org_id`, and `app_id`, and that it has not been removed. Unconfigured identities receive the same error as invalid signatures to avoid exposing trust registrations. Also check that `TUIST_OIDC_ACCOUNT` names the Tuist account that owns the trusted project.

### OIDC token scopes {#oidc-token-scopes}

OIDC tokens are granted the `ci` scope group. For repository-based providers, this provides access to all projects connected to the repository. For Fly.io, access is limited to projects with a matching workload trust policy. See [Scope groups](#scope-groups) for details about what the `ci` scope includes.

> [!TIP]
> **Security Benefits**
>
> OIDC authentication is more secure than long-lived tokens because:
> - No secrets to rotate or manage
> - Tokens are short-lived
> - Authentication is tied to your repository identity or an explicitly authorized workload identity


## Gradle plugin authentication {#gradle-plugin-authentication}

The Gradle plugin uses the Tuist CLI authentication state and does not define a separate login flow. Authenticate once with the CLI and the plugin will reuse those credentials.

For project and server configuration, including `project` and `url`, use the canonical <.localized_link href="/references/tuist-toml">tuist.toml reference</.localized_link>.

For local usage, run:

```bash
tuist auth login
```

For CI, use either:

- <.localized_link href="/guides/server/authentication#setting-up-oidc-authentication">OIDC authentication</.localized_link> (recommended when available)
- <.localized_link href="/guides/server/authentication#continuous-integration">Account token authentication</.localized_link> via `TUIST_TOKEN`

For self-hosted Tuist servers, define the server URL in `tuist.toml` (for example `url = "https://tuist.your-company.com"`) and run the standard login flow. The URL is resolved from the same configuration file used by the plugin.

After authentication is configured, run your Gradle caching commands and tasks normally.

## Account tokens {#account-tokens}

For CI environments that don't support OIDC, or when you need fine-grained control over permissions, you can use account tokens. Account tokens allow you to specify exactly which scopes and projects the token can access.

### Creating an account token {#creating-an-account-token}

The easiest way to create an account token is from the dashboard:

1. Open the organization in the Tuist dashboard.
2. Go to **Settings** > **Tokens**.
3. Select **Generate token**.
4. Choose a name, optional expiration, project access, and the scopes the token needs.
5. Copy the generated token value before closing the dialog. Token values are only shown once.

You can also create account tokens from the CLI, which is useful for scripting or automation:

```bash
tuist account tokens create account-handle \
  --scopes account:cache:write project:cache:read project:cache:write \
  --name ci-cache-token \
  --expires 1y
```

> [!IMPORTANT]
> Replace `account-handle` with the handle of the account that owns the projects you want the token to access. This can be an organization account, not necessarily your personal account.

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
| `account:cache:read` | Download account-scoped cached binaries |
| `account:cache:write` | Upload account-scoped cached binaries |
| `account:members:read` | Read account members |
| `account:members:write` | Manage account members |
| `account:registry:read` | Read from the Swift package registry |
| `account:registry:write` | Publish to the Swift package registry |
| `account:runners:read` | Read runner jobs, workflows, profiles, and volumes |
| `account:runners:write` | Manage runner profiles and clear runner volumes |
| `project:previews:read` | Download previews |
| `project:previews:write` | Upload previews |
| `project:admin:read` | Read projects and their settings |
| `project:admin:write` | Create, update, and delete projects. Creating a project requires a token with access to all projects |
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
| `ci` | `account:cache:write`, `project:cache:write`, `project:previews:write`, `project:bundles:write`, `project:tests:write`, `project:builds:write`, `project:runs:write` |
| `mcp` | `project:cache:read`, `project:previews:read`, `project:bundles:read`, `project:tests:read`, `project:builds:read`, `project:runs:read` |

### Continuous Integration {#continuous-integration}

For CI environments that don't support OIDC, create an account token with the `ci` scope group to authenticate your CI workflows. In the dashboard, select the **CI** preset when generating the token.

You can also create the same token from the CLI:

```bash
tuist account tokens create account-handle --scopes ci --name ci
```

This creates a token with all the scopes needed for typical CI operations (cache, previews, bundles, tests, builds, and runs). Store the generated token as a secret in your CI environment and set it as the `TUIST_TOKEN` environment variable.

### Managing account tokens {#managing-account-tokens}

Open **Settings** > **Tokens** in the account dashboard to view account tokens, inspect a token's scopes and project access, and revoke tokens during rotation.

To list all tokens for an account:

```bash
tuist account tokens list account-handle
```

To revoke a token by name:

```bash
tuist account tokens revoke account-handle ci-cache-token
```

### Using account tokens {#using-account-tokens}

Account tokens are expected to be defined as the environment variable `TUIST_TOKEN`:

```bash
export TUIST_TOKEN=your-account-token
```

> [!TIP]
> **When To Use Account Tokens**
>
> Use account tokens when you need:
> - Authentication in CI environments that don't support OIDC
> - Fine-grained control over which operations the token can perform
> - A token that can access multiple projects within an account
> - Time-limited tokens that automatically expire
