# LLM connections and transport

- `Runner.with_reply_stream/5` owns transient reply sessions. Local mode must use the buffered Condukt run path: ReqLLM's direct Finch streaming transport bypasses Req's Plug adapter. Buffer only the model delivery, not tool execution or session auditing; preserve provider errors, no-reply decisions, and supersession checks in the Slack consumer. External-provider replies retain incremental streaming. Do not make the sentinel `atlas-local` hostname network-reachable as a workaround.

- `Runner.profile_client_opts/2` binds a caller to one Atlas inference role (`{LocalTransport, role: role}`), independent of `LLM_MODE`. An explicit role serves only chat completions and returns 503 when no enabled profile and role token exist; it never substitutes another role's profile. Orbit uses this with the `orbit` role, which has no output cap.
- `Connections` owns per-user Claude setup tokens and ChatGPT device authorization, independent of `Atlas.LLMs`'s server-wide inference configuration. Orbit uses `Runner.orbit_client_opts/2`: `ModelFence` wraps `PersonalTransport`, which reloads only the acting user's credentials on every model turn (also children and resumes). Prefer ChatGPT, then Claude; fall back only to the explicitly bound `orbit` role for missing/unavailable accounts, auth/billing/rate limits, or transport errors. Invalid requests do not trigger provider hopping. Never borrow a thread owner's or another participant's connection. `Runner.orbit_configured?/1` is a metadata-only readiness check; saved credentials are not proof of working provider access.
- `PersonalProviders` translates the buffered OpenAI protocol to ChatGPT's Codex Responses endpoint (`store: false`, SSE with a successful terminal event) and Claude's subscription Messages protocol (bearer token plus OAuth beta/CLI identity, not `x-api-key`). Preserve tool IDs, argument JSON, results and image content. Model defaults are `gpt-5.4` and `claude-sonnet-4-6`. Upstream eligibility/terms still apply; fixture tests do not prove real subscription access. External calls have 45-second receive and five-second connect budgets, with no automatic retries or redirects; the existing four-minute run ceiling is unchanged. Return sanitized status-only failures, never provider bodies or raw transport exceptions. Session options carry only the user ID, not credentials.
- Credential-bearing `Connection` structs and `credentials/2` results are server-only. Dashboard, API, and MCP return explicit metadata maps, never tokens, pending device IDs, authorization codes, or PKCE verifiers. Cloak encrypts all credential fields and redacts inspection. Failed provider responses must remain sanitized; never log Req requests or responses.
- Every mutation and credential refresh locks the owning user row in PostgreSQL. Keep external exchanges bounded and without retries or redirects while that lock is held. Configure the ChatGPT connection timeout through Req's `finch: [conn_opts: [transport_opts: ...]]` pool options; top-level `connect_options` conflicts with Atlas's named default Finch pool. Transport regression tests exercise Req's real setup and stub only Finch's network request. Disconnect must not be undone by an in-flight login or refresh. Device polls require the current user and an opaque login ID, expire after 15 minutes, and enforce the upstream polling interval in the database. Cancellation preserves an existing connection; disconnect removes both saved credentials and pending login.
- ChatGPT device authorization needs an explicitly configured `ATLAS_CHATGPT_CLIENT_ID` with this upstream flow enabled; there is no built-in client ID fallback. The supported deployment requires an Atlas-authorized client. As a temporary, explicitly operator-requested exception, Tuist's managed production overlay sources the public Codex client used by Pi from `atlas-chatgpt-oauth/client_id` in 1Password through its application ExternalSecret; this is not confirmation of OpenAI approval and must not become a standalone default. Replace that 1Password field once an Atlas client is provisioned, wait for Secret reconciliation, and restart Atlas; existing connections may need reauthorization when the client changes. The transport follows the published OpenAI Codex device flow (`codex-rs/login/src/device_code_auth.rs`); it is not a generic OpenAI API-key flow. Operator/provider eligibility is required and real account authorization needs staging validation.
- Claude's pasted `claude setup-token` credential is a subscription token, not an Anthropic API key. Saving is format validation, not a provider access check, and provider terms apply. Never imply a stored token has verified inference access or seed actual credentials.
- Audit actions record the actor, interface, provider and settings path, never credentials or provider responses. Personal settings are `/settings/llm-providers`; API endpoints are under `/api/me/llm-providers`. The MCP surface supports metadata reads, Claude create/update, ChatGPT start/poll/cancel, and disconnect. Claude setup tokens are input-only and require explicit user approval because MCP clients/models may retain them; prefer the browser form. Omit the entire argument payload of the credential-entry and device-login tools from Atlas's MCP audits, including failed calls and malformed inputs. Start returns only the owner-scoped login handle and user-facing authorization instructions, never the upstream device ID or tokens.
- Data inventory and deletion/export guidance are in `atlas/data-export.md`.

ChatGPT explicitly uses GPT-5.4's supported non-reasoning mode (`reasoning.effort: none`)
because Condukt's buffered chat protocol cannot retain opaque Responses reasoning items.
An empty reasoning envelope (`summary: []`, without nonempty content or encrypted state)
does not invalidate a completed response. Nonempty reasoning still fails closed rather
than losing required state between tools. Public model documentation is not proof that
a particular subscription account or the Codex backend accepts the request.
Treat SSE `response.failed`, `error`, and `response.incomplete` as failures even with
HTTP 200. Codex may send complete items in `response.output_item.done` and omit
output/status from the terminal metadata. Buffer done items, but never accept them
without successful completion or substitute text/argument deltas for complete items.
Only allowlisted structured codes/types can select a more specific status;
never classify message text. Personal-provider failures emit fixed provider/category/status
diagnostics to Logger and the current OpenTelemetry span, never bodies or credentials.
Claude `max_tokens` stops are incomplete, not permission to execute a partial tool call.
Keep real Condukt + ReqLLM + Req fixture tests across parallel tool continuation; stub
only Finch's network boundary. Synthetic fixtures do not establish live compatibility.
Sanitized HTTP 504 preserves personal-provider timeouts; upstream 503 is an outage, not
missing configuration. Only the fixed `not_configured` error code means no account/fallback.

Anthropic's [authentication and credential-use policy](https://code.claude.com/docs/en/legal-and-compliance#authentication-and-credential-use)
does not permit third-party applications to collect/intermediate Claude subscription
credentials. `claude setup-token` documentation describes use by Claude Code, not an
approved custom Messages transport. Do not add identity/header spoofing to bypass
provider restrictions; a supported integration needs an approved provider arrangement
or the existing explicitly configured Orbit inference role.
