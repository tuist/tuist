# Atlas Automation

Automation is a scoped control plane under `/automation`: workflows, behaviors, executions, schedules, webhooks, and approvals. Domain entry points and MCP tools enforce `automation:read` / `automation:write`; execution rechecks the initiating user's current permissions. These scopes never grant permissions to other domains.

Workflow drafts accept JSON plans or JavaScript that returns a plan. Publishing creates an immutable revision with a validated, bounded sequence of steps and pinned behavior configurations. References use `{"$ref": "input.field"}` or `{"$ref": "steps.step_id.field"}` and may only read prior outputs. This initial executor deliberately supports at most 32 ordered steps, not arbitrary graphs or dynamically generated work. Object contracts enforce 64 KiB payload and 32-level nesting budgets before JSON encoding, including after reference expansion; compiled plans are capped at 256 KiB.

The dashboard presents the published definition and a single create/save-new-version action. `save_workflow_version/4` validates and compiles before opening a database transaction, then saves the definition and immutable revision together under a workflow lock. Invalid saves leave no changes; expected revision IDs and a post-compilation fingerprint prevent stale writers. Cancel is client/UI state only. Runs and triggers remain pinned, and compiled execution plans are an internal inspection detail, not a second editable workflow. MCP exposes atomic publication through `save_automation_workflow` with `publish: true`; the separate draft/validate/publish operations remain available for advanced clients.

Behaviors are registered built-in types (`core.value`, legacy `tasks.create`, `javascript.evaluate`), explicitly registered platform-domain operations and saved configurations. Domain configurations persist an exact `name@version` reference, not a floating latest-version lookup. JavaScript only computes JSON or constructs plans, never invokes host tools. `Atlas.Automations.JavaScript` compiles and runs through a Linux isolated Javex runtime; unsupported platforms fail closed. Do not fall back to in-process execution for user/agent code. Isolated compile/run deadlines include cold worker startup and provider compilation, so both use a bounded 30-second wall-clock budget; the 5-million-fuel, 16 MiB guest, 512 MiB process, and concurrency-two limits remain independent. Keep the Linux integration test's deadline long enough for its five isolated evaluations, and assert compilation succeeds even for programs expected to fail at execution. Native agent sessions and coding sandboxes are different boundaries; see `../agents/AGENTS.md`.

Runs pin revisions and persist step attempts, resolved inputs, outputs, approval decisions, and executor placement. PostgreSQL transactions/row locks serialize state transitions. Local database actions commit their results with their attempt records; do not add external effects without action-specific idempotency and ambiguous-outcome reconciliation. Oban transports work on a bounded `:automation` queue, not authoritative workflow state. Future remote executors must retain the same run/attempt identities and reject stale results.

Execution observability is durable, not a capture of arbitrary process stdout. `automation_events` holds payload-free, fixed-message structured events ordered by a transactionally allocated per-run sequence; paginate reads, never preload the entire event history. Attempts have microsecond start/end timestamps, measured behavior execution time, approval-wait timestamps/durations, Oban delivery ownership and sanitized diagnostics. Missing historical measurements remain nil, not estimated zero. Precise run trace timestamps are separate from the existing second-precision business/analytics timestamps.

A short claim transaction persists a running attempt before the action transaction. The latter locks the run, rechecks permissions and claim status, and commits local effects with cursor/output progress. Cancellation fences the claim. Only a higher attempt of the same Oban job may recover a still-running claim; another delivery snoozes. Exceptions are diagnosed after rollback; transport retries preserve failed attempts and committed progress. Oban exception telemetry handles interrupted owned claims, while Lifeline redelivery recovers claims after node loss. A whole-node outage cannot emit its own immediate failure event; recovery evidence appears on redelivery. This is local-worker fencing, not a remote-executor lease protocol.

`Tracing` creates OpenTelemetry admission, worker, step and approval-wait spans, persists W3C IDs and restores process context after each scope. The admission span ends at admission, not after a potentially multi-day approval; elapsed workflow timing comes from the durable trace view. Payloads/source/credentials, exception messages, stack arguments and locals must never enter trace attributes or event metadata. Diagnostics include only exception class and at most ten MFA/line frames. `get_automation_execution_trace` provides reader-scoped, payload-free trace inspection and event pagination; the existing execution getter remains the protected payload view.

Tracing export defaults to disabled. Operators can set standard `OTEL_TRACES_EXPORTER=otlp`, `OTEL_EXPORTER_OTLP_ENDPOINT`, protocol/headers and resource environment variables to configure a collector. Keep exporter credentials out of URLs. An optional `ATLAS_AUTOMATION_TRACE_URL_TEMPLATE` containing `{trace_id}` enables an external trace link; only HTTP(S) URLs without embedded credentials are accepted. Durable events/timings remain available without a collector. Retention follows runs with cascading event deletion, with no new automatic expiry.

Approvals persist the exact payload and reviewer; only that reviewer with current write permission may decide. Resuming does not accept payload overrides. Webhooks use a high-entropy bearer credential stored only as a hash, require a bounded delivery ID, and bind to a specific published revision and execution identity. Schedules use UTC cron, coalesce missed occurrences, and skip overlapping nonterminal runs. Pausing a trigger prevents new admissions, not already-admitted runs.

`Analytics` aggregates executions by UTC admission date over at most 90 days plus the preceding comparison period. Workflow scoping includes every revision. Read aggregate counts and elapsed-time sums in PostgreSQL, never run payloads; use the `inserted_at` range index and zero-fill only counts. Rates and durations without observations stay nil; average durations are sample-weighted and include queue/retry/approval time, not CPU or step time. Finished outcomes include success, failure, rejection, and cancellation. Awaiting approval counts currently waiting runs in the selected admission cohort, not historical backlog. Execution history accepts the same bounded period/workflow filters; unfiltered MCP history retains its existing all-time behavior. The UI loads asynchronously and caches by scope/date window; metric switches and pagination reuse results, while periodic refresh rechecks permissions and current statuses.

`Native` projects published workflows, personal execution history, assigned exact-payload
approvals and payload-free execution steps for native clients. Admission binds a
published revision and actor-scoped UUID request key under a transaction advisory lock;
replays must match workflow, revision and input, even after a new publication. MCP
`run_automation_workflow` exposes the same optional revision/request pair. Query pages
are bounded to 20. Protected result reads are separate and capped at 64 KiB for native
display; larger results remain available through the protected web/MCP getters.
Approval payloads/results are server-serialized JSON strings for native display, so
platform JSON numeric coercion cannot round what the reviewer sees. Compact JSON
is used if pretty formatting exceeds 128 KiB. Progress elapsed time is server-measured;
missing terminal timings stay nil.

`Notifier` publishes run-ID-only hints through the existing Oban PostgreSQL notifier
inside event transactions, so notifications become visible only after commit and reach
other replicas. Skip nontransactional test/PG notifiers. Each authenticated execution
channel subscribes before its authoritative join snapshot and reconciles every five
seconds thereafter. Socket authentication must be enabled at the endpoint socket level
(`auth_token: true`), not only inside WebSocket options. Each update rechecks Guardian access-token
revocation and current domain permission, and terminates on lost access. Hints are not
state; missed hints/reconnects must never lose durable progress. Automation does not integrate background execution/approval notifications or a Live
Activity extension. Other fixed notification kinds use the separate native push
subsystem and its device registrations; do not claim Automation delivery through it.

## API and MCP primitive interfaces

`Interfaces` is the shared inventory of operation name, scope, HTTP method/path and
MCP tool. The router derives API routes from it, and MCP derives its read/write tool
registrations from it. `Interface` owns the common closed input schemas, dispatch and
serialization; HTTP and MCP are thin adapters with their own error formatting and
`api`/`mcp` audit attribution. Do not add a transport-only mutation or duplicate a
schema in a controller/tool. Catalog discovery (`GET /api/automation/types` and
`list_automation_types`) returns primitive lifecycle rules and each operation's full
API path, MCP name, input schema and output schema.

| Primitive | Creation / reads / mutations |
| --- | --- |
| Registered behavior types | Code-defined; list/get only. Never upload host implementations. |
| Workflows | Create, list/get, partial draft update, validate, publish/save new version, run. Only creator-owned drafts with no revisions can be deleted. |
| Saved behavior configurations | Create, list/get, creator-owned partial update/delete. Published plans embed snapshots, so these edits/deletions cannot rewrite existing executions. Drafts referencing a deleted ID need replacement before publication. |
| Revisions | Publication creates them; list by workflow/get. No arbitrary update/delete. |
| Executions | Run creates them; list/get/trace, initiator-owned retry/cancel. No raw CRUD overwrite or history deletion. |
| Attempts / events | Executor-managed, read by ID or bounded run-scoped pages. No user creation/overwrite/deletion. |
| Approvals | Execution-managed, list/get, assigned reviewer decision only. Payloads and history cannot be edited/deleted. |
| Triggers / schedules / webhooks | Create, list/get, execution-owner partial update/delete. Kind, pinned revision and execution identity stay fixed. Webhook credential rotation returns a new secret once and invalidates the old one. Already-admitted executions survive trigger deletion. |

Canonical routes live under `/api/automation`; schedules/webhooks also have kind-bound
collection/detail CRUD aliases. Revisions, attempts and events have nested scoped list
routes. Unsupported methods return 405 with actual allowed methods rather than
bypassing the lifecycle. Authenticated responses carry `no-store`; access requires a bearer token;
serializers exclude credential hashes. Page size is 20. Trigger changes/deletion and
workflow deletion/publication serialize on row locks; scheduling tolerates IDs removed
after the due scan. Published workflow deletion is deliberately rejected to protect
its immutable revisions and dependent execution evidence.

`interfaces_test.exs` checks unique operations, API route/MCP registration/schema
parity, primitive discovery and scope classification. Controller/resource tests cover
cross-transport CRUD, ownership, immutable records, credential rotation, safe deletion
and execution of old snapshots after configuration changes/deletion. Keep these gates
current when adding a primitive or operation. This transport inventory is separate from the domain behavior registry described below.

## Table controls

Every Automation inventory reuses the server's compact Noora search / Sort by / Filter toolbar, removable active filters and sortable column headers, including empty tables. Keep toolbar, chips, table, empty state and pagination in one white `card_section`, never a separate bordered search panel. `AtlasWeb.AutomationLive.Table` owns bounded URL state and the shared presentation. Workflow filters cover publication and effective definition language; saved configurations filter by behavior type; execution filters cover status and trigger; schedules/webhooks filter enabled/paused status and workflow; approvals filter pending/approved/rejected/cancelled status, workflow and reviewer. Type catalog filters cover domain, effect, permissions and approval. Configuration controls use `config_`-scoped state so they cannot filter or reorder the independent type catalog on the same page.

Query/sort/filter changes reset numbered pagination, preserve other controls and the date/metric selection, and do not reload unchanged analytics. Refresh and pagination retain table controls. Filtering to zero results keeps the toolbar and active chips available. Text filters use the existing Noora popover and option filters the existing dropdown; neither needs custom client JavaScript.

`ListQuery` and `ExecutionQuery` apply metadata-only search, allowlisted ordering and filters to the authorized SQL query before Flop pagination, with stable ID tie breakers, null-last ordering and escaped LIKE wildcards. Search never examines inputs, outputs, configuration bodies, source, exact approval payloads or credential hashes. Workflow names/descriptions, saved configuration names/types/descriptions, trigger names/workflows/cron/endpoint IDs and approval step/workflow/reviewer labels are searchable metadata. Execution search matches workflow name or execution ID only. API/MCP lists expose the same optional metadata controls. Do not filter or sort a single loaded page. The bounded, code-defined type catalog is filtered/sorted in memory; schema/permission checks remain independent of display state.

## Platform-domain behavior contracts

The `time_off_approvals` authorization area and new personal provider/leave tools from the native workspace are explicitly excluded, not automatically converted into workflow behaviors. Their reviewer/credential ownership rules require dedicated adapters. Registry coverage accepts a domain only when it has a registered behavior or an explicit excluded policy; preserve all published operation contracts when adding inventory classifications.

Shared Moodboard resource and discussion tools are explicitly excluded from workflow behaviors. Authenticated dashboard/MCP access does not grant workflow authority over contributor-owned resources or author-owned comments. Keep both the contract ledger and its projection helper exclusions current until dedicated adapters are versioned.

Personal self-description tools (`get_my_profile`, `update_my_profile`) are also explicitly excluded in the ledger and its projection helper: private caller context must not enter shared workflow outputs, and profile changes require the caller's explicit request rather than automated inference. Keep that exclusion covered by the registry tests when adding self-service MCP tools.

`DomainRegistry` compiles the explicit `priv/automation/contracts/v1.json` ledger. It is not runtime MCP discovery or a blanket exposure of internal functions. The ledger classifies every static MCP tool as supported or explicitly excluded and records domain policies. `Catalog` resolves exact operation versions; immutable plans embed their configuration/input/output contracts. Bare domain names resolve at publication, while `name@version` is preferred for deliberate authoring. Bare `tasks.create` remains the old v1 contract (`task_id`, `title`); the fuller task contract is `tasks.create@2`.

`DomainRuntime` reuses approved, static MCP serialization adapters or `LocalOperations`, enforcing current domain scopes and source-tool allowlisting independently of Automation scopes. Source-tool authorization is name-based, so an old version's implementation can remain pinned even if the current MCP module changes. Do not silently route old versions to a new handler. Validate resolved inputs before invocation, normalize bounded JSON output, validate output against the frozen contract and commit effects with run progress. Invalid/oversized output rolls back domain mutations and records failure separately. Runtime errors use fixed messages, not provider/domain payloads.

Compiled domain plans carry derived read permissions. `DomainAccess` applies them in SQL to workflow definitions, revision/run/evidence/trigger reads, analytics and native results/progress/approvals. Automation read access does not imply permission to inspect another domain's captured outputs. Assigned reviewers also need those read permissions. Keep the native and generic resource paths covered; never add a payload getter that bypasses this filter. Protected Automation execution/source getters are deliberately not workflow behaviors, which would otherwise copy domain-protected data into a less-restricted plan.

Destructive and sensitive operations require a prior, assigned-reviewer approval in the same run. Its exact payload is `{"behavior":"notes.delete","version":1,"step_id":"delete_note","input":{"id":"..."}}`, matching the target action's resolved input, operation version and step ID. A generic approval, another step's approval or an altered input is insufficient. External mail/postal sends, credentials/grants, arbitrary queries, agent/vector operations and unsupported provider writes remain excluded until an explicit safe adapter supplies idempotency and ambiguous-outcome reconciliation.

Local search indexing uses `Search.with_deferred_vectors/1`: only commit-bound Oban jobs carry record IDs to vector maintenance, never network effects inside the action transaction. Account-handle cache changes inside a transaction use the existing authoritative 30-second reload rather than broadcasting uncommitted snapshots.

Compatibility gates:
- `ContractCompatibility` and the database/dependency-free `scripts/check_automation_contracts.exs` compare the ledger against the PR base in CI. Existing identities, handlers, schemas, permissions, approval requirements and execution modes cannot change or disappear; add an explicit version and retain the old adapter.
- `scripts/update_automation_contracts.exs` is the explicit reviewed inventory/projection helper (`mix run scripts/update_automation_contracts.exs` from `atlas/`), not permission to overwrite published contracts. The base comparison prevents regenerating away a breaking change.
- Registry tests cover exact dispatch, every supported/excluded MCP tool, every authorization area, schema drift and missing domain permissions. Existing MCP domain fixtures also validate frozen output contracts when they exercise that exact handler; keep separate version fixtures when adapters diverge.
- `Composition` rejects known missing output fields, incompatible types and invalid literal input for registered operations. Open schemas and dynamic outputs still require execution-time validation; do not claim complete static JSON Schema subsumption.
- Published task/note workflows exercise composition, exact approvals, configuration deletion/pinning, current authorization, read-scope propagation and transactional output-failure rollback. Extend these real workflows when adding new capabilities.

All changes and execution transitions are audited with resource links. Inputs, source, output, and artifacts can contain organizational data and require Automation read permission plus the compiled domain read permissions; credentials must never be ordinary inputs. Lists use Flop and LiveView streams. Demo mode does not expose this subsystem. Keep the dashboard and MCP capabilities in sync.
