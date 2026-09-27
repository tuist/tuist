# Server scale-out review

Reviewed checkout: `c9976713fc8981ab7316977b91b0031bc3642af1`.

The review below records the baseline findings. The implementation now uses the stateless 2026-07-28 Model Context Protocol transport, rechecks credentials and permissions on every request, fixes the image-lock identity, broadcasts display-cache invalidations, elects a marketing poller, and reconciles Erlang discovery with the chart. No sticky traffic is required.

## Implementation and validation

- Modern protocol requests include validated per-request metadata; `server/discover` is implemented, session identifiers are ignored, and no session tables are initialized. Legacy initialization clients remain compatible without sessions.
- Cluster discovery starts whenever configured, including self-hosted installations. Web replicas share an upgrade-preserved cookie Secret, use pod-address node names, and listen on a fixed private distribution port. The chart rejects multiple replicas with discovery disabled and supports an externally managed cookie.
- Security decisions always consult authoritative storage. Shared Valkey failures deny admission instead of replacing the shared budget with empty local counters.
- Balance mutations invalidate display caches across nodes. Membership changes clear local caches. One globally registered marketing process polls and publishes snapshots; followers recover polling after its departure.
- Required test-ingestion staging, flaky-run updates, and alert-job enqueueing finish before acknowledgement. Optional tasks have a supervisor and a bounded drain before buffers shut down.

Validation: the implementation regression run passed all 477 tests, including credential revocation, protocol requests, image concurrency, polling, ingestion, and shutdown coverage. Following the full-server contention fix described below, all 16 focused image and image-controller tests passed, with formatting and strict code analysis passing for the changed files. The isolated checked-in two-node probe passed address discovery, remote invalidation, modern tool discovery on either node, same/different image locking, and cache clearing on departure. Helm rendering was checked with production values, clustering enabled/disabled, custom distribution ports, and an external cookie Secret; disabling clustering with two replicas was rejected. The permanent two-replica chart profile passed Helm lint and schema validation for all 27 rendered resources. The updated deployment-check workflow passed actionlint.

The Phoenix application ran locally on port 14002. Headless Chrome screenshots record the discovery card before and after: the protocol version changes from 2025-06-18 to 2026-07-28, and unsupported change subscriptions are no longer advertised.

Before and after screenshots were captured locally and retained outside the branch for pull request attachments.

### Complete two-server verification

Two ordinary operating-system processes booted the complete Phoenix application against a private PostgreSQL instance, an isolated ClickHouse database, real MinIO storage, and a private Redis instance. A round-robin proxy alternated requests between them and retried the surviving backend during shutdown. No session affinity was used. The default Kubernetes discovery strategy queried actual local address records and connected nodes with the same application prefix on two existing host addresses. The reusable [harness and setup instructions](server/verification/cluster_e2e/README.md) and [complete assertion results](server-scale-out-verification/full-server-results.txt) are checked in.

The final automated run passed:

- Twelve authenticated modern tool calls reached each server six times, without initialization or sessions; discovery and tool lists agreed between servers.
- Credential rotation and organization membership removal were enforced on both servers after warming both request paths. Credential revocation also worked while the distribution connection was deliberately disconnected.
- Display-cache and feature-flag invalidations crossed nodes; discovery recovered after restoring the distribution cookie.
- Eight concurrent signed image requests returned identical bytes from real storage with exactly one render across both nodes.
- Both nodes agreed on the elected marketing poller. Terminating its server finished an already-running supervised task, cleared the survivor's stale cache, and elected the survivor's poller. Authenticated tool calls continued while one server was down.
- A fresh server process automatically rejoined. All 175 readiness requests succeeded during departure, failover, and restart; the original credential worked on both nodes afterward.
- A shared 120-request budget admitted 120 of 130 alternating requests and rejected ten. Both servers rejected admission while the real shared store was paused and recovered when it responded again.

This run uncovered a second image-lock issue: three acquisition retries can expire before an actual cold image finishes rendering, returning an avoidable service-unavailable response. The implementation now retries the correctly identified Erlang lock against a 30-second contention deadline, releases it in an `after` block, and rechecks storage after acquisition. The focused regression holds the first render longer than the former retry budget and verifies that the contender waits while unrelated images proceed.

Headless Chrome captured the public discovery card through the proxy with both servers, only the survivor, and the restarted server rejoined. These images are retained outside the branch for pull request attachments.

Limits: no live cluster was changed or inspected. The complete local run uses the test build with ordinary database connection pools and asynchronous supervised tasks; scheduled jobs remain disabled and the normal marketing process is explicitly started. Test-profile ingestion remains synchronous, so this run does not establish crash durability for production ingestion buffers. A hidden controller observes the nodes without joining their visible membership. Because both processes share one machine's Erlang port mapper, fixed-port lookup substitutes for separate pod port mappers. Kubernetes network policies and mixed-release compatibility still require deployment verification. The partition check disconnects Erlang distribution and changes its peer cookie rather than dropping packets. Prepaid views remain eventually consistent, disconnected partitions may duplicate regenerable image work or marketing polls, installations without Valkey retain approximate admission, and hard node loss can still discard unflushed analytics. Neither supervision nor global registration makes process memory durable.

### Adversarial review

Claude reviewed the complete implementation and pinned dependency semantics and found no verified correctness or security regressions. Follow-ups remove ignored authorization-cache options from the cache controller and document full-cache eviction costs, offline cookie rendering, and cookie-key migration. Router cache assigns remain because loader and billing caches still use them. The claimed single-node monitoring error did not reproduce: `:net_kernel.monitor_nodes(true)` returned `:ok` in a non-distributed local runtime. Display balance invalidation remains eventual; an already-running read can refill an older value after eviction until the five-minute expiration. Legacy initialization intentionally returns no session identifier, and advertising no resources reflects the empty resource list.

Claude checked the follow-ups and confirmed the same verdict. A fresh focused run passed all 85 cache-controller, authentication, authorization, and invalidator tests against a private database. The controller's existing worker reference was aliased to satisfy strict code analysis for the newly touched file.

## Scope and validation

This was a codebase-wide state audit, not a line-by-line certification of every function. Searches covered `server/lib`, configuration, release packaging, stateful dependencies, relevant shared ingestion code, tests, and deployment templates. I traced process state, local tables, caches, publish/subscribe messaging, sessions, timers, background jobs, buffers, and file ownership to their callers and persistence boundaries.

Three findings were reproduced in two real connected Erlang nodes using the checkout's rate limiter, the exact pinned session-store dependency, Phoenix.PubSub 2.3.0, and Hammer 7.1.0. Other findings are identified below as source-traced or deployment-dependent. The initial audit used component probes before dependency setup. The subsequent implementation and full application/regression validation are recorded above. No deployed cluster was inspected.

The component probe and its output are retained at `/tmp/tuist-scale-audit/probe.exs` and `/tmp/tuist-scale-audit/probe-output.txt`. Run from the checkout root with `elixir --sname scale_probe_a /tmp/tuist-scale-audit/probe.exs`. The probe uses `Mix.install` for its two pinned dependencies and reads three downloaded files from the pinned [session library revision](https://github.com/addstar34/emcp/tree/c687e279cf4f550f69934549a1303312ed3a23b5/lib/emcp). It is a component reproduction, not a complete request-path test.

## Findings

### 1. Model Context Protocol sessions have separate owners on each instance

**Medium, reproduced; high priority if streaming notifications are relied upon.**

Evidence: `server/lib/tuist/application.ex:7,58`, `server/lib/tuist/mcp/server.ex:129`, `server/lib/tuist/mcp/transport/streamable_http.ex:18`, and `server/lib/tuist_web/router.ex:636`. The application initializes `EMCP.SessionStore.ETS`; no alternative store is supplied to the server. This uses node-local [Erlang Term Storage](https://www.erlang.org/doc/apps/stdlib/ets.html).

Sequence: create a session and register its stream on instance A; send a subsequent request with the same session identifier to B. B has no record of A's session or stream process. The pinned transport defaults `recreate_missing_session` to true, so ordinary tool calls usually continue by creating another local record. A DELETE on B deletes that record and cannot close A's stream. Touches, expiry, and stream registration also diverge. This is not a claim that ordinary tool calls universally return “session not found.” No current Tuist caller of the dependency's notification helpers was found.

The two-node probe returned `nil` for B's lookup after creation on A, and confirmed A's stream remained registered after deletion on B. The dependency's DELETE path looks up the stream process in that store and sends `:close_sse` only when found.

**Implemented solution:** use the [stateless 2026-07-28 transport](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http). Every modern request carries its version and client capabilities, and results identify the server. Tuist responds inline and does not support change subscriptions. Legacy initialization remains available without allocating sessions. This removes session ownership, expiry, and cross-node stream deletion from the application entirely.

### 2. Authentication caches continue serving revoked credentials

**High security relevance, source-traced. Existing on one instance; multiple instances make acceptance depend on routing.**

Evidence: `server/lib/tuist_web/router.ex:661` enables authentication caching for the request routes; `server/lib/tuist_web/plugs/authentication_plug.ex:67` caches the entire authenticated subject for one minute. `server/lib/tuist/key_value_store.ex:270` only selects shared Redis storage when `persist_across_deployments` is explicitly requested, which this caller does not do. `server/lib/tuist/accounts.ex:2467` deletes an account token without invalidating these caches.

Sequence: warm a token on A, revoke it on B, then use it on A before the cached entry expires. A skips `Tuist.Authentication.authenticated_subject/1`, including its backing credential checks, and returns the cached subject. A cold B rejects it. Independently warmed nodes have different expiry times. The cache authorization path additionally caches positive authorization decisions in `server/lib/tuist_web/plugs/api/authorization/authorization_plug.ex:65`.

**Solution:** broadcast explicit invalidations after credential and permission mutations, with subscribers evicting both subject and authorization entries. A generation per token/account makes broad permission changes manageable; clear local security caches after disconnection/rejoin. This improves coherence but asynchronous invalidation alone cannot guarantee immediate revocation. For that guarantee, retain a durable authoritative revocation/version check on each protected request, or synchronously consult an owner whose failure causes the request to be rejected. Do not claim publish/subscribe messages alone solve revocation during partitions or cache-fill races.

### 3. The distributed image lock identifies the wrong resource

**Medium, reproduced, including the corrected behavior.**

Evidence: `server/lib/tuist/open_graph_images.ex:59` calls `:global.trans({__MODULE__, key}, ...)`.

Erlang interprets this tuple as `{resource, requester}`, not `{namespace, key}`. All image keys therefore share the same resource, while simultaneous callers rendering the same image claim to be the same requester. In the two-node probe, another caller for the same image acquired the lock while A held it; a caller for a different image was blocked. This defeats the documented deduplication and serializes unrelated renders. The bug also exists with concurrent callers on one node.

**Solution:** use `:global.trans({{__MODULE__, key}, self()}, function)` and handle bounded acquisition failure explicitly. The corrected identifier rejected the same-image contender and admitted the different-image contender in the probe. This is an appropriate use of Erlang coordination for regenerable output; duplicate rendering after a partition remains tolerable. See [Erlang global lock identities](https://www.erlang.org/doc/apps/kernel/global.html#t:id/0).

### 4. The rate limiter's fallback cannot enforce a strict shared budget

**Medium, reproduced under delayed message delivery. Conditional on fallback or no Redis configuration.**

Evidence: `server/lib/tuist_web/rate_limit/in_memory.ex:21,26,55` broadcasts a hit and then independently decides against the local counter. `server/lib/tuist_web/rate_limit.ex:114` selects this fallback on persistent-store failures. Checked-in production configuration enables Valkey, so this is not a claim that the normal persistent path is node-local.

With the remote listener suspended while both nodes remained connected, a limit of one admitted one request on each node. A cross-node publish/subscribe control message succeeded, ruling out a disconnected test cluster. Broadcasts eventually converge counters; they do not serialize admission. Newly joined nodes also lack earlier counter history. Normal persistent hits do not populate the fallback counters, so switching to fallback introduces another budget discontinuity.

**Solution:** if approximate limiting is acceptable, document and measure the overshoot. For a strict Erlang-based limiter, route each key to a single supervised bucket owner and make admission a synchronous serialized call. Shard owners to spread load, but do not independently recompute ownership on different sides of a partition. Owner failure must reject/retry requests or recover from replicated authoritative state. A new owner starting an empty bucket silently replenishes the budget. Authentication endpoints should have a deliberate conservative policy when coordination fails.

### 5. Refreshing prepaid balances only refreshes one instance

**Medium user-visible inconsistency, source-traced.**

Evidence: `server/lib/tuist/runners/prepaid.ex:201,647,655,740` caches balances for five minutes and refreshes only the local `KeyValueStore`. Billing and operations pages read this cache.

Sequence: B caches a balance; a grant mutation on A refreshes A; the next page request on B can show the previous balance for the rest of its cache lifetime. The source comment promising an immediate refreshed view only holds locally. I found display consumers, not evidence that this cache alone controls spending authorization.

**Solution:** publish a customer-scoped invalidation after the mutation and evict the balance on every node. Prefer invalidation over broadcasting possibly out-of-order balance snapshots. Retain expiration and reload after cluster rejoin to recover from missed notifications. This is a good fit for eventual publish/subscribe coherence because the authoritative balance lives elsewhere.

### 6. Every web instance polls and broadcasts the same marketing totals

**Low correctness severity; avoidable scaling cost, source-traced.**

Evidence: `server/lib/tuist/application/runtime_children.ex:58`, `server/lib/tuist/marketing/stats.ex:13,57`. Every web instance starts a locally named process that reads five totals and broadcasts them every five seconds. Two instances run two polling loops and send both snapshots to subscribers, potentially producing out-of-order observations.

**Solution:** one supervised, elected poller publishes versioned snapshots to local readers on all nodes. Use a distributed process name with explicit takeover/retry and local last-known snapshots, or the existing elected background-job machinery. A duplicate poller during a partition is acceptable here; database-backed safety is unnecessary for this regenerable display data. Keep per-instance telemetry and connection pools local.

## Deployment and failure conditions

**Stable cluster credentials need verification before relying on the distributed features.** The chart configures node names and discovery, and production enables clustering. However, `server/mix.exs:255` supplies no release cookie, `server/Dockerfile:169` assembles the release, and the checked-in server templates/managed values do not explicitly inject `RELEASE_COOKIE`. Freshly assembled releases default to random cookies, so old/new images can fail to connect during rollout. Two replicas of the same image share its baked cookie. An external environment secret may override this; its live contents were not inspected. Supply a stable deployment-specific secret explicitly and test mixed-release membership. [Mix release documentation](https://hexdocs.pm/mix/Mix.Tasks.Release.html#module-options) documents both the random default and runtime override.

**Self-hosted clustering is gated out.** `server/lib/tuist/application.ex:397` starts `Cluster.Supervisor` only when `Environment.tuist_hosted?()` is true. Enabling the chart's cluster setting for a self-hosted installation supplies distribution configuration but does not start this discovery supervisor. Gate discovery on configured topology instead of hosted product mode. Manual external node connections are possible, but are not provided by this path.

**Readiness does not establish cluster health.** `server/lib/tuist_web/controllers/page_controller.ex:10` always returns success. A serving but isolated node can lose shell messages, disconnect broadcasts, feature-flag invalidations, and replicated-cache changes. Monitor membership with `:net_kernel.monitor_nodes/2`, expose expected versus connected peers, and test an actual cross-node message. Readiness policy must distinguish stateless routes from owner-dependent operations. Do not require two healthy nodes unconditionally: that would prevent the surviving replica from serving during ordinary maintenance.

**Acknowledged in-memory work is not durable.** `server/lib/tuist/tasks.ex:5` uses unsupervised `Task.start/1`; test creation launches it for failure/attachment writes and other follow-up work (`server/lib/tuist/tests.ex:2346`, also 561 and 1959). A returned success can outlive the node containing unfinished work. Shared ingestion buffers have graceful shutdown drains, but a hard kill still loses memory; test configuration uses synchronous writes and can hide production timing. These are existing single-instance crash risks made more relevant by frequent replica replacement, not request-routing failures. Use a supervised task for nonessential work, and persisted Oban jobs or an outbox for work that must survive acknowledgement. Replicating a process name or moving work to `Task.Supervisor` does not provide durability.

## Stateful pieces that should not be blindly distributed

| Area | Assessment |
| --- | --- |
| Browser login | Signed cookie session plus database-backed user tokens. Any instance can authenticate with consistent signing secrets. LiveView remounts after connection loss; local assigns are not automatically migrated. |
| LiveView and runner shell messaging | Already use Phoenix.PubSub, which communicates across connected nodes. Existing connections live on their serving node; a node failure requires reconnect/reconstruction. Shell bytes are not durably replayed. |
| Feature flags | Persistent Ecto storage plus Phoenix.PubSub invalidation is configured in `server/config/config.exs:120`. Healthy cluster operation already addresses ordinary cross-node changes. |
| Open Authorization library | The exact pinned Boruta dependency uses `Nebulex.Adapters.Replicated`, not a purely local cache. It must be tested under partition/rejoin, but should not be reported as lacking replication. This is separate from Tuist's authenticated-subject cache. |
| Background jobs | Oban persists jobs and elects leaders for scheduled work; runtime configuration excludes processor roles from leadership. Queue concurrency and database pools are per instance, so adding replicas increases downstream load. Job uniqueness is not a universal exactly-once guarantee; side effects still need idempotency. |
| Runner concurrency | The path uses database-backed coordination and row locks. Replacing these with a loosely elected process would weaken partition safety. |
| Kura demand/origin buffers | Local batching is intentional. Demand uses a greatest-timestamp upsert, origin rollups use additive upserts, and cold placement can write through. Keep local accumulation; account for the documented lost flush window. |
| Test attachment follow-up requests | Test-case run and argument buffers are explicitly flushed before returning their identifiers (`server/lib/tuist/tests.ex:1982`). Moving the following request to another instance does not by itself require a global flush. Flush-error handling and database visibility still deserve separate failure tests. |
| Uploads and processing files | Multipart state/artifacts are storage-backed; processor temporary files are scoped to individual executions. No general dependency on routing a subsequent upload request to a local temporary file was identified. |
| Documentation, keys and rendered assets | Immutable release data and regenerable read caches may remain local. Replicating them adds coordination without improving correctness. |

## Recommended architecture and acceptance checks

Use four explicit state contracts: local regenerable caches; publish/subscribe invalidation for eventually consistent views; supervised owners for serialized ephemeral operations; durable transactions/jobs for security and acknowledged business work. Phoenix.PubSub already supplies the messaging layer. Erlang's [global registration](https://www.erlang.org/doc/apps/kernel/global.html) supplies discovery of named owners, but does not make their memory durable or guarantee one writer across disconnected partitions.

If Mnesia is selected, define table copies, transaction boundaries, stable membership, recovery, and partition policy. [Mnesia's majority option](https://www.erlang.org/doc/apps/mnesia/mnesia.html#create_table/2) prevents writes without a majority of replicas. With only two copies, losing either prevents majority writes; two web instances do not provide both strict consistency and independent write availability during a split. Keep existing PostgreSQL authority where this tradeoff has already been solved operationally.

Implementation order: establish reliable membership across releases; repair the small image-lock defect; address session ownership and authentication revocation; add view-cache invalidation; decide the rate-limit failure policy; consolidate redundant polling; move essential detached work to durable jobs.

Before rollout, automate: alternating-node stateless discovery and tool calls with modern metadata and legacy initialization; warm-cache token revocation and permission removal; concurrent same/different image rendering; delayed limiter broadcasts and Valkey outage/recovery; prepaid refresh across nodes; rolling mixed-version restart; forced owner death; cluster partition/rejoin; and kill-after-acknowledgement ingestion recovery. Verify that cached security decisions do not survive whatever revocation deadline the product promises.
