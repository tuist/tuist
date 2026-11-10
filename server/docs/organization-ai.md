# Organization AI routing

Organization Settings → AI has **Providers**, **Models**, and **Default model**
sections for upcoming organization workflows. Each provider entry is a named
connection with its own API key; multiple entries can use the same provider service.
The **Provider** selector offers OpenAI, Fireworks AI, Together AI, and **Custom**.
Named providers supply their names and API base URLs automatically and only ask
for an API key. Choosing Custom reveals editable name and API base URL fields,
supporting any public HTTPS OpenAI-compatible Chat Completions endpoint with
bearer-key authentication. The selector is not persisted; routing uses the saved
endpoint. These API keys are
separate from ChatGPT/Claude subscription sessions. Personal threads continue to
use personal subscriptions; this change does not redirect existing threads or
enable a new workflow.

## Configuration data

- `organization_ai_connections` stores `id`, `organization_id`, `name`, the
  `base_url` (including any API version prefix), encrypted `api_key`, and
  `inserted_at`/`updated_at`. An organization can have multiple connections for
  the same provider, and each connection can serve several configured models.
- `organization_ai_models` stores `id`, `organization_id`, `connection_id`,
  `name`, `model_id` (the exact upstream model ID), and
  `inserted_at`/`updated_at`. Credentials belong to the connection, not the model.
- `organization_ai_defaults` stores `id`, unique `organization_id`, `model_id`
  (a foreign key to a configured model's `id`, not its upstream `model_id`), and
  `inserted_at`/`updated_at`. There is at most one default per organization.

Foreign keys enforce organization ownership across the connection, model and
default relationships. Creating a connection or model never selects a default;
an administrator must select it explicitly. Removing a connection cascades its
models and any default referencing one of them. Removing the default model
clears the default without selecting a replacement.

## Contract

- `Tuist.Accounts.OrganizationAI` exposes `settings/2`, `save_connection/3`,
  `remove_connection/3`, `save_model/3`, `remove_model/3`, `set_default/3`, and
  `complete/2`. Settings reads and configuration writes reload the account and
  require organization account-update authorization.
- Every settings read, configuration write and inference call requires
  `FeatureFlags.organization_ai_enabled?(account)`, checking `:ai` on the
  organization account, not the administrator, in **every environment**.
  Unlike personal `FeatureFlags.ai_enabled?/1`, this strict gate does not inherit
  enabled defaults in development, test or staging.
- Keys are encrypted at rest by `Tuist.Vault` (AES-GCM), redacted from inspection,
  and never returned by settings or retained in LiveView assigns. A blank key
  preserves the existing connection's credential only when the base URL stays
  unchanged. Changing the base URL requires explicitly entering the key again,
  even when it is the same key, so a saved secret cannot silently move hosts.
  Rotating a key affects every model using that connection. Saving validates
  syntax, not remote model access or key validity.
- `complete(account, messages)` is the server-side entry point for future
  **already-authorized** workflows. The caller must establish the workflow's
  owning account, never take it from an unauthenticated request. Each call
  reloads the account, checks the strict organization flag, and reads the
  explicitly selected default model and its connection/key from PostgreSQL.
  Without a default, inference is unavailable. There is no authoritative
  process-local state or sticky session.
- Inference uses buffered OpenAI-compatible Chat Completions. The configured
  provider and model cannot be overridden by request options. Requests append
  `/chat/completions` to the saved base URL. URLs must use public HTTPS without
  embedded credentials, query parameters or fragments; private destinations
  are unsupported, including on self-hosted installations. Every dispatch uses
  `OAuth2.SSRFGuard` to resolve and validate all DNS addresses, then
  `OAuth2.PinnedHTTP` to connect to that exact IP with the original TLS hostname.
  Each request uses an unpooled connection, a 60-second receive deadline and a
  4 MiB response limit. Redirects and automatic retries are disabled, and errors
  expose status codes rather than upstream bodies or credential-bearing request
  structs. No provider, platform-key, or personal-subscription fallback exists.
- All configuration writes serialize by locking the organization row, including
  first creation, edits, removals and default selection. Removing a connection
  prevents subsequent inference through it; already-dispatched inference can
  finish. Key rotation/removal does not revoke the upstream key. Disabling `ai`
  retains configuration but blocks new inference and all configuration access.
- This layer does not store prompts, completions or conversation sessions, and
  has no refresh-token lifecycle: provider API keys are rotated by admins.
  Streaming, tool orchestration, model catalogs, workload-specific routes,
  automatic failover and spend budgets are not part of this initial contract.

Migrate PostgreSQL before enabling organization access. The export inventory
is in [data-export.md](../data-export.md). No provider request is made merely
by opening or saving settings.

## Product research

Official public documentation reviewed November 7, 2026:

- [Raycast organization BYOK](https://manual.raycast.com/enterprise/byok)
  documents manager-configured provider keys and optional enforcement. Its
  [provider allow-list](https://manual.raycast.com/enterprise/provider-allow-list)
  is a separate governance control.
- [Raycast custom providers](https://manual.raycast.com/enterprise/custom-provider)
  accepts organization-wide OpenAI-compatible endpoint/model configuration.
  Keys in that YAML are distributed to members' clients. Tuist instead retains
  provider credentials server-side and validates/pins custom endpoints.
- [Raycast subscriptions](https://manual.raycast.com/ai/bring-your-own-subscription)
  use locally authenticated Claude Code/Codex tools, not centrally shared
  organization subscription sessions.
- [Linear cloud coding agent](https://linear.app/docs/linear-cloud-coding-agent)
  documents workspace model selection, admin controls and team scoping;
  [AI credits](https://linear.app/docs/ai-credits) documents pooled workspace
  billing. These sources do **not** establish customer BYOK inference support.
  Coding environment secrets must not be mistaken for inference credentials.

The initial design borrows workspace governance from Linear and explicit BYOK
ownership from Raycast, without implicitly moving organization data between
providers on failure.

Provider protocol references:
[OpenAI](https://developers.openai.com/api/reference/overview),
[Fireworks](https://docs.fireworks.ai/tools-sdks/openai-compatibility), and
[Together](https://docs.together.ai/docs/inference/openai-compatibility).
