# Tuist query compatibility checkpoint

Pulse remains a headless storage/querying/alerting backend. This increment closes concrete query gaps; it does not enable Grafana rules or authorize a cutover.

## Implemented

- PromQL `absent`, `absent_over_time`, `floor`, `sgn`, `timestamp`, `stddev_over_time`, `stdvar_over_time`, and `predict_linear`.
- Explicit-resolution subqueries over vector expressions, including Tuist's `sum_over_time((max-max)[6h:5m])` and `predict_linear((max or fallback)[3d:30m], 3*86400)`. Grids align to the epoch independently of outer steps; nested and positive-offset cases are bounded.
- Independent subquery intermediate-sample accounting (`max_materialized_samples`, default 100,000, `query_intermediate_limit`). HTTP/MCP classify exhaustion and alert evaluation skips it rather than treating it as a fire.
- Original sample timestamps for bare selectors, evaluation timestamps for derived expressions; exact millisecond-aligned conversion prevents large-epoch double rounding.
- Equal-label range-series coalescing for disjoint lifetimes; same-step collisions still error.
- Bounded native trace string regex predicates via `attributes_regex` / `resource_regex`: eight combined patterns, 1,024 bytes each, 256-byte keys, anchored dot-all RE2 subset. Missing/non-string fields never match. Patterns and bounded DFA caches remain query-local and are reused across segment reads, before BEAM expansion. Exact-ID assembly's fixed filters and coverage are unchanged.
- Discovery schemas expose and enforce dictionary value/key/count constraints, including schema-valued additional properties.
- Subsequent `search_traces` work adds bounded original-string resource/span AND equality/regex selectors, optional `most_recent=true` syntax, and native grouping across all source-start-window spans before trace limits. It is explicitly window-local, not verified Tempo trace-wide/root/client behavior. Typed-unknown legacy rows fail the whole search; all window trace IDs count toward 65,536 groups. See `tempo-replacement.md` for the latest validation and remaining acceptance gates.

## Independent evidence

`scripts/promql_conformance.exs` uses the already installed Prometheus **promtool 3.5.0**, checks its version, and runs entirely offline with a privately owned Memory runtime. No production sources, tokens, deployments or new dependencies are involved.

- **780 expression/time cases** passed the independent oracle, using fuzzy floating-point ULP comparison and separate NaN masks. Top-k cases avoid unspecified tied-ranking choices.
- **Four exact large-epoch timestamp cases** passed without fuzzy comparison.
- Hash-linked `test/fixtures/promql/verified-results.json` is written only after both independent checks pass. Default tests verify it through Memory and native Parquet storage.
- All **104 distinct Prometheus source expressions** in the complete 115-rule inventory parse and execute on empty input. This is grammar/dispatch coverage, not numerical validation of every production expression.
- The paused rule with `$__rate_interval` uses `5m` in the syntax test only. It still requires an explicit producer/scrape/window decision before migration.
- Public OTLP -> S3 -> MCP tests exercise native regex filtering. Additional parity cases cover escapes, newlines, Unicode, missing fields and typed non-string values.

## Adversarial review

Claude performed read-only reviews and follow-ups, without edits, builds, tests or probes. Fixed ordered absent inference, timestamp precision and disjoint-label lifetime handling; separated subquery intermediate accounting; cached native regex programs and DFA state; enforced the newly advertised schema vocabulary.

A review counterexample for mixed absent matchers was initially wrong when tested against promtool: TSDB mutates matcher order during selection. The implementation reproduces the observed intersecting-before-subtracting order. That is backend-dependent, not universal PromQL identity parity. The four actual Tuist absence expressions use singleton exact matchers or aggregation, so that caveat does not affect their label inference. It is documented for other users. No live Grafana Cloud comparison was performed.

Local review artifacts: `/tmp/pulse-replacement-next/promql-claude-{review,followup,finalcheck}.md` and `trace-regex-review.md`.

## Validation checkpoint

- `mix precommit --max-cases 4`: **864 passed, 1 skipped, 33 excluded**.
- Codec Rust: **59 passed**; strict Clippy and formatting clean.
- Strict Credo: **237 files, no issues**; warnings-as-errors compile, formatter and diff checks passed.
- Final small source review found only a Unicode schema-length nit; it is fixed with an allocation-free code-point walk and combining/ZWJ/invalid-UTF tests.
- A synthetic metadata-fanout fixture initially sat too close to the scaled byte limit as tenant-key lengths varied. It now has robust success headroom while still exceeding the explicit 8 MiB limit. No production limit was raised.
- Local command/review artifacts live in `/tmp/pulse-replacement-next/`. Excluded external/provider integrations were not run.

## Still required for replacement

- Actual telemetry residency and recording-rule producer closure; the independent corpus is synthetic.
- Grafana condition-graph execution, recording translation/group ordering, templates, lifecycle policies and durable routed webhook delivery to Atlas. Native recording publication is now implemented in the subsequent [recording checkpoint](tuist-recording-publication.md); imported Grafana definitions remain disabled.
- Full/verified Tempo TraceQL and trace-wide ordering/root/search semantics beyond the native window-local selector foundation, complete trace/label postings, oversized-trace completeness/pagination, discovery and required client envelopes.
- Node-wide ingest admission, workload-shaped capacity/availability, authorized shadow comparisons, object-store/process/node faults, recovery and rollback rehearsal.

See `grafana-replacement.md`, `tempo-replacement.md`, and `tuist-adversarial-review.md`. Changes remain uncommitted and existing production observability remains authoritative.
