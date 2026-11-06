# Alerting

Pulse currently implements **experimental native threshold and recording rules**,
durable rule management, configuration-change history, and per-rule event replay. These
features share object storage; restarting evaluators does not erase pending,
firing, or keep-firing state.

Native rules support **opt-in Slack webhook delivery** and live MCP resource
update hints. Grafana routing/grouping, OnCall and Atlas webhook compatibility
remain unimplemented. Do not transfer production paging responsibility to Pulse.
Grafana definitions can be
validated and stored losslessly, but remain disabled and cannot publish alert lifecycles.
Read-only expression previews support explicitly bound native Prometheus and LogQL sources;
see [imported graph previews](#preview-an-imported-expression-graph).
Import success is not query, template, lifecycle, or notification compatibility.

## Configure credentials and evaluation

Alerting does not accept the existing tenant-shared token as an administrative
identity. A [trusted issuer](issuer-credentials.md) credential acts as a
principal for its tenant: its `alert:*` scopes are the capabilities and its
subject (with any delegating `act`) is the recorded identity. Suspended tenants
stop evaluating. Otherwise, configure dedicated principals in
`PULSE_ALERTING_PRINCIPALS_JSON`:

```json
[
  {
    "tenant": "production",
    "id": "operator",
    "type": "human",
    "token_hash": "<64 lowercase hexadecimal SHA-256 characters>",
    "capabilities": [
      "alert:read", "alert:rules:write", "alert:audit:read",
      "alert:preview", "alert:evaluate", "alert:import", "alert:record"
    ]
  }
]
```

Generate a random bearer token and hash it offline. Store only the hash in
configuration; give the plaintext token to its owner. Principal types are
`human`, `agent`, and `service`. History identifies the credential holder. A
shared service token does not identify a person behind that service, and
caller-supplied identity assertions are not accepted.

| Capability | Permission |
| --- | --- |
| `alert:read` | Read authorized configurations, current state and events. |
| `alert:rules:write` | Create, replace, disable, delete and restore rules. |
| `alert:audit:read` | Read changes and historical snapshots. |
| `alert:preview` | Read-only native or explicitly bound imported graph preview; also requires `alert:read` and the rule's classification. |
| `alert:evaluate` | Commit native lifecycle or metric publication intents; also requires `alert:read`. |
| `alert:import` | Validate imports and access imported Grafana content. |
| `alert:record` | Access native recording definitions/state/history and authorize their metric-writing actions, in addition to the corresponding read, rule-write, preview or evaluation capability. |

Import administration also needs rule-write permission. Imported configuration
and the edit that removes it retain the import classification. Generic read or
audit permission does not expose those historical definitions. Credentials for
existing signal-query and ingest APIs remain configured separately through
`PULSE_TENANT_TOKENS`; alerting principals do not automatically grant that access.
Recording rules can synthesize tenant metric series, so ordinary rule-write or
evaluation permission without `alert:record` cannot create, change or evaluate
them. Read-only recording access can combine `alert:record` with `alert:read`
without granting rule-write/evaluation permission. Historical classifications
remain protected after a rule changes kind. `recording_expired` events always
require `alert:record`, including historical events whose stored classification
was empty; any additional stored restrictions still apply. Reads do not rewrite
immutable history. Full state and state-resource reads/subscriptions also require
`alert:record` while recording queues, series, last/error diagnostics or retirement
fences remain, even after conversion to a threshold and after its queue drains.
The new threshold's configuration and evaluation remain separately authorized;
evaluation omits `recording_pending` when the caller cannot read retained recording
state. Upgrade all serving application instances before relying on these checks;
a native capability tuple alone does not fence an older reader's authorization
policy.

Persistent query budget failures are locally memoized for the same rule revision
and cadence tick, avoiding a full repeated scan on every worker poll. At most
10,000 rule entries are retained per worker. A new revision/tick retries; capacity,
freshness and timeout failures remain retryable. This disposable optimization
never advances durable health or progress, is lost on restart, and cannot prevent
another instance from attempting work.

Automatic evaluation is opt-in:

- `PULSE_ALERTING_EVALUATION_ENABLED=true`, default `false`.
- `PULSE_ALERTING_POLL_INTERVAL_MS=5000`, range `1000..60000`.

The Helm equivalents are `alerting.principals`, `alerting.evaluationEnabled`, and
`alerting.pollIntervalMs`. Deploy identical principal configuration, object-store
identity, and `SECRET_KEY_BASE` across nodes. Revocation requires updating and
restarting all affected nodes. Keep clocks synchronized. Workers discover durable
rules and use live cluster membership to reduce duplicate work; conditional
writes, not ownership, enforce correctness.

Evaluation queries have a dedicated background slot rather than consuming the
interactive reservation. Query budgets and per-tenant limits still apply. Polling
many rule heads can be costly; benchmark the interval before enabling evaluation
at scale. No local durable queue or database is introduced.

## Create a native rule

HTTP calls use `Authorization: Bearer <token>` and `X-Scope-OrgID`. Tenant and rule
IDs are at most 128 characters, using letters, digits, `.`, `_`, and `-`; `.` and
`..` alone are not valid IDs. All request bodies are JSON.

`POST /api/v1/alerting/rules/backup-failed`:

```json
{
  "operation_id": "<new UUID>",
  "reason": "Watch for backup failures",
  "rule": {
    "kind": "promql_threshold",
    "name": "Backup failed",
    "query": "max(backup_failed)",
    "threshold": {"op": "gt", "value": 0},
    "enabled": true,
    "cadence_ms": 60000,
    "for_ms": 300000,
    "keep_firing_ms": 0,
    "labels": {"severity": "warning"}
  }
}
```

`promql_threshold` queries use the supported [Prometheus query subset](querying.md).
`logql_threshold` queries use metric-producing [LogQL](querying.md#loki-api),
not raw log streams. Both evaluate an instant vector within the rule's tenant;
LogQL range-vector windows come from the expression. Threshold operators are
`gt`, `lt`, and `eq`. Nonfinite values or invalid sample/label sets are evaluation
errors, never successful empty results.
Rules default to disabled, a 60-second cadence, and zero pending/keep-firing
holds. Cadence is `1000..86400000` milliseconds; holds are `0..604800000`.
Custom labels are bounded; `__name__` and `alertname` are reserved. Up to eight
operator-provisioned `notification_targets` may be referenced by ID. The rule name
becomes `alertname`. Unknown native configuration fields are rejected.

Eligible ticks follow a UTC cadence grid. Pending and keep-firing timers advance
only at successful eligible evaluations, never by an independent timer. Retrigger
preserves the original firing start. In a nonempty result, missing active series
are treated as false predicates. A wholly empty result sets `no_data` and keeps
previous instances/timers by default (`no_data_policy: "keep_last"`). Set
`no_data_policy: "ok"` explicitly to treat empty results as false predicates:
pending instances resolve; firing instances honor `keep_firing_ms` before
resolving. Health still reports `no_data`, not a successful observed zero.
This is useful for event-count log alerts, but may also resolve an alert when a
producer stops sending; choose the policy deliberately. Source errors keep state
and report `error` regardless of the empty-result policy. Admission/resource
deferral and query overrun skip publication, not a healthy empty result. These are native semantics, **not Grafana compatibility claims**.

Every configuration replacement resets native lifecycle state and records
resolution of previous instances. Deleted rules have durable tombstones.
Re-creation uses a fresh generation and preserves audit ancestry. Restore always
creates a new disabled revision; enabling it requires a separate explicit edit.

## Alert directly on stored logs

Use the same HTTP/MCP rule endpoints with `kind: "logql_threshold"`. For example,
`POST /api/v1/alerting/rules/api-errors`:

```json
{
  "operation_id": "<new UUID>",
  "reason": "Watch for API errors in stored logs",
  "rule": {
    "kind": "logql_threshold",
    "name": "API errors",
    "query": "sum by (service) (count_over_time({service=\"api\"} |= \"error\" [5m]))",
    "threshold": {"op": "gt", "value": 0},
    "enabled": false,
    "cadence_ms": 60000,
    "for_ms": 60000,
    "keep_firing_ms": 300000,
    "no_data_policy": "ok",
    "notification_targets": ["slack"]
  }
}
```

Provision the notification target separately, preview the query, then enable the
rule explicitly. Automatic execution still requires
`PULSE_ALERTING_EVALUATION_ENABLED=true`; delivery independently requires the
notification switch described below. This is a native rule, not an enabled or
translated Grafana import. It uses the same conditional rule-head publication,
revision audit, pending/firing/hold state, event history and optional Slack outbox
as native Prometheus thresholds. No datasource binding or external URL is needed.
Native LogQL limitations and incomplete Loki parity still apply.

LogQL alert queries share the PromQL sample/work/output/scan configuration,
use the reserved `alerting` admission class, and reject more than 128 result
instances rather than publishing a truncated set of fires. Instance overflow
commits `error` health and preserves prior instances; it is not a successful
subset or a silent transient skip. Dense/long windows
can exceed bounds; do not remove limits merely to fit the cadence. There is no
log-to-metric materialization or local counter authority.

Threshold queries must return vectors. Bare numbers and scalar-only LogQL
arithmetic now retain their scalar type and reject as threshold results, like
scalar PromQL queries; use a vector expression when authoring a threshold.
Explicitly bound expression previews accept scalar sources as scalars.

### Required signal freshness

Native threshold and recording evaluations require a freshly validated S3
manifest for each selected signal. Each selector performs a conditional root
read even when the local cache was just refreshed. Provider failures or missing
signal authority skip evaluation, preserve instances and the completed watermark,
and cannot become no-data or emit a recovery. A cold required read never adopts
objects through LIST or creates a missing manifest. Establish the signal through
successful ingestion or an explicitly verified legacy migration before enabling
rules. Ordinary interactive query cache behavior is unchanged.

These reads are per request/selector, not an atomic multi-source snapshot or a
bound on total provider traffic across instances. Include them in capacity and
cost testing. Monitor the age of `completed_at_ns` and the
`pulse_alert_evaluation_skips_total` counter. Its bounded reasons distinguish
`authority_missing` (including never-written signals) from `freshness_unavailable`,
`capacity`, `timeout`, `budget`, and `overrun`. Counters are node-local and reset
on restart, not durable rule progress. A skipped tick leaves the previous
health/state unchanged, not proof that the current source is healthy.
Explicit HTTP evaluation skips return `503 evaluation_skipped` with
`Retry-After: 1`; narrow exhausted queries or repair source authority rather than
retrying indefinitely. Preview never commits lifecycle or sends notifications.

Upgrade every evaluator to the same compatible version before creating/enabling
LogQL rules or changing `no_data_policy`. Older evaluators do not understand the
new rule kind/policy and do not require fresh signal snapshots. Mixed-version
workers can otherwise select different behavior under ownership changes. Before
rolling back, disable incompatible rules and replace their definitions with
supported configurations; disabling the automatic switch alone does not prevent
manual evaluation.

## Combine native log and metric conditions

`expression_threshold` is an explicitly authored native rule, not a translated
or enabled Grafana graph. Its `sources` are 1–16 instant queries against Pulse's
own tenant-local storage. Each source has required `ref`, `language` (`promql` or
`logql`), and `query`, and optional integer `empty_value: 0`, with no other keys.
Refs are unique ASCII identifiers up to 128 bytes and
`__condition` is reserved. The expression must reference every declared source
and no undeclared ones. There are no datasource URLs, foreign tenants, credentials,
range frames, inferred resampling, or external adapters. LogQL sources must
produce metrics, not raw log streams. Prometheus scalars can broadcast over
number frames.

For example, combine stored error logs with a stored request-rate metric:

```json
{
  "rule": {
    "kind": "expression_threshold",
    "name": "Elevated API errors",
    "sources": [
      {"ref": "errors", "language": "logql", "query": "sum by(service)(count_over_time({service=\"api\"} |= \"error\" [5m]))", "empty_value": 0},
      {"ref": "requests", "language": "promql", "query": "sum by(service)(rate(http_requests_total{service=\"api\"}[5m]))"}
    ],
    "expression": "$errors > 10 && $requests > 1",
    "threshold": {"op": "gt", "value": 0},
    "enabled": false,
    "cadence_ms": 60000,
    "for_ms": 120000,
    "keep_firing_ms": 60000,
    "no_data_policy": "keep_last"
  },
  "operation_id": "create-combined-api-alert",
  "reason": "Require both errors and active request traffic"
}
```

Use the same create/update/preview/evaluate/state/history and notification APIs
as other native thresholds. Native math supports bounded arithmetic, comparisons,
boolean operators and scalar/equal-or-subset label joins. Aggregate sources to
intentional, compatible dimensions; remove conflicting metric names with
aggregation when combining different metrics. **Any label-drop notice is an
error**, including incompatible singleton fallback, rather than an unlabeled or
partial set of alerts. Null/nonfinite values and >128 terminal instances are
whole-evaluation errors preserving previous instances. By default, empty inputs
are absent, not zero. Even `||` joins matching frames; it is not a set-union
operator, and an empty source can make the terminal empty despite another true
source. An empty terminal uses the configured no-data policy. `keep_last` can
therefore retain firing after errors stop; `ok` can resolve despite a true
unmatched input. Do not rely on these defaults to infer boolean truth from sparse
log counts.

For a count where no matching stored logs is deliberately considered zero, opt
into `empty_value: 0` as in the example. Only a **successful fully empty instant
vector** becomes scalar zero, which broadcasts over the other source's known
labels. Missing authority, errors, budgets and timeouts never become zero. This
does not fill individual missing label sets in a partially populated source,
invent service identities, or establish exporter completeness. Multi-service
sparse counts can still produce label-loss errors; use separate per-service rules
or verified complete, aligned metric series when partial absence is normal.
Aggregate both sources to the same dimensions: if the present source has extra
labels, switching to scalar zero can change instance identity. Old instances then
resolve and differently labelled instances start rather than sharing one timer.

All sources and the expression execute in one admitted worker under the same
tenant, deadline, heap and background `alerting` slot. Source scan quotas are
conservatively partitioned across both languages; sample/work/materialized/output
counters accumulate across sources. The math kernel additionally has fixed limits
of 1,024 frames, 100,000 input/output points, 1 MiB label bytes and 1,000,000 work
units. Fixed kernel input/label/work violations publish `error` health and
preserve instances, rather than indefinitely skipping a persistently incompatible
rule. Kernel timeouts remain transient skips. These are per-instance bounds, not
deployment-wide admission. Every
scheduled selector requires fresh authority; one source failure prevents partial
publication. Reads are not an atomic cross-signal snapshot. Queries, the expression
and the complete rule retain their 16,384/16,384/65,536-byte limits.

Keep the rule disabled until actual sources, label identity, missing-input
semantics and limits have been verified. Upgrade all evaluators before enabling
this new kind. Existing Grafana imports stay disabled; this native contract does
not establish Grafana frame/lifecycle/notification or deployed Loki parity.

## Create a native recording rule

Use the same audited rule-management endpoints, with `kind: "promql_recording"`:

```json
{
  "operation_id": "<new UUID>",
  "reason": "Record backup totals for downstream queries",
  "rule": {
    "kind": "promql_recording",
    "name": "backup_failed:sum",
    "query": "sum by (region) (backup_failed)",
    "enabled": false,
    "cadence_ms": 60000,
    "labels": {"cluster": "production"}
  }
}
```

The query must return an instant vector from the current tenant. `name` becomes
`__name__`; static labels overwrite source labels, and empty values remove labels.
Metric and label names use the legacy ASCII Prometheus grammar. Recording rules
accept only `kind`, `name`, `query`, `enabled`, `cadence_ms`, and `labels`. They do
not emit alert instances or notifications. Defaults and cadence bounds match
native threshold rules. Recording operations additionally require `alert:record`.
Preview returns proposed samples without writing anything.
Explicit evaluation **acknowledges a durable publication intent**, not immediate
query visibility. State reports `recording_pending`, `recording_last`,
`recording_error`, and `recording_fence_ns` separately from query health.

Publication requires the S3 storage adapter. Use the same object-store backend
for rule authority and signal storage. Upgrade every evaluator and publisher to a
recording-aware version before enabling this capability. Older versions cannot
drain its intents or provide recording lifecycle semantics; disabling rules does
not erase the queue. Do not roll back until outstanding publication/retirement
work has drained and the target reader supports the existing metric stale markers. Enable `PULSE_ALERTING_EVALUATION_ENABLED`
to run automatic evaluation and publication; disabling that switch also pauses
outbox draining. Individual rule disable/delete does not cancel previously
acknowledged intents. Draining survives configuration changes, deletion, and
re-creation. A committed intent is replayed with the same sample bytes and
idempotency key until metric-segment PUT and manifest CAS succeed. Failed or
ambiguous attempts remain queued. Missing or corrupt committed payloads fail
closed and must be recovered, not removed from authority.

Each worker visit drains at most eight results, with a two-second budget for
starting new publication work. An in-flight storage call can exceed that budget.
Automatic recording evaluation waits for that rule's queue to empty, preventing
catch-up from being cancelled out by new ticks. Missed ticks are **not backfilled**.
Manual evaluations can queue up to 63 intents; the 64th slot is reserved for
configuration retirement. A full queue defers before querying, never drops work.
Fix errors reported in `recording_error` and leave draining enabled to recover.
Do not transfer production recording responsibility without measuring freshness
and maintenance capacity under the actual rule count and cadence.

Successful evaluation marks disappeared series stale, including a wholly empty
result. NaN and infinity remain arithmetic values, distinct from stale markers.
Source errors or resource deferral do not mark series stale. Configuration edits,
disable/delete, and restoration retire the last successful series at a timestamp
strictly after the last completed tick; historical answers before that timestamp
remain intact. New recording ticks must be after this retirement fence. Keep all
nodes' clocks synchronized: a fast mutation clock can delay evaluation or leave a
future-dated retirement intent waiting for the ingest future-time guard. Inspect
`recording_fence_ns` when diagnosing `not_due`; clock-skew tolerance is not a
cluster-clock guarantee.

Limits for a single `promql_recording` are **128 current samples**, 32 final labels per series (including
`__name__`), 128-byte label names, and 512-byte UTF-8 label values. The encoded
current set and its potential stale markers must each fit **31 KiB**; their joint
transition fits 62 KiB, with a 64 KiB immutable-object ceiling. Duplicate final
label sets, oversized sets, and invalid values fail the entire evaluation, not a
subset. Large churn cannot wedge two otherwise admissible sets at the joint
budget. Metrics retention applies equally to recorded data: if the committed
floor overtakes a pending intent, it is retired with a durable `recording_expired`
event requiring `alert:record` to read. Other permanent publication errors are
not silently discarded.

Separate recording rules are not ordered: a rule that reads another rule's
metric sees it from an earlier tick, up to one cadence old per hop. Put chained
recordings in one [recording group](#record-a-rule-group) instead. Pulse does not
prove source residency, detect cross-rule metric ownership conflicts, or provide
atomic multi-rule snapshots. Use unique recording metric names per producer;
competing producers or direct ingest can otherwise write conflicting samples
under the ordinary metric query rules.

## Record a rule group

A `promql_recording_group` evaluates its rules the way a Prometheus rule group
does: in order, all at the same evaluation timestamp, and each rule sees what
earlier rules of the group recorded at that timestamp. Chained recordings
therefore never lag. Results are compared with Prometheus 3.5.0 rule-group
evaluation in the test suite.

```json
{
  "operation_id": "<new UUID>",
  "reason": "Record kura topology",
  "rule": {
    "kind": "promql_recording_group",
    "name": "Kura Recording",
    "enabled": true,
    "cadence_ms": 60000,
    "rules": [
      {"record": "kura:pod_region", "expr": "max by (cluster, pod, region) (kura_node_geo_info)"},
      {"record": "kura:pool_region", "expr": "max by (cluster, pool, region) (kura:pod_region)", "labels": {"source": "pulse"}}
    ]
  }
}
```

Create it with `POST /api/v1/alerting/rules/<id>` like any rule. Each entry has
`record`, `expr` and optional `labels`, with the same meaning as in a Prometheus
rule file and the same naming and label rules as a single recording. A group
holds 1 to 64 rules; record names must be unique within it. Rules read the
recorded metrics of **earlier** rules at the current tick, including stale
markers for series that disappeared; a rule that reads a later rule, or itself,
sees that metric's previous tick, as in Prometheus.

Evaluation follows Prometheus's failure rules per rule. A rule whose query fails
(for example on many-to-many matching or a query budget) records nothing for
that tick and marks none of its series stale; later rules that read it see its
previous samples. The group's `health` is `error` when any rule failed,
`no_data` when every rule returned nothing, and `ok` otherwise; state reports
each rule's `health`, `series` count and `error` code in `recording_rules`.
Capacity, timeout and manifest-freshness failures skip the whole tick and are
retried, as for single rules.

One tick of a group is **one publication**: one intent, one metric segment and
one manifest update, however many rules it has. Limits apply per group: **4,096
current series** across its rules, and the encoded current set and its potential
stale markers must each fit **384 KiB**; their joint transition fits 960 KiB.
Exceeding a limit fails the whole tick without publishing anything. Intents up to
128 KiB travel inside the rule head's commit instead of a separate object.

Object-store requests per group tick are one head write that commits the intent,
one segment PUT, one manifest root write (shared with concurrent ingest
publications when [ingest coalescing](configuration.md#ingest-coalescing) is on)
and one head write acknowledging publication: at most **4 Class A requests**,
independent of the number of rules and series. A one-minute group costs at most
172,800 Class A requests per 30 days, about $0.86 at $5 per million. Separately
declared rules cost five Class A requests each per tick. Polling rule heads is
Class B, and each evaluation pass also LISTs tenants and their rules (Class A)
once per `PULSE_ALERTING_POLL_INTERVAL_MS` on every evaluating instance.

Upgrade every instance before creating a group: older versions cannot evaluate
it and reject its rule head.

## Import recording rules from Prometheus or Grafana

`POST /api/v1/alerting/import/rule-file/preview` with `{"content": "<file>"}`
converts the recording rules of a Prometheus rule file, or of a Grafana
alert-rule export in provisioning format (YAML or JSON, at most 256 KiB), into
disabled `promql_recording_group` rules. It needs `alert:import` and
`alert:record` and writes nothing:

```json
{
  "rules": [{"id": "kura-recording", "rule": {"kind": "promql_recording_group", "...": "..."}}],
  "skipped": [{"group": "Kura Recording", "rule": "KuraDown", "reason": "alerting_rule_not_converted"}]
}
```

Review each rule, set `enabled`, and create it with the normal create call.

- **Prometheus:** each group becomes one native group with the group's
  `interval` (default `1m`) and its recording rules in file order. Group
  `labels` apply to every rule; rule labels win. Groups with a nonzero
  `query_offset` or `limit` are skipped.
- **Grafana:** each recording rule must record a single instant Prometheus query
  (`record.from` naming a non-expression query with no time shift). Grafana
  evaluates a group's recordings independently, so the converted rules are
  ordered so that every rule follows the rules it reads.

Alerting rules are reported in `skipped`, never converted.

To move Grafana-managed recordings, export their rule group (or write the
equivalent Prometheus rule file), convert it with this preview, and create the
resulting group. Grafana evaluates recordings independently, so recordings that
read other recordings lag up to one interval per hop there; in a Pulse group they
read same-tick results instead.

## Management, preview and state

| Method/path under `/api/v1/alerting` | Operation |
| --- | --- |
| `GET /rules` | List authorized current rules. |
| `GET /rules/:id` | Read current configuration and revision. |
| `POST /rules/:id` | Create, or explicitly re-create a deleted rule. |
| `PUT /rules/:id` | Replace configuration. |
| `DELETE /rules/:id` | Publish a tombstone. |
| `POST /rules/:id/preview` | Preview native results or an explicitly bound imported expression graph, without alert-state writes. |
| `POST /rules/:id/evaluate` | Commit an eligible native evaluation. |
| `GET /rules/:id/state` | Read durable instances, health and evaluation revision. |
| `GET /rules/:id/changes` | Read the first newest-first change page. |
| `POST /rules/:id/changes` | Continue change pagination with a body cursor. |
| `GET /rules/:id/revisions/:revision` | Read a historical revision by digest. |
| `POST /rules/:id/revisions/:revision` | Read using a body `revision_cursor`. |
| `POST /rules/:id/restore` | Restore a historical configuration as a new revision. |
| `POST /rules/:id/events` | Page committed lifecycle/health events. |
| `POST /import/preview` | Validate a Grafana definition array without writes. |

Mutations require a nonempty bounded `reason`, a fresh `operation_id`, and the
current `expected_revision` except for first creation. HTTP `If-Match` can carry
the same revision returned in `ETag`. If both are supplied, they must agree.
Exact retries reuse their operation ID and unchanged request. Changed payloads
or a rebase onto a different configuration revision require a new ID.
Retries verify their original committed notification bindings, so target removal
or secret-reference changes do not turn an already committed mutation into a
new request or prevent receipt/ancestry recovery. New mutations still require
valid current target configuration. Existing receipt digests remain readable;
this does not migrate or rewrite history.
Reasons are untrusted context; do not put credentials or sensitive incident data
in rule names, labels, queries, or reasons.

The rule head publishes the configuration pointer and its audit record together.
Immutable candidates that lose conditional publication never become history or
fires. After an uncertain conditional response, Pulse reads back the committed
authority. Unresolved outcomes return an availability/ambiguity error; do not
assume that means the operation definitely failed. Recent mutation receipts are
bounded to 128 entries, independently of evaluation ticks. Bounded ancestry
resolution can still return ambiguity; retain operation IDs and inspect history
rather than blindly creating another operation.

Successful requests return `200`; malformed input returns `400`, missing/denied
credentials `401`/`403`, missing rules `404`, conflicts or cursor reset `409`,
disabled/unsupported execution `422`, and unavailable/indeterminate publication
`503`.

## History and replay

A full immutable revision snapshot is the audit record, including parent,
verified principal, reason and operation identity. Change listing pages backwards
from a frozen committed tip. Edits during pagination do not move that tip. Use
`next_cursor` in a POST body or tool arguments, never a URL. This is not
chronological forward replay or an automatic-action feed.

Each change includes an encrypted `revision_cursor`. Supply it with `revision`
when reading/restoring an old snapshot to avoid walking from the newest head.
A bare historical digest lookup scans at most 400 revisions, returning a scan
limit rather than a false not-found result. Page changes to obtain a fresh
revision cursor for older snapshots. Restore additionally needs current
`expected_revision`, `operation_id`, and `reason`.

Event pages read forward from an encrypted per-rule cursor. They retain up to
64 inline references and 32 sealed pages of 64 events: at most 2,111 readable
transitions while the current tail is open. The actual floor advances when the
oldest page is dropped. This is a count bound, not a guaranteed number of days.
Below-floor positions require explicit resynchronization. A cursor omitted from
a fresh request starts at the earliest retained event, not at current state.

Event bodies use their historical classification, not today's rule kind. An
otherwise authorized threshold event remains readable after conversion to a
recording rule; recording events remain protected after conversion away. A page
can contain no visible events while its cursor advances past protected events.
Persist the returned cursor even for empty pages; an empty body alone does not
prove that replay is caught up. Current resource frontiers have their own
current-rule authorization and do not grant access to protected historical bodies.

Cursors are principal/view/rule-bound, expire after ten minutes, and derive their
key from `SECRET_KEY_BASE`. Changing permissions or rotating that secret requires
an explicit earliest-retained restart. Deduplicate by stable event IDs, not only
an old sequence high-water mark: newly authorized older events may become visible.
Current-state reconciliation is separate from claiming transitions were processed.

Audit snapshots and unreferenced candidates are not garbage-collected in this
initial implementation. Do not apply a bucket lifecycle expiry to the alerting
namespace. Event replay pruning does not authorize deleting longer-lived audit
snapshots or entire generation prefixes. Retention cleanup and operational cost
controls remain follow-up work.

## Model Context Protocol tools

The existing stateless `POST /mcp` transport exposes:

- `list_alert_rules`, `get_alert_rule`, `create_alert_rule`, `update_alert_rule`,
  `delete_alert_rule`;
- `list_alert_rule_changes`, `get_alert_rule_revision`,
  `restore_alert_rule_revision`;
- `get_alert_state`, `read_alert_events`, `preview_alert_rule`,
  `evaluate_alert_rule`, and `validate_alert_import`.

Calls take `tenant` and, where applicable, `id`, with the same mutation and cursor
fields as HTTP. Mutation annotations are distinct from read-only query tools;
authentication and capability checks happen before execution. Preview does not
write state or send notifications. Rule administration does not grant infrastructure
remediation. Silences, acknowledgements and dynamic notification-configuration APIs remain
unsupported. Targets are provisioned by the operator, not by model-generated URLs.

## Native Slack delivery

Configure public target descriptors in `PULSE_ALERTING_NOTIFICATION_TARGETS_JSON`:

```json
[{"tenant":"production","id":"slack-prod","type":"slack_webhook","secret_env":"PULSE_ALERTING_SLACK_PROD_URL"}]
```

Set `PULSE_ALERTING_SLACK_PROD_URL` to the HTTPS incoming-webhook URL through your
secret manager or a Kubernetes Secret, not a rule body or values file. The webhook
URL is never stored in alert history or events. Pulse disables HTTP redirects and
does not expose transport error details. Changing a target's descriptor requires
a new target ID; rotate a secret under the same reference only when preserving
its logical destination. Retain old descriptors/secrets until their work drains.

Add `"notification_targets":["slack-prod"]` to the native rule and enable
`PULSE_ALERTING_NOTIFICATIONS_ENABLED=true` separately from evaluation. Both
features default to disabled. Provisioning a target alone never sends a message.
Only committed firing/retrigger/resolution events enqueue native notifications;
pending disappearance does not send a phantom resolution. Health is available
through state/resources, not a Grafana-style DatasourceError notification yet.

Each target has a durable bounded outbox and a leased sender claim. Event replay
pruning cannot drop queued payload references. Failed sends retain work for retry
after the 30-second lease expires. Successful sends advance delivery progress by
conditional head write. Restarted or competing senders may duplicate an external
message after an uncertain response or lease expiration: delivery is at-least-once,
not Slack exactly-once or guaranteed remote ordering. Producer text uses Slack
`plain_text`, not executable instructions, markup or mention parsing.

Outboxes hold at most 64 events per target and 16 live/retiring bindings per rule.
Full backlogs reject additional transition publication rather than silently losing
notifications. Configuration changes that must publish resolution notifications
may also wait for backlog drainage. Stop automatic evaluation through its enable
flag if delivery is unavailable; monitor current state and the object-store costs.
This initial delivery is one native event per message, not Grafana notification
policy grouping, repeat intervals, escalation or template parity.

## Live resources and subscriptions

`resources/list`, `resources/templates/list` and `resources/read` expose authorized
resources at `pulse://alerts/tenants/<tenant>/rules/<id>/{state,events,changes}`.
Reads are private and uncached (`ttlMs: 0`). State resources contain current
instances; events and changes contain committed replay/audit frontiers. A
checkpoint is not proof that events were processed. Drain the history tools with
your own body cursor and durable event-ID deduplication.

Use standard `subscriptions/listen` with a `resourceSubscriptions` array. The POST
response is actually streamed: acknowledgement first, then
`notifications/resources/updated` hints carrying the subscription ID. There are
no GET streams, protocol sessions, or `Last-Event-ID` replay. Hints may coalesce;
durable tool replay is the continuity mechanism.

Subscriptions poll committed authority heads once per second, refresh credential
and classification checks on every poll, and close gracefully on revocation or a
view change. They last at most ten minutes, accept at most 32 resource URIs and
have local admission limits of 64 streams globally and two per principal.
Reconnection requires a new authenticated POST and replay from your persisted
cursor. Infrastructure actions still require a separate authorized server and
human approval; a resource update is never action authorization.

## Grafana import

`POST /api/v1/alerting/import/preview` accepts `{"rules": [<definitions>]}`.
It validates identities and expression references/cycles and returns a disabled
`grafana` wrapper for each complete original definition, with explicit
`executable: false` and migration blockers. No partial import writes occur.
Persist approved wrappers individually with the normal create operation.

The checked-in inventory test covers all 115 definitions, including four
recordings, two paused rules and 13 nonzero keep-firing settings. Original query
graphs, unknown fields, recording metadata and template defects are retained,
not silently repaired or dropped. Native recording publication is implemented,
but production Grafana lifecycle execution, recording translation/source closure,
external adapters, notification rendering/routing and migration fixtures remain
future work. No imported rule may be enabled until those gates are implemented.

## Preview an imported expression graph

For a disabled imported rule, provision explicit datasource mappings in
`PULSE_ALERTING_SOURCE_BINDINGS_JSON` (chart `alerting.sourceBindings`):

```json
[
  {"tenant":"production","uid":"original-prometheus-uid","type":"native_promql"},
  {"tenant":"production","uid":"original-loki-uid","type":"native_logql"}
]
```

The mapping routes the original datasource UID to **that same tenant's Pulse
metrics or logs**, not to an external Grafana datasource. Bindings default to empty and
accept at most 256 unique tenant/UID pairs. They have exactly `tenant`, `uid`,
and `type`; only `native_promql` and `native_logql` are accepted. URLs,
credentials, alternative types and duplicate pairs fail
startup. Tenant and UID use the same bounded ID grammar as rules. Deploy identical
bindings on all instances and restart them when changing bindings. Configuration
is operator-provisioned, not supplied in the preview request or rule body.

Call the existing `POST /rules/:id/preview` or `preview_alert_rule` tool. It needs
`alert:preview`, `alert:read`, and `alert:import` for imported definitions. Every
source must have an authorized tenant-local binding; unbound or unsupported
sources reject the whole preview. There is no fallback to another tenant,
external network request, or successful partial graph. Supported native sources:

- **Prometheus:** instant queries only (`instant: true`, no range or time shift).
- **LogQL:** metric-producing queries with explicit `queryType: instant` or
  `queryType: range`. Raw log-stream queries reject. Range queries require an
  explicit relative window and positive integer `intervalMs`, use that exact
  step, and fail when the evaluation grid exceeds 11,000 steps. The explicit
  `queryType` controls Loki mode, including legacy models carrying `instant: true`
  alongside `queryType: range`. This is a native preview contract, not a verified
  Grafana datasource adapter.

A relative window's `to` shifts the evaluation time back by that many seconds;
`from` does not constrain an instant source selector's lookback. LogQL range
queries evaluate from `now - from` to `now - to`; their range-vector lookback
still comes from the query itself. Windows must be ordered, nonnegative and no
longer than one year. Grafana macros are not expanded. Display hints (`interval`,
`maxDataPoints`, `legendFormat`, `editorMode`, `hide`) do not alter queries;
`intervalMs` changes only Loki range resolution. There is no automatic
resampling/downsampling to fit `maxDataPoints`. Exemplar/table queries, unknown
model fields, conflicting nested UIDs and unsupported query modes reject rather
than being silently reinterpreted. ClickHouse, external adapters and Prometheus
range sources remain unsupported here.

Supported expression nodes are arithmetic/comparisons/boolean math with `$ref`
or `${ref}`, parentheses and unary minus/not; one-condition `gt`, `lt`, `eq`,
`ne`, `gte` or `lte` thresholds; and strict `last` reduction. Functions, range
thresholds, hysteresis, alternate reducers/modes and raw-series binary math fail
closed. Reference names use ASCII identifier syntax. Numeric operands are
float64, including integer inputs; null, NaN, infinities and signed zero remain
distinct. Math NaN propagation differs from a threshold predicate. Exponentiation
is left-associative, unlike Prometheus query-language exponentiation.

Labels are preserved from native source results, including `__name__` when
Prometheus retains it. Native Loki instant vectors become number frames; range
results become sparse time-series frames with nanosecond timestamps. Missing
window samples are not padded with nulls or zeros. Strict `last` therefore selects
the last native point, which may precede the window end; it does not prove
Grafana's gap-filling/frame-conversion or missing-series behavior. Math joins equal or subset label sets and can fan out; a
single incompatible item on each side joins without labels and emits a dropped
label notice. This is not Prometheus vector matching or proof of Grafana's
original datasource frame translation. Establish the intended dimensions in the
source expressions; Pulse does not silently rewrite definitions or invent series
identity.

Results contain a typed `result`, decimal-string values (or null), and dropped
input notices. They explicitly remain `executable: false` and `migrated: false`.
An empty result is not a healthy alert, a no-data policy decision or evidence
that the source data is resident. Preview does not checkpoint lifecycle, enqueue
recordings, create events, render templates or send notifications. Enabling an
import is still rejected.

A preview uses one admitted supervised query task for all sources and expression
work, with one deadline and heap limit. Mixed previews use the `promql` admission
class and PromQL heap configuration, in addition to the common tenant/interactive
slots; direct LogQL class limits do not separately apply inside that task. Sample, work, intermediate and output
budgets accumulate across both query languages. Log records consume sample/work
allowances before pipeline filtering, so discarded records do not evade the
shared input bound. Work also charges pipeline output and repeated range-window
visits, independently of the once-per-record sample charge. Nonempty `__error__`
labels remaining after pipeline filtering reject metric queries before grouping
can hide them; this does not implement all Loki parser/error-label generation.
Object segment/byte/row scan ceilings use the smaller of the
PromQL and shared query-runner limits, conservatively divided across every
syntactic selector in the batch; unused allowances are not redistributed. Metadata reads and provider
retries retain the ordinary storage accounting, so these ceilings are not billed
provider traffic limits. Expression evaluation additionally caps total source
frames at 1,024, cumulative retained/allocated points at 100,000, label bytes at
1 MiB and matching work at one million units. Source points consume that shared
point budget; a near-limit source may leave no room for computed results.
Parsing is bounded at 16 KiB and 256 tokens per expression, depth 64 and 4,096
compiled nodes per graph. Budget exhaustion errors instead of truncating.
These are per-instance/request safeguards, not deployment-wide admission or
production capacity promises. Final response expansion also has a conservative
1 MiB encoded-byte ceiling, counting escaped/repeated labels before constructing
response frames; even a smaller actual encoding can fail that upper-bound proof.
The graph uses explicit evaluation times, not an atomic multi-source storage
snapshot.

Unsupported source/expression graphs, macros and query/result/resource limits
return HTTP `422` with a distinct error code; narrow or correct the definition
instead of repeatedly retrying it. Busy admission is `429`; expired request
execution is `504`. Storage/task availability failures remain `503`, while an
invalid running binding configuration is `500` and needs operator repair.
MCP tool failures preserve unsupported-source/expression and budget reason codes
in the error result. Neither a timeout nor exhaustion becomes successful no-data.
