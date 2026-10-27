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

`list_automation_records` accepts `kind` values `workflows`, `behaviors`, `revisions`, `executions`, `attempts`, `events`, `approvals`, `triggers`, `schedules`, and `webhooks`. Lists use pages of 20 records. Use the returned pagination metadata rather than assuming one page is complete. Kind-specific metadata filters and sorting happen before pagination; source, payloads, and credentials are not searched.

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
