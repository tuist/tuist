---
{
  "title": "Claude",
  "titleTemplate": ":title · Sandboxes · Features · Guides · Tuist",
  "description": "Run Claude Managed Agents sessions and Claude Code cloud sessions (claude.ai, the desktop and mobile apps, and claude --cloud) on Tuist Sandboxes, on Linux or macOS."
}
---
# Claude {#claude}

> [!IMPORTANT]
> **Invite-only**
>
> Tuist Sandboxes, both Linux and macOS, are currently invite-only. [Reach out](mailto:contact@tuist.dev) or ping us in the [community Slack](https://slack.tuist.dev) to request access for your account.

Anthropic runs Claude's agent loop, and a *self-hosted environment* decides where Claude's tools run. Connect one to Tuist, and every session in it gets its own Tuist <.localized_link href="/guides/features/sandboxes">sandbox</.localized_link>, on Linux or macOS. Tuist runs the workers and runners those environments need, so you don't host anything.

There are two kinds of environments, one per Claude product:

- **[Claude Managed Agents](#managed-agents)**: sessions you start with the Claude API or Tuist's agent-sessions API. You create the environment (`env_…`) in the [Claude Console](https://platform.claude.com/environments), and each session can choose Linux or macOS.
- **[Claude Code](#claude-code)**: cloud sessions developers start from claude.ai, the Claude desktop and mobile apps, and `claude --cloud`. A Claude Team or Enterprise Owner creates the environments (`ccpool_…`) in claude.ai admin settings, one for each platform, and developers pick Linux or macOS by picking the environment.

Both are connected through the Tuist API by an account administrator. Authenticate with `tuist auth login`, then:

```bash
export TUIST_TOKEN=$(tuist auth token)
```

## Claude Managed Agents {#managed-agents}

### Connect an environment {#managed-agents-connect}

Connect from your account's **Settings → Integrations → Claude**, or from **Connect** on the Claude tile of the Sandboxes page. Tuist authenticates with Anthropic's [Workload Identity Federation](https://platform.claude.com/docs/en/manage-claude/workload-identity-federation), so you never give it an Anthropic API key. You need the admin role in your Anthropic organization.

1. **Trust Tuist.** Tuist shows your account's issuer URL and subject prefix. In the Claude Console, open [Workload identity](https://platform.claude.com/settings/workload-identity-federation), click **Connect workload**, choose **Custom OIDC**, and enter them with the scope `workspace:developer`. Add the service account the wizard creates to the workspace that should run the sessions.
2. **Paste the IDs.** Paste the exchange snippet from the federation rule's page, or enter the organization, workspace, service account and rule IDs. None of them is a secret. Tuist exchanges a token right away to check the setup; if Anthropic rejects it, the Console's [authentication history](https://platform.claude.com/settings/workload-identity-federation?tab=history) shows why.
3. **Create the environment.** Tuist creates a self-hosted environment in your workspace.
4. **Paste the environment key.** Anthropic only generates environment keys in the Console: open the environment on the [Environments](https://platform.claude.com/environments) page, click **Generate environment key**, paste it into Tuist and choose the platform and shape of the environment's sandboxes. Tuist stores the key encrypted and never shows it again.

Within a minute, Tuist starts serving the environment's sessions. See <.localized_link href="/guides/features/sandboxes#platforms">Linux and macOS</.localized_link> for the shapes.

#### With the API {#managed-agents-connect-api}

To connect from automation, create a self-hosted environment in the [Claude Console](https://platform.claude.com/environments), generate its key, and send both to Tuist:

```bash
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "anthropic_environment_id": "env_...",
    "environment_key": "<environment key>"
  }'
```

To start sessions through Tuist's API, also send either the four federation IDs (see [Connect without an API key](#managed-agents-federation)) or an `anthropic_api_key`. The environment runs on Linux unless you pass `"platform": "darwin"`; `vcpus`, `memory_mb` and `workspace_gb` change the shape of its sandboxes.

### Start a session {#managed-agents-sessions}

Each session runs on the environment's platform unless the session asks for another one.

**With the Claude API**, create the session as usual with the environment's ID, and set `tuist_platform` in the session's metadata to `macos` or `linux`:

```bash
curl https://api.anthropic.com/v1/sessions \
  -H "x-api-key: $ANTHROPIC_API_KEY" \
  -H "anthropic-version: 2023-06-01" \
  -H "anthropic-beta: managed-agents-2026-04-01" \
  -H "content-type: application/json" \
  -d '{
    "agent": "agent_...",
    "environment_id": "env_...",
    "metadata": {
      "tuist_platform": "macos",
      "repository_url": "https://github.com/my-org/my-app"
    }
  }'
```

`repository_url` and, optionally, `repository_ref` (a branch or commit) make Tuist clone a public repository into the sandbox before the agent's first turn.

**With Tuist's agent-sessions API**, Tuist creates the agent and the session for you, and clones private GitHub repositories that are connected to your Tuist account:

```bash
curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-sessions" \
  -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
  -d '{
    "prompt": "Fix the failing snapshot tests",
    "platform": "darwin",
    "repository_url": "https://github.com/my-org/my-app",
    "repository_ref": "main"
  }'
```

When the account has more than one environment, pass `agent_environment_id`. You can follow the session with `GET /agent-sessions/{id}/events`, reply with `POST /agent-sessions/{id}/messages`, and end it with `POST /agent-sessions/{id}/archive`.

The repository is checked out in `/workspace` on Linux and `/Users/runner/work` on macOS. A session's sandbox pauses after the agent finishes a turn and resumes on the next message.

> [!WARNING]
> Anyone who can create sessions in the Claude workspace that owns the environment can run sessions on your Tuist account, and can ask for macOS with session metadata. Limit access to that workspace accordingly.

### Connect without an API key {#managed-agents-federation}

The dashboard sets this up for you. Through the API, Tuist works the same way: every account has its own OpenID Connect issuer at Tuist, `https://tuist.dev/oidc/accounts/<account id>`, and signs a short-lived token for each call to Anthropic, which it exchanges for an Anthropic access token that lasts a few minutes. A federation rule that trusts your issuer never accepts tokens Tuist signs for other accounts.

- Every agent environment response includes `federation_issuer_url` and `federation_subject` (`account:123:agent-environment:456`). In the Console's Custom OIDC wizard, use the issuer URL and either that exact subject, to admit only this environment, or `account:123:*` to admit every environment of the account. The dashboard's setup checks use the subject `account:123:setup`, which only the prefix admits. Use the scope `workspace:developer`.
- Send the organization, workspace, service account and rule IDs as `anthropic_organization_id`, `anthropic_workspace_id`, `anthropic_service_account_id` and `anthropic_federation_rule_id`, on create or with `PATCH /agent-environments/{id}`. When an environment has both the IDs and an API key, Tuist uses federation.

> [!NOTE]
> Anthropic fetches the issuer's keys over HTTPS on port 443 from a public hostname. If your self-hosted Tuist server is not reachable from the internet, choose the **inline** JWKS source in the Console and paste the key set your server serves at `<issuer>/jwks.json`. Paste it again whenever Tuist's signing key changes, which happens when the server's `TUIST_SECRET_KEY_TOKENS` (or, when it is unset, `TUIST_SECRET_KEY_BASE`) changes.

## Claude Code {#claude-code}

Claude Code cloud sessions are the ones developers start from [claude.ai/code](https://claude.ai/code), the Claude desktop and mobile apps, and `claude --cloud`. They pick where a session runs by its environment, so you connect one environment for each platform you want to offer.

### Connect environments {#claude-code-connect}

1. A Claude organization Owner turns on **Allow self-hosted environments** on the [Cloud environments](https://claude.ai/admin-settings/cloud-environments) admin page. This needs a Team or Enterprise plan; see Anthropic's [self-hosted environments](https://code.claude.com/docs/en/self-hosted-environments) guide.
2. On the same page, create a self-hosted environment for each platform, with the name developers will see, for example **Tuist Linux** and **Tuist macOS**. Copy each environment's `ccpool_…` ID and its environment key, which is shown only once.
3. Connect each environment to your Tuist account with `kind` set to `claude_code` and its platform:

   ```bash
   curl -X POST "https://tuist.dev/api/accounts/my-org/sandboxes/agent-environments" \
     -H "Authorization: Bearer $TUIST_TOKEN" -H "Content-Type: application/json" \
     -d '{
       "kind": "claude_code",
       "platform": "darwin",
       "name": "Tuist macOS",
       "anthropic_environment_id": "ccpool_...",
       "environment_key": "<environment key>"
     }'
   ```

   Repeat with `"platform": "linux"` and the other environment's ID and key.

Within a minute, the environments are ready to take sessions. An idle session keeps its sandbox running for 30 minutes, then pauses it; the session's next message resumes the same sandbox. Change the wait with `max_idle_seconds` (up to 3600).

### Choose Linux or macOS {#claude-code-choose}

Developers pick the environment, and with it the platform, when they start a cloud session:

- **claude.ai, desktop and mobile apps:** choose **Tuist Linux** or **Tuist macOS** in the environment picker of a new session.
- **Claude Code CLI:** run `/remote-env` in `claude` and choose the environment by name. `claude --cloud "<task>"` then runs on it. To pick one for a single session, pass its ID: `claude --cloud "<task>" --environment ccpool_...`.
- **A whole team or repository:** set the default environment's ID in Claude Code [settings](https://code.claude.com/docs/en/settings), for example in a repository's `.claude/settings.json`:

  ```json
  { "remote": { "defaultEnvironmentId": "ccpool_..." } }
  ```

Sessions in these environments use your organization's Claude Code usage as usual, and their sandboxes count toward your Tuist account.
