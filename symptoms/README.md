# Symptoms

Symptoms replaces alert rules for Tuist's own operations. It turns every
telemetry type into one kind of evidence, counts each failure once at its root,
and decides for each symptom whether to page, put it on the board or only log
it. The Tuist server mirrors symptoms, shows them on `/:account/pulse`, owns
human and agent state (ack, mute, investigations, outcomes) and records
investigation requests. Agent execution is not wired yet.

The full design, with its reasoning, sources and reviews, is the "Alert-free
attention model" document (revision 8). This README keeps what the code must
follow.

## Systems of record

- **This service (the evaluator)** is the only writer of detection state:
  entities, evidence, detector state, symptoms, revisions, tiers, roots, the
  audit log, baseline re-anchors and the template registry. It has its own
  PostgreSQL database (CNPG) and runs in its own namespace, like `tuist-ops`.
- **The Tuist server** is the system of record for human and agent state: ack,
  mute (scoped to entity and phenomenon, with an expiry), investigations and
  confirmed outcomes. The evaluator reads that state back for
  labels and the budget.
- Grafana IRM and Slack are delivery channels only. Atlas Signals is not a sink.

## Inputs

| Type | Entity | Per-window statistic | Raw statistic | Novelty |
| --- | --- | --- | --- | --- |
| Traces | `(service, span kind, span name)`; version is a dimension | Per minute: `count`, `count where status = error`; per 5 min a log-bucket latency histogram, γ = 1.1 (about 115 buckets from 1 ms to 60 s). From Pulse Flows, never tail-sampled data | Errors: beta-binomial residual against the trailing baseline, between-window variance fitted on the trailing 28 days. Latency: share above the baseline p95 and median buckets, baseline from at least 28 days | New span names enter the catalogue |
| Logs | `(service, template_key)` | VRL keys templates on logger metadata (module, function, line), falling back to masked text; a Flow counts per minute by service, level and key, plus per-service totals | Counts against the service total (its own stream). Vanished templates count only when expected ≥ 20 a window and explicit removal metadata confirms the code remains; without that metadata disappearance evidence is disabled | New after 3 sightings in 2 windows; deploy-introduced keys count only when error-level |
| Errors | `(service, fingerprint)` issue, attached to its route through `trace_id` | Event count and affected users per window from the Pulse `errors` table | Negative binomial on event count against the issue's own baseline; impact is affected users per minute | A new issue is a new hypothesis |
| Metrics | Queues, Kura regions, runner pools, saturation per workload, ingress per host | PromQL at 1 min | Robust residual against an hour-of-week baseline. Backlogs: growth, oldest-job age, time to drain from `predict_linear` | None |
| Shared resources | `postgres`, `clickhouse`, `kura-<region>`, `beam-<node>`, each pool's queue | Database client spans grouped by resource after merging aliases (`tuist-tuist-pg-rw`, `tuist-tuist-pg-pooler-rw`, `tuist-pg-pooler-production.taild6d7bb.ts.net` are one Postgres) | Client-side latency and errors; pool checkout time counts against the caller | None |
| Kubernetes events | `(workload, reason)` | Count per reason per workload | Negative binomial against the pair's baseline. Chronic reasons (`DNSConfigForming`, `Unhealthy` on known pods) go to a daily digest, never evidence | A first-seen pair is a new hypothesis |
| Probes | Journey: signup, registry resolve, test upload, API, cache | Pass or fail per check per location | A failure confirmed from 2+ locations or 2 consecutive runs reaches the cap at once. A pass lowers evidence only for its journey | None |
| Change events | Deploys (new `service.version`), config, rollouts | Version changes in traces, rollout events, commit ranges, `feature_flag_changes` | Not evidence. Start comparisons; add a small capped prior where they apply | Each is a hypothesis |
| Presence | `(service, telemetry type)` and the evaluator | Expected count against what arrived, and Pulse lag | Missing data marks entities *unknown*, never quiet, and is evidence of a pipeline failure | None |

## Evidence record

One per `(entity, source, window)`. See the build plan for the exact fields:
`entity`, `phenomenon` (`request_errors`, `latency`, `saturation`,
`availability`, `platform_events`, `novelty`), `source`, `window_start`,
`window_seconds`, `statistic`, `e`, `observed`, `expected`, `n`, `impact`
(`unit`, `rate`; when a flow is missing, the expected baseline volume),
`examples` (at most 3 IDs, never raw text).

## Calibration

Raw likelihood ratios are invalid on our series: cache 5xx alone crossed a
15.6-nat Lorden threshold 17 times in a quiet week. So:

1. Each stream computes its raw statistic.
2. The statistic is ranked against the stream's own trailing null history at
   the same hour of week, excluding windows with an open symptom. The rank is
   a conformal p-value: `p = (1 + #{history >= s}) / (1 + n)`.
3. A p-to-e calibrator turns it into an e-value, capped at 20 (about 3 nats)
   per window. Use the calibrator `e = κ p^(κ-1)` with κ = 0.5 (or the
   admissible mixture `(1 - p + p ln p) / (p (ln p)^2)`); either is valid.
   **Effective cap:** the p-value is at least `1/(n+1)`, and an entity's own
   history at one hour of week over 28 days is `n` = 240 one-minute or 48
   five-minute windows, so a ranked window reaches at most `0.5 · √241 ≈
   7.76` (2.05 nats) or `0.5 · √49 = 3.5` (1.25 nats)
   (`Symptoms.Evidence.Calibration.max_e/2`). The cap of 20 binds only from
   `n` = 1599 (borrowed family history), for confirmed probe failures and
   for the deploy version tests. A loud failure still crosses `h` = 6 in 3
   one-minute windows, as at the nominal cap; on 5-minute windows it takes
   5.
4. The detection threshold `h` is set per pipeline (1- and 5-minute) by
   replaying the combined score over the last 28 days, every window except
   those of incidents labelled bad, until the false-crossing rate matches
   the budget, not by Lorden's bound. The replay reads 200 entities at a
   time and keeps each entity's threshold/opening-count response and window
   count, discarding its raw windows after summarizing. Replay resolves an
   open detector after five non-positive windows and resets its CUSUM,
   matching the live quiet-window reset rather than counting uninterrupted
   excursions. Counts need not be monotone in the threshold; adversarial
   sequences can require many replay passes. This is an observed-series
   replay, not a reconstruction of historical roots or unknown telemetry.

A loud failure that reaches the cap each window crosses in minutes; slow drifts
land on the board.

## Isolated bursts (offline only)

`Symptoms.Evidence.Burst.evaluate/3` is a separate, pure candidate detector
for **service-wide error counts**, including new fingerprints. It does not
feed CUSUM, modify source calibration, open symptoms or page. Live integration
remains blocked until an independent held-out incident/quiet replay passes.

Fit the existing negative-binomial count model on a separate earlier interval
of complete windows, including real zeros, with at least seven days of
exposure. Freeze that fit during evaluation. Missing observations, absent
baselines and shorter histories return unknown. Never substitute zeros for
failed reads or select a fingerprint because its observed count is large.

The detector compares the model's single-window Chernoff upper-tail bound
against a nominal budget of 0.001 crossings per service-day divided by the
number of windows per day. It works in log space and retains overdispersion;
it uses the Poisson limit when dispersion is zero. This is a **model-conditional
bound**, not a production-calibrated p-value, an e-value, P(degraded), or a
false-positive guarantee for estimated parameters and non-stationary data.

Synthetic null checks and replaying unlabelled production bursts are necessary
checks, not the deployment gate. Recorded incidents and quiet controls must
overlap retained telemetry, be independent of these detections, and include
previously uninspected evaluation data. Until then candidates remain offline
and the sustained detector is unchanged.

## Combining

1. Within a phenomenon, for one entity, average the e-values of all sources
   with the daily source weights (a weighted mean of e-values is an e-value
   under any dependence).
2. Across phenomena, add their logs with weights fixed at 1, each phenomenon
   capped.
3. One CUSUM per root entity on the combined score: `S_t = max(0, S_{t-1} +
   x_t)` where `x_t` is the combined log-evidence for the window minus a drift
   term; a crossing of `h` makes a symptom.
4. Platt scaling, intercept and slope fitted on all labels so far, maps the
   score to P(degraded). Each pipeline (1- and 5-minute) has its own fit on
   its own symptoms' labels, centred on its own `h`. Before labels exist,
   use priors that make the score at `h` map to P = 0.5.
5. Roots: edges come from an hourly read-only Pulse query of span parent
   edges (`infra/helm/pulse/span-edges.sql`), kept in the evaluator's database. Shared
   resources are nodes; cycles collapse into one node; jobs link to the
   request that enqueued them where trace context propagates. A degraded
   entity whose callee is degraded in the same direction, starting no more
   than one window later, is explained by it; callers then add only impact.
   When every caller of a shared resource degrades together, or several
   entities degrade with no shared callee, it is a **shared-cause** symptom and
   an attribute contrast runs on host, pod, version and region. Retries per
   request count against the callee being the cause.

Each new source is added only after a held-out replay shows it does not lower
recall.

Implementation choices (`Symptoms.Lifecycle`):

- An entity is degraded in a window when its combined log-evidence exceeds
  `degraded_nats` (1). The CUSUM input of a root is the largest combined
  log-evidence among its unexplained members; explained callers add only
  impact. Root keys carry the window length, so the 1- and 5-minute
  pipelines keep separate detectors and symptoms.
- A failure's degraded run is excluded from its own null history before it
  crosses, so it cannot dilute its own evidence; once a symptom opens, the
  run is marked with the symptom (`stream_windows.symptom_id`). The null
  history then leaves it out only while that symptom is open (or merged) at
  board tier or above, or once it is labelled bad; a run that stayed at
  audit tier, resolved unlabelled or was labelled fine is history again.
  Each pipeline keeps its own degraded run per entity
  (`Symptoms.Store.DegradedRun`), so the 1- and 5-minute pipelines never
  reset each other's.
- Database client spans call their resource (`postgres`, `clickhouse`), as
  do the routes that issue them, so a resource failure behind one route has
  two callers degrading together and opens one shared-cause root.
  A merged caller can separate onto its own active root when its callee
  recovers but the caller remains degraded, retaining its symptom identity.
- The attribute contrast (`Symptoms.Contrast`) runs once when a
  shared-cause root opens or reopens: Pulse's top values of
  `host.name`, `k8s.pod.name`, `service.version` and `cloud.region` on the
  affected span entities' spans of the last 15 minutes, with each value's
  share of error spans, of all spans, and their ratio (`lift`). It lands in
  `evidence.attribute_contrast` of an `annotated` revision and is kept
  afterwards; an attribute Pulse does not have is left out. It never changes
  a score.
- Only one job per pipeline processes windows at a time: `Symptoms.Pipeline`
  holds a session advisory lock keyed by the window length, and a job that
  finds it held does nothing. The lock's connection has a 25-minute budget
  for source collection and up to five catch-up windows, below Oban's
  30-minute rescue age; individual SQL queries and HTTP requests keep their
  own shorter timeouts. Root scores are unique per root key, pipeline
  and window. Direct window calls take the same lock and skip completed
  windows. Detector state, revisions and the completion marker commit in
  one transaction, so a retry cannot accumulate the same window twice.
  Oban's Lifeline rescues jobs a dead node left executing.
- Every writer of revisions (the window, the board push, the state
  read-back and its labels, the contrast, deploys) takes the log's advisory
  lock first and reads the symptom only after it, so locks are always taken
  in the same order and no revision is built from a snapshot another writer
  replaced: a board push, outcome or resolution committed meanwhile is
  carried into the next revision.
- A mute matches an entity by its full key or by the trimmed key a snapshot
  over 16 KB carries.
- "Several quiet windows" is 5 consecutive windows with no member degraded
  and non-positive log-evidence; a non-positive window with any unknown
  member neither counts nor resets. Missing expected trace entities, source
  errors and probes with no valid samples are unknown, not healthy. Unknown
  state is retained per stream across windows and pipelines until that
  stream produces valid evidence; another stream's success cannot clear it.

## Deploys

Main gets 34–152 commits and 8–25 production deploys a day.

- Each deploy's commit range maps to the modules it changed and, through span
  code attributes, to the routes and jobs that run them. For each touched
  entity, the new version's first requests are compared with the last accepted
  version's recent requests with anytime-valid tests on error share and
  latency exceedance. Concurrent when both versions serve traffic; adjacent
  windows otherwise, at a smaller weight.
  Mixture evidence and rejection comparisons remain in log space. Per-window
  e-values are capped before exponentiation; very strong improvements may
  store zero e-value without attempting to take its logarithm.
- A small prior only where the change landed: about ×1.5 for code, ×2 for
  configuration or Helm values, ×3 for a migration, capped at ×3, decaying over
  30 minutes.
- Re-anchoring: if a deploy shifts a route and nothing bad follows within about
  2 hours (no independent label, no open symptom on that entity, no backstop
  burn), the new version's distribution becomes the baseline. Shifts above a
  cap (errors ×3, p95 ×2) never re-anchor on their own; they go to the board as
  "intended?". Every re-anchor is logged. Baselines never update while a
  symptom on that entity is open.

| Part | Cadence |
| --- | --- |
| Catalogue (routes, queues, span names, log templates) | Continuously, within minutes. A new entity borrows its service family's baseline and counts only for novelty in its first hour. Retirement requires explicit code-removal metadata; automatic per-template removal tracking is not implemented. Disappearance evidence stays disabled without removal metadata, rather than relying on a temporary deploy guard |
| Baselines | Rolling, re-anchored per accepted version. A failed history read preserves the entire source's last good snapshot and timestamp, returns an error and fails the refresh job; a successful empty history is valid data |
| Source weights within a phenomenon | Daily from outcome labels, each weight between 0.5 and 2 times the equal weight |
| Beta-binomial variance and calibrators | Weekly on the trailing 28 days of null history |
| Platt calibration and page price | Weekly, and right after a missed incident or a page labelled fine; an event-triggered refit moves the intercept by at most 0.5 logit and applies only if a 28-day replay loses no recall and adds no false pages |
| Impact rates, grouping, known noise | By a person, in a pull request behind the same replay gate |

Implementation choices (`Symptoms.Deploys`): a deploy's touched entities
are the service's span entities that served traffic on both the old and the
new version (`Symptoms.Sources.PulseTraces.changes/2`). The evaluator has no
commit-to-module mapping, so this stands in for "the code the commit range
changed" and over-counts: every route both versions serve gets the prior
and the version tests. The version test is a mixture
SPRT over odds ratios {1.5, 2, 3, 5, 10} on the new version's share of
errors given the window's errors, which has conditional mean 1 under equal
error rates; it rejects at e ≥ 20. Sources report per-version counts with
`Symptoms.Store.put_version_counts/2`; `PulseTraces` does so every minute,
and on 5-minute windows with each version's latency histogram and p95. The
same test runs on latency exceedance: each version's requests above the old
version's p95 bucket from its 30 minutes before the deploy
(`deploy.version_latency_exceedance`, `:latency`). Adjacent-window comparisons use the
old version's last 30 minutes, at raw weight 0.5. The deploy prior adds
`ln(multiplier)` to the touched entity's log-evidence. Re-anchoring is
decided 2 hours after a deploy; a frozen baseline waits, and gives up after
a day. An "intended?" symptom (`kind: "intended"`) resolves 72 hours after
it opened (three board pushes) or as soon as its outcome is confirmed
(`Symptoms.Deploys.resolve_intended/1`, every minute). Until then it freezes
the entity's baselines; it never marks stream windows as a degraded run.

## Decision

Page when `P × impact × minutes until the board is read > interruption price`;
put the top five symptoms by expected cost on the 09:00 Europe/Berlin board;
otherwise log.

- The budget is charged per root: a shared-cause outage that spawns ten
  symptoms costs one page.
- Hard floor: P ≥ 0.9 with impact above a set rate always pages. Unknown
  impact also uses this confidence floor, without inventing a conversion
  from queue depth, seconds or resource saturation to failed requests.
  Known zero does not use this fallback. A root with any unknown member
  impact has unknown expected cost (`null`); those costs are excluded from
  price fitting, while recall-gate replay includes confidence-floor pages.
  This fallback needs held-out historical validation before operational use;
  the prior P is not an empirically established probability of degradation.
- Pages are sent only after the window's transaction commits.
- Separate day and night prices; at night minutes-until-review grows to about
  15 hours, so the night price accounts for interrupting sleep. The board runs
  on weekends too.
- A random 20% of pages and board symptoms below the hard floor are delayed by
  10–15 minutes, with the probability recorded. Pages at the hard floor are
  never delayed. The delay is drawn once, when a root is charged a page or at
  the board push, and only that stored delay is published. A delayed page is
  sent only if its root is still at page tier and not muted when the delay
  ends.
- The evaluator calls no model: every decision, ranking and label is
  statistical or a fixed rule.

Implementation choices:

- `Symptoms.Board` acts hourly at 09:00 Europe/Berlin: it ranks open board
  roots by `ln(expected cost)`, writes an `annotated` revision with `board:
  {date, rank, nats, delayed_until, delay_probability}` on the top five and records the push
  (`board_pushed`). Each item's random delay is drawn at the push and stored
  on the symptom (`delayed_until`, `delay_probability`), so a restart, the
  labels' reweighting and `GET /api/v1/symptoms/board` all see it; the
  endpoint serves the push until the next one, each item once its delay has
  passed. It also writes the daily digest of chronic Kubernetes reasons
  (`k8s_chronic_digest` in the audit log).

## Labels

Training labels come only from outcomes the system could not cause:

- **Bad:** a customer support thread about the service within 7 days; SLO
  backstop burn; an IRM incident opened by a person before any page, or
  without one.
- **Fine:** none of these within 7 days and the signal stayed recovered.
- **Missed incident:** Bad with no symptom at board tier or above; triggers
  recalibration.

System-caused outcomes (incidents after a page, outcomes confirmed after a
page, reverts after a brief) are recorded and shown but never trained on.
Only items confirmed before any page (during a delay) or never paged train,
reweighted by their recorded delay probability.

Implementation choices (`Symptoms.Labels`): an outcome is system-caused
when the latest state row (highest `change_seq`) of an investigation on the
symptom or its root says `"reverted": true` (a mitigation step of it was
taken; `revert_after_brief`), when it is `bad` and the symptom opened after
its own or its root's page (`incident_after_page`), or when a person
confirmed it, `bad` or `fine`, after that page (`confirmed_after_page`): the
page may have shaped the confirmation either way, and training only on
fine ones would push the calibration toward fewer pages. A page here is a
delivered one (`paged_at`); with paging off a page is only logged
(`page_logged_at`) and nobody was interrupted. The read-back re-derives the
labels of an investigation's symptom, members and root whenever a new
investigation row arrives, so a revert reported (or undone) after the
outcome still counts. A delayed item weighs `1/q` and an item that could
have been delayed but was not `1/(1-q)`. An independent missed incident, or
an independent `fine` on a symptom that paged, enqueues the bounded refit
per pipeline; its replay gate replays the stored per-window root scores of
labelled symptoms over 28 days and needs at least 3 independent `bad`
symptoms in the replay (`:min_refit_bads`), so "no loss of recall" never
passes vacuously.

## Symptom log

Every revision is a full snapshot of at most 16 KB, appended with a global
`seq` and kept 30 days. A revision is written only on a material change
(state, tier, root or merge, a brief or outcome attached, impact changing 2× or
more); anything else coalesces to at most one revision per 15 minutes. A
symptom resolves after several quiet windows; the same `symptom_key` within 24
hours reopens the same symptom within its one- or five-minute pipeline. The
idempotency key is `symptom_id:revision`; a consumer applies a revision only
if it is newer and rejects an unknown major `schema_version`. The server
persists eligible MCP opening-event jobs in the same transaction as its
mirror and cursor, so a failed enqueue rolls back the page for retry.

```json
{
  "schema_version": "1.0",
  "seq": 1042,
  "symptom_id": "uuidv7",
  "symptom_key": "sha256 of environment, service, entity kind, entity key, phenomenon class of the root",
  "scope": {"kind": "tuist_ops"},
  "revision": 3,
  "state": "open | resolved | merged",
  "merged_into": null,
  "tier": "audit | board | page",
  "transition": "opened | escalated | deescalated | merged | resolved | reopened | annotated",
  "entity": {"environment": "production", "service": "tuist-server", "kind": "route", "key": "POST /api/..."},
  "phenomenon": "request_errors",
  "title": "masked, untrusted",
  "phenomena": [{"phenomenon": "request_errors", "nats": 2.4, "sources": ["trace.error_betabinomial"]}],
  "score": 6.1,
  "p_degraded": 0.42,
  "impact": {"unit": "failed_requests_per_min", "rate": 12.0},
  "budget_price": 3.5,
  "decision": {"tier": "board", "would_page": false, "delayed_until": null, "delay_probability": 0.2},
  "root": {"root_symptom_id": "uuidv7", "member_symptom_ids": [], "shared_cause": false},
  "suspected_change": {"kind": "deploy | config", "ref": "sha or change id", "at": "iso8601", "touched_entities": []},
  "evidence": {"series_refs": [{"query": "...", "from": 0, "to": 0, "baseline": [0, 0]}], "example_ids": [], "masked_excerpts": [], "attribute_contrast": "optional, shared-cause roots"},
  "board": {"date": "2026-11-16", "rank": 1, "nats": 7.2},
  "brief_ref": null,
  "outcome": null,
  "opened_at": "iso8601",
  "updated_at": "iso8601",
  "resolved_at": null
}
```

API, projected Kubernetes ServiceAccount tokens, tailnet-only, both directions pull:

- Evaluator: `GET /api/v1/symptoms/log?after=<seq>&limit=500` returns
  `{"revisions": [...], "next": <seq>}`; `GET /api/v1/symptoms/:id` returns the
  latest revision.
- Tuist server: `GET /api/internal/symptoms/state?after=<cursor>` returns
  acks, mutes (entity, phenomenon, expiry), investigations and confirmed
  outcomes, with a `next` cursor. Each investigation row also carries
  `reverted` (boolean): `true` once a person marked any mitigate-now step of
  any brief of the investigation's symptom `taken`, `helped` or
  `did_not_help`, and `false` again if all such steps are set back to
  `proposed`. It is per symptom, so every investigation row of that symptom
  carries the same value, and a change moves the row to a new `change_seq`.
  The evaluator normalizes timestamps to microsecond precision. It applies
  each page and cursor under the shared log lock, discarding stale in-flight
  responses if another reader has already advanced the cursor.

Implementation notes: `board` is `null` until a board push ranks the
symptom. `phenomenon` is the symptom's own phenomenon, fixed when it opens
(`phenomena` lists every phenomenon with evidence); a mute matches the
entity and this phenomenon, so it is the one to offer muting for. `entity.key` longer than 200 characters is trimmed to its first
200 plus `…sha256:<digest of the whole key>` only when the snapshot would
exceed 16 KB. `limit` is 1–500 (default 500); `next` is the last `seq`
returned, or `after` when nothing is newer. Revisions commit in `seq`
order under an advisory lock. `GET /api/v1/symptoms/board` returns
`{"symptoms": [...]}`, the open root symptoms at board tier with the highest
expected cost. The server presents a pod-bound token with audience
`tuist-symptoms-api`. The evaluator verifies it with Kubernetes TokenReview,
requiring that audience and the exact configured server namespace and ServiceAccount.
It rereads its own Kubernetes API token for each review and caches no decisions;
expired or revoked tokens fail closed. Missing trust configuration or an unavailable
API server returns 503; invalid credentials return 401. No shared API secret is used.
The evaluator reads `/api/internal/symptoms/state` from
`SYMPTOMS_STATE_URL` with the projected token at
`SYMPTOMS_STATE_TOKEN_PATH`. Pages go to an IRM webhook only with
`SYMPTOMS_PAGING_ENABLED=true` and `SYMPTOMS_IRM_WEBHOOK_URL`; otherwise
`decision.would_page` is the only trace.

## Investigations (in the Tuist server)

- The server records investigation requests on qualifying symptom revisions
  and board pushes. It generates no briefs, mitigation steps or commands.
  An agent should investigate the evidence and generate its own steps;
  agent dispatch and result ingestion are not wired yet. Recording a request
  does not mean an agent ran or completed an investigation.
- Existing briefs and step feedback remain stored and readable. The state
  read-back carries requests (`investigations[]`), with `brief_id` and
  `brief_revision` null until a brief exists. New requests have empty
  `steps_taken` and `reverted: false` when the symptom has no prior feedback.
  Historical mitigation feedback retains the existing `reverted` behavior;
  the evaluator uses that only for labels (README "Labels").

## Configuration

Every environment variable is read in `config/runtime.exs`; modules read
application config only. `infra/helm/symptoms/README.md` maps each to its
chart value or 1Password field.

| Variable | Use |
| --- | --- |
| `DATABASE_URL`, `PHX_HOST`, `PORT`, `POOL_SIZE`, `SKIP_MIGRATIONS` | Phoenix and Ecto (no sessions or signing key) |
| `SYMPTOMS_ENVIRONMENT` | Entity `environment` (default `production`) |
| `SYMPTOMS_SERVER_NAMESPACE`, `SYMPTOMS_SERVER_SERVICE_ACCOUNT` | Exact server ServiceAccount allowed to read the evaluator API |
| `KUBERNETES_SERVICE_HOST`, `KUBERNETES_SERVICE_PORT` | In-cluster API server for TokenReview, using the mounted ServiceAccount token and CA |
| `SYMPTOMS_METRICS_PORT` | Port of the separate `/metrics` listener; unset starts none |
| `SYMPTOMS_PAGING_ENABLED`, `SYMPTOMS_IRM_WEBHOOK_URL`, `SYMPTOMS_IRM_WEBHOOK_TOKEN`, `SYMPTOMS_LINK_BASE_URL` | Paging |
| `SYMPTOMS_STATE_URL`, `SYMPTOMS_STATE_TOKEN_PATH` | The Tuist server (state read-back) |
| `SYMPTOMS_PULSE_URL`, `SYMPTOMS_PULSE_USER`, `SYMPTOMS_PULSE_TOKEN` | Pulse reads (default user `symptoms`, read-only). The evaluator never writes to Pulse |
| `SYMPTOMS_PROMETHEUS_URL`, `SYMPTOMS_PROMETHEUS_USER`, `SYMPTOMS_PROMETHEUS_TOKEN` | Pulse's Prometheus-compatible API (`/v1/prometheus`, database `public`), using the same read-only identity for metrics and probes |

`KubernetesEvents` uses the in-cluster ServiceAccount. Sources are listed in
`config :symptoms, :sources` (none in test).

The managed deployment reads no telemetry from Grafana Cloud. IRM integration
is deferred: the chart supplies no webhook credentials and paging remains off.

## Backstops and watching the watcher

These stay outside the system until shadow precision covers them: server and
cache ingress SLO fast-burn pages, oldest available job age on
`process_xcresult`, registry and Kura region probes, and the evaluator's
heartbeat and coverage alert in Grafana Cloud. The evaluator exports coverage
(entities with evidence over entities expected, input freshness, disabled
streams) to Grafana Cloud, outside the cluster it watches.

`GET /metrics` exports, in Prometheus text, on its own listener
(`SYMPTOMS_METRICS_PORT`), not the API port: the Service and its tailnet device
expose only the API, and the NetworkPolicy admits only the observability
namespace (the scraper) to the metrics port. It has no auth:

| Metric | Meaning |
| --- | --- |
| `symptoms_up` | 1 when the database answered |
| `symptoms_entities_expected` | Non-retired entities seen in the last 24 hours |
| `symptoms_entities_with_evidence` | Of those, entities with evidence in the last 10 minutes |
| `symptoms_coverage_ratio` | The ratio of the two (1 when none are expected) |
| `symptoms_sources_configured` | Configured sources that are not disabled; with 0, or 0 entities expected, nothing is watched |
| `symptoms_entities_unknown` | Entities marked unknown |
| `symptoms_source_up{source}` | 0 when a configured source is disabled or its last collect failed |
| `symptoms_streams_disabled` | Number of sources with `symptoms_source_up` 0 |
| `symptoms_source_last_success_timestamp_seconds{source}` | Last successful collect |
| `symptoms_source_freshness_seconds{source}` | Age of the end of the last window a source collected |
| `symptoms_pipeline_last_success_timestamp_seconds{window_seconds}` | Last finished window |
| `symptoms_pipeline_lag_seconds{window_seconds}` | How far the end of the latest finished window is behind now |
| `symptoms_open_symptoms{tier}` | Open symptoms per tier |
