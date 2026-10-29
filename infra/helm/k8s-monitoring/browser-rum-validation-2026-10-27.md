# Browser RUM validation — October 27, 2026

## Result and deployment status

The production enrichment gateway is live. Grafana had no `Browser RUM` rules
at initial inspection. Nine corrected rules were subsequently installed at
11:16 UTC in `Browser RUM quality`, all paused. Readback confirmed every query
matches the repository artifact and the group evaluates every minute. The legacy
pooled rules remain active and unchanged. The application changes have not been
deployed.

The original artifacts were not ready to enable: liveness returned an extra zero
series while healthy, and the six-hour floors left most docs/marketing windows
unevaluated. Keep performance and deduplication-coverage rules paused until the
new gateway is deployed and a full 24 hours of classified observations has been
validated. Keep legacy alerting through that gate.

## Alert reproduction

The October 27 07:45 UTC evaluation covered 01:45–07:45 UTC: 248 LCP reports,
138 reported sessions, p75 1.74325s and p90 4.0132s. It recovered at 07:46 UTC.
All reports were retrieved in three non-truncated batches; linear interpolation
independently reproduced the percentile.

One 7.524s report for an obsolete Spanish docs example appeared twice with the
same session, navigation ID, Faro measurement ID, timestamp and values but
different collector Ray IDs (HKG and SOF). Deduplicating it gives 247 reports and
p90 3.9616s. This is delivery evidence, not a reason to discard the slow report.

Two Linux/Chrome cohorts contributed 20 reports (19 sessions), including 14 of the
25 LCPs above four seconds: Chrome 148 at 1200×3000 and Chrome 149 at 1350×1286.
Removing them diagnostically gives p90 2.5056s. Several reports were 404 pages.
Their automation status remains unknown; no fingerprint exclusion is introduced.
Three slow reports had navigation ID `unknown`, accepted by the old quality check.

## Seven-day backtest

Source: `grafanacloud-logs`, `{service_name="tuist-web"}`, parsed measurement kind,
web-vitals type, prod environment and schema 1. Window: October 20 08:00 through
October 27 08:00 UTC, hourly steps (169 points), using the old eligible population.
The [JSON summary](browser-rum-validation-2026-10-27.json) preserves the counts.

| Surface | Six-hour samples, min–max | Checks with data | Checks meeting >100 reports and >=50 sessions | p75 >2.5s with both floors |
| --- | ---: | ---: | ---: | ---: |
| Marketing | 11–175 | 169 | 25 | 0 |
| Docs | 3–202 | 169 | 12 | 0 |
| Auth | 5–190 | 168 | 43 | 0 |
| Authenticated dashboard | 8–314 | 169 | 71 | 1 |
| Anonymous dashboard | 1–31 | 163 | 0 | 0 |
| Challenge | 1–27 | 165 | 0 | 0 |
| API docs | 1–2 | 71 | 0 | 0 |

These are sampled conditions, **not** a replay of the 30-minute pending period.
Absent/below-floor windows are unevaluated, not healthy.

Separate 24-hour marketing/docs rules improve coverage without lowering floors:

| Surface | 24-hour samples, min–max | Checks meeting both floors | p75 range | p75 >2.5s with both floors |
| --- | ---: | ---: | ---: | ---: |
| Marketing | 91–420 | 162/169 | 1.0625–1.908s | 0 |
| Docs | 53–438 | 131/169 | 0.944–4.727s | 2 |

Retain six hours for auth/authenticated dashboards. Low-volume surfaces stay
visible in raw/quality breakdowns without pretending they meet performance floors.
The docs conditions occurred at October 26 05:00 and 07:00 UTC; the intervening
sampled point did not meet the full condition.

Gateway schema and trusted collector Ray-ID coverage were 100% at every sampled
six-hour evaluation. Known surfaces had zero ineligible fraction under the old
check. Unknown surfaces contributed 1–5 reports where present. Enriched liveness
had 7–368 reports per two hours.

The original `sum by (app_environment)(...) or vector(0)` liveness query produced
both a healthy labeled series and an unlabeled zero. The fixed
`sum(...) or vector(0)` returns one series: at October 27 08:00 it returned 105;
the same query selecting a nonexistent environment returned only zero. Static
rule labels still supply `app_environment=prod`.

Long distinct-session range queries exceeded Loki's 500-series limit because
the union spans many sessions. All hourly points were recovered through bounded
daily/six-hour queries and instants. Keeping only grouping labels before counting
reduces cardinality but does not remove the need to bound long backtests. The
marketing/docs rules are separate so their 24-hour populations do not accumulate.

Historical volume is an upper bound on future eligibility: the new rules exclude
replays and placeholder navigation IDs. It does not validate the undeployed
classifier; repeat the baseline after rollout.

## Download request investigation

The affected production navigation had 13.856s LCP, 12.314s TTFB and 12.292s
request time; the LCP image transfer was 1.070s. The navigation began around
02:27:44 UTC, while the report was buffered until 02:31:05 UTC. Search navigation
time, not only collector arrival time.

The exact document request was absent from retained production traces and sampled
ingress logs. Two nearby static assets completed in 3ms; their entries carry
adaptive-sampling metadata. A different production `/download` at 02:29:30 UTC
ended in HTTP 499 after 9.953s, including 9.953s upstream time (request ID
`55d65842b79d55d7f20477365f204312`). This supports a slow request path but is not
an exact join to the browser observation.

A separate **canary** trace lasted 10.846s at 02:06:49 UTC:
`5e43ee0e101c583c9790fd4d63d02fa7`, application `sha-28e45f052583`. It has only
the root `GET /download` span. It is corroborating evidence, not a production
trace or proof of a particular slow dependency.

The controller synchronously looks up GitHub app releases and the App Store
version through one-hour caches. GitHub follows pagination and permits three
exponential-backoff retries (1s, 2s, 4s). Cachex runs misses in another process,
so an outer request span alone cannot establish parent context for those calls.

`Marketing.ReleaseMetadata` now adds `marketing.release_metadata.github`,
`marketing.release_metadata.github_page`, and
`marketing.release_metadata.app_store` spans around lookups, and corresponding
`.fetch` spans in cache misses. It attaches/restores OTel context in workers and
logs lookups taking >=1s using only provider/duration. Coalesced waiters have
lookup spans; the first miss owns the fetch span. No upstream URLs, credentials
or response contents are added.

The original dependency delay cannot be attributed retrospectively. This closes
the instrumentation gap for the next deployed observation; no speculative timeout
or cache-policy change is included.

## Validation and rollout gates

- Focused ExUnit tests cover actual gateway behavior, identity classification,
  independent PostgreSQL connections, overlapping batches, retryable failures,
  stale-owner recovery, retention/pruning, worker context restoration and existing
  GitHub release parsing/pagination: **29 passed**. Migration rollback/reapply,
  Elixir formatting (with Styler) and `git diff --check` passed. A standalone harness uses existing compiled
  dependencies, recompiles changed modules and an isolated local database. This
  is not a full server build or full test-suite run.
- All **19 distinct final Loki queries** executed without errors against the
  fixed October 27 08:00 evaluation. Unique-only queries correctly returned no
  data before deployment; deduplication coverage returned 100% unclassified.
  These results validate syntax/transition behavior, not future performance.
- Migrate the new table before the application. Old gateways ignore it during
  rollout. No raw report or identifier is persisted in the receipts.
- Verify cross-replica retries and unique/duplicate/untracked context after
  deployment. Check gateway 503s and database load. Keep raw distributions beside
  unique distributions and repeat the full 24-hour volume/quality baseline.
- Current Grafana routing sends these warning labels to `Slack #notifications 2`;
  no paging route matches. The installed group has one-minute evaluations.
  All nine rules were read back as paused with matching expressions.
- Enable quality/liveness first and performance after coverage is established.
  Deduplication coverage is expected to breach on old data. Retire pooled rules
  only after replacement is verified. If retaining legacy percentiles, add
  `context_rum_deduplication!="duplicate"` to value/count/session populations after
  validating the transition.
- Pause unique-only rules before application rollback. Drop the receipt table
  only after all gateway replicas have rolled back, retaining raw legacy alerts.
