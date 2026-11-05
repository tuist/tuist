# Alerting adversarial review: correctness and simplicity

Date: 2026-10-07. Reviewed the current implementation plan, MCP events plan, architecture and 115-rule inventory with Claude. An independent adversarial review, a challenge of the proposed simplifications, then a final consistency check of the revised documents. This is a design review, not runtime validation.

## Verdict

The plan's central invariants are sound in intent: S3-only durable state, one conditional publication authority, completed-timestamp fencing on every evaluation, classified history and honest at-least-once external effects. The design nevertheless accumulated redundant journals and coordination boundaries. Simplify those before implementation, without silently reducing migration guarantees.

## Correctness findings incorporated

### Operation identity must identify one request

An update can upload a candidate, lose to another editor, and then retry against a newer revision. Reusing the old operation ID for the rebased request collides with the old immutable candidate or makes idempotency ambiguous.

Bind each API operation ID to a canonical request digest including tenant/principal, action, target/generation, expected configuration revision and payload. Exact retries reuse the ID; rebased requests use a new ID. A reused ID with different input is an explicit conflict. Internal retries after evaluator-only head updates may continue when the expected configuration revision has not changed. Bounded searches that do not find an operation are not proof of failure.

### Logical event IDs are not immutable candidate keys

Two evaluators can prepare the same next transition ID with different values or timestamps. If both upload to a logical-ID key, a losing evaluator can reserve the bytes before the winning head CAS.

Use content-addressed immutable candidate keys, with logical identity inside the object. The committed head references the exact key/digest/size. Validate existing-object bytes and identity before reuse. Keep recording append identities stable and guard the exact committed payload before calling storage. Current storage hashes key AND content, so different content under the same key creates another segment rather than a conflict. Recording correctness therefore requires the publisher to re-read and verify the committed intent; do not claim storage enforces that invariant.

### Shared credentials cannot identify a human editor

Existing auth verifies a tenant secret and returns no principal identity. The planned write surface needs operator-configured per-principal hashed credentials with tenant, principal ID/type and capabilities. No new accounts database or S3 credential registry is needed. Calls through a shared service credential identify that service, not an independently verified person. Delegated identities are deferred; caller-supplied names/reasons cannot fill that gap.

### Cursor resets need a replay contract

“Safe resync” was underspecified. Key expiry or view/permission changes must not mark in-horizon events processed by jumping to current state. Explicit restart begins at the earliest retained authorized events, reports continuity uncertainty/possible duplicates, and uses consumer-owned deduplication. Keep AEAD confidentiality and keys for the advertised cursor lifetime. Broadening access or changing filters can expose previously filtered events within an existing producer, so resetting only newly discovered producers is insufficient. After restart, durable event-ID deduplication over retained replay is required; an old per-producer sequence high-water mark would silently discard newly authorized lower-sequence events.

## Simplifications incorporated

- **One revision object is the audit record.** Full snapshot, parent reference, change sequence, actor/reason, request identity, impact and classification. No separate audit-entry journal, audit index or duplicate administrative event. Compute authorized diffs on read.
- **Administrative catch-up is frozen-tip, newest-first pagination.** A continuation advances backwards through the revision chain without repeatedly starting at the latest head. Budget exhaustion returns continuation, not a fake retention gap. This is not chronological forward replay or an automation trigger.
- **Flat, bounded history page references replace a copy-on-write tree.** Up to T inline references and P sealed pages in each producer authority. Forward replay is direct within the committed floor; retention is count or time, whichever is reached first. Floor publication precedes deletion. No guaranteed D-day window under arbitrary event churn.
- **Rule discovery uses paginated prefix listing.** No independently published catalog is needed for the current scope; only the fetched rule head establishes commitment. Group producers use the same principle and retain their authority heads through replay and drain rather than maintaining a second producer registry.
- **Agents cannot create or alter silences in v1.** Human silence administration remains capability-gated and audited. Ack/annotation may be permitted independently. Defer approval attestation protocols and cumulative agent-suppression budgets until an approved workflow actually exists.

## Alternatives requiring an explicit decision, not silently adopted

### State-reconciled delivery

Reading current/recently-resolved rule state instead of durable source outboxes can remove per-target cursors, gaps, retirement and detached drains. It can also miss a fire/resolve cycle during an outage or resolved-state eviction and lose its exact resolution time. This is a real delivery guarantee change. The current outbox also has explicit lag limits, but coalescing an observable gap is not equivalent to silently missing an unobserved cycle.

Notifier validity is not simply `last_completed_timestamp + k * cadence`. Lease expiration, resends, routing changes and deletion remain pinned Grafana fixture gates (F-STALE-1, F-NFLOG-1, F-ROUTE-1, F-DEL-1). Keep the outbox design until an alternative's guarantees are explicitly accepted.

### Permanent tombstones or linked incarnations

Permanent rule heads could simplify history across re-creation, but add permanent metadata and a head-continuity/backup dependency. A linked prior-incarnation root may also reduce registry bookkeeping, but needs bounded discovery of old live drains and retained history. Neither alternative is a fix for a proven consistency bug. Keep fresh generation IDs and current retained-generation/drain authority until a replacement is proven; quotas are explicit availability limits, not corruption.

### Channel state inside group heads

This could remove a group-to-channel publication boundary, but would serialize claims/receipts and routing changes on one CAS and require bounded channel state. Benchmark and fault-test before adopting. A stuck channel must never block the others.

## Retention correction from the final check

Generation-level cleanup must not interpret expired lifecycle history as permission to delete longer-retained audit snapshots. GC is class-specific: lifecycle events/pages behind their own floor, revisions behind the audit floor, and live payloads after terminal evidence. Lifecycle registry entries can expire independently because audit protection follows the parent chain. Never delete a whole generation prefix while retained revisions remain reachable.

## Claims corrected during the follow-up

Claude explicitly retracted the initial claims that state reconciliation preserved every required guarantee, generation IDs should be removed, body-only cursors made encryption unnecessary, and external bindings automatically made all 111 alerts executable. Backend bindings remove native query work from a possible shadowing critical path, not SSE/template/frame/lifecycle/cadence/freshness validation. All four recording rules remain modeled; only an owner can approve retaining them in Grafana or choosing a different execution sink.

## Required validation

Implement fault tests for competing candidate bytes; exact retry versus rebased request; commit-then-error and later head advance; service/human attribution; audit publication and restore; deep frozen-tip walks; bounded forward page reads; floor-before-GC; reset replay with permission/filter changes; classification and secret exclusion. Test recording payload rejection BEFORE storage append, audit ancestry surviving lifecycle-registry removal, and event-ID dedup for newly authorized lower-sequence events. Test real streaming MCP clients and all version-pinned Grafana behaviors before migration.

Planning checks do not prove these runtime properties. No application code or production configuration was changed during this review.
