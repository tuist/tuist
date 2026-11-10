# Reliability-first Pulse and external agent workflows

Status: an experimental first slice now implements periodic cross-signal
summaries, Decisions judgments with shared CAS reservations, durable MCP signals
and capped single-attempt external webhook/completion. See the exact implemented
[operator contract and limits](../docs/reliability.md). Fair inventory rotation,
physical object-cost metering, reliable workflow delivery and processing-only
ingestion remain open. [Architecture](../docs/architecture.md) is authoritative.
The broader profiles below remain target design, not blanket acceptance of every
requirement, a provider subscription or deployment authorization. No retention
default, storage format or existing data is changed.

## Product decision

Pulse's primary job is to turn incoming telemetry into useful reliability
signals that an external GPT workflow can investigate and act on. Keeping a
complete raw archive is an optional capability, not the definition of the
product. Tuist is the first intended integration and validation workload, not
the boundary of supported applications or public ingestion protocols.

The default target experience is: connect collectors, receive meaningful changes
with evidence, and let an authorized workflow investigate. Customers needing
historical queries, dashboards or auditing can opt into raw retention. Do not
claim that most customers prefer this until actual adoption validates it.
Do not promise a 99% reduction, guaranteed root causes or full historical
debuggability. Measure what investigations survive reduction.

Automatically assess tenant/environment/service groups on a fixed cadence,
including windows that no deterministic detector flagged. Mathematics prepares
bounded, trustworthy measurements; a decision model judges whether the combined
observations merit investigation. Users select spend and coverage policy, not
one alert expression per service. Keep authored alerts and deterministic
detectors available without making them the only admission path to assessment.

## Current implementation and the gap

- All successful raw ingestion still requires Parquet PUT and manifest CAS.
  Raw data is kept indefinitely by default; configured event-time retention
  expires it. A retention duration of zero does **not** mean processing-only.
- The experimental error projection publishes issue summaries and replayable
  changes from retained logs, now including fixed-window `error_rate_increase`
  findings. Counts and coverage still depend on raw retention. Compact examples
  survive inside replay pages, not as a separate full-payload evidence store.
  The count-ratio detector is not a general statistical anomaly engine.
  `new_in_retained_history` is not a regression or first-ever occurrence.
- Native alerts already publish bounded durable transitions with read-only MCP
  replay and live resource hints. They evaluate authored conditions, not general
  learned patterns. Error changes currently support polling, not subscriptions.
- Experimental bounded cross-signal windows, an OpenAI Decisions adapter,
  shared assessment reservations and capped external handoffs now run under
  opt-in supervision. They reject above 100 known groups rather than rotate a
  larger inventory fairly. Handoff is single-attempt, not reliable workflow
  delivery, and the external runtime must enforce actual execution costs.
  Existing logical object-operation metrics and fixed planning charges do not
  prove physical provider request counts or exact billing.
- None of these paths yet guarantees analysis before raw expiry. Shortening
  retention today can force resets and lose example payloads. Do not present
  that configuration as implementing this design.

## Responsibility boundary

```text
collectors / SDKs
  -> Pulse: validate and durably admit bounded processing inputs
  -> Pulse: summarize logs + metrics + traces per service/window
  -> Pulse: reserve assessment spend, ask a bounded decision model
  -> Pulse: publish ReliabilitySignal + measurements + assessment provenance
  -> external workflow: replay changes, deduplicate, check current state
  -> external workflow: reserve investigation budget and a concurrency slot
  -> external GPT: investigate through read-only Pulse MCP
  -> external action policy: notify / propose fix / request human approval
  -> separate remediation tools, when explicitly authorized

optional branch: admitted inputs -> queryable raw archive
```

Pulse owns measured observations, assessment scheduling, constrained provider
calls, assessment credentials/budgets, coverage, evidence and replay. The
external runtime owns investigative model credentials, agent execution, its own
model/tool budgets and infrastructure actions. A provider adapter is not an
arbitrary agent runtime. Preserve the assessment separately from measurements;
an external workflow may attach a hypothesis without rewriting observation as
proven causality. Deployment correlation is not proof of cause.

## Assessment and investigation budgets

### Reference profile and pricing assumptions

Start with the following per-tenant opt-in profile. These are initial engineering
choices requiring replay and prospective shadow validation, not accuracy claims.

| Control | Reference value | Enforcement owner |
| --- | --- | --- |
| Active service/environment groups | 100; overflow explicitly unassessed | Pulse |
| Assessment cadence | Every 5 minutes, with stable jitter | Pulse |
| Total billed input per assessment | At most 5000 tokens, including rubric/questions | Pulse adapter |
| Model assessment allowance | $500 per UTC calendar month | Pulse shared ledger |
| Additional reliability object-work allowance | $100/month estimated; separate request/byte caps | Pulse |
| Investigation allowance | $1000 per UTC calendar month | External runtime |
| Investigation starts | At most 20 per UTC day | External runtime |
| Concurrent investigations | At most 2 per tenant across all workers | External runtime |
| Per-investigation allowance | At most $5 in model and tool charges | External runtime |
| Same-episode automatic restart | No sooner than 1 hour, only for material new evidence | External runtime |

The OpenAI [Decisions guide](https://developers.openai.com/api/docs/guides/decisions)
and [pricing](https://developers.openai.com/api/docs/pricing), verified October 31,
2026, quote $0.10/million uncached input tokens for `gpt-6-luna` on Decisions,
with no output charge. Thus 100 groups × 8640 five-minute assessments in 30 days
× 5000 tokens × $0.10/million = $432. At one-minute cadence this becomes $2160;
at 1000 groups and five minutes, $4320. Group count includes environments and
tenants; adding replicas must not multiply scheduled assessments.

The $500 cap allows some headroom, not guaranteed full coverage. A 31-day month
costs $446.40 at that rate; with a 10% regional premium it costs $491.04 before
retries. Cache reads are cheaper, but cache writes cost extra and require an
identical eligible prefix. Reserve the applicable cache-write, regional and
context maximum, never assume a hit or a Batch discount. Refuse admission if the
adapter cannot conservatively bound charged tokens and price. Version the
provider/model, token-count bound and price schedule; block new dispatch on an
unknown/expired schedule until operator reconciliation. Budgets do not cover
unrelated use of shared credentials, taxes, provider price changes or compute.

At 864,000 assessments/month, a 0.1% investigation choice means 864 candidates.
The separate $1000 allowance funds at most 200 starts reserving $5 each until
reconciled charges free capacity; 20/day and concurrency limits may reduce that
further. A $5 limit is a policy choice, not a quoted agent price or proof of
investigation quality. Do not automatically transfer unused allowance between
assessment, object work and investigation.

### Moving windows and fair scheduling

Discover bounded service groups without raw paths, user IDs or arbitrary label
combinations. Use explicit tenant/environment/service identity, retaining unknown
environment as unknown. Aggregate all three available telemetry kinds into one
assessment rather than three independent calls. Service-level coverage is the
default; route drilldown consumes the same allowance. Reserve a rotating share
of the 100 slots for newly discovered/unassessed groups, keeping selection stable
for an epoch and publishing inventory exclusions. Operators may pin important
groups within the cap. No automatic change to a more expensive cadence or wider
coverage; if the funded cadence cannot cover admitted groups, defer slots fairly
and publish actual coverage instead of silently dropping low-volume services.

Use one-minute half-open event-time bins and assess the latest completed
five-minute window against the immediately preceding thirty minutes. Initially
delay evaluation two minutes and repair late data for ten minutes; these are
provisional policies, not exporter-completeness guarantees. Persist bounded
aggregates and source lineage; compare distributions/counts, never averages of
quantiles or sampled spans interpreted as complete request traffic. Include
volume, latency buckets, errors, severity/template mix, representative redacted
examples and coverage. Cold start, unsupported instrument semantics, scan
failure and missing denominator remain explicit. A summary that cannot fit the
token bound drops optional examples/dimensions with exclusions, never coverage
or units; if mandatory evidence cannot fit, do not dispatch.

An assessment is identified by tenant/group, window finish, input revision and
policy/model generation. Freeze its admitted evidence and hash for replay. Late
corrections can create a new revision but any reassessment spends the same
budget; never rerun all overlapping historical windows without a bound. After
downtime, assess current coverage, record missed slots and do bounded aggregate
recovery rather than enqueue an unlimited backlog of old model calls.

### Typed decision contract and ReliabilitySignal

The initial OpenAI adapter uses Decisions `choice` with fixed outcomes:
`expected`, `watch`, `investigate`, `insufficient_evidence`. Fixed, versioned
instructions ask about the combined evidence; no model-supplied executable
queries, tools or remediation. Other providers must satisfy the same typed
contract and cost-bound interface, not pretend to share token prices or
probability calibration. Telemetry is untrusted input, never authorization.

Decisions does not generate a written explanation or arbitrary structured
finding. Pulse supplies measured evidence and lineage; store returned choices,
probabilities and confidence as model outputs, not calibrated incident likelihood.
Any explanatory/investigative generation is a separately charged external step.
Refusal, malformed output, timeout and exhausted budget are assessment status,
never `expected`. Even `expected` means assessed evidence, not application health;
models cannot override missing coverage or directly declare an incident resolved.

Materialize `ReliabilitySignal` outside the existing `Storage.signal` enum.
Keep stable population/episode identity and immutable revisions containing input
hash, windows, source receipts, measured values, exclusions, evidence expiry,
provider/model/rubric versions, returned assessment, publication time and spend
provenance. Retain bounded ordinary assessment receipts as well as escalations,
so investigation rates and false negatives can be evaluated. New windows update
an existing episode; they are not new incidents by default. An `investigate`
choice publishes a candidate, not an investigation start. No model-generated
confidence threshold silently bypasses dispatch policy or hard spending limits.

### Reservation, dispatch and failure contract

Use a bounded per-tenant/month object-store CAS ledger, separate from raw ingest
and not a deployment-global head. Admission atomically checks committed spend
plus outstanding reservations before recording a unique attempt's maximum cost.
Tie the attempt to the immutable assessment identity/evidence. A single-use
dispatch claim prevents competing workers sending the same attempt; rendezvous
alone does not. Do not hold a CAS operation open over provider I/O. Bound ledger
entries, reconciliation work and contention; after finalization retain aggregate
spend plus enough attempt receipts for the declared replay horizon. Exhausted
ledger capacity defers work rather than weakening spend admission.

Provider calls have no transaction with S3. Disable hidden automatic retries or
reserve their entire worst-case cost. A crash after claiming dispatch may mean
no request was sent or a charged result was lost: retain maximum spend and expose
`outcome_unknown`; do not hand the same attempt to a replacement worker. Any
retry/reassessment gets a separately funded attempt. Reconcile trusted usage
into settled spend only with evidence; wall-clock timeout alone cannot refund
an outstanding charge. Bound recovery calls and include them in the allowance.
Persist results before the signal head advertises them; a lost signal CAS may
replay an already persisted result without another provider call.

Preserve outstanding liabilities across UTC day/month rollover and budget edits;
keep a limit on total open reservations across periods, not only within each
month. Do not resubmit in-flight requests against a new month's empty ledger.
Lowering a cap below committed/reserved spend stops new work without cancelling
the accounting obligation. Financial reservations are distinct from concurrency
leases: timed-out provider work still counts against known in-flight pressure
until completion or a proven upper execution bound; unresolved cases quarantine
capacity. No exactly-once external execution or exact invoice guarantee is made.

### Capped external investigation

The consumer durably accepts each signal revision, then coalesces it into a
stable episode before reserving a start, per-run cost and tenant concurrency
slot. These caps are shared across external workers, never per Pulse node. Runs
are read-only initially. Reserve each model/tool step within the $5 allowance;
unknown outcomes retain their charge. An uncapped external runtime cannot claim
to enforce this profile merely because Pulse limits how many signals it emits.

During a run, attach newer revisions instead of spawning siblings. After it
finishes, require material new evidence and the one-hour cooldown before another
automatic run for that episode; a new timestamp alone is not material change.
Repeated `investigate` choices do not repeatedly spend $5. Correlate related
services only with explicit evidence; budgets are not an excuse to merge
unrelated failures or silently discard them. Deferred candidates remain visible
in a bounded, TTL-based queue with explicit expiry counters; recheck current
signal/evidence before a funded start. Use age-aware selection so ranking cannot
starve quieter services. Stale or missing evidence is unknown, not resolved.

Keep periodic assessment independent of investigation cooldowns. Budget/rate
exhaustion yields `assessment_deferred` or `investigation_deferred` and a reason,
without an application-health claim. Surface spend, reservations, group/slot
coverage, deferred/expired candidates and oldest pending age independently of
the model pipeline. Severity never automatically bypasses a cap. Remediation
and human notification policy remain separately authorized external concerns.

## Object storage and total operating cost

The cost envelope must include ingest, processing, summaries, model calls and
investigation, not just tokens. The $100 reliability object-work example is
incremental analysis overhead, **not a ceiling for existing accepted data or the
whole bucket bill**. Mandatory ingest durability, configured raw retention and
safe cleanup keep their existing contracts. Never shorten retention or delete
acknowledged data because an assessment budget is exhausted.

### Tigris reference rates

The official [Tigris pricing](https://www.tigrisdata.com/pricing.md), verified
October 31, 2026, gives Global/Single-region Standard prices of $0.02 per stored
GiB-month, $5 per million Class A requests (including PUT/LIST), $0.50 per million
Class B requests (including GET/HEAD), free DELETE and no egress/retrieval fee.
Tigris labels binary GiB as GB and bills the average of daily storage peaks;
do not price against uncompressed ingress bytes or month-end object counts.
Multi-region lists $0.025/GiB-month and $10/million Class A; dual-region pricing
multiplies storage/Class A by underlying region count. Recheck bucket placement
and the current quote; these figures are not interchangeable across layouts.
Examples ignore the account-wide free tier and negotiated discounts.

Short-lived processing, frequently rewritten heads and evidence belong in
Standard for this design. Infrequent Access has a 30-day minimum and $0.01/GiB
retrieval; Archive classes have 90-day minima. Cheaper byte rates do not imply
cheaper transient state, repeated reads or safe archival-query semantics.
Object notifications cost $10/million events, not per webhook batch; do not
introduce one paid notification per event when bounded manifest discovery works.

For 1 TiB/day of **stored Parquet**, steady retained payload is approximately
1024 GiB per retention day: $20.48/month at one day, $143.36 at seven, $614.40 at
thirty. These exclude peak timing, versions, delayed GC, originals overlapping
compaction, evidence and metadata; no compression ratio is assumed. Today's
default indefinite retention grows the stock continuously. Versioned hot heads
need separate lifecycle costing because expiry of current references alone does
not reclaim historical versions.

Small objects can cost more in requests than in retained payload:

| 1 TiB/day stored Parquet, 30 days | 1 MiB segments | 8 MiB segments |
| --- | --- | --- |
| New objects/month | 31,457,280 | 3,932,160 |
| Two successful Class A requests per object | $314.57 | $39.32 |
| One GET per object | $15.73 | $1.97 |
| Seven overlapping reads per object | $110.10 | $13.76 |

Two Class A requests is an illustrative data PUT plus manifest update, not a
promise for managed catalogs: immutable page writes, budget/result/signal CAS,
discovery LISTs, compaction, cleanup, retries and independent owners add work.
Seven reads models a 35-minute comparison reevaluated every five minutes without
aggregate reuse; scanning that input independently for 100 services multiplies
reads again. Those seven passes fetch about 210 TiB/month of compressed input
rather than 30 TiB, with repeated decode work even though egress is free. No
benchmark, expansion ratio or compute-price claim is implied.

### Storage-aware execution and admission

1. Read tenant/signal candidates once per bounded scan epoch and reduce all
   admitted services together, reusing captured bytes within the attempt. Raw
   kinds still have separate source snapshots; do not claim a fused scanner or
   transaction already exists. Avoid listing the full bucket per assessment.
2. Persist versioned one-minute summary blocks and build comparisons from them,
   replacing affected bins during bounded late repair. Do not reread thirty-five
   minutes of raw history per service/model question. Inventory/compaction/source
   replacement must preserve counts; arbitrary identical logs are not duplicates.
   Source receipts, replay bounds and retained inputs must make recovery honest;
   loss of disposable caches cannot lose acknowledged work or silently double it.
3. Batch summary/evidence/receipt pages per tenant/kind/epoch with bounded sizes,
   not per event. Reuse existing ingest coalescing/compaction where appropriate;
   increasing segment size is a measured latency/memory tradeoff, not permission
   to change keyed bytes, acknowledgment or retention semantics.
4. Keep physical request, fetched-byte, decode-row/work and memory ceilings as
   well as estimated money. Count publication, ledger CAS, polling, orphan
   cleanup and native/client retries; current logical metrics are insufficient
   for a strict provider-billing bound. Reserve analysis request attempts before
   dispatch; include bounded control-plane overhead rather than recursively
   charging a separate ledger write for every GET. Ownership is an optimization;
   measure duplicate reads and CAS contention across independent instances.
5. Enforce the incremental allowance with prepaid bounded work reservations,
   request/byte counters and capped derived live bytes/lifetimes. Outstanding
   reserved work remains charged until completion. Storage dollars are projected
   from retention and daily peaks, not instantly refundable prepaid tokens.
   Fail closed for new optional analysis if its reservation cannot be bounded;
   do not block safe retirement/erasure or alter raw-ingest obligations. Reserve
   enough cleanup/control capacity to report deferral and prevent orphan growth.

Report base ingest/archive costs separately from incremental reliability and
external investigation costs; count each physical operation once. A model token
budget does not cover native CPU, application-host networking or storage on
other providers. Reconcile estimates with provider usage/invoices and expose
unknown physical-attempt coverage. No hard whole-account dollar cap is claimed.

## Three independent data lifetimes

1. **Processing inputs:** short-lived durable batches for analysis/recovery.
   Reuse existing Parquet/manifest primitives rather than a second raw inbox or
   a local WAL. Processing-only means no promised raw query archive, not that
   raw bytes never touch disk/object storage. Disclose transient persistence.
2. **Findings, baselines and evidence:** bounded durable detector state,
   comparison windows, replay history and selected redacted examples. Evidence
   must remain readable for its advertised lifetime after source expiry;
   references alone are insufficient. Bound examples per finding, payload bytes,
   total tenant evidence, cardinality and state/history growth. Expired evidence
   is explicit, never a misleading empty successful lookup.
3. **Raw archive:** opt-in queryable history with independently configured
   signal/window policies. Enabling it is prospective; it cannot reconstruct
   discarded inputs. Disabling it requires explicit policy change and does not
   bypass existing irreversible-retention and cleanup safeguards.

Finding history need not live forever. Declare each lifetime and replay floor;
disconnected agents cannot pin storage indefinitely. Counts/baselines refer to
their observation window, not the number of retained examples. Exactness and
deduplication have declared horizons; unlimited retry deduplication cannot be
promised with bounded state. Raw queries outside coverage must expose the
available horizon/mode, not imply an empty healthy system. Query-derived alert
rules and dashboards require enough retained source data for their windows;
they do not automatically work in processing-only mode.

Evidence and derived labels can expose the same secrets as raw events. Apply
tenant/source authorization, scrubbing, per-class expiry and explicit erasure
to all derived objects. Deleting raw inputs alone is not tenant erasure; neither
is data minimization a claim of zero vendor exposure during processing.

## Durable processing before optional archival retention

Any instance must accept work; any eligible worker can recover it after restart.
Rendezvous ownership reduces duplicate work only. Shared authority remains S3
conditional publication with bounded immutable batches/pages, not a database,
broker, elected singleton, sticky routing or an in-memory baseline.

Before processing-only acknowledgement is introduced, specify and prove:

- The authoritative source publication commits the admitted batch and required
  processing policy/detector version together. No successful response depends
  on a later best-effort enqueue, notification or local buffer.
- Detector output, baseline advancement, deduplication and replay publication
  commit together under their owning CAS. Losing candidates cannot emit findings.
  Persist selected evidence before publishing references to it.
- Source completion is recorded only after committed output is verified. A crash
  between output publication and source completion replays safely. Do not assume
  transactions across independent manifest and detector heads.
- Raw-input reclamation requires durable completion of every required detector,
  or a committed explicit coverage gap after the declared processing deadline.
  Expiry cannot erase the only record of unfinished work. Preserve bounded gap
  summaries after reclaiming inputs; backlog overflow applies backpressure before
  accepting work it cannot track, not silent deletion or unbounded retention.
- Define source partitioning, exact retry identities/horizons, out-of-order/late
  input policy, policy edits and version migration, read/cleanup grace and bounds
  for pending-work discovery, deduplication and orphan cleanup. Avoid per-event
  CAS and a deployment-wide mutable head on the hot path.

The precise source/receipt layout is an implementation gate, not a new shipped
format in this proposal. No existing raw-retention worker may simply become
completion-aware by assumption. The current projection intentionally never gates
raw expiry; processing-only needs a separately versioned publication/cleanup
contract and coherent writer/worker upgrades.

## Finding and workflow contract

Use a versioned domain finding model, not new MCP protocol methods. A finding
needs stable ID/revision, tenant/service scope, detector identity/version,
occurrence window and observation/publication times, grouping identity, measured
values, comparison baseline, units, coverage/freshness and bounded evidence.
Expose uncertainty/estimation and detector-specific score semantics; do not invent
a universal confidence number. Distinguish detector recovery from application
recovery. Missing traffic, worker failure or expired evidence never resolves an
incident by itself.

Prepare ordinary log volume/pattern mix, recognized metric traffic/latency/error
features and observed trace distributions in the first cross-signal slice.
Preserve source types, minimum support and baseline coverage; historical
normality is not a healthy baseline. A low-traffic cold start, known deploy,
recurring daily pattern and telemetry outage must not all produce the same
diagnosis. Existing error findings and authored thresholds are additional
evidence, not mandatory gates for model assessment.

The workflow durably accepts a change using its stable ID before advancing its
cursor. Workflow creation must be idempotent across crash/replay; Pulse replay
does not make external actions exactly once. Persist investigation state in the
external runtime, recheck the current finding revision before actions, coalesce
repeated observations, cap concurrent investigations/cost and prevent feedback
loops from agent-generated telemetry. Untrusted logs and stack traces are data,
not instructions or authorization. Remediation remains separately policy/HITL
gated, including when a finding recommends an action.

Reuse the [alert replay/subscription contracts](alerting-mcp-events-plan.md):
ordered per producer/generation, explicit floors/resets, tenant-scoped reads,
durable consumer checkpoints and periodic reconciliation. No global order or
unbounded replay. Hints wake consumers; missed hints do not lose retained changes.
Do not force existing alert/error feeds into a common transport before needed,
or reinterpret their existing changes as statistically unusual behavior.

## Implementation sequence and acceptance

The local [error-count-ratio-v1](../docs/error-monitoring.md#error-rate-findings-for-agent-workflows)
is an initial deterministic building block, not completion of this sequence.
Next work targets all three telemetry kinds without requiring authored alerts:

1. **Build shared budget and signal contracts.** Add the `Pulse.Reliability`
   boundary with window, assessment, ReliabilitySignal, repository and budget
   modules under `lib/pulse/reliability/`, following existing alerting CAS/replay
   patterns without inheriting authored-rule semantics. Async public-interface
   tests must cover exact budget boundaries, simultaneous independent clients,
   ambiguous dispatch/write outcomes, retry reservations, day/month rollover,
   lower edited caps, bounded receipts, cross-tenant isolation and expired cursors.
   No live provider credentials or billed calls are needed for these tests.
2. **Persist storage-aware summaries and fair service inventory.** Extend
   `lib/pulse/storage.ex`, `storage/s3.ex` and existing native log/metric/trace
   reducers with explicit reference contracts and capability fences where needed.
   Add bounded aggregate/scan workers through existing application/query
   admission. Replay INFO-only logs, HTTP metrics and sampled server spans
   through real native Parquet/S3 adapters. Prove half-open boundaries, late
   corrections, no double counting across compaction, honest missingness,
   bounded cardinality and restart recovery. Instrument physical attempts and
   transferred bytes; show input is shared across service reductions and
   baseline summaries are reused rather than raw history rescanned per group.
3. **Implement opt-in periodic Decisions assessment and MCP replay.** Add a
   constrained provider behaviour plus OpenAI adapter using Req; inject an owned
   fake provider/clock/price schedule for tests. No general agent or new MCP
   protocol method. Add proposed `list_reliability_changes`,
   `list_reliability_signals` and `get_reliability_signal` tools through the
   existing registry with tenant authorization. Tests must demonstrate ordinary
   unflagged windows reach assessment; unknown/failed/deferred states cannot
   become expected/healthy; only funded single-use attempts reach the provider;
   persisted results replay without another call. Validate total prompt bound,
   refusal/malformed output, 429s, independent owners, pauses and stale evidence.
   Operator env/chart documentation ships only when this configuration exists.
4. **Integrate a capped external consumer, then shadow.** Tuist's runtime must
   own durable acceptance, episode coalescing, $5 stepwise limits, $1000/month,
   20 starts/day, two concurrent runs and cooldowns. Prove crash-after-accept,
   repeated revisions, pending-provider outcomes, expired candidates and
   allowance exhaustion cannot duplicate starts or reset spend. Run time-ordered
   labeled replay and prospective shadow before relying on model verdicts;
   measure missed useful investigations as well as noise and cost. Real provider
   calls, companion-repository changes and deployment require scoped execution
   authorization; this design alone neither contacts a provider nor deploys.
5. **Decouple processing from archival retention.** Specify/version the source
   completion/gap contract above. Validate processing-only and archival modes
   side by side before exposing a new mode or changing defaults. Fault-inject
   worker downtime beyond deadlines, ambiguous writes, CAS races, rolling version
   disagreement and raw/evidence GC. Prove each acknowledged batch is covered by
   completed processing or an explicit durable gap, including after all-node
   restart, and retained evidence survives raw deletion.
6. **Expand only with measured value.** Add seasonal summaries, budgeted route
   drilldown, custom metric semantics and model-proposed assessment criteria only
   after held-out replay, prospective shadow and explicit promotion. Preserve
   generic public protocol breadth. Full backend replacement and paging cutover
   remain independent compatibility, operational and authorization gates.

Measure missed known incidents, false/noisy findings, detection delay, stale/gap
duration, investigation success after source deletion, actual evidence/raw bytes,
provider requests, CAS contention, node memory, sustained ingest and model/workflow
cost. Compare both with a full-retention reference and with ordinary sampling.
Evaluate rare failures amid repetitive healthy traffic, burst retries and
high-cardinality dimensions; average compression alone is not acceptance.

Run publication/replay/cleanup tests across independent instances and ownership
changes. All safety budgets remain enforced; scaling instances multiplies
provider pressure and does not create a deployment-wide quota. Keep independent
self-monitoring for detector lag, coverage loss, replay gaps, admission failures
and evidence availability. No absence-of-findings health promise without fresh
coverage. Local validation is not authorization to dual-ship, delete production
data, change paging or deploy companion workflows.
