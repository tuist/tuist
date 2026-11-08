# Landing review checkpoint

## Scope and authority

This pass pauses feature breadth and reviews the existing **uncommitted full
worktree**, including untracked sources/fixtures and intentional deletions. The
initial snapshot at base `ada01bf` covered 624 changed/untracked paths, 621 existing
files. The first pass's final capture contains **641 paths: 638 existing files and three
intentional deletions**. The follow-up below supersedes its source validation;
that archive remains historical evidence. A tracked diff alone is not its scope. Original patch/archive/manifests,
failed runs and complete reviewer reports remain in
`/tmp/pulse-adversarial-final/`; a final snapshot belongs under `landing-final/`
there. This page is the portable finding disposition, not a claim that every
changed file received an independent review.

No commit, merge, deployment, provider/production exercise or cutover occurred.
No private application workspace was modified or built. Existing stashes,
reconciliation archives, merge history and intended storage-module deletions
must be preserved. S3/CAS remains the only shared durable authority.

## Review method and limits

Six initial Claude slices covered ingestion, storage, queries, alerting, native
metrics and native traces. Two large fix reviews completed (storage/queries);
the ingestion/alert fix attempts returned `is_error: true` / `Request timed out`
and **are not review closure**. Smaller source-only ingest/alert/regex reviews
then completed. Targeted final ingestion/regex re-reviews inspect subsequent
fixes. Every reviewer was restricted to Read/Glob/Grep, with no execution,
edits, Git, network, private workspaces or subagents. Reports state actual reads
and blind spots. Some sources changed during review, so an earlier favorable
report does not certify the final tree. The last targeted report confirmed
copy-before-reservation and literal-caret handling, then identified a closing-brace
false rejection and a remaining word-complement/range-joining case. Those were
corrected and pinned in Rust/actual-Go replay after that report; no independent
report certifies every final line.

The implementation author owns tests and measurements. Local tests, public
producer fixtures and source review are not deployed-client, independent-node,
provider, restoration, native-cancellation or capacity acceptance.

## Concrete corrections

| Finding IDs | Disposition |
| --- | --- |
| ING-01/02 | gRPC native API 2 acquires owned admission before buffering/decompression. Permits follow outstanding BEAM replies after client timeout/cancellation. Monitored heap death returns permanent 8 without RetryInfo; other exits return 14. A watchdog requests task termination one second after the RPC timeout, retaining admission until monitored exit (not a native preemption deadline). Already-running native/provider work is not preempted. |
| Quick ingest arena concern | Append buffering detaches normalized slices before enqueue and before reserving credit, so a heap/watchdog kill during copying cannot strand a reservation; Memory detaches before ETS. Tuple/struct-aware conditional detachment replaces full serialization in log top-k and also detaches sort keys. Standalone binaries are reused. |
| ING-03/04/05 | Reference fallback checks duplicate exponential fields; logs accept protobuf response negotiation outside the JSON-only pipeline; gzip scans overlapping trailer candidates incrementally and caps concatenated members at 64, including empty members. |
| Storage F1, SR-1 | Reader cache writes compare their starting ETag; owner writes remain unconditional. Tests delay actual HTTP 200/304 reads across a real acknowledged owner append, not merely test the ETS primitive. |
| Storage F2, SR-3 | Combined buffered floor failures return retryable `retention_floor_advanced`; never split a possibly published upload. Tests prove no visible subset, fresh retry success and permanent single-request expiry. |
| Storage F4/F6 | Flat log retirement cleanup runs through retention independently of compaction. Lost legacy CAS responses succeed only when a fresh ETag-bearing root proves every pending key visible; LIST bootstrap is not an acknowledgement. |
| Storage F5 | Upgrade docs explicitly cover changed plain keyed metric/log bytes from nullable metadata columns, not only rich writes. Drain legacy retries; never evade exact-byte conflicts by overwrite, deletion, new keys or unkeyed/subset resend. |
| Metadata eviction | Exact envelope/comma accounting, one singleton serialization per metric on overflow, bounded 8 MiB reads and boundary regressions replace quadratic whole-map eviction. Oversized historical objects remain fail-closed; no automatic repair/deletion tool was added. |
| TAIL-1/2, STO-01 | Native batch regex matching and producer-side atomic credits replace divergent PCRE matching and dequeue-only backpressure. Disposable-registry failure cannot invalidate an already durable append. |
| Tail identity collision | Exact detached timestamp/labels/line keys replace 32-bit hashes; collision and retained-arena regressions cover the reproduced collision. Limits: 120 seconds, 200,000 identities, 16 MiB payload, not total process memory. |
| TAIL-3 / large idle batch | More than 64 unseen original segments closes tails explicitly instead of advancing a partial cursor. One idle-queue batch up to 32 MiB accommodates an admitted ingest batch's term overhead; ordinary queued credit remains 64 batches/16 MiB. Larger aggregate polls still close 1013 by policy, not chunk/demand-driven delivery. |
| REGEX-01 / quick regex P2s | Shared native policy and independent PCRE reference preserve codepoint dots, ASCII Perl classes/boundaries, Go whitespace, strict ends and insensitive Unicode folds. Malformed POSIX prefixes reject; escaped angle brackets remain literals; leading literal closing brackets normalize. All pipeline positions reject unsupported syntax instead of changing dialect after a parser. Ordinary replay includes 221 actual Go 1.25.10 answers (all prior controls unchanged), with no Go runtime requirement. |
| PROM-1 | Native histogram Sum StaleNaN survives wire and repeated Parquet storage; evaluator treats it as staleness before windowing. |
| LOKI-1 | Detected fields retain only observation inputs and parse only the final global top-k sample inside the admitted query task. Unused original OTLP/body data is not retained for sampling. |
| Native metrics F-1/F-2 | Footer negative proofs share required/optional schema checks with decoding; stored exemplar labels validate before map construction instead of panicking. Full metric/footer input uses Erlang-owned shared bytes rather than copying entire blobs/tails. |
| TM-1/TM-2/TM-3, TS-1 | Attribute/selector queries reject unknown legacy originals instead of fabricating missing groups or dropping numeric values. Trace output uses Counter then direct binary sink, no final full-response Vec copy; numeric formatting is stack-based. Window bounds reject negative/overflowing values. Tempo replay reuses validated row fields. |
| ALR-01/03 | Recording operations require the separate `alert:record` classification, including edits to old queued/series state. Worker-owned optional bounded revision/tick memo avoids deterministic budget rescans, never advances durable health/completion and never caches transient failures. |
| MCP-1/MCP-01, DOC-01/02/03 | `query_traces` rejects unknown keys; detailed metrics include trace/discovery names and bounded `alert_tool`; resource/subscription, closed-schema and self-monitoring docs reflect implementation. |

## Explicitly open or operationally constrained

- **ALR-02 (P2):** future-skewed mutation clocks can delay or wedge recording
  evaluation behind its fence. Synchronized clocks remain an explicit
  precondition. Backdating retirement to `completed+1` was not adopted: it
  changes effective deletion semantics. A bounded-skew/fence-recovery product
  policy remains open; there is no claim of arbitrary-clock correctness.
- **Storage F3 / live-tail completeness (P2):** event-time compaction settle is
  not a publication receipt. Late publication, failed polls or retirement
  between snapshots can hide originals. Live tail is now documented as
  best-effort, not a complete changefeed. The lag guard does not repair this.
- **Native TS-2/TS-3 (P3):** ordinary search's base per-trace Summary containers
  are not included in its 16 MiB charged-retention counter; hard source/group
  bounds still limit population, but that counter is not total native memory.
  Root classification retains exact per-span IDs and can exhaust the budget
  well before hard row/group ceilings. Do not replace exact IDs with lossy
  hashes. Exact numeric span-ID keys and budget-policy/capacity work are
  separate follow-ups.
- **SR-2/4/6/7 (P3):** conditional cache refresh still copies manifest containers;
  retirement tests do not establish all scheduled-worker wiring; historical
  exemplar compatibility and additional malformed footer permutations need
  broader evidence. The new boundary tests are not exhaustive corruption
  scrubbing.
- **ALR-04..07 / TST-01 (P3):** per-owned-rule drain reads, backlog metrics,
  wrong-query-type validation, permanent recording FIFO-conflict recovery and
  harness/tool/port robustness remain follow-ups. Full queues can block edits.
  Never delete authority or bypass 409 to unstick a queue. The memo is
  disposable and may become less effective after its finite entry ceiling.
- **Other P3s:** ING-06..09, storage F7..09, LOKI-2..5, TAIL-4/5 and TMET-1
  remain explicitly outside this correction pass: permissive root inputs,
  path/body-error controls, request-local temporality aliases, coalesced bucket
  failures, implicit custom compaction configuration/boot fencing, parameter
  validation, tie ordering, default detected labels, follower lifecycle,
  unfiltered dropped-entry reports and per-attempt retry budgets. ING-07's
  claimed URI exception was not reproduced with the pinned URI decoder;
  malformed percent text stayed unchanged. Do not present it as a proven fix.
- Native work can outlive task death; transport buffers, referenced arenas,
  currently processing batches, output frames and deployment-wide provider
  pressure are outside local queued-byte credit. HTTP/2 connection admission
  needs a proxy. Background tail polling has source/window caps, not complete
  cumulative process/native-memory admission; queued-byte credits do not bound
  work materialized before delivery. The pre-existing tiny append reserve/send
  kill race can still strand disposable coalescing credit until owner cleanup;
  moving the expensive copy before reservation removes its amplification, not
  that race itself. No total memory, process-tree cleanup, native cancellation,
  node-wide admission or representative-capacity claim is made.

## Performance evidence

The exact-tail cache benchmark is deliberately a tradeoff, not a blanket win.
Local medians in microseconds, old 32-bit identity to exact detached identity:
1,000 × 128 B `667 → 1025`; 10,000 × 128 B `14581 → 14196`;
1,000 × 8 KiB `5646 → 9797`; 10,000 × 8 KiB `63336 → 145556`.
The last exact cache retained 2,039 identities under its payload cap. A stale
benchmark label said `encoded_identity_bytes`; it measured payload bytes.

Other improvements are specific source/lifetime reductions, not measured
throughput or RSS acceptance: one fanout size calculation, compiled batch
regex resources, conditional retained-slice copies, shared metric/footer input,
once-parsed replay rows, precomputed trace lookup requirements, entry-based
series insertion, released accumulators and direct native response output.
Sub-binary sort-key/value duplication and control-plane container copying still
have room for separately measured improvements.

## Validation checkpoint

First-pass semantic-source validation (`precommit11`, `credo11`, `native11`):

- `ERL_FLAGS='+S 4:4' mix precommit --max-cases 4`: **1,511 passed, 1 skipped,
  37 excluded**, 85.2 seconds. This includes strict compilation, unused-dependency
  checking and formatter verification. Optional SDK/Collector profiles remain
  excluded. A preceding full run also passed all 1,511 tests.
- `mix credo --strict`: no issues across 412 files.
- Codec `cargo test --locked --offline`: **127 passed**; locked/offline
  `cargo clippy --all-targets -- -D warnings` and Rust formatting passed.
- Object-store locked/offline unit tests: **5 passed**. gRPC Cargo has **0 unit
  tests**, not native runtime coverage; its actual transport/watchdog regressions
  run in ExUnit. Both crates' strict all-target Clippy and formatting passed.
- **221 actual Go regex answers** replay against independent PCRE/native byte
  matchers in ordinary tests. The original 80 and intermediate 154 answers remain
  unchanged. The formatted optional Go producer reproduced the checked-in JSON
  byte-for-byte; ordinary replay requires no Go or network.
- Local path links checked across 28 documentation/checkpoint files (not external
  URLs or all anchors); `git diff --check` passed. Final manifest/archive capture
  follows documentation-only checkpoint updates.

Preserve earlier failures (`focused2/3/6/8`, `precommit7/9`) rather than refreshing
fixtures to conceal them. In particular the last pipeline test change explicitly
removes an old PCRE-only lookahead exception after `json`; unsupported syntax
now rejects in every pipeline position.

Operational/deployed acceptance, generic protocol breadth and external posting
index/capacity work stay in their existing plans. This review does not authorize
landing or cutover on its own.

## Follow-up: independent Claude/Pi dialogue

The second landing pass preserved a fresh full-worktree baseline under
`/tmp/pulse-landing-dialogue-2/before/`, then ran four overlapping source-only
reviews: Claude storage/authority and bytes/native boundaries, plus separate Pi
authority and bytes processes. Their only tools were source read/search/list;
no execution, edits, Git, network, private application reads or subagents were
authorized. These CLI restrictions are not OS sandboxing. The implementation
author, not the reviewers, ran every reproduction and test.

Reviewers challenged one another's publication-order, native lifetime and
regex hypotheses. Claude's first dialogue could not access the public `/tmp`
reports because of its worktree restriction; that attempt is not successful
artifact exchange. A corrected prompt embedded Pi's reply inline for a genuine
Claude counter-review. That reply used nine calls against an eight-call budget,
an explicitly retained overrun. Later focused source checks cover specific fixes,
not the whole tree. Claude's last bytes check did not read gRPC test bodies or
all retention boundaries; Pi's receipt review did not exhaust authorization
combinations. Some later changes, including repeated-ETag fencing, follow those
reports and are author-tested rather than independently certified.

### Correctness changes

- **gRPC admission/body deadline:** loopback probes demonstrated that an
  incomplete unary body could hold admission beyond the configured timeout.
  One end-to-end deadline now covers waiting, body completion and storage;
  incomplete calls release pre-handoff admission. BEAM retains reply-owned
  admission for already handed-off work, even after timeout/disconnection.
  The redundant inner timer was removed. A review suggested separate body and
  processing budgets; the chosen policy deliberately keeps one total deadline,
  documented as reducing remaining response time after waiting/body reception.
  It does not cancel native/provider work or promise each late admission a fresh
  storage budget. Retried unkeyed calls can duplicate an uncertain success.
- **Forwarded metadata:** invalid text values for authorization, tenant or
  idempotency reject instead of disappearing into default/unkeyed interpretation.
  Unknown binary metadata remains uninterpreted. Tests exercise actual h2c.
- **Manifest cache ordering:** reads install only against their captured
  generation. Publications require their pre-CAS generation and predecessor
  ETag; incomparable state invalidates. Disposable tombstones prevent delayed
  cold reads/publications from resurrecting older authority, and warm tokens
  also fence repeated-ETag/ABA observations. A first publication may populate
  only its original empty generation, preserving the ordinary warm-cache path.
  A final Pi challenge found that rejected-only flushes performed no CAS/read
  but could reinstall stale private state; skipped results now bypass cache
  publication. Owned tests cover that case and subsequent fresh load.
- **Authority corruption:** a successfully fetched unsupported/malformed root
  now invalidates and fails, rather than hiding behind warm legacy state.
  Only the documented legacy transport-failure fallback remains.
- **Managed ambiguous publication:** bounded visibility proof now runs on
  conflict responses too, before retrying. Real local HTTP tests commit a root,
  advance another nonce, then return 412 for the committed append. Both retained
  and newly expired cases recover without another manifest PUT. Fresh floors
  still govern genuinely unpublished retry candidates; initial admission is
  never frozen. Cleanup that has erased all proof can still leave ambiguity.
- **Production regex and captures:** a concrete supported expression returned
  PCRE `:match_limit` while the native engine matched. Boolean PCRE APIs silently
  converted this to false, reversing negative predicates too. Remaining pipeline
  and Memory predicates/captures now use the shared native engine; Memory
  compiles once per query. Captures borrow input via subbinaries and detach at
  retained-result boundaries, avoiding capture payload copies. Independent
  reference/actual-Go controls remain separate. A fully printed follow-up probe
  also confirmed Rust acceptance of nested counted repeats that Go rejects;
  the shared validator now rejects them, with Rust/Elixir regressions. Go's
  literal `{,3}` is still an explicitly narrower unsupported case, not claimed
  parity. Dirty-NIF per-entry matching is not a batching or throughput claim.
- **Alert operation replay:** the caller request is verified against the
  committed revision's original notification bindings before current target
  resolution. Exact retries survive target changes/removal and receipt-eviction
  ancestry recovery; changed caller requests reject. New mutations still bind
  current targets. Existing receipt digest bytes and authorization order remain
  unchanged; no history migration was introduced.

### Clarity and validation

Architecture now distinguishes today's per-instance CAS writers, local buffers
and native query paths from planned ingest forwarding, UDP gossip, DataFusion
and NVMe/sidecar caches. It no longer claims one normal writer or a fresh GET on
every ordinary query. Stale live-tail completeness claims in the replacement
plan/moduledoc were corrected to the best-effort contract. Operator pages cover
the deadline, text-metadata rejection, corrupt authority and retry behavior.

The prior 1,511-test baseline passed before these edits. Intermediate failures
remain preserved: a timed-out compile's broken pipe, an incorrect encoder return
shape in a new test, the first cold-cache test mismatch, and a full run with two
local stub connection errors. A subsequent intermediate full run passed 1,526
tests, but does not certify the later generation/ABA change.

Final-source validation (`/tmp/pulse-landing-dialogue-2/final-validation-2/`):

- `ERL_FLAGS='+S 4:4' mix precommit --max-cases 4`: **1,527 passed, 1 skipped,
  37 excluded**, 72.3 seconds; strict compile, unused-dependency and formatter
  checks included. Optional external SDK/Collector profiles stayed excluded.
- `mix credo --strict`: no issues across 412 files.
- Locked/offline Cargo tests: codec **127 passed**, object-store **5 passed**,
  gRPC **0 unit tests** (transport evidence is the owned ExUnit h2c tests).
  Strict all-target Clippy and Rust formatting passed for all three crates.
- Existing **221 actual-Go regex controls** still replay in ordinary tests.
  Additional local Go 1.25.10 syntax probes and fully printed before/after native
  results retain the four nested-repeat rejection controls and literal `{,3}`
  limitation, rather than claiming the abbreviated earlier probe proved them.
- Local-path documentation/checkpoint links and `git diff --check` passed.
  Full tracked/untracked/deleted capture and hash re-verification live under
  `/tmp/pulse-landing-dialogue-2/landing-final/`; prior snapshots/logs remain
  preserved. These are source/runtime correctness checks, not throughput/RSS,
  independent-node/provider or deployed-client acceptance.

No commit, merge, deployment, production/provider operation or private application
change/build occurred. Recording clock skew, best-effort tail completeness,
legacy old-writer fencing, total/native memory accounting, provider/capacity
acceptance and the first pass's other scoped limitations remain open. These fixes
are not full Grafana replacement or landing authorization.

## Third adversarial pass: shared wrong answers and classified history

This follow-up supersedes the preceding section's validation for current sources.
The review unit remains the full dirty tracked/untracked/deleted worktree, not
only a PR's tracked patch. Evidence is preserved under
`/tmp/pulse-landing-dialogue-3/`, including the before snapshot, original reports,
peer exchanges, failed regressions and intermediate validation runs. No commit,
merge, deployment, production/provider exercise or private-application change or
build was authorized or performed.

### Review and counter-review

Four independent source-only processes challenged overlapping query/authority
boundaries: Claude query and authority, and separate Pi query and alerting
processes. Initial reports are `claude-{query,authority}.md` and
`pi-{query,alerts}.md`. `dialogue.sh` exchanged findings inline, so both models
could challenge actual peer arguments without relying on inaccessible scratch
files. Subsequent `fix-review.sh` and `final-challenge.sh` examined the fixes and
regressions, producing `*-fix.md` and `*-final.md`.

Claude had Read/Glob/Grep only, restricted/safe mode, empty strict MCP config and
no session persistence. Pi had read/grep/find/ls only and disabled extensions,
MCP, skills, templates, themes and session persistence. These are tool policies,
not OS sandboxing or runtime verification. The author alone performed probes,
public-source retrieval, edits and tests. Initial Claude reports disclosed
**20/18** and **21/18** tool calls; their budgets were exceeded, not enforced
sandbox limits. Both initial Pi reports reported 18/18; both first dialogues
8/8; fix reviews 10/10; final challenges 6/6. Original outputs and CLI scripts
remain available; these scoped reports are not whole-tree certification.

Coverage was deliberately bounded. Claude authority omitted native footer-plan
bodies, some provider/retention internals and most test bodies. Initial query
reviews did not independently exercise public Loki. The final query challenge
read window validation and native fallback, but only native/test excerpts; the
author checked its remaining stream-key/promotion gaps. The final auth challenge
read complete repository/evaluator/recording/principal source and the recording
tests, but not full transports, subscriptions or storage. No reviewer executed
or independently certified the reported test results. The late confirmed
missing-root cache fix and test-model correction below are author-tested
follow-ups, not independently reviewed final lines.

### Confirmed fixes and regression oracles

- **Parser collisions:** all five existing parsers (`json`, `logfmt`, `regexp`,
  `pattern`, `unpack`) now use immutable original-name provenance, rather than
  overwriting an original name and merging distinct metric streams. Resource
  and promoted service/level names receive exactly one `_extracted` suffix;
  structured attributes without those names remain overridable. Repeated
  parsing updates extracted keys; drop/rename do not erase provenance. A
  pre-existing suffixed key can be replaced, matching the pinned single-suffix
  policy rather than inventing unused names. Elixir shares its base map; native
  scans cache stream-key sets alongside existing labels and reuse noncolliding
  owned parser strings. Explicit expected labels/counts and negative predicates
  test every parser through Memory and Parquet-backed paths. Native logfmt/regexp
  tests assert an actual successful scan, not only equality with a shared
  pipeline reference. Present empty and absent promoted fields are separately
  pinned on both paths; the native `present` helper is selection-only, not a
  filter on entry-label construction.
- **First/last windows:** valid endpoints no longer hide an invalid middle
  unwrap sample. Every sample in each evaluated window validates before endpoint
  selection, without creating a production values list. Tied timestamps and
  vector/matrix forms are covered, as are valid endpoint controls and invalid
  fetched samples between sparse windows. Those gap samples remain irrelevant.
  A late randomized parity failure exposed the historical materializing model's
  same endpoint-only bug. That test model now independently materializes every
  selected value before choosing an endpoint; deterministic literal error and
  gap expectations pin both models. Agreement alone is not the oracle. The
  reported failure seed **541590** replays successfully after the correction.
- **Quantities:** filters, unwrap and literals use checked signed-int64 decimal
  scaling and component sums, not float multiplication or unbounded fraction
  integers. Zero, compound/fractional durations, petabyte units, unitless bytes,
  signs, overflow and junk have explicit tests. Duration unwrap still returns
  seconds and bytes unwrap floating samples of the integral-byte contract.
  Runtime duration units deliberately differ from query-literal `w`/`y` units;
  pinned Loki v3.5.0 source uses Go `time.ParseDuration` for runtime filters,
  which rejects weeks/years. Pulse retains its day and signed-byte extensions,
  not full humanize compatibility. All **1,047** existing independent public-Go
  formatter controls reverse successfully; separate bounded rational controls
  test fractional scaling. An actual Go 1.25.10 probe proves the explicit
  long-fraction divergence: exact `0.3333333333333333333h` truncates one nanosecond
  below Go's float-based parser. Overflowing log/metric literals produce HTTP400
  on both query routes. This is a documented exact-decimal policy, not a claim
  of exhaustive Go numerical parity.
- **Recording authorization:** new expiry events carry `alert:record`, and
  effective read classification protects already committed empty-class expiry
  events without rewriting immutable history or removing additional restrictions.
  Full state/resources also protect retained queue/series/last/error/fence data
  after kind conversion and queue drain. A fix review found a further count leak
  through successful threshold evaluation; an author regression observed
  `recording_pending: 2`. Evaluation remains authorized for the new threshold,
  but its explicit response allowlist omits that protected count without retained
  recording-state authority. Privileged responses retain the count.
- **Real historical fixtures:** the first attempted legacy fixture mistakenly
  inspected head-tail references as event bodies; it did not test old history.
  Pi caught that, plus a Resources assertion incorrectly passing an actor instead
  of a connection. Corrected tests commit real immutable legacy event bodies via
  the acknowledgement seam, verify raw stored classes `[]` and `[alert:preview]`,
  then require expiry visibility **3/2/0** for fully privileged / record-without-
  preview / no-record readers after conversion. Actual new-writer expiry still
  goes through S3. Real owned bearer connections test state resource read and
  fingerprint denial before and after drain, plus privileged positive controls.
- **Required-fresh authority:** fetched malformed/unsupported roots now invalidate
  an unexpired ordinary cache too. A separate late probe confirmed that a missing
  managed root had the same stale-cache reuse; confirmed absence now invalidates
  as well, and the managed ordinary reload fails without LIST reconstruction.
  Tests cover malformed/unsupported bodies, warm/cold and required/ordinary paths,
  a 60-second freshness interval, and preservation of warm state after transport
  errors. Conservative invalidation can evict an intervening valid cache entry;
  that adds reads, not authority or ordering inferred from opaque ETags.
- **Rename controls:** self-renames preserve their source and missing sources do
  not manufacture empty destination labels. Blocked concurrent-evaluator tests
  now terminate owned supervisor children in cleanup, rather than hanging on a
  consumed Task monitor or leaving blocked test work alive after an assertion.
  The self-rename assertion above is historical and was subsequently corrected
  against actual pinned Loki execution: `label_format x=x` deletes `x`.
  See the [formatter continuation](protocol-breadth.md#label-formatter-assignment-continuation).

### Validation and preserved failures

The untouched baseline passed **1,527 tests**, with 1 skipped and 37 excluded.
Initial corrected regressions failed **10/71** before fixes. Intermediate logs
retain a test syntax mistake, a native-marker assertion aimed at a spawned query
process's mailbox, blocked-task cleanup/cascading named-process failures, invalid
Resources and repository-return-shape assertions, the ineffective legacy fixture,
owned-case enforcement and a strict-Credo complexity finding. They are not erased
or counted as successful closure. Focused runs subsequently passed 134, 135, 84,
37 and 17 tests for their respective source states. An empty-promotion probe's
initial expectations were wrong; both adapters actually preserve present empty
keys, and the final test distinguishes that from absent projections. The fourth
full run's sole failure exposed the stale materializing oracle, not an unexplained
transport flake; its deterministic replacement and exact seed replay now pass.

Final current-source validation (`final-validation-5/`):

- `ERL_FLAGS='+S 4:4' mix precommit --max-cases 4`: **1,551 passed, 1 skipped,
  37 excluded**, 88.1 seconds, exit0. This adds **24 test cases** over the
  untouched baseline, plus expanded existing cases and the 1,047-control replay.
  Strict compilation, unused-dependency and formatter checks are included.
- `mix credo --strict`: no issues across **415 files**, exit0.
- Locked/offline Cargo tests: codec **127 passed**, object-store **5 passed**,
  gRPC **0 unit tests**; all three crates passed strict all-target Clippy and
  Rust formatting. ExUnit, not the zero-test crate, supplies transport coverage.
- Local-path documentation/checkpoint checks and `git diff --check` passed.
  Link checking covers local paths, not external URLs or all anchors.
- Final full dirty tracked/untracked/deleted capture and content re-verification
  live under `landing-final/`: **645 paths, 642 existing files, 3 deletions**.
  The extra dirty paths include three new files and the previously clean tracked
  entry module; previous archives/stashes and intentional deletions stay intact.

Optional external SDK/Collector profiles remain excluded. Passing checks do not
establish provider/separate-node/crash/restore/deployed-client or throughput/RSS
acceptance.

### Remaining scope limits

No full Loki/Go/humanize or Grafana replacement is claimed. Existing incomplete
numeric/parser error-label generation, legacy old-writer fencing, recording
clock skew, best-effort tail completeness, native/total-memory accounting and
operational acceptance remain open. Source-only P3 observations include
conservative generation/304 cache churn, retained provenance/container costs,
unused fixture cache APIs, interval-boundary retirement admission and the
already documented footer-probe capacity cliff. They are not new durable
corruption findings and were not silently represented as fixed. Ordinary
legacy reconstruction/fallback policy remains separate from required-fresh and
managed authority. No source review or green test grants landing approval.

## Fourth adversarial pass: explicit boundary matrices

This was a bounded continuation, not permission to expand protocol breadth or
reopen every known limitation. The previous 645-path worktree was captured and
verified against the third-pass archive before work. Evidence and the frozen
scope live under `/tmp/pulse-landing-dialogue-4/`. **No new P1/P2 was established,
no production code changed, and no failing production regression required a fix.**
Only three existing test files, this checkpoint and the alerting documentation
changed during this pass.

### Independent review and finding disposition

Four independent source-only reviews overlapped authorization/authority and
query/oracle boundaries, using separate Claude and Pi processes. Initial budgets
were ten tool calls each. Peer reports were embedded inline for actual dialogue,
followed by independent authority, authorization and query counter-reviews with
six-call budgets. Claude's final authorization report counted a paired action as
one call while enumerating seven source operations; that exceeds a six-operation
interpretation and is disclosed, not presented as strict compliance. The final
narrow oracle reply used one read of three allowed. Initial Claude attempts to
read the scratch scope file were denied by worktree restrictions; later prompts
carried scope inline. Restricted tools are not an OS sandbox.

Claude initially proposed requiring the current rule classification for event
body replay. Cross-review showed this would revoke otherwise authorized old
threshold history after conversion to recording. Actual rule classifications are
closed, event producers preserve historical classification, and current resource
frontiers are a different payload. Claude explicitly withdrew the P2 hypothesis;
Pi independently rejected it. There was no reproduced authorization leak and no
blanket current-head gate was added. Existing legacy expiry protections remain.

All final scoped counter-reviews found no concrete P1/P2 within actual reads.
They did not read the whole dirty tree or execute tests. Authority review omitted
cold reconstruction bodies and native internals; query review omitted Rust bodies
and broader runtime/storage internals; authorization review omitted full tool,
router/socket and durable replay implementations. Author execution, not favorable
source reports, supplies the runtime evidence below.

### Added controls and stronger oracles

- **Historical authorization:** a real threshold firing, recording conversion,
  recording evaluation and S3 expiry establish distinct committed revisions.
  Expected visible/protected events are partitioned by revision provenance,
  independently of production-stamped classes; exact classes and a protected
  non-expiry health event are asserted separately. A no-record reader retains
  old threshold bodies but cannot read current recording config/state or its
  resource frontier. One-event pages check exact raw cursor advancement through
  hidden events, followed by an empty end-position read. Owned bearer connections
  exercise MCP tool and HTTP controller-action output, not routed/socket HTTP.
  Immutable object bytes remain unchanged. Existing real legacy expiry fixtures
  still pin the type override and additional restrictions with 3/2/0 visibility.
- **Authority:** managed and legacy matrices cover ordinary warm no-GET reads,
  required transport errors preserving warm ordinary cache, conditional warm
  revalidation, 200 replacement with a distinct opaque ETag, malformed-body
  invalidation, cold 304 rejection, and confirmed missing authority invalidation
  without LIST reconstruction. The replacement rewrites identical bytes: it tests
  tag replacement, not changed manifest contents or ETag ordering. Managed ordinary
  missing-root failure is checked; legacy ordinary reconstruction is deliberately
  not prohibited by this matrix.
- **Query oracles:** literal grouped equal-time expectations discriminate both
  first and last under body versus observed-time ordering. Explicit open-lower,
  closed-upper controls distinguish irrelevant invalid rows from selected errors.
  Native packed-error controls require sparse sums of 1 and 3 despite a fetched
  invalid middle row, then require whole failure when that row enters a window.
  Each eligible logfmt/regexp evaluation consumes its own native marker; unsupported
  parser and first/last paths reject markers, preventing one query from proving
  another ran natively. First/last under the Parquet adapter is Elixir evaluation
  after actual segment encode/decode, not a native first/last claim.

A final counter-review challenged the initial new authorization oracle's reliance
on stamped classes. Revision-based partitioning and explicit protected-event
controls replaced it, then passed a targeted test and a separate narrow source
reply. Existing legacy fixtures already covered the reviewer's other concern;
no duplicate fixture or production change was needed. An initial authority-test
version passed but emitted constant-conditional warnings; owned test tags removed
those warnings. The unsuccessful exact-text edit and intermediate outputs remain
in the evidence rather than being described as failing product regressions.

### Final checks and exit

The untouched baseline passed **1,551 tests**, with 1 skipped and 37 excluded.
Focused combined tests passed **89 cases**. The definitive final validation is
`final-validation-2/`, after the strengthened authorization partition:

- `ERL_FLAGS='+S 4:4' mix precommit --max-cases 4`: **1,560 passed, 1 skipped,
  37 excluded**, 96.1 seconds, exit0. This adds **nine test cases**, plus stronger
  assertions in existing cases. Strict compilation, unused-dependency and
  formatter checks are included.
- `mix credo --strict`: no issues across **415 files**, exit0.
- Locked/offline Cargo: codec **127 passed**, object-store **5 passed**, gRPC
  **0 unit tests**; all three passed strict all-target Clippy and Rust formatting.
  The first complete validation also passed, before the final oracle tightening.
- Local documentation-path checks and `git diff --check` passed. A fresh complete
  tracked/untracked/deleted archive and independent extracted hash verification
  live under `landing-final/` and `landing-final-verify/`: **645 paths, 642 existing
  files, three intentional deletions**. Previous archives and stashes are intact.

The bounded exit criterion is met: no unexplained new scoped P1/P2, independent
counter-review of the strengthened boundaries, and green final checks. Stop this
review loop rather than automatically opening another broad round. This is not
landing approval, deployed-client/capacity acceptance, or a correctness
certificate. Optional SDK/Collector profiles remain excluded; all previously
listed clock, tail, legacy fencing, protocol, memory and operational limits
remain open. Nothing was committed, merged, deployed or run against a provider
or private application.

## Main integration: Sentry and typed telemetry

After draft publication, integrate `origin/main` at `560fc19` (Sentry error
tracking and the 1.8.0 release). Resolve 18 conflicted files across configuration,
Helm, documentation, metrics, MCP, manifest metadata and native log decoding.
Preserve both `log_labels` and `trace_summary`, both tool registries, rich and
legacy log schemas, cumulative decoded-byte bounds and record limits that count
identical rows before term sharing.

Fresh error queries use required manifest authority without stale-cache or LIST
fallback, retaining their existing `:not_found` missing-root result. Four new
regression cases exercise this public option, bounded rich/legacy metadata,
malformed present metadata and duplicate-row quotas. A checked-in legacy Parquet
fixture strengthens the upstream expansion test without relaxing the current
16 MiB normalized-write ceiling. Its native generator and hash are documented in
`test/fixtures/logs/README.md`.

The final integration checks, with `PULSE_NIF_FORCE_BUILD=1`, are recorded under
`/tmp/pulse-main-merge/final-3/`:

- `ERL_FLAGS='+S 4:4' mix precommit --max-cases 4`: **1,608 passed, 1 skipped,
  37 excluded**, 267.4 seconds; compile-with-warnings-as-errors, dependency and
  formatter checks passed.
- Strict Credo: clean across **427 files**.
- Locked/offline Cargo: **130 codec**, **5 object-store** and **0 gRPC unit tests**;
  strict all-target Clippy and Rust formatting passed for all three crates.
- Helm lint and combined Sentry/OTLP-gRPC/Tempo configuration rendering passed.

Earlier failed compiles, timed-out command wrappers and the two integration
failures remain in the evidence. Missing-authority compatibility and the invalid
oversized-write test setup were corrected before the final green run. This is
merge-integration validation, not a fifth independent review or an update to the
historical fourth-pass archive. No provider, deployment, capacity or optional
external-client exercise was added; existing limitations remain open.
