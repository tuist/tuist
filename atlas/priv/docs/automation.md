Use Automation to turn a repeatable process into a versioned workflow: accept input, run registered operations, ask a person to approve an exact action, and retain an execution history.

Author and administer workflows on the web. Use the iOS and Android apps to run published workflows, follow your executions, and review approvals assigned to you.

## Understand the building blocks

Automation separates three things that are easy to confuse:

- A **behavior type** is a registered operation with an input contract, output contract, permissions, and effect classification. For example, `tasks.create@2` creates an Atlas task. The `@2` means version 2 of that operation's contract, not version 2 of your workflow.
- A **saved behavior configuration** gives a registered type a name and reusable configuration. For example, a JavaScript behavior stores its source. A workflow can reference a saved configuration by its ID.
- A **workflow** connects operations and approvals into ordered steps. Publishing creates an immutable workflow revision containing the exact operation versions and configuration snapshots it will use.

An **execution** is one run of a published revision with its own input, step attempts, outputs, and approval decisions. Outputs belong to that execution; one run cannot reference another run's output.

## Get access

Ask your administrator for `automation:read` to inspect Automation and `automation:write` to author, launch, or review work. These permissions do not grant access to other parts of Atlas.

A workflow that creates tasks also requires the relevant task permissions. Atlas checks the initiating user's current grants when admitting an execution and again when running its actions. Revoking access can therefore stop work that was previously allowed.

Workflow definitions and execution evidence can contain organizational data. Their visibility also requires the read permissions derived from their domain operations. An assigned reviewer needs those read permissions as well as Automation write access; assignment alone does not grant access to the underlying data.

## Find your way around

Open **Automation** in the web sidebar:

| Page | Use it to |
| --- | --- |
| **Workflows** | Create a workflow, inspect its published definition, save a new version, or launch it |
| **Behaviors** | Browse registered behavior contracts and manage saved configurations |
| **Executions** | Follow runs, inspect step outputs and timing, or investigate failures |
| **Schedules** | Start a pinned workflow revision on a UTC schedule |
| **Webhooks** | Admit executions from an authenticated external caller |
| **Approvals** | Inspect pending requests and their recorded decisions |

Every inventory has search, sorting, and filters, even when it is empty. Search covers labels and other displayed metadata, not workflow source, input/output bodies, exact approval payloads, or credentials. Remove an active filter to recover from an empty result. Search and filter state stays in the page URL.

## Create your first workflow

This example creates a task assigned to the person starting the execution, then records the created task's ID. It needs Automation write access and the task permissions shown on the `tasks.create@2` contract.

1. Open **Workflows** and select **Create workflow**.
2. Give it a name such as **Prepare a document request**.
3. Set **Definition language** to **JSON**.
4. Replace **Workflow definition** with the following plan.
5. Save the workflow. Atlas validates the definition and publishes its first revision.

```json
{
  "steps": [
    {
      "id": "create_task",
      "behavior": "tasks.create@2",
      "inputs": {
        "title": {"$ref": "input.title"}
      }
    },
    {
      "id": "record_result",
      "behavior": "core.value",
      "inputs": {
        "task_id": {"$ref": "steps.create_task.task.id"},
        "title": {"$ref": "steps.create_task.task.title"}
      }
    }
  ]
}
```

Open the workflow, choose **Run workflow**, and supply this input:

```json
{
  "title": "Prepare the documents requested by our customer"
}
```

Follow the resulting execution to inspect the task output and recorded result. This workflow creates a preparation task; it does not produce a document, send an email, or deliver anything to the customer.

`core.value` returns its input unchanged. `tasks.create@2` returns an object containing `task`, whose `id` and `title` the next step reads. The legacy `tasks.create` / `tasks.create@1` contract instead returns `task_id` and `title`; do not interchange their output paths.

## Compose steps and validate inputs

A JSON plan contains only `steps`, with between 1 and 32 ordered steps. Give each step a unique lowercase ID, using underscores where needed. An action step has `id`, `behavior`, and an object of `inputs`.

Use an object containing only `$ref` to reference a value:

- `{"$ref": "input.title"}` reads an execution input.
- `{"$ref": "steps.create_task.task.id"}` reads an earlier step's output.

References cannot point forward or read a different execution. Atlas rejects known missing output fields, invalid literal inputs, and obvious type mismatches during publication. Dynamic inputs are still validated when the action runs.

Use **Behaviors** to inspect an operation's input/output JSON schemas, effect, permissions, and approval requirement before composing it. Only deliberately registered operations are available. Connecting an upstream MCP server does not automatically make its tools usable as workflow behaviors.

The API and MCP support an `input_schema` when saving a workflow. Use it to describe and validate the execution input, and to enable supported native form controls. The current web editor preserves an existing schema but does not provide a schema-authoring form. See the [Automation reference](/docs/automation-tools) for programmatic authoring.

## Change a workflow safely

Open the workflow and choose **Edit workflow**. **Save new version** validates and publishes a new immutable revision. **Cancel** leaves the existing version unchanged. Invalid definitions stay in the editor without publishing partial changes; a stale edit must be reconciled rather than overwriting a newer publication.

Existing executions keep their original revisions. Schedules and webhooks also stay pinned to the revision selected when they were created; publishing a new workflow version does not upgrade them. Create a replacement trigger when you want it to use a different revision.

Published revisions embed saved behavior configurations. Editing or deleting a configuration cannot rewrite an already-published plan. An unpublished draft that still references a deleted configuration needs a replacement before it can be published.

## Require an exact approval

An approval step has `id`, `type: "approval"`, an existing Atlas user's `reviewer_id`, and an `inputs` object describing what that person is being asked to approve. Execution pauses at that step until the assigned reviewer decides. Other reviewers cannot substitute a decision.

For a destructive or sensitive domain action, the approval must identify the exact operation, contract version, target step ID, and resolved input. For example, approval for a later `delete_note` step using `notes.delete@1` must contain:

```json
{
  "behavior": "notes.delete",
  "version": 1,
  "step_id": "delete_note",
  "input": {
    "id": "NOTE_ID"
  }
}
```

Replace `NOTE_ID` with the target note's actual ID, or resolve the same value in both steps using `$ref`. Put this object in the preceding approval step's `inputs` and set that step's `reviewer_id` to the intended reviewer's actual user ID. A generic confirmation, approval of a different step, or approval of a different note is insufficient.

Review the persisted payload on **Approvals**, then approve or reject it. Approval resumes the existing execution without accepting a replacement payload. An approval records authorization for the specified action; it does not itself send a payment, place an order, or perform an operation absent from the plan.

## Start work on a schedule

On **Schedules**, create a trigger with a published workflow ID, input, and a five-field UTC cron expression. For example, `0 9 * * 1-5` requests a run at 09:00 UTC on weekdays; it does not follow local daylight-saving changes.

A trigger retains its execution owner's identity and selected revision. Atlas coalesces missed occurrences instead of replaying every missed tick and skips an occurrence while the trigger already has a nonterminal execution. An execution awaiting approval therefore prevents overlap too.

Pause a schedule to stop new admissions. Pausing or deleting a trigger does not cancel executions it already admitted. To change its pinned revision or execution owner, replace the trigger rather than editing that identity.

## Start work from a webhook

Create a webhook for a published workflow. Store the bearer credential returned at creation securely: Atlas keeps only its hash and does not display the original credential again. Rotation returns a replacement once and invalidates the previous credential.

Send a JSON object to the webhook endpoint with:

- `Authorization: Bearer …` containing that webhook's credential.
- `X-Delivery-ID` containing a stable, unique ID for the logical delivery.
- The execution input as the JSON request body.

Retry an uncertain delivery with the same delivery ID rather than inventing a new one. Atlas deduplicates admissions for that webhook and delivery ID. The endpoint is `/api/automation/hooks/WEBHOOK_ID`; use the actual endpoint shown for your trigger. Its bound workflow, revision, and execution identity cannot be overridden by the request body.

Webhook requests are bounded and rate-limited. Never use ordinary workflow inputs to pass provider credentials or the webhook secret. A webhook admits work into Atlas; it is not an arbitrary proxy to external services.

## Monitor and recover an execution

Open **Executions** to see the run's status and the workflow revision it used. Its detail page shows step attempts, protected inputs/outputs, a timing waterfall, and a paginated event history.

The waterfall distinguishes measured processing, approval waiting, and gaps without measurements. Missing timing is not a measured zero. Analytics group executions by their UTC admission date; elapsed duration includes queueing, retries, and approval waits rather than measuring CPU time alone.

The initiating user can retry a retryable failed execution or cancel a nonterminal one. Retrying preserves committed progress rather than replaying every successful step. Cancellation prevents further progress; it does not undo effects that already committed.

Atlas keeps durable execution state independently of the browser and worker delivery. Closing a page, losing a socket, or restarting a worker does not turn the client into the authority for what completed. Operational events and diagnostics omit arbitrary source, payloads, and raw exception messages; inspect protected step data only with the relevant permissions.

## Use the native apps

On iOS or Android, open **Browse → Automation** to find published workflows, your executions, and approvals assigned to you. Authoring, configuration, and trigger administration remain web-first.

Supported workflow input schemas render as native forms. Unsupported schemas explicitly direct you to the web rather than silently dropping fields or weakening validation. Review the frozen revision and input before launch.

If a launch has an uncertain network outcome, use the app's pending-launch reconciliation instead of submitting a second independent request. The apps securely retain the original request identity and input so Atlas can resolve whether that execution was admitted.

Execution updates use a foreground connection with authoritative refresh and HTTP fallback. Background push delivery and Live Activities are not implemented for Automation executions and approvals. Atlas's separate opt-in notification support for other features does not provide workflow progress delivery. Review exact approval payloads and confirm inside the app, not through a one-tap notification.

## Know the current boundaries

- JavaScript definitions construct a plan; saved `javascript.evaluate` behaviors compute JSON objects. Both use a bounded, isolated Linux executor. They cannot call host tools, access the network, read secrets, or grant approvals. Unsupported hosts, including a local macOS server, reject JavaScript rather than running it in-process. JSON workflows with supported local operations remain usable there.
- Plans are ordered and bounded, not arbitrary parallel graphs or dynamically unbounded loops. Individual JSON payloads are limited to 64 KiB and 32 levels of nesting; compiled plans have a 256 KiB budget.
- Registered operations are versioned explicitly. External delivery, credentials, permission changes, arbitrary queries, and unsupported provider writes are not implicitly exposed as behaviors.
- Execution history and published evidence are not ordinary editable records. Only unpublished creator-owned workflow drafts without revisions can be deleted; retained revisions, attempts, events, and approval evidence cannot be overwritten through CRUD.

For clients and agents, continue with the [Automation API and MCP reference](/docs/automation-tools).
