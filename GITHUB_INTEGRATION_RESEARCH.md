# Tuist Server GitHub Integration Research

## Executive Summary
The Tuist server has a well-established GitHub integration that handles app installations, tokens, webhooks, and repository operations. This research identifies the key modules, scoping patterns, existing token/webhook patterns, and natural integration points for a dynamic runner registration and control plane.

---

## (1) KEY MODULES AND RESPONSIBILITIES

### Core GitHub Integration
**`server/lib/tuist/github/`**
- **`app.ex`**: Token lifecycle management
  - Generates app JWT from private key
  - Fetches and caches installation access tokens
  - Implements 10-minute token TTL with KeyValueStore caching
  - Clears cache on 401 responses for token refresh

- **`client.ex`**: GitHub API client (authenticated as GitHub App)
  - Lists installation repositories with pagination
  - Creates/updates/reads comments on issues/PRs
  - Manages check-runs (create, update)
  - Downloads source archives by tag
  - Fetches repository content and tags
  - All methods use installation tokens for authentication

- **`retry.ex`**: HTTP retry logic with exponential backoff
- **`releases.ex`**: GitHub release management

### VCS Context Layer
**`server/lib/tuist/vcs/`**
- **`github_app_installation.ex`** (Schema)
  - Belongs to Account (one-to-one, unique constraint)
  - Stores GitHub installation_id and html_url
  - Links account to GitHub app installations
  - Primary scoping point: account → GitHub installation

- **`comment.ex`**: VCS comment model for storing comment metadata
- **`user.ex`**: VCS user model
- **`repositories/`**: Repository content/tag models
- **`workers/comment_worker.ex`**: Async comment posting to VCS

### VCS Context Functions
**`server/lib/tuist/vcs.ex`** (Core business logic)
- GitHub installation management:
  - `get_github_app_installation_by_installation_id/1`
  - `create_github_app_installation/1`
  - `update_github_app_installation/2`
  - `delete_github_app_installation/1`
  - `get_github_app_installation_repositories/1`
  
- State token functions (prevent account-takeover):
  - `generate_github_state_token/1` – Phoenix.Token signed JWT
  - `verify_github_state_token/1` – Verify with 90-day max_age
  
- High-level VCS operations:
  - Comment creation/updates on PRs
  - Repository content fetching
  - Source archive downloads
  - Check-run status updates
  - CI URL construction for multiple providers

### Web Layer - Webhooks
**`server/lib/tuist_web/plugs/webhook_plug.ex`**
- Generic HMAC-SHA256 signature verification middleware
- Supports configurable signature headers/prefixes
- Caches raw request body for signature verification
- Returns 401 on missing signature, 403 on invalid signature
- Calls handler module's `handle/2` function with parsed body

**`server/lib/tuist_web/controllers/webhooks/github_controller.ex`**
- Handles GitHub webhook events: issue_comment, installation, check_run
- **issue_comment**: Triggers QA runs on `/tuist qa` commands in PRs
- **installation**: 
  - `created` → Updates installation URL with retries
  - `deleted` → Removes installation from DB
- **check_run**: Handles user action requests on check-run summaries
- Routes to VCS context for database operations

**`server/lib/tuist_web/controllers/github_app_setup_controller.ex`**
- Post-installation redirect handler
- Validates state token to prevent CSRF
- Creates GitHubAppInstallation record in DB
- Links installation to account

### Web Layer - Routing
**`server/lib/tuist_web/endpoint.ex`**
- Configures webhook plug for `/webhooks/github`
- Uses `{Tuist.Environment, :github_app_webhook_secret, []}` for secrets
- Also registers cache and registry webhooks using same pattern

---

## (2) TENANT/REPOSITORY SCOPING ARCHITECTURE

### Account-Level Scoping
```
Account (billing entity)
  ├── has_one :github_app_installation (unique)
  ├── has_many :projects
  └── has_many :users (via User schema)
```

**Key Point**: One GitHub app installation per Account. This means:
- An account (organization or user) installs the Tuist app once
- All projects in that account share the same GitHub app installation
- The `installation_id` is scoped to the account

### Project-Level Scoping
```
Project (account_id, name)
  ├── has_one :vcs_connection
  │   ├── provider (enum: github)
  │   ├── repository_full_handle (string: "owner/repo")
  │   └── github_app_installation_id
  ├── has_many :previews (app builds)
  └── belongs_to :account
```

**Key Points**:
- A project connects to exactly one repository via VCSConnection
- VCSConnection stores the full GitHub handle and links to the app installation
- Projects within same account can connect to different repositories
- `get_github_app_installation_id` pattern: Project → VCSConnection → Installation

### Repository Ownership
Currently implicit through:
1. GitHub app has permission on repos
2. Project's VCSConnection.repository_full_handle matches GitHub repo
3. Webhook events include repository.full_name
4. System matches webhook repo to project's VCSConnection

### Lookup Patterns
**From webhook:**
```
webhook.repository.full_name
  → Projects.projects_by_vcs_repository_full_handle(repo_handle)
  → [Project | Projects]
```

**From project:**
```
Project.id
  → load vcs_connection.github_app_installation_id
  → use installation_id for API calls
```

---

## (3) NATURAL FIT FOR DYNAMIC RUNNER REGISTRATION & CONTROL PLANE

### Recommended Location: New `tuist/runners/` Module

Based on existing patterns, a runner registration system should live in `server/lib/tuist/runners/`:

```
server/lib/tuist/runners/
├── AGENTS.md                          # Intent layer docs
├── runner_installation.ex             # Schema: Runner metadata per account
├── runner_token.ex                    # Schema: Fine-grained runner tokens
├── runner_job.ex                      # Schema: Job assignment/status
├── workers/
│   └── runner_sync_worker.ex          # Async job polling/status updates
└── (context functions in runners.ex)
```

### Design Pattern

#### 1. **Runner Installation (Account-Scoped)**
Similar to GitHubAppInstallation, but for runners:

```elixir
schema "runner_installations" do
  field :runner_id, :string              # GitHub runner ID or UUID
  field :platform, :string               # "macos", "linux", etc
  field :architecture, :string           # "x86_64", "arm64"
  field :status, :string                 # "online", "offline", "expired"
  field :endpoint_url, :string           # Control plane base URL
  field :last_heartbeat_at, :utc_datetime
  
  belongs_to :account, Account           # Scoped to account like GitHub app
  belongs_to :github_app_installation, GitHubAppInstallation
  
  timestamps(type: :utc_datetime)
end
```

**Why this pattern:**
- One per account (like GitHub installation)
- Can be linked to GitHub installation for webhook-driven operations
- Allows per-account billing/quotas
- Multiple projects in same account share runner pool

#### 2. **Runner Tokens**
Similar to AccountToken, but provider-specific:

```elixir
schema "runner_tokens" do
  field :encrypted_token_hash, :string
  field :platform, :string               # "macos"
  field :scopes, {:array, :string}       # "runners:jobs:read", "runners:heartbeat:write"
  field :expires_at, :utc_datetime
  field :last_used_at, :utc_datetime
  
  belongs_to :runner_installation, RunnerInstallation
  belongs_to :account, Account
  
  timestamps(type: :utc_datetime)
end
```

#### 3. **Runner Jobs (Project & Repository Scoped)**
Links jobs to both project and repository:

```elixir
schema "runner_jobs" do
  field :external_job_id, :string        # GitHub Actions workflow_id or custom ID
  field :git_ref, :string                # "refs/pull/123/merge" or branch
  field :status, :string                 # "pending", "queued", "running", "completed"
  field :result, :string                 # "success", "failure", "cancelled"
  field :assigned_runner_id, :string
  field :started_at, :utc_datetime
  field :completed_at, :utc_datetime
  
  belongs_to :project, Project           # Project scoping
  belongs_to :account, Account           # Account scoping
  
  timestamps(type: :utc_datetime)
end
```

### Webhook Integration Points

**Existing GitHub webhook channel:** Can be extended
```
/webhooks/github
  ├── issue_comment
  ├── installation
  ├── check_run
  └── workflow_run (NEW) ← Runner job lifecycle events
      ├── queued
      ├── in_progress
      ├── completed
```

**New runner control plane webhooks:** Similar to existing pattern
```
/webhooks/runners
  ├── health_check (heartbeat)
  ├── job_status_update
  ├── logs (streaming or batch)
```

Both would use `WebhookPlug` pattern with HMAC verification.

---

## (4) EXISTING WEBHOOK & TOKEN PATTERNS TO REUSE

### Webhook Pattern
**File:** `server/lib/tuist_web/plugs/webhook_plug.ex`

**Pattern:**
```elixir
# In endpoint.ex
plug WebhookPlug,
  at: "/webhooks/github",
  handler: GitHubController,
  secret: {Tuist.Environment, :github_app_webhook_secret, []},
  signature_header: "x-hub-signature-256",
  signature_prefix: "sha256=",
  read_timeout: 60_000

# Handler module implements:
defmodule TuistWeb.Webhooks.GitHubController do
  def handle(conn, params) do
    # event_type = get_req_header(conn, "x-github-event") |> List.first()
    # Dispatch based on event
    conn |> put_status(:ok) |> json(%{status: "ok"})
  end
end
```

**For runners, follow identical pattern:**
```elixir
plug WebhookPlug,
  at: "/webhooks/runners",
  handler: TuistWeb.Webhooks.RunnersController,
  secret: {Tuist.Environment, :runners_webhook_secret, []},
  signature_header: "x-runner-signature",
  signature_prefix: "sha256=",
  read_timeout: 30_000
```

### Token Minting & Verification Pattern
**File:** `server/lib/tuist/accounts/account_token.ex`

**Pattern for Runner Tokens:**
```elixir
# Token generation in context:
def mint_runner_token(runner_installation, attrs) do
  token_hash = :crypto.hash(:sha256, SecureRandom.uuid()) |> Base.encode16(case: :lower)
  
  attrs_with_hash = Map.put(attrs, :encrypted_token_hash, hash_token(token_hash))
  
  %RunnerToken{}
  |> RunnerToken.create_changeset(attrs_with_hash)
  |> Repo.insert()
end

# Token validation on webhook:
def verify_runner_token(raw_token) do
  token_hash = hash_token(raw_token)
  case Repo.get_by(RunnerToken, encrypted_token_hash: token_hash) do
    nil -> {:error, :invalid_token}
    token -> check_expiration_and_return(token)
  end
end
```

Reuse existing patterns:
- Encrypted hash storage (like AccountToken)
- Scope-based access control (like AccountToken.valid_scopes)
- Expiration validation
- Unique constraints on token + account

### State Token Pattern
**File:** `server/lib/tuist/vcs.ex` (lines 1001-1013)

**Pattern:**
```elixir
def generate_runner_pairing_token(account_id, runner_id) do
  Phoenix.Token.sign(TuistWeb.Endpoint, "runner_pairing", {account_id, runner_id})
end

def verify_runner_pairing_token(token) do
  Phoenix.Token.verify(TuistWeb.Endpoint, "runner_pairing", token, max_age: 3600)
end
```

This prevents CSRF/account-takeover during runner registration, identical to GitHub app installation.

### Installation Lookup Pattern
**File:** `server/lib/tuist/vcs.ex`

Reuse existing pattern for runner lookups:
```elixir
# Current GitHub pattern:
def get_github_app_installation_by_installation_id(installation_id) do
  case Repo.get_by(GitHubAppInstallation, installation_id: to_string(installation_id)) do
    nil -> {:error, :not_found}
    installation -> {:ok, installation}
  end
end

# For runners:
def get_runner_installation_by_runner_id(runner_id) do
  case Repo.get_by(RunnerInstallation, runner_id: to_string(runner_id)) do
    nil -> {:error, :not_found}
    installation -> {:ok, installation}
  end
end
```

### Async Worker Pattern
**File:** `server/lib/tuist/vcs/workers/comment_worker.ex`

**Pattern for runner sync:**
```elixir
defmodule Tuist.Runners.Workers.JobSyncWorker do
  use Oban.Worker, queue: :default, max_attempts: 5

  def perform(%Job{args: %{"runner_id" => runner_id, "job_id" => job_id}}) do
    # Fetch job status from runner control plane
    # Update runner_jobs table
    :ok
  end
end

# Enqueue pattern (from vcs.ex):
args
|> Runners.Workers.JobSyncWorker.new(schedule_in: 30)
|> Oban.insert()
```

---

## ARCHITECTURAL SUMMARY

### Project Hierarchy
```
Account (one GitHub installation)
  ├── has_many :projects
  │   ├── has_one :vcs_connection (→ GitHub repo)
  │   └── has_many :jobs (runner assignments)
  │
  ├── has_one :github_app_installation (→ GitHub)
  │
  └── has_one :runner_installation (→ Control Plane) [NEW]
      ├── has_many :runner_tokens
      └── has_many :jobs (indirect)
```

### Scoping Rules
1. **Webhooks** always include account context (via GitHub repo → project → account lookup)
2. **Tokens** are per-account, optional per-project
3. **Jobs** are per-project and per-account (dual scoping)
4. **Runners** are per-account (shared pool) but can be assigned to specific projects

### Security Boundaries
- **GitHub**: HMAC-SHA256 on GitHub-signed webhook body
- **Runners**: HMAC on runner-signed webhook + token verification
- **State tokens**: Phoenix.Token with max_age (prevents account switching)
- **Bearer tokens**: Scoped access (runners:jobs:read, etc.)

---

## FILES TO CREATE/MODIFY

### New Files (for runners)
```
server/lib/tuist/runners/
  ├── AGENTS.md
  ├── runners.ex                        # Context functions
  ├── runner_installation.ex            # Schema
  ├── runner_token.ex                   # Schema
  ├── runner_job.ex                     # Schema
  └── workers/
      └── runner_job_sync_worker.ex     # Oban worker

server/lib/tuist_web/controllers/webhooks/
  └── runners_controller.ex             # Webhook handler

server/priv/repo/migrations/
  ├── *_add_runner_installations_table.exs
  ├── *_add_runner_tokens_table.exs
  └── *_add_runner_jobs_table.exs
```

### Modified Files
```
server/lib/tuist/vcs.ex
  + Runner installation lookups (if shared context) OR keep in runners.ex

server/lib/tuist_web/endpoint.ex
  + Register /webhooks/runners plug

server/lib/tuist_web/router.ex
  + Runner registration/pairing endpoints (likely under scope "/integrations/runners")

server/lib/tuist/accounts/account.ex
  + Add has_one :runner_installation association

server/data-export.md
  + Document runner_installations, runner_tokens, runner_jobs tables
```

---

## REFERENCES

### Code Files Reviewed
- `server/lib/tuist/github/{app.ex, client.ex, retry.ex}`
- `server/lib/tuist/vcs/{github_app_installation.ex, comment.ex, .ex}`
- `server/lib/tuist_web/plugs/webhook_plug.ex`
- `server/lib/tuist_web/controllers/webhooks/github_controller.ex`
- `server/lib/tuist_web/controllers/github_app_setup_controller.ex`
- `server/lib/tuist_web/endpoint.ex`
- `server/lib/tuist/accounts/{account.ex, account_token.ex}`
- `server/lib/tuist/projects/{project.ex, vcs_connection.ex}`

### Key Patterns
- **Token lifecycle**: `server/lib/tuist/github/app.ex` (installation token caching)
- **Webhook security**: `server/lib/tuist_web/plugs/webhook_plug.ex` (HMAC verification)
- **State tokens**: `server/lib/tuist/vcs.ex:1001-1013` (Phoenix.Token signed state)
- **Account scoping**: `server/lib/tuist/vcs/github_app_installation.ex` (one per account)
- **Fine-grained tokens**: `server/lib/tuist/accounts/account_token.ex` (scopes + expiration)
