Use Atlas's authenticated `/mcp` endpoint or `/api/automation` HTTP API to inspect contracts, publish workflows, admit executions, manage triggers, and review approvals. Both transports share the same operation schemas, permission checks, and lifecycle rules.

For the authoring and review sequence, start with the [Automation guide](/docs/automation).

## Discover contracts before authoring

Call `list_automation_types`, or request `GET /api/automation/types`, before composing a workflow. Discovery describes registered behavior contracts and the Automation lifecycle operations, including their API paths, MCP names, input schemas, and output schemas.

The behavior catalog is a deliberate registry, not discovery of arbitrary internal functions or connected upstream MCP servers. Use exact domain references such as `tasks.create@2` when selecting a contract. A saved behavior configuration has a separate record ID; published plans snapshot its selected version and configuration.

Read operations require `automation:read`. Mutations require `automation:write`, plus their ownership and domain checks. Those scopes do not imply access to task, note, finance, or other domain data. Compiled domain read permissions also protect workflow definitions, executions, evidence, approvals, and analytics.

## Choose an operation

The following are the MCP operation names. The discovery response supplies the corresponding HTTP routes and full argument schemas.

| Intent | Tools |
| --- | --- |
| Discover behavior and lifecycle contracts | `list_automation_types` |
| List authorized records | `list_automation_records` |
| Inspect a behavior, revision, attempt, event, approval, or trigger | `get_automation_record` |
| Inspect a workflow and its published definition | `get_automation_workflow` |
| Inspect execution data | `get_automation_execution` |
| Inspect paginated operational events and timing | `get_automation_execution_trace` |
| Aggregate execution metrics | `get_automation_analytics` |
| Create or save a workflow, optionally publishing atomically | `save_automation_workflow` |
| Partially edit a draft | `update_automation_workflow` |
| Delete an unpublished, creator-owned workflow without revisions | `delete_automation_workflow` |
| Validate a draft without publishing | `validate_automation_workflow` |
| Publish a draft as an immutable revision | `publish_automation_workflow` |
| Admit an execution | `run_automation_workflow` |
| Create, edit, or delete a saved configuration | `create_automation_behavior`, `update_automation_behavior`, `delete_automation_behavior` |
| Create, edit, or delete a schedule/webhook | `create_automation_trigger`, `update_automation_trigger`, `delete_automation_trigger` |
| Pause or resume a trigger | `set_automation_trigger_enabled` |
| Replace a webhook credential | `rotate_automation_webhook_credential` |
| Retry or cancel an execution as its initiator | `control_automation_execution` |
| Approve or reject an exact request as its assigned reviewer | `decide_automation_approval` |
| Create or inspect your portable signal sources | `create_signal_source`, `list_signal_sources` |
| Pause or enable your signal source | `set_signal_source_enabled` |
| Admit an event through a source's pinned policy | `ingest_signal` |
| Inspect your authorized priority queue and protected evidence | `list_signals`, `get_signal` |
| Preview eligible business-profile routing | `get_signal_candidates` |
| Record a source-owner decision and optionally open Orbit | `decide_signal` |

`list_automation_records` accepts `kind` values `workflows`, `behaviors`, `revisions`, `executions`, `attempts`, `events`, `approvals`, `triggers`, `schedules`, and `webhooks`. Lists use pages of 20 records. Use the returned pagination metadata rather than assuming one page is complete. Kind-specific metadata filters and sorting happen before pagination; source, payloads, and credentials are not searched.

Signal sources are disabled by default and pin a published `revision_id`, the
caller's execution identity, allowed `reader_ids`, `required_scopes`, and optional
fallback `routing_roles`. Configure the revision to accept `signal_id`; its
`signals.decide@1` action can record `opened` or `ignored`, priority `now`, `today`
or `later`, and a bounded reason. Source authority is immutable; create a new source
to change its audience or revision. The owner ingests a bounded envelope with an
external ID, correlation key, event type/schema version, occurrence time, title and
summary, plus optional subject/topic tags and provider data. Exact external-ID
retries reuse the admission; changed evidence conflicts. Workflow inputs/results
carry opaque IDs, not source evidence. `get_signal` and `get_signal_candidates`
also enforce the source's reader ceiling and required scopes.
Signal tools are unavailable through Slack's shared operator identity; they
require requester-specific authorization.

Instance operators must finish the Signals-compatible server/worker rollout and
establish a compatible rollback release before enabling admission. The instance
gate is closed by default; source activation and admission return 503
`signals_disabled` until it opens. Preparing sources and signed verification does
not start investigations. See the deployment guide for activation requirements.

Opening creates or appends to a correlated shared Orbit investigation with Pip.
Routing selects at most three opted-in people within the allowed audience, by
exact account/service responsibility, then expertise, then configured business
role. People maintain this separate shared metadata through `get_my_business_profile`
and `update_my_business_profile`; private Pip descriptions never supply routing
context. Opt-out stops future matching, not existing thread membership. Opening
queues a generic attention notification for registered devices and starts Pip's
read-only investigation when inference is configured. It does not send an external
reply. The native iOS/Android Orbit inbox groups prioritized conversations under
Now, Today and Later. Provider polling and a source configuration UI are not
included; operators must explicitly wire event producers to ingestion.

## Receive MCP events

For upstream MCP servers supporting signed webhook event delivery, add
`event_receiver` when creating the signal source. For example, [Tuist](https://tuist.dev)
publishes `test_case.marked_flaky`; this source configuration scopes it to one project:

```json
{
  "name": "test_case.marked_flaky",
  "match": {"account_handle": "example", "project_handle": "ios"},
  "correlation_field": "test_case_id",
  "title": "New flaky test",
  "summary": "Inspect recent runs and propose a fix. Do not change test state.",
  "subjects": ["service:ios"],
  "topics": ["testing"]
}
```

Creation returns `delivery.path` and a generated `delivery.secret` once. The
signing key is encrypted at rest and absent from later reads; save it securely.
MCP clients can retain this creation response, so use the bearer API directly if
that credential must not enter a model/client conversation. Recreate the source
to replace a lost or compromised key; pausing the old source stops new admissions.

Subscribe using the upstream's own authorized credential, never Atlas operator
read elevation. For Tuist, call `events/subscribe` with `name`,
`arguments: {account_handle, project_handle}`, and
`delivery: {mode: "webhook", url, secret}`. Construct `url` from your public HTTPS
Atlas origin and the returned path; `secret` is the returned `whsec_` value. The
receiver answers signed verification challenges while the source is disabled.
Enable the source only after enrollment. Record the upstream subscription ID and
renew before its returned `refreshBefore`; Atlas does not yet enroll, renew or
unsubscribe upstream subscriptions automatically. Pausing Atlas does not cancel
the upstream subscription.

The receiver verifies Standard Webhooks HMAC-SHA256 signatures over the exact
body, with a five-minute timestamp tolerance. Deliveries require matching
`webhook-id`/`eventId`, `name`, `timestamp`, and object `data`. Exact configured
data filters must match, and the correlation field must be a nonblank string or
integer. Filters accept nonempty strings, booleans and safe JSON integers and
compare both value and type: `true` is not `"true"`, and `37` is not `"37"` or
`37.0`. `eventId` deduplicates deliveries; the configured field correlates
different events about the same test within that source. Another test gets a
separate investigation. Data is untrusted evidence, not permission or instructions;
Pip obtains detailed failure evidence only through its authorized read tools.
Bodies and normalized envelopes are each limited to 12,000 bytes. New work still
requires the enabled source owner's current Automation/domain grants and uses
the existing pinned policy, audience ceiling and opt-in routing.

## Save and publish a definition

`save_automation_workflow` accepts `name`, `source`, optional `description`, `language` (`json` or `javascript`), and `input_schema`. The `source` argument is a string containing the definition, not an embedded plan object. For JSON plan syntax, see [Create your first workflow](/docs/automation#create-your-first-workflow).

Set `publish: true` to validate, save, and publish atomically. Include `id` when saving a new version of an existing workflow and `expected_revision_id` when protecting against a stale published version. Without atomic publication, draft updates, validation, and publication remain separate operations.

An input schema is an object JSON Schema. For example, the guide's task workflow can use:

```json
{
  "type": "object",
  "required": ["title"],
  "additionalProperties": false,
  "properties": {
    "title": {"type": "string", "minLength": 1, "maxLength": 255}
  }
}
```

This lets Atlas reject invalid admission input and lets supported native clients present a form. Schema documents are bounded to 16 KiB and cannot contain schema `$ref` references. The plan's separate data-reference syntax is still supported.

A validation error does not publish a partial revision. Never patch an existing revision or treat a published definition as mutable evidence. Publish a new version instead.

## Admit and reconcile an execution

`run_automation_workflow` accepts the workflow `id` and an `input` object. To reconcile uncertain network outcomes safely, also send the exact published `revision_id` and a fresh UUID `request_id` generated once for that logical launch.

Freeze all four values before sending. If the response is lost, resend the identical request with the same UUID. Admission is idempotent for that initiating user and request identity; a replay remains bound to the original revision even if the workflow subsequently publishes a new one. Reusing the key with different workflow, revision, or input is not a new launch.

The canonical HTTP route is `POST /api/automation/workflows/WORKFLOW_ID/run`. Send a bearer-authenticated JSON body with `input` and, for reconciled admission, `revision_id` and `request_id`. Replace path and revision placeholders with real identifiers. Do not generate a new request UUID simply because the first response timed out.

Use `get_automation_execution` for protected execution data and `get_automation_execution_trace` for paginated operational evidence. Successful local effects and execution progress commit together. Retrying a failed execution preserves committed progress; cancellation does not reverse completed effects.

## Manage triggers and approvals

Create a trigger with `workflow_id`, `name`, and `kind` (`schedule` or `webhook`). Schedules additionally use `cron` and an `input` object. Creation pins the workflow's published revision and the caller's execution identity. Updates cannot rebind its kind, revision, or execution owner; create a replacement for those changes.

Webhook creation and credential rotation return a secret once. Keep it outside ordinary workflow input and client/model conversation history. For delivery headers and deduplication, see [Start work from a webhook](/docs/automation#start-work-from-a-webhook).

`decide_automation_approval` takes the approval `id` and a `decision` of `approved` or `rejected`. It does not accept an edited payload. First inspect the persisted request and obtain the reviewer's explicit decision. A destructive action's approval must match its exact operation, contract version, target step, and resolved input in the same execution.

Approvals do not grant missing domain permissions or enable unsupported external effects. A tool client must not treat access to the decision tool as permission to approve on a person's behalf without their confirmation.

## Respect lifecycle and privacy boundaries

Saved configurations and unpublished creator-owned drafts are editable; published revisions, executions, attempts, events, and approval evidence are not general-purpose CRUD records. Supported transitions have dedicated operations. Published workflow deletion is rejected to preserve its revision and execution history. Deleting a trigger does not delete the runs it admitted.

HTTP API calls require a bearer token and responses use `Cache-Control: no-store`. Path identifiers take precedence over conflicting body values. Unsupported methods return `405` with the allowed methods; unknown paths return `404`.

Workflow source, inputs, outputs, and approval payloads may contain organizational data. Sending them through an MCP client can also expose them to that client and its model or conversation history. Restrict client access accordingly. Never submit provider credentials as ordinary behavior inputs, and do not confuse protected execution inspection with payload-free operational logging.
