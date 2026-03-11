# Tuist GitHub Integration - Quick Reference

## Key Modules at a Glance

| Module | File | Purpose |
|--------|------|---------|
| **Tuist.GitHub.App** | `server/lib/tuist/github/app.ex` | Token lifecycle: JWT generation, installation token caching (10min TTL), cache invalidation |
| **Tuist.GitHub.Client** | `server/lib/tuist/github/client.ex` | GitHub API operations: repos, comments, check-runs, archives, content |
| **Tuist.VCS.GitHubAppInstallation** | `server/lib/tuist/vcs/github_app_installation.ex` | Schema: maps Account 1:1 to GitHub installation_id |
| **Tuist.VCS** | `server/lib/tuist/vcs.ex` | Context functions for installation CRUD, state tokens, high-level VCS ops |
| **TuistWeb.Plugs.WebhookPlug** | `server/lib/tuist_web/plugs/webhook_plug.ex` | Generic HMAC-SHA256 webhook signature verification |
| **TuistWeb.Webhooks.GitHubController** | `server/lib/tuist_web/controllers/webhooks/github_controller.ex` | GitHub webhook handler: issue_comment, installation, check_run events |
| **TuistWeb.GitHubAppSetupController** | `server/lib/tuist_web/controllers/github_app_setup_controller.ex` | Post-install redirect, state token verification, DB linkage |

## Scoping Hierarchy

```
Account (billing/multi-tenant)
  ├─ 1:1 GitHubAppInstallation (installation_id from GitHub)
  ├─ N:1 Project (account_id)
  │   └─ 1:1 VCSConnection (repo_full_handle, github_app_installation_id)
  └─ N:1 User
```

**Key Rules:**
- One GitHub app installation per account
- All projects in account share same installation
- Each project connects to exactly one repository
- VCSConnection holds the explicit link to installation

## Webhook Flow

```
GitHub → /webhooks/github (port 443, HMAC verified)
    ↓
TuistWeb.Plugs.WebhookPlug
    ├─ Verify "x-hub-signature-256: sha256=..." header
    ├─ Parse JSON body
    └─ Call TuistWeb.Webhooks.GitHubController.handle/2
        ↓
        Read "x-github-event" header
        ├─ "installation" → get_github_app_installation_by_installation_id → CRUD
        ├─ "issue_comment" → find project by repo → create comment
        └─ "check_run" → find project by repo → update check-run
```

## Token Patterns

### Installation Token (GitHub App → Access Token)
**Location:** `Tuist.GitHub.App.get_installation_token/1`
- Generate JWT from app private key (`GITHUB_APP_PRIVATE_KEY` env)
- POST to GitHub API: `/app/installations/{id}/access_tokens`
- Cache for 10 minutes in Cachex
- 401 response clears cache (token expired, fetch fresh one)
- Used for all GitHub API calls on behalf of app

### State Token (Account Registration CSRF Prevention)
**Location:** `Tuist.VCS.{generate,verify}_github_state_token/1`
- Phoenix.Token.sign/verify wrapper
- Used: `/integrations/github/setup?state={token}`
- Max age: 90 days
- Purpose: Prevent account takeover during GitHub app install

### Runner Token (Proposed)
**Pattern to follow:**
- Encrypted hash storage (like `AccountToken`)
- Scoped access: `runners:jobs:read`, `runners:heartbeat:write`
- Expiration validation
- Per-account unique constraint

## Webhook Endpoint Configuration

**File:** `server/lib/tuist_web/endpoint.ex`

```elixir
plug WebhookPlug,
  at: "/webhooks/github",
  handler: GitHubController,
  secret: {Tuist.Environment, :github_app_webhook_secret, []},
  signature_header: "x-hub-signature-256",
  signature_prefix: "sha256=",
  read_timeout: 60_000
```

**For runners:**
```elixir
plug WebhookPlug,
  at: "/webhooks/runners",
  handler: TuistWeb.Webhooks.RunnersController,
  secret: {Tuist.Environment, :runners_webhook_secret, []},
  signature_header: "x-runner-signature",
  signature_prefix: "sha256=",
  read_timeout: 30_000
```

## Runner Control Plane Natural Fit

**Location:** `server/lib/tuist/runners/` (new module)

**Components:**
1. **RunnerInstallation** schema (per account, like GitHubAppInstallation)
2. **RunnerToken** schema (fine-grained, like AccountToken)
3. **RunnerJob** schema (per project assignment)
4. **Runners context** (CRUD + token management)
5. **RunnersController** webhook handler
6. **JobSyncWorker** (Oban async sync)

**Scoping:**
- One RunnerInstallation per Account
- Multiple RunnerTokens per Installation
- Jobs assigned to Projects (dual-scoped: account_id + project_id)
- Runners shared pool within account

## Data Export Impact

**File to update:** `server/data-export.md`

**Tables to document:**
- `github_app_installations` (account_id, installation_id, html_url)
- `vcs_connections` (project_id, repository_full_handle, github_app_installation_id)
- `runner_installations` (account_id, runner_id, platform, status)
- `runner_tokens` (account_id, runner_installation_id, scopes, expires_at)
- `runner_jobs` (account_id, project_id, external_job_id, status)

## Common Lookup Patterns

### By Installation ID
```elixir
Tuist.VCS.get_github_app_installation_by_installation_id(installation_id)
# Returns {:ok, GitHubAppInstallation} or {:error, :not_found}
```

### By Repository Handle
```elixir
Tuist.Projects.projects_by_vcs_repository_full_handle("owner/repo")
# Returns [Project, ...] (projects connected to this repo)
```

### From Project to Installation
```elixir
project = Repo.preload(project, vcs_connection: :github_app_installation)
installation_id = project.vcs_connection.github_app_installation.installation_id
# Use installation_id for API calls
```

### Webhook Account Context
```elixir
webhook_repo = params["repository"]["full_name"]
case Projects.projects_by_vcs_repository_full_handle(webhook_repo) do
  [] -> {:error, :repository_not_connected}
  [project] -> {:ok, project}  # Implicit account: project.account_id
  multiple -> {:error, {:multiple_projects, multiple}}
end
```

## Security Boundaries

| Boundary | Mechanism | Enforced By |
|----------|-----------|------------|
| Webhook authenticity | HMAC-SHA256 on body | WebhookPlug |
| Account takeover (install) | Phoenix.Token with max_age | VCS state token |
| Installation token expiry | Cache TTL + 401 refresh | GitHub.App.get_installation_token |
| Token scope enforcement | LetMe.Policy + scopes array | Authorization module |
| Runner identity | Encrypted hash + expiration | RunnerToken (proposed) |

## Files to Review for Runners Implementation

1. **Schema examples:** `github_app_installation.ex`, `account_token.ex`
2. **Context pattern:** `vcs.ex` (installation CRUD + functions)
3. **Webhook handler:** `github_controller.ex` (event dispatch)
4. **Webhook config:** `endpoint.ex` (plug registration)
5. **State token:** `vcs.ex` lines 1001-1013
6. **Token lifecycle:** `github/app.ex` (caching + refresh)
7. **Async worker:** `vcs/workers/comment_worker.ex` (Oban pattern)
8. **Authorization:** `authorization.ex` (policy definitions)

## Testing Patterns

**Webhook signature verification:**
```elixir
# See WebhookPlug tests
body = Jason.encode!(%{test: "data"})
signature = generate_hmac_signature(body, secret)
conn = post(conn, "/webhooks/runners", body, headers: [{"x-runner-signature", signature}])
```

**Token validation:**
```elixir
# Create token, hash it, verify against DB
raw_token = "abc123xyz"
hashed = hash_token(raw_token)
{:ok, token} = Runners.verify_token(raw_token)
```

**State token:**
```elixir
token = VCS.generate_github_state_token(account.id)
{:ok, ^account_id} = VCS.verify_github_state_token(token)
```
