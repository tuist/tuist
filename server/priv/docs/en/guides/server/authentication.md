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

### Supported providers {#supported-ci-providers}

Tuist recognizes these CI providers and maps their tokens to projects through your repository connection:

- GitHub Actions
- CircleCI
- Bitrise

Any other identity provider that issues OpenID Connect tokens can authenticate through a [workload identity trust policy](#workload-identity-trust-policies) that you configure on the project, for example [Fly.io Machines](#flyio-machines).

### Setting up OIDC authentication {#setting-up-oidc-authentication}

For GitHub Actions, CircleCI, and Bitrise:

1. **Connect your repository to Tuist**: Follow the <.localized_link href="/guides/integrations/gitforge/github">GitHub integration guide</.localized_link> to connect your GitHub repository to your Tuist project.

2. **Run `tuist auth login`**: In your CI workflow, run `tuist auth login` before any commands that require authentication. The CLI will automatically detect the CI environment and authenticate using OIDC.

See the <.localized_link href="/guides/integrations/continuous-integration">Continuous Integration guide</.localized_link> for provider-specific configuration examples.

### Workload identity trust policies {#workload-identity-trust-policies}

A trust policy lets workloads from another identity provider, such as a deployment platform, a Kubernetes cluster, or a self-managed CI system, access a project without a long-lived Tuist secret. The provider must:

- Be reachable over HTTPS at a public address. Tuist doesn't follow redirects and doesn't connect to private or internal network addresses, including from self-hosted Tuist servers.
- Issue JWTs signed with an asymmetric key, for example `RS256` or `ES256`. Unsigned tokens and tokens signed with a shared secret (`HS256` and similar) are rejected.
- Publish its signing keys as a JSON Web Key Set (JWKS) at a fixed HTTPS URL. The response must be at most 64 KiB and contain at most 20 keys.
- Include an expiration (`exp`) in every token.

GitHub Actions, CircleCI, and Bitrise issuers are reserved for the repository-based flow above and can't be used in a trust policy.

#### Create a policy {#create-a-trust-policy}

In the Tuist dashboard, open your project's **Settings** > **Authentication** and add a policy under **Workload identities**. You must have permission to update the project. Each project can have up to 20 policies.

| Field | Description |
| --- | --- |
| Name | A label to recognize the policy, unique within the project. |
| Issuer URL | The token's `iss` claim. It must match exactly, including any trailing slash. |
| JWKS URL | The HTTPS URL of the provider's signing keys. Tuist uses this URL directly and doesn't read the provider's OpenID Connect discovery document, so copy the `jwks_uri` from the provider's documentation or from `<issuer>/.well-known/openid-configuration`. |
| Audience | The audience the token must be issued for, `tuist` by default. The token's `aud` must equal it or, when `aud` is a list, contain it. Use a value that only Tuist accepts so tokens minted for other services can't be replayed here. |
| Claims | A JSON object with 1 to 10 claims that the token must contain, for example `{"sub": "system:serviceaccount:ci:builder"}`. The JSON input is limited to 8 KiB. Values must be strings, signed 64-bit integers, or booleans, and they must match exactly, including their type: `"123"` doesn't match `123`. Nested objects, lists, and time or token claims such as `iss`, `aud`, `exp`, `nbf`, `iat`, and `jti` aren't allowed. |

Every workload that can obtain a token with matching claims can access the project, so choose claims that the provider guarantees and that nobody can reuse. Prefer stable numeric IDs over names that can be renamed or registered again after deletion.

Tuist grants access only for policies whose own JWKS URL holds the key that signed the token, after checking the issuer, audience, expiration, not-before time (with up to 60 seconds of clock skew), and every claim. A policy in another project or account can't vouch for yours.

#### Authenticate a workload {#authenticate-a-workload}

1. Request an identity token from your provider with the policy's audience.
2. Set `TUIST_OIDC_TOKEN` to that token and `TUIST_OIDC_ACCOUNT` to the handle of the Tuist account that owns the project. The account is required for every trust policy exchange. It only selects where to look and grants nothing by itself.
3. Run `tuist auth login`. For Elixir projects, you can use `mix tuist.login` instead, or let the Elixir integration exchange the token automatically when no `TUIST_TOKEN` or valid stored credentials are available.

The resulting Tuist access token has the `ci` scope group for every project in that account whose policy matches the token. Exchanges fail if more than 20 policies in the account match the same token or if they use more than two different JWKS URLs.

Tuist doesn't refresh these sessions. Access tokens expire after one hour and have no refresh token. Provider identity tokens are often valid for only a few minutes, so keeping an old `TUIST_OIDC_TOKEN` isn't a renewal strategy: for jobs that run longer than an hour, request a new identity token and log in again before the Tuist session expires. Removing a policy stops new exchanges, but access tokens that were already issued remain valid until they expire.

Tuist caches a provider's signing keys for 15 minutes after a successful fetch. Failed fetches aren't cached. If your provider rotates keys, it should publish the new key in its JWKS at least 15 minutes before signing tokens with it, because tokens signed with a key that isn't in the cached set are rejected until the cache expires. Tokens without a key ID (`kid`) are accepted only when the JWKS contains a single eligible signing key.

> [!NOTE]
> `TUIST_OIDC_TOKEN` is a generic token input, not a way to bypass server trust. It takes precedence over CI provider detection, and the server still accepts only the built-in providers and identities with a matching trust policy. Do not put an identity token in `TUIST_TOKEN`, which expects a Tuist credential.

If the exchange fails, check that the issuer, audience, and every claim in the policy exactly match the token, that the JWKS URL serves the key that signed the token, that the policy hasn't been removed, and that `TUIST_OIDC_ACCOUNT` names the account that owns the project. To avoid exposing which identities are trusted, Tuist returns the same error for all of these cases.

### Fly.io Machines {#flyio-machines}

[Fly.io supports OIDC workload identity](https://docs.fly.io/reference/openid-connect/). A Machine can request a short-lived, signed identity token from its local `/.fly/api` Unix socket, without a Fly API token or a long-lived Tuist secret. Fly tokens identify an organization and application, not a source repository, so use a trust policy instead of connecting a GitHub repository:

1. Obtain the issuer (`iss`), organization ID (`org_id`), and application ID (`app_id`) from an identity token issued inside your Fly Machine. The issuer is `https://oidc.fly.io/<organization-slug>`. Use the numeric IDs, not organization or app names.
2. [Create a trust policy](#create-a-trust-policy) with these values. Fly sends both IDs as strings, so keep the quotes around them in the claims.

   | Field | Value |
   | --- | --- |
   | Issuer URL | `https://oidc.fly.io/<organization-slug>` |
   | JWKS URL | `https://oidc.fly.io/<organization-slug>/.well-known/jwks` |
   | Audience | `tuist` |
   | Claims | `{"org_id": "<organization-id>", "app_id": "<application-id>"}` |

3. Inside the Machine, set `TUIST_OIDC_ACCOUNT` to the Tuist account handle that owns the project (not the Fly organization slug), request a token with audience `tuist`, and pass it to `tuist auth login` using `TUIST_OIDC_TOKEN`:

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

Do not print or commit the token itself. Every Machine in the authorized Fly app can authenticate to the project, so add a separate policy for each additional app or project that needs access. Fly identity tokens expire after about ten minutes, so on long-running Machines request a new one and run `tuist auth login` again before the one-hour Tuist session expires.

### OIDC token scopes {#oidc-token-scopes}

OIDC tokens are granted the `ci` scope group. For GitHub Actions, CircleCI, and Bitrise, this provides access to all projects connected to the repository. For workload identity trust policies, access is limited to projects in the selected account with a matching policy. See [Scope groups](#scope-groups) for details about what the `ci` scope includes.

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
