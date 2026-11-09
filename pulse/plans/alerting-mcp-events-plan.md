# MCP alert events and proactive consumers

Status: implementation design reviewed with Claude, including adversarial correctness/simplicity passes ([decisions](alerting/adversarial-review.md)), per-rule replay tools, frontier/state resources and real request-scoped live subscription streams are implemented for the native slice; the complete classified tenant-feed and proactive-policy surface remains planned. Complements [S3-backed alerting](alerting-implementation-plan.md); all 115 rule entries remain in that plan's scope. Alert subscriptions and replay are a first-class implementation milestone, not a Slack-only follow-up.

## Verified protocol, not a custom event RPC

Checked the official MCP `2026-07-28` schema and these specification pages on 2026-10-06:

- [Subscriptions](https://modelcontextprotocol.io/specification/2026-07-28/basic/patterns/subscriptions)
- [Streamable HTTP](https://modelcontextprotocol.io/specification/2026-07-28/basic/transports/streamable-http)
- [Resources](https://modelcontextprotocol.io/specification/2026-07-28/server/resources)
- [Schema](https://modelcontextprotocol.io/specification/2026-07-28/schema)

This revision provides opt-in resource notifications on the POST response stream of `subscriptions/listen`. It does NOT define a generic `notifications/alerts/fired`, durable event-broker acknowledgement, wildcard event filters, or HTTP stream replay with `Last-Event-ID`. Do not invent these as core MCP methods/fields. Domain alert events live in resource/tool data; the standard notification is a change hint containing a resource URI.

Current Pulse acknowledges an empty subscription filter and immediately completes; `MCPController` builds the whole SSE body before `send_resp`. Neither is a live subscription implementation. Add actual request-scoped streaming, resource discovery/reads and authorized resource watches. Keep GET/DELETE at 405, no initialize handshake, no protocol session IDs and no persistent per-connection client state.

## Resources and tools

Advertise `resources: {subscribe: true, listChanged: false}` initially, and implement the required `resources/list` and `resources/read` methods. List the fixed authorized tenant resources, not per-connection registrations. Add `resources/templates/list` for bounded parameterized reads. Resource sets may vary with current credentials, never as a side effect of opening a connection.

Proposed stable URIs (validated/encoded tenant IDs):

- `pulse://tenants/<tenant>/alerts`: classified current-state snapshot.
- `pulse://tenants/<tenant>/alert-events`: classified durable transition feed.
- `pulse://tenants/<tenant>/alert-rule-changes`: separately authorized, opt-in configuration-change audit feed (actor, reason, before/after revisions and authorized diffs), as specified in the main plan's [modification history](alerting-implementation-plan.md#alert-modification-history).
- Optional rule-filtered resources follow a documented URI template, not caller-selected filesystem/S3/HTTP paths.

`resources/read` returns application/json text content with a bounded frontier/checkpoint, replay floor and opaque cursor IN THE RESPONSE BODY. Lifecycle pagination uses read_alert_events (tenant, after, limit, explicit filters); administrative history uses list_alert_rule_changes and frozen-tip parent traversal. Cursors/continuations are body-only, never URIs or mirrored Mcp-Name headers/access logs. Stable/filtered resource URIs stay small. Reads/tools share authorization; no fake subscription cursor parameter. Feed/checkpoint reads use ttlMs=0 and cacheScope=private; classified resource lists are never public-cacheable.

A page returns:

- schema version, authorized events and an opaque `next_cursor`;
- current replay floor and whether more committed events are available;
- a typed retention/scope/generation gap if continuity cannot be established;
- a bounded current-state snapshot/checkpoint when explicitly requested for resynchronization.

Events contain stable ID, producer kind/ID/generation, rule generation/revision, sequence, event_class, actor, evaluation/commit times, instance identity/fingerprint and immutable source classification. Wire times are precise RFC3339 strings and sequences decimal strings; non-finite query values use explicit tagged/string representations rather than invalid JSON NaN/Infinity or lossy JavaScript integers. Classification belongs to each EVENT/instance, not the current edited rule. Rendered annotations include structured untrusted_values/origins or provenance spans: interpolated SQL/log/customer values never become trusted runbook instructions. Health events retain originating rule generation and pinned labels. No event on every unchanged tick/retry; recovering is not a fresh firing intent unless fixtures require it. Admin/ack/annotation and delivery-receipt classes are separate opt-in resources/filters. For alert-rule-changes the immutable revision IS the change record, published by the configuration CAS, not a second event journal. It carries parent, change sequence, actor/reason and request identity; authorized diffs are computed on read. Snapshot content and change metadata retain their own historical sensitivity. Audit retention is independent of firing-event replay. Reading an old revision does not inherit weaker permissions from today's rule.

Administrative catch-up freezes a committed tip and pages BACKWARDS toward the client's last accepted revision with a bounded authenticated continuation. New edits do not move that tip mid-walk. Budget exhaustion produces continuation, never a fake retention gap; a subsequent catch-up starts from the next tip after the batch is durably accepted. This opt-in feed is not chronological forward replay and is not an automated-action trigger. The lifecycle feed below still guarantees forward progress within its committed floor.

## Standard subscription wire shape

The client sends one POST `/mcp` with `Content-Type: application/json`, `Accept: application/json, text/event-stream`, tenant-scoped authorization, `MCP-Protocol-Version: 2026-07-28`, and `Mcp-Method: subscriptions/listen`:

```json
{
  "jsonrpc": "2.0",
  "id": "watch-alerts",
  "method": "subscriptions/listen",
  "params": {
    "_meta": {
      "io.modelcontextprotocol/protocolVersion": "2026-07-28",
      "io.modelcontextprotocol/clientCapabilities": {}
    },
    "notifications": {
      "resourceSubscriptions": ["pulse://tenants/example/alert-events"]
    }
  }
}
```

The first SSE data message MUST acknowledge exactly the supported/authorized subset:

```json
{
  "jsonrpc": "2.0",
  "method": "notifications/subscriptions/acknowledged",
  "params": {
    "_meta": {"io.modelcontextprotocol/subscriptionId": "watch-alerts"},
    "notifications": {
      "resourceSubscriptions": ["pulse://tenants/example/alert-events"]
    }
  }
}
```

On an authorized committed feed change, emit the standard hint:

```json
{
  "jsonrpc": "2.0",
  "method": "notifications/resources/updated",
  "params": {
    "_meta": {"io.modelcontextprotocol/subscriptionId": "watch-alerts"},
    "uri": "pulse://tenants/example/alert-events"
  }
}
```

The consumer then calls `resources/read` or `read_alert_events`. Resource reads must also validate `Mcp-Name` against `params.uri`, including the spec's encoded header format where needed. No hint is emitted for unrequested notification types or unauthorized-only changes. Unsupported filters are reflected by omission, not falsely acknowledged. Authentication/invalid URI errors fail closed without exposing cross-tenant resource existence.

On server-initiated graceful closure, send the original request's completion result with matching subscription metadata, then close. A disconnect cancels that request and releases all stream work; no notification POST or separate unsubscribe/session DELETE is needed. SSE comment heartbeats carry no JSON-RPC event. Document proxy buffering, idle/maximum connection lifetime and reconnect expectations.

## Durable events are separate from delivery queues

Slack/webhook delivery uses coalescing current-group snapshots. An MCP agent that wants transitions needs the exact committed history, NOT that coalescing queue or a PubSub-only bus.

Keep at most T committed event REFERENCES inline and at most P sealed-page references/ranges in each producer authority, with byte limits for both. On overflow, prepare a content-addressed immutable page containing bounded event bodies; CAS its reference, new tail, lifecycle and any advanced replay floor together. There is no copy-on-write tree. Losing sealers/pages are orphans. Logical event IDs/sequence ranges are fields, not candidate storage keys; verify referenced digest/size and embedded identity before reading or reusing bytes.

Binary-search the bounded in-head page ranges, then read FORWARD one page GET at a time. A consumer lagging 10x the per-request traversal budget still advances; never restart backwards from newest. Retention is at most T×(P+1) transitions OR D days, whichever limit is reached first (byte caps can seal pages sooner). Advertise these limits and the actual committed floor, not a guaranteed D-day window under arbitrary churn. Floor advancement commits before GC with read grace. Only authority reachability proves commitment; LIST does not. Missing in-horizon pages are availability errors.

Delete commits an immutable generation drain descriptor/final history root via rule-head CAS. A separate generation-scoped drain head executes it only after that descriptor was committed. Re-create immediately gets a fresh nonce (subject to explicit quotas), carrying forward a bounded retained-generation registry/root; it does not wait for target drain. Old workers never write the new-generation head. Lifecycle registry removal needs terminal drain and lifecycle replay expiry. It does not authorize whole-generation deletion: revisions still reachable through the cross-generation audit chain survive until their independent audit floor permits GC. On churn/registry overflow, never silently discard live drain/history: report quota/degraded status or require an approved explicit history gap. The registry is durable head-owned metadata, not orphan-prefix LIST.

Notification-outbox pruning never removes retained event history. Rule lifecycle and group/channel lease/receipt histories use this bounded publication/page-list pattern under their OWN authority. Group owners publish notification_lease_expired/renewed events with instance, target and source-rule generation to GROUP history, not rule heads. A classified feed can merge them without global-order claims. Discover group producers with paginated group-prefix LIST and fetch their authority heads, just as for rules; there is no second producer registry. Candidate-only prefixes are not producers. Retired group heads remain durable through replay expiry and terminal drain, so restart discovery cannot lose their committed history. The fetched authority, not LIST existence, proves commitment. F-STALE-1 must establish notifier resolved/re-fire/event parity before incident routes migrate.

Retention floors are monotonic. If an older-root reader finds a missing page, refresh the authority/floor: below the new floor is an explicit gap; missing within the refreshed horizon is an availability error. GC grace exceeds maximum read duration. Date-partitioned expired pages cannot be a recovery dependency for live delivery. Maintain an explicit oldest readable checkpoint; if a page inside the advertised horizon is missing or unreadable, return an availability error, not a successful truncated page. Positions below the committed floor return a true retention gap. Undecodable/lifetime-expired tokens return reset_required followed by the explicit earliest-retained restart described below; a current snapshot is only a separate reconciliation aid. No claim of indefinite replay. Bound retained history, page size, events/page, URI/cursor bytes, rules represented per cursor, history-read scan work and response bytes.

## Reconnect, ordering and processing guarantees

MCP transport resumption is NOT supported. `Last-Event-ID` stays ignored and SSE IDs are not a replay contract. Application event pages provide replay instead:

1. The server establishes the authorized watcher baseline BEFORE acknowledging the fresh subscription.
2. Read from the client's last durable application cursor, including any changes during disconnection/stream establishment.
3. Drain pages to a committed checkpoint; react to hints and periodically reconcile even if hints are coalesced/lost.
4. Persist the cursor only after the consumer has durably accepted/processed the events, using its own workflow checkpoint.
5. Reconnect through any Pulse node using credentials plus the same application cursor; no session lookup or sticky routing.

This watch-then-catch-up sequence plus a mandatory reconciliation timer avoids a read-then-watch race. Change hints are at-most wakeups, not the event ledger. Duplicated hints/events/pages are harmless only if the client durably deduplicates stable event IDs over the retained replay window. After a key/scope restart, a per-producer sequence high-water mark is NOT sufficient: newly authorized lower-sequence events were never processed. High-water optimizations apply only within an unchanged authorized view; the reference consumer must test this case. Ordering is per `(rule_id,generation)` sequence; there is NO global tenant sequence or total chronological order. Merge presentation order does not become processing correctness. New rules/generations are discovered independently of cursor vectors; their committed retained events cannot be silently skipped because they did not exist in the prior cursor.

Opaque versioned cursors bind tenant, subject/authorized filtered view and per-producer-generation progress. Use dictionary-encoded frontier vectors with AEAD authenticated ENCRYPTION, not readable MAC-only tokens. Deployment-configured multi-node key IDs/rotation overlap retain keys for at least the advertised cursor lifetime. Undecodable/expired tokens return reset_required, not an implicit current-state resume. An explicit replay restart begins at the EARLIEST RETAINED authorized positions with continuity_unknown/possible_duplicates; the consumer deduplicates and reconciles current state separately, never marking an unseen range processed. Reauthorize every read. On bounded token/vector overflow, return cursor_too_large with per-rule/sharded-feed options; do not truncate coverage. Views are deterministic request inputs, not connection-created resources. Default alert-events covers lifecycle/health RULE producers; group delivery/lease histories use a separate opt-in alert-delivery-events resource. Offer deterministic per-rule/class shards and measure cursor size with current generations plus opted-in groups so ordinary clients do not routinely hit vector overflow. New generations/producers begin at their retained floor with an explicit gap when needed; old vectors cannot skip them. Changed view/filter/permission scope requires an explicit replay restart from authorized retained floors. Newly authorized events may be inside an EXISTING producer below its old cursor, not only in newly discovered producers. Revoked data is filtered immediately; never retain access through an old cursor. Cursor possession grants nothing.

Slow or disconnected subscribers do not pin S3 retention, notification queues or evaluator progress. Streams are request-local and disposable. If a client needs guaranteed processing beyond retention, it must own a durable consumer checkpoint/backlog or request an explicitly designed application consumer capability; this is not a hidden MCP session. No consumer processing/external action is exactly once merely because it received an MCP notification.

## Authorization, revocation and backpressure

- Use alert-read/event-subscribe plus every source classification required by the requested view. SQL/billing/customer-derived state/events stay classified after evaluation; generic read access cannot launder privileged data.
- Filter before resource listing, reads, cursor serialization and hint change detection. A denied source's updates must not leak through payloads, URI lists, counts or watch timing. Fine-grained ACL changes cannot reuse a cached broad feed version unchecked.
- Revalidate credentials/expiry and authorization during long-lived streams; revoke/close without further protected messages. Check resource access independently on every follow-up POST.
- Bound streams globally, per tenant/principal, filter/URI count, lifetime, frame bytes, write deadlines and watcher memory. Maximum lifetimes/reconnect backoff use jitter to avoid deploy storms. On shutdown, attempt graceful completion before bounded listener drain. Streams do not reserve query slots indefinitely.
- Keep only a coalesced dirty/version marker, not an unbounded per-event mailbox. Pull pages on demand; close slow sockets for reconnect/catch-up. Copy retained URI/filter/principal strings at the native JSON boundary and discard large request-body/params references before the long-lived loop; tiny sub-binaries must not pin expanded request buffers. No permanently queued subscriber process.
- Use shared bounded node-local watchers and invalidation hints to avoid each subscription polling every rule head; conditional storage checks are the freshness backstop. Poll/read failures surface as degraded/closure, never permission-blind cached data advertised as current.
- Instrument subscriber counts, admission, reconnects, replay/target gaps, gap-elided notification transitions, coalescing, history work and S3 reads with finite labels. Notification gaps are observable degraded delivery, not a parity guarantee that every short-lived fire was notified.

## Proactive agent flow and risk boundary

```text
committed alert transition in S3
  -> MCP resource-update hint
  -> external consumer reads/replays event pages
  -> consumer deduplicates event ID and checks current alert/generation
  -> read-only Pulse MCP diagnosis (logs/metrics/context)
  -> consumer records diagnosis / proposes a response
  -> optional separately authorized ack/annotation in Pulse (no agent silences in v1)
  -> infrastructure action through SEPARATE remediation server/runtime policy
```

Action eligibility requires current applicable rule/generation/instance state, sufficiently fresh successful evaluation and non-expired notifier status AND commit age inside a configured window. Degraded/lease-expired state is diagnosis/escalation context, not default automatic-action authorization. Older replay is diagnosis-only, even if still firing. Consumers enforce per-tenant/per-rule rate limits, durable workflow claims/dedup and already-handled checks. They ignore their own actor's events; admin/ack/annotation classes are not default triggers. Rendered text retains untrusted-value provenance. Runbook fetches use an operator host allowlist with bounded redirects/bytes; context never expands action authority.

Silence creation affects human paging. V1 allows it only for authenticated human principals with a SEPARATE silence:create capability, explicit matchers and verified audit history. Agent principals cannot create, extend, expire or delete silences, including human-created ones; ack/annotate do not imply silence rights. Creation emits an unsilenceable audit notification/history event. Defer agent suppression, cumulative suppression limits and approval attestations until a real trusted workflow is designed, rather than building an unused approval protocol now. Workflows own action claims; events do not make external effects exactly once. Remediation stays in a separate server with runtime policy/HITL.

## Implementation and validation gates

Add this work after kernel/history + authorization, alongside the HTTP/MCP service milestone, BEFORE considering Slack-only implementation complete:

1. Kernel milestone: inline tails and bounded flat sealed-page references, revision-as-audit parent chains, retained generations/detached drain, encrypted body-only cursors with explicit replay restart, independent lease history and immutable event classification.
2. Resources/list/read/templates and mirrored header validation; accurate capabilities, including the opt-in modification-history resource and authorized change-list/revision/diff reads.
3. Real streaming subscriptions with acknowledgement-first ordering, opt-in filters, cancellation, heartbeat/closure and bounded watchers.
4. Reference proactive consumer using client-owned checkpoint/dedup and a fake diagnosis/action adapter; no production remediation in tests.

Required tests cover schema/correlation/filters; encrypted cursor tampering/size/key rotation and earliest-floor restart; historical classification and scope changes within an existing producer with event-ID rather than high-water-only dedup; revocation; baseline-before-ack races; two-node reconnect; 10x-lag forward lifecycle replay and frozen-tip administrative progress; competing candidate bytes/racing sealers; floor-before-GC; old-generation drain/reads through immediate re-create; outbox pruning without history loss; lease-event parity; missing/expired pages; action age/rate/feedback limits; audited human silence and denied agent suppression; slow/disconnected clients; S3 outage; private zero-TTL caching; no protocol sessions/GET/Last-Event-ID replay; and cancellation cleanup. Start test processes with start_supervised!, use monitors/barriers rather than sleeps, and capture real chunked streaming behavior rather than prebuilding an SSE response string.

Grafana-compatible Atlas/Hive webhooks cannot be assumed to carry provenance extensions: consumers treat whole rendered annotations as untrusted unless the approved contract accepts additive provenance fields. Include this in payload-migration fixtures.

The runtime must have an MCP client that supports this revision's resource subscriptions and streaming POST response. Atlas's legacy initialize-based proxy is an existing compatibility blocker; it must migrate client-side rather than Pulse adding protocol sessions or a legacy shim. Polling application event pages can be a documented fallback for clients unable to keep a stream open, with the same checkpoint/authorization semantics.
