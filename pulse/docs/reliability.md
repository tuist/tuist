# Periodic reliability assessments

Pulse can periodically assess observed logs, scalar metric samples and server
spans without requiring manually authored alert expressions. This experimental
feature is **off by default** and requires S3-compatible conditional writes.
It does not alter ingest acknowledgments, raw storage or retention. Processing-only
ingestion remains unimplemented; do not turn off raw publication to enable it.

The path is:

1. Capture service/environment summaries jointly across all three signals.
2. Ask OpenAI Decisions to choose `expected`, `watch`, `investigate` or
   `insufficient_evidence`, including for ordinary windows.
3. Optionally execute one of three fixed captured-evidence queries, then make
   one more assessment under the same budget. There are no generated queries.
4. Publish a durable reliability signal, with measured evidence separate from
   the model's judgment. Read it and its changes through authenticated MCP.
5. Optionally hand an `investigate` verdict to a configured external runtime
   after reserving its allowance. That runtime owns investigation and actions.

This is not a calibrated anomaly detector, complete telemetry analysis, or a
guarantee that the model identifies real incidents. An `expected` judgment means
only the model's assessment of the supplied observations, not proven health.

## Enable assessments

Configure the same settings on every participant sharing a tenant/bucket:

| Variable | Default | Contract |
| --- | --- | --- |
| `PULSE_RELIABILITY_ENABLED` | `false` | Start background assessment on S3-backed instances. |
| `PULSE_RELIABILITY_TENANTS_JSON` | `[]` | Explicit unique tenant identifiers, at most 64; `.` and `..` reject. No automatic paid enrollment. |
| `PULSE_RELIABILITY_OPENAI_API_KEY` | unset | Secret used only for Decisions requests. Required when enabled. |
| `PULSE_RELIABILITY_PRICE_VALID_UNTIL` | unset | Required ISO date through which the operator has approved the declared price. Dispatch stops after it. |
| `PULSE_RELIABILITY_INPUT_NANO_USD_PER_TOKEN` | `110` | Declared maximum input price: 110 nanoUSD/token is $0.11/million, allowing a 10% premium over the verified $0.10/million rate. |
| `PULSE_RELIABILITY_ASSESSMENT_BUDGET_USD` | `500` | Whole USD/month **per tenant** for reserved model attempts; range `0..100000`. |
| `PULSE_RELIABILITY_OBJECT_BUDGET_USD` | `100` | Whole USD/month per tenant for **estimated** reliability object work; range `0..100000`, not a storage invoice cap. |
| `PULSE_RELIABILITY_INVESTIGATION_BUDGET_USD` | `1000` | Separate whole USD/month per tenant for external grants; range `0..100000`. |
| `PULSE_RELIABILITY_INVESTIGATION_URL` | unset | Optional fixed HTTPS webhook; no model-supplied destinations or redirects. |
| `PULSE_RELIABILITY_INVESTIGATION_TOKEN` | unset | Separate secret bearer credential for that webhook. Required with its URL. |

Use the chart's `reliability` values for non-secret settings. Supply the API key
and webhook token using Secret-backed `extraEnv`, not plaintext chart values.
Explicit enrollment authorizes sending service/environment identities and bounded
statistics to the provider. Metric inventory follow-ups include selected metric
names and scalar values. Log evidence contains hashed shape signatures, not
message text; arbitrary log fields, span attributes and trace IDs are not sent.
Treat derived summaries as sensitive and apply your provider/data residency policy.

The initial adapter uses `gpt-6-luna` at `/v1/decisions`, with fixed choice
questions and explicit caching with no cache boundaries. It neither writes
explanations nor generates queries. Unsupported/refused/malformed responses,
oversized requests and failed calls yield unknown, not healthy. Model decisions
are untrusted: the query catalog and all limits remain code-controlled.

## Windows, coverage and scale

Each capture ends at an epoch-aligned five-minute boundary with a two-minute
settle delay. Compare five current minutes against thirty preceding baseline
minutes. On the next capture, replace the previous ten minutes plus newly elapsed
time, retaining older minute bins. Late arrivals beyond repair can be missed.
Reads are fresh but not an atomic cross-signal snapshot or exporter watermark.
Missing instrumentation and sampling remain unknown, not zero total traffic.

Group by service and deployment environment, with explicit `unknown` identities
when absent. For rich OTLP records, original string resource attributes are
authoritative across logs, metrics and traces; namespaced metric `job` labels do
not change that identity. Use `service.name` and `deployment.environment.name`;
the deprecated `deployment.environment` is a fallback only when the canonical
environment key is absent. Custom underscore aliases never override original
OTLP dimensions, and present empty/nonstring dimensions remain `unknown`. Legacy
records and remote-write samples use their existing service/environment labels.
Custom log severity text does not reject a capture; numeric error severity still
counts even when its text is not a recognized severity name.
Logs measure count/severity and bounded shape signatures. Metrics
are a bounded scalar sample inventory, **not inferred counter rates** or a full
series model. Traces describe observed server spans, not all requests. There are
at most eight selected metric names and four log shapes per minute/group;
exclusion counters expose omitted contributions. Raw error payloads are not
automatically analyzed as Sentry issues; the separate error monitor retains its
own contract. Missing published segments and corrupt/oversized scans fail whole.

The first version admits at most **100 known groups per tenant**, retaining
previously observed identities even when now missing. Exceeding this rejects
the capture; it does not select an arbitrary 100 or implement fair inventory
rotation. One worker pass assesses one group, round-robin across enrolled tenants,
with a one-second delay after each pass. Storage/model latency and contention
add to that cadence. Once all slots in a tenant's window are claimed or deferred,
the worker skips that tenant's storage reads until the next five-minute boundary
plus settle delay. This scheduling cache is disposable: restart or a new owner
checks the durable head, without rereading a completed snapshot or repeating
paid work. Five minutes is the evidence interval, **not a guaranteed
assessment SLA**. Uncompleted slots are recorded when the next snapshot publishes.
Priority rotates deterministically across windows so exhausted budgets do not
always favor lexical service order.

Each capture admits at most 10,000 returned records, 128 selected segments,
16 MiB scanned bytes and 100,000 scanned rows **per signal**: 30,000 records,
384 segments, 48 MiB and 300,000 rows across the attempt. Logs additionally cap
decoded column buffers at 8 MiB. Existing metadata/deadline/heap/query admission
limits also apply; native/provider work already dispatched can outlive a caller.
The captured snapshot is at most 4 MiB, and the tenant control head at most 2 MiB.
No findings are published from partial captures. Fixed `log_patterns`,
`slow_traces` and `metric_inventory` queries read the captured summary, with
**no second raw-data scan**. A second model response cannot start another query.

## Budget behavior and object-storage costs

Model dispatch reserves all 5000 input tokens at the declared price **before**
the HTTP attempt. The complete text request has a conservative byte-based
admission bound plus framing margin; reported usage must also fit. Reservations
are never refunded, even after local admission rejection, transport failure or
unknown outcome. There are no automatic HTTP retries. A follow-up requires a
second full reservation and may defer an otherwise promising observation.

At 110 nanoUSD/token, each attempt reserves $0.00055. One attempt for 100 groups
every five minutes reserves $475.20 in 30 days or $491.04 in 31 days; follow-ups
consume remaining allowance, not an extra budget. Actual invoices may be lower.
The ledger bounds authorized attempts under the declared price, not price changes,
unrelated credential use or provider billing behavior. Review current
[Decisions pricing](https://developers.openai.com/api/docs/guides/decisions).

Object work is charged as fixed **planning estimates**: $0.003 per capture attempt
and $0.00005 per reserved assessment attempt. These estimates gate new work; they
are not metering of physical GET/PUT/LIST requests or a guaranteed $100 invoice.
Root reads, polling, retries, provider metadata reads, versioned-head bytes,
cleanup, orphan objects, and externally initiated MCP reads can differ from the
estimate. The physical scan limits above remain authoritative. Raw ingest/archive,
compute, other features and baseline storage charges are outside this allowance.

For reference, Tigris Standard Global/Single-region advertised $0.02/GiB-month,
$5/million PUT/LIST and $0.50/million GET/HEAD with free egress on October 31,
2026. Other storage classes differ; daily-peak billing and bucket version history
can dominate small payload storage. See [current Tigris pricing](https://www.tigrisdata.com/pricing).
Pulse captures all services together and replaces one snapshot per window, rather
than scanning a raw baseline independently per service. Each group still reads
the shared snapshot and CAS-updates a bounded head; measure those costs before
raising scale or shortening intervals. A completed replacement deletes its old
snapshot best-effort. Interrupted publication/cleanup can leave unreferenced
snapshots; automatic orphan sweeping is not implemented. Do not apply a blanket
TTL to the control head or delete the currently referenced snapshot. Manage
noncurrent bucket versions and reconcile orphan snapshots during maintenance.

Per-tenant CAS claims and reservations survive overlapping owners and independent
instances. Rendezvous reduces duplicate polling among connected nodes but is
not correctness authority. Independent unclustered replicas add polling and
conflict costs. Time must be synchronized; regressed clocks cannot reserve work.
Each reservation, including conditional-write retries, samples the clock anew;
follow-ups and handoffs use their own authorization time for calendar budgets,
daily limits and cooldowns, while retaining the original evidence window.
Price approval is checked again before reservations and HTTP dispatches. A
snapshot-publication retry preserves already-created assessment claims, and a
stale budget deferral cannot replace another worker's reservation or result.
Assessment-publication retries return the committed result without advancing its
revision, replacing its episode or emitting another assessment change.
UTC calendar months/days determine ledgers and limits, with current/previous
month accounting retained. Deleting/restoring the head can reset budgets and
deduplication: protect it as authority, not a disposable cache.

## Consume signals

Use existing tenant-authenticated MCP tools:

- `list_reliability_signals`: latest service signals, budgets, current assessment
  slots, snapshot time and investigation statuses; optional `limit` and `cursor`.
- `get_reliability_signal`: latest signal by `id`.
- `list_reliability_changes`: bounded replay of assessments, coverage,
  investigation starts/outcomes and deferrals; optional `limit` and `cursor`.

All require `tenant`. Pages default to 20 rows and cap at 100. Persist change
cursors and deduplicate `change_id`. The head retains 128 changes; falling behind
`replay_floor` returns `reset_required`. Restart from a fresh signal snapshot,
then resume change replay. Signal-list pagination also resets when publication
changes. Read tools never authorize investigation starts or remediation.
Read current assessment status and timestamps before acting: a previous signal
can remain available while the newest window is failed, pending or deferred.

Signals carry stable service/environment identity, revision, episode, window end,
publication time, measured evidence and the model assessment. When selected,
`followup_evidence` preserves the fixed query's bounded result alongside the
initial evidence, independently of rolling snapshot replacement. A model's `expected`
verdict starts a new episode on the next non-expected window; it does not resolve
authored alerts or prove recovery. Unknown attempts keep their claims so a crash
does not silently dispatch duplicate paid work. A failed scan is not retried
within the same window; the next capture can repair bounded context.

## External investigations

Configure a receiver only after it implements this grant contract:

- Authenticate the configured bearer credential and durably deduplicate the
  `Idempotency-Key`/run ID **before** starting any work. Answer 200 or 202 after
  durable acceptance; no redirects or automatic delivery retries are used.
- Persist the payload's `completion_token` privately. It is never exposed to
  read-only MCP clients; only its hash is stored in the control head.
- Enforce `max_cost_nano_usd` (currently $5, including all model/tool work),
  `deadline_ns` (15 minutes) and your own concurrency/action policy. Pulse cannot
  enforce another system's model/tool charges or stop its execution.
- Use separately provisioned read-only tenant MCP credentials to investigate.
  The completion token grants no query or infrastructure permissions. Any
  remediation stays in a separate server with the runtime's approval policy.
- Once execution has **stopped**, POST JSON `{"tenant":"…","outcome":"completed"}`
  or `failed` to the supplied relative `completion_path`, on your configured
  Pulse origin, using `Authorization: Bearer <completion_token>`. The same final
  outcome is idempotent for **seven days from its first committed completion**;
  a different terminal outcome returns 409 within that horizon. Replays do not
  extend the horizon. A late completion receives the full seven days regardless
  of when execution started.

Completion callbacks use their own supervised, heap/deadline-bounded admission
lane (one concurrent callback per instance by default), not authenticated query
capacity or the tenant's interactive-query slots. Unauthenticated requests can
still contend with legitimate callbacks and add storage/provider pressure;
rate-limit this public route at your ingress. A completion token does not grant
query access. Existing grants can complete even when assessments are disabled
or price approval has expired.

Receivers must distinguish these responses:

| HTTP status | Meaning and action |
| --- | --- |
| 200 | Completion committed, or the same retained outcome replayed. |
| 400 | Invalid completion arguments; fix the request. |
| 403 | Missing/invalid credentials for a retained run; do not treat this as overload. |
| 409 | A different terminal outcome was already recorded. Reconcile rather than overwrite. |
| 410 | Completion receipt unavailable: expired or unknown run/tenant. This does **not** establish whether execution completed. Reconcile with the external runtime; do not start another run automatically. |
| 429 | Callback admission busy; retry the identical request with backoff. |
| 503 | Storage, contention or execution failure; retry the identical request with backoff. |
| 504 | Deadline expired; publication may have committed. Retry the identical request. |

429 and 503 include `Retry-After: 1`. Authenticate retained tokens before
returning their outcome. Expired receipts may be removed on a later grant;
unknown IDs cannot be distinguished from removed receipts and also return 410,
without authenticating an outcome. Neither case frees an unresolved slot.
Terminal receipts are retained by **completion time**, never evicted just to
keep the newest 30 starts. Under the existing start/concurrency caps, a seven-day
horizon fits at most 162 completed receipts plus two unresolved runs; the 2 MiB
head limit still applies. Older heads lacking completion timestamps receive a
seven-day grace period from their first successful replay or subsequent grant;
already-deleted receipts cannot be reconstructed.

Pulse reserves the full $5 before dispatch, at most 20 starts per UTC day and
two unresolved runs per tenant, plus a one-hour service cooldown that survives
new assessments and episodes. The $1000 monthly allowance grants at most 200
runs. Lowering the allowance does not cancel existing grants. Repeated findings
continue assessment independently but cannot bypass the cooldown/caps.

Ambiguous/failed webhook delivery retains its full reservation **and concurrency
slot**. Slots never expire automatically, even across month boundaries: the
external runtime may still be executing. Only authenticated completion releases
one. Receiver recovery must retain completion tokens. If an outcome cannot be
reconciled or its token was lost, assessment continues but investigation capacity
can remain blocked; there is no automatic safe retry or administrative release
endpoint in this version. A crash between signal publication and dispatch may
miss that handoff; later periodic assessment can try again under the same caps.
This is a bounded single-attempt integration, not guaranteed exactly-once workflow
delivery, an investigation engine, or a deployed GPT workflow.
