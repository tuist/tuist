# Distributed Key-Value Store Plan

## Problem

KV entries live in per-node SQLite. As we scale horizontally within a region, an Xcode cache upload that lands on one node is a miss on its sibling nodes behind the same load balancer. That means one request can be a miss and the next a hit inside the same region, which is not acceptable. We also have globally split teams, so cross-region visibility matters too.

## Constraints

- Eventually consistent is fine; cross-node visibility can lag by minutes.
- Last-write-wins at the key level is acceptable.
- Request latency is critical; shared infra must stay off the hot path.
- S3 PUTs are a major cost driver; no per-entry S3 uploads for KV metadata.
- Self-hosted single-node deployments must keep working with local-only SQLite.
- KV PUTs can burst to ~1000 req/s; synchronous remote writes on the request path are not viable.
- Local SQLite on each node must stay within the current storage budget; we cannot mirror the full global dataset onto every node.

---

## Decisions and alternatives considered

### Why a shared metadata store at all?

Each cache node has its own SQLite database. In a horizontally scaled region, there is no mechanism for sibling nodes behind the same load balancer to converge on the same KV state. The options were:

1. **Shared metadata store** (chosen): nodes replicate KV state asynchronously to a central database. Local SQLite becomes an edge cache; the shared store is the global source of truth.
2. **S3-based replication**: upload KV entries to S3 and have nodes poll/download them. Rejected because S3 PUTs are already a major cost driver for Xcode cache artifacts; adding per-entry KV uploads would multiply that cost for metadata that is small but high-frequency.
3. **Erlang clustering / distributed ETS / libcluster**: rejected because the cache nodes are globally distributed across 7 regions with no shared network. BEAM distribution assumes low-latency, reliable connections. Cross-ocean netsplits would cause constant cluster instability.
4. **Do nothing; accept per-node misses**: rejected because same-region miss/hit flip-flopping behind a load balancer is operationally unacceptable.

### Why Postgres, not ClickHouse?

The KV metadata workload is OLTP, not analytics:

- Point lookups by `key` (read path)
- Frequent upserts with LWW conflict resolution (write path)
- Deletes and tombstones (retention/cleanup)

ClickHouse is optimized for append-heavy event streams and columnar scans. Using it here would mean fighting its data model for correctness on mutations, deletes, and point lookups. Postgres is the boring-correct choice for this workload shape.

### Why a dedicated Postgres, not the server's Postgres?

- The cache KV workload is bursty (up to 1000 writes/s), write-heavy, and operationally separate from the server's transactional workload.
- Mixing them risks cache bursts degrading server DB performance.
- Independent scaling, maintenance windows, and failure domains.

### Why not route KV reads/writes through the server application?

- Adds an extra network hop, serialization layer, and queueing point on the request path.
- The server is not on the cache request path today and should not be.
- Cache nodes should talk directly to the shared metadata store.

### Why `us-east` for the primary?

- `cache-us-east` is by far the largest traffic region and will remain so for the foreseeable future.
- The shared DB is still off the request path in the core design, so non-local regions pay that latency only on background replication.
- It is the lowest-risk place to put the primary because it is already where most cache traffic originates.

### Why wall-clock timestamps are acceptable here

- We rely on normal host wall clocks for `source_updated_at`, `last_accessed_at`, and cleanup cutoffs.
- All production cache nodes are expected to run with NTP-synchronized clocks.
- We are not introducing hybrid logical clocks or a separate version service for the initial design.
- If a node's clock is badly skewed, LWW decisions can be wrong, so basic clock health should be part of node monitoring.

### Why single-region Postgres is acceptable

- Convergence can lag by minutes (stated requirement).
- Most requests never touch the shared DB (local Cachex + SQLite serve the hot path).
- Async replication amortizes RTT across batches.
- Cross-ocean latency matters, but it is paid by background shippers and pollers rather than by the normal request path.

### Why `local` mode must remain the default

Self-hosted Tuist users run a single cache node with block storage. They have no shared DB and should not need one, and forcing a roundtrip to a remote shared database would make their single-node setup strictly worse. All existing behavior (Cachex + SQLite, local eviction behavior) must remain unchanged and be the default.

### Why existing local rows serve until evicted on first distributed rollout

- We are not doing an initial local-to-shared backfill.
- Existing nodes may already hold useful local SQLite rows, and forcing a cold start would create avoidable misses.
- So when `KEY_VALUE_MODE=distributed` is first enabled on an existing node, its pre-cutover local rows remain readable locally until they are overwritten, explicitly cleaned, or evicted.
- Those legacy rows are still local-only state. Access bumps for rows whose `source_updated_at` is NULL must not create placeholder shared rows in Postgres.
- Global convergence therefore applies to rows written in distributed mode or materialized from Postgres after enablement, not to untouched legacy rows.

### Why shared Postgres migrations still run at boot on every distributed node

- The cache service already auto-migrates its local repos on boot; distributed mode keeps the same operational model.
- The implementation must rely on normal Ecto/Postgres migration locking so concurrent boot-time migrators serialize instead of racing DDL.
- Nodes that lose the migration race simply wait for the winning node to finish and then continue booting against the same schema.
- If the shared migration fails, the node should fail fast rather than serve against an unknown shared-schema state.

### Why pending replication coalesces by key

At 1000 req/s burst, if many writes hit the same key, the local SQLite row is updated in place and remains a single pending shipment. If writes hit different keys, the shipper batches them into a small number of SQL transactions. This is the key property that makes the burst rate compatible with async replication to a remote DB. Without coalescing, 1000 req/s would mean 1000 remote upserts/s, which is fragile under cross-region latency.

### Why no per-entry count cap on `entries[]`

- Xcode controls the payload shape; we do not.
- Currently one entry per key, but this may change.
- A count cap would be brittle and require coordinated client/server changes.
- Instead: the authoritative global row stores the opaque `json_payload` blob. Pathological payloads may slow background processing, not request serving.
- Byte-size cap already exists at the request level (25MB body limit).

### Why poll-based replication, not LISTEN/NOTIFY or push

- 7 globally distributed hosts with minutes-level convergence tolerance.
- Polling is simpler, stateless, and tolerant of network interruptions.
- `LISTEN/NOTIFY` requires persistent connections and is fragile across regions.
- Push/fanout adds complexity for marginal latency improvement that is not needed given the convergence requirements.

### Why `key_value_entry_hashes` is removed and artifact cleanup no longer tracks KV references

Today, KV eviction extracts CAS hashes from deleted entries, checks which are unreferenced via `key_value_entry_hashes`, and enqueues `XcodeCleanupWorker` jobs to delete local disk artifacts and their `cache_artifacts` metadata. This coupling is removed entirely (both modes) for two reasons:

1. **S3 lifecycle policies own artifact expiration.** Xcode cache artifacts are moving to S3 with aggressive lifecycle policies. Cache nodes should not be in the business of deleting S3 objects on eviction. The only S3 deletion that cache nodes perform is explicit user-initiated cleanup via `tuist cache clean`.
2. **Local artifact cleanup is now decoupled from KV references.** After a KV row is evicted, any related local artifacts are no longer cleaned up immediately when the last KV reference disappears. Instead, local artifact lifetime is governed by `cache_artifacts` metadata and `DiskEvictionWorker`, while `OrphanCleanupWorker` remains the safety net for true no-metadata leftovers from interrupted writes.

Self-hosted deployments that use S3 must configure appropriate lifecycle policies on their buckets. This should be documented in the self-hosting guide.

The cleanup model after this change:
- **Eviction** (both modes): delete KV metadata from SQLite. Nothing else.
- **`DiskEvictionWorker`**: reclaims local artifacts using `cache_artifacts` recency when disk pressure requires it.
- **`OrphanCleanupWorker`**: deletes true no-metadata leftovers from interrupted writes.
- **S3 lifecycle policies**: handle S3 artifact expiration.
- **`tuist cache clean`**: explicit user action - deletes artifacts from local disk and S3 and (in distributed mode) writes Postgres tombstones. In distributed mode those artifact deletes are cutoff-aware so post-start writes survive.

### Why explicit project cleanup must protect post-cutoff artifact writes

- `tuist cache clean --remote` is an explicit invalidation flow, not a best-effort prefix wipe.
- Blind local `rm -rf` and blind S3 prefix deletes can remove artifacts written after the cleanup started.
- Distributed cleanup therefore reuses the same canonical `cleanup_started_at` for KV rows, local disk artifacts, and S3 objects.
- Local disk deletion must walk the project tree and re-stat each candidate immediately before unlinking, deleting only files whose current `mtime <= cleanup_started_at`.
- S3 deletion must operate per object, revalidating the current object metadata (`Last-Modified`) before delete instead of issuing one blind bulk prefix delete. That is slower, but it is an explicit user action and stays off the hot path.

### Why local eviction must be decoupled from shared-store invalidation in distributed mode

In `distributed` mode, a local eviction only means "this node dropped its cached copy to free SQLite space." The entry still exists globally in Postgres. Other nodes may still have it materialized.

So in distributed mode:
- Local eviction = free local space only. No tombstones.
- Shared-store deletes are only for explicit invalidation flows such as project cleanup, and they propagate as tombstones.

---

## Architecture

### Two modes

| Mode | Default | Behavior |
|------|---------|----------|
| `local` | Yes | Current behavior. Cachex + local SQLite. No shared state. |
| `distributed` | No | Local Cachex + SQLite as edge cache. PlanetScale Postgres in `us-east` as global truth. |

Mode is selected via `KEY_VALUE_MODE=local|distributed`. All existing behavior stays unchanged in `local` mode.

### Production topology

```
cache-eu-central ──┐
cache-eu-north ────┤
cache-us-east ─────┤
cache-us-west ─────┼──▶ PlanetScale Postgres (us-east)
cache-ap-southeast ┤
cache-sa-west ─────┤
cache-au-east ─────┘
```

PlanetScale Postgres is located in `us-east` for the initial deployment described above.

---

## Data model

### PlanetScale Postgres

#### `kv_entries`

| Column | Type | Notes |
|--------|------|-------|
| `key` | `text` | PK. Format: `keyvalue:{account}:{project}:{cas_id}` |
| `account_handle` | `text` | Extracted from key for query efficiency |
| `project_handle` | `text` | Extracted from key for query efficiency |
| `cas_id` | `text` | Extracted from key |
| `json_payload` | `text` | Opaque blob, same format as today |
| `source_node` | `text` | Originating cache instance |
| `source_updated_at` | `timestamptz` | LWW timestamp from originating node |
| `last_accessed_at` | `timestamptz` | Latest globally replicated access timestamp; used to decide what stays hot locally |
| `updated_at` | `timestamptz` | DB-side timestamp for sync ordering |
| `deleted_at` | `timestamptz` | Soft-delete tombstone, NULL when alive |

Indexes:
- PK on `key`
- `(updated_at, key)` for poller watermark queries
- `(last_accessed_at, key)` for optional recency-based operational queries
- `(account_handle, project_handle)` for project-scoped cleanup
- `(deleted_at)` partial index for tombstone purging

#### `distributed_kv_project_cleanups`

| Column | Type | Notes |
|--------|------|-------|
| `account_handle` | `text` | Part of PK |
| `project_handle` | `text` | Part of PK |
| `cleanup_started_at` | `timestamptz` | Canonical cutoff reused by concurrent clean requests |
| `lease_expires_at` | `timestamptz` | Cleanup record is considered active only before this timestamp |
| `updated_at` | `timestamptz` | DB-side timestamp |

Indexes:
- PK on `(account_handle, project_handle)`
- `(lease_expires_at)` for operational cleanup of expired coordination rows if needed

### Local SQLite (changed in distributed mode)

`key_value_entries` stays as it is in `local` mode. In `distributed` mode, it becomes a materialized hot cache rather than the source of truth.

A new migration adds:

- `source_updated_at` (`utc_datetime_usec`, nullable) for payload-version conflict resolution. This is intentionally separate from `last_accessed_at`: reads bump `last_accessed_at`, but must not make an older payload look newer than a later write.
- `replication_enqueued_at` (`utc_datetime_usec`, nullable) to mark rows whose latest write or access bump still needs to be shipped to Postgres.

An additional small local SQLite table stores inbound replication state:

#### `distributed_kv_state`

| Column | Type | Notes |
|--------|------|-------|
| `name` | `text` | PK. Initially only `poller_watermark` |
| `updated_at_value` | `utc_datetime_usec` | Last successfully applied shared `updated_at` |
| `key_value` | `text` | Last successfully applied shared `key` |

In `local` mode these columns are unused and remain NULL. In `distributed` mode, `KeyValueBuffer.write_batch/2` sets `source_updated_at` to the current timestamp for payload writes, and both writes and access bumps set `replication_enqueued_at` when they need shipping.

If an existing node enables distributed mode while already holding local KV rows, those legacy rows keep serving locally until they are overwritten, explicitly cleaned, or evicted. Access-only reads for rows whose `source_updated_at` is still NULL remain local-only and must not create placeholder shared rows in Postgres. Rows materialized by `KeyValueReplicationPoller` also must not set `replication_enqueued_at`; inbound replication cannot be allowed to echo back out through the shipper.

In `distributed` mode, every node converges on the global hot working set using one background sync loop: `KeyValueReplicationPoller` follows rows in Postgres ordered by `updated_at`, and `updated_at` advances for both payload writes and replicated access bumps.

The local database is then kept below the existing 25GB limit by the current time- and size-based eviction policy, which already orders by `last_accessed_at`.

- Practically, this means each node converges toward the global hot working set, not the full historical dataset.
- Different nodes will not hold the exact same set, but they should broadly converge as globally hot keys keep getting touched and therefore keep moving through the sync stream.
- Cold entries can be dropped locally and later re-materialized when another node writes or accesses them, because both actions advance the shared row's `updated_at`.

`key_value_entry_hashes` is removed entirely (see "Why `key_value_entry_hashes` is removed" in Decisions above). The table, schema, and all code that reads or writes hash references are deleted as part of this plan.

### Local replication queue (piggyback on `key_value_entries`)

We do not add a second SQLite table for replication. The existing `key_value_entries` table is enough.

- New writes already flow through `KeyValueBuffer`.
- In distributed mode, `KeyValueBuffer.write_batch/2` writes the row locally and sets `replication_enqueued_at`.
- `KeyValueReplicationShipper` scans `key_value_entries WHERE replication_enqueued_at IS NOT NULL ORDER BY replication_enqueued_at, id LIMIT ...`.
- `replication_enqueued_at` is the shipment token. On successful shipment the shipper clears it only when the row still has the exact `replication_enqueued_at` value that was shipped.
- Repeated writes to the same key naturally coalesce because `key_value_entries.key` is already unique.

- Add a partial index on `replication_enqueued_at` for `IS NOT NULL` rows so the shipper only scans pending work.
- Pending rows must not be evicted locally before they have been shipped successfully.

---

## Write path

```
Client PUT
  │
  ▼
Cache node (any)
  ├─▶ Cachex.put (in-memory, immediate)
  └─▶ KeyValueBuffer.enqueue (ETS buffer → local SQLite, marks row for replication)
  │
  ▼
ACK to client
  │
  ▼ (async, background)
KeyValueReplicationShipper (GenServer, per-node)
  ├─ polls pending local rows every 200ms (configurable via DISTRIBUTED_KV_SHIP_INTERVAL_MS)
  ├─ batches pending rows (up to 500-2000 per batch)
  ├─ INSERT INTO kv_entries ... ON CONFLICT (key) DO UPDATE
  │    SET json_payload = CASE
  │          WHEN EXCLUDED.source_updated_at > kv_entries.source_updated_at
  │          THEN EXCLUDED.json_payload
  │          ELSE kv_entries.json_payload
  │        END,
  │        source_updated_at = GREATEST(kv_entries.source_updated_at, EXCLUDED.source_updated_at),
  │        last_accessed_at = GREATEST(kv_entries.last_accessed_at, EXCLUDED.last_accessed_at),
  │        ...
  └─ compare-and-clear `replication_enqueued_at` on success
```

LWW resolution: payload fields use `source_updated_at`; access recency uses `GREATEST(last_accessed_at)` so an access bump can propagate without overwriting a newer payload. If two payload writes somehow arrive with identical `source_updated_at`, break the tie by lexicographically comparing `source_node` so the rule is explicit and deterministic.

Delete interaction rule: a tombstoned row behaves as if it has a delete cutoff at `deleted_at = cleanup_started_at`. A shipped payload write may only revive the row if its winning `source_updated_at` is strictly greater than `deleted_at`; older or equal writes are stale and must leave the tombstone in place. Access-only updates never clear `deleted_at`.

Burst absorption: duplicate-key bursts are rare, so the main protection is batching many different keys into a small number of SQL transactions. When the same key is hit repeatedly, the local row is updated in place and remains a single pending shipment.

Shipment token rule: if row version A is shipped and the row is updated locally to version B while that batch is in flight, the success path must not clear B's pending marker. The shipper therefore clears `replication_enqueued_at` with a predicate matching the exact shipped token; if the row has been re-enqueued meanwhile, the clear affects 0 rows and the newer state remains pending.

Cross-region note: shipper database timeouts and batch sizes must be tuned for the farthest regions. The correct answer for high-latency regions is smaller batches and a longer shared-DB timeout, not a single huge transaction that times out from Australia.

## Read path

```
Client GET
  │
  ▼
Cachex.get(key)
  ├─ hit ──▶ enqueue throttled access update, return payload
  └─ miss
      │
      ▼
  KeyValueRepo.get_by(key) [local SQLite]
  ├─ hit ──▶ populate Cachex, enqueue access update, return payload
  └─ miss ──▶ return {:error, :not_found}
```

The initial design keeps Postgres entirely off the read path. Xcode cache artifacts are small enough that a cross-ocean metadata lookup may not beat a miss and rebuild anyway, so remote miss fallback is intentionally not part of the core feature. If metrics later show a clear benefit, it can be added as an explicit follow-up behind a flag.

### Access replication

Distributed mode needs a coalesced access-bump path, not just payload-write replication. When a key is read locally, we eventually mark it for shipment so the shipper can propagate an updated `last_accessed_at` to Postgres. That access bump also advances the shared row's `updated_at`, so it naturally flows through the same inbound poller as payload writes.

- Payload freshness is still governed by `source_updated_at`.
- Hotness is governed by `last_accessed_at`.
- We do not need to ship every individual read; the latest observed access time per key is enough.
- Both SQLite read-through hits and `Cachex` hits should feed this path in distributed mode; otherwise entries that stay hot in memory stop refreshing the global hotset signal.
- In practice this should be throttled/coalesced so hot `Cachex` hits still refresh global hotness without turning every hit into a SQLite + Postgres write.
- Access-only reads for legacy local rows with `source_updated_at IS NULL` are excluded from shipping; those rows stay local-only until a distributed-mode payload write or inbound replication gives them shared lineage.
- The default policy is at most one replicated access bump per key per 30-second window, configurable via `DISTRIBUTED_KV_ACCESS_THROTTLE_MS`.
- This throttle should live in process-local memory/ETS only. If a node restarts and loses the throttle state, the worst case is a few extra access bumps, which is acceptable.

## Replication (inbound)

```
KeyValueReplicationPoller (GenServer, per-node)
  │
   ├─ loads local watermark from SQLite `distributed_kv_state`
   ├─ polls PlanetScale every 30-60s (configurable)
   ├─ SELECT * FROM kv_entries
   │    WHERE updated_at < NOW() - interval '@poll_lag'
   │      AND (updated_at, key) > (@last_updated_at, @last_key)
   │    ORDER BY updated_at, key
   │    LIMIT 1000
  │
  ├─ for each row:
   │    ├─ alive (deleted_at IS NULL):
   │    │    upsert into local SQLite key_value_entries
   │    │    payload fields use LWW on `source_updated_at`
   │    │    `last_accessed_at` uses GREATEST(local, remote)
   │    └─ tombstoned (deleted_at IS NOT NULL):
  │         skip if local row has `replication_enqueued_at IS NOT NULL`
  │           (pending shipment must reach Postgres before local delete)
  │         otherwise delete from local SQLite key_value_entries
  │
  └─ persist advanced watermark to SQLite `distributed_kv_state`
```

Key details:

- **No `source_node != @current_node` filter**: a node must be able to re-materialize rows that it originally wrote after local eviction. The poller therefore applies shared rows idempotently, including rows whose `source_node` matches the current node.
- **`DISTRIBUTED_KV_NODE_NAME` still must be unique**: it is written to `source_node` and is used as the equal-timestamp tie-breaker for payload LWW decisions, not as a poller filter.
- **`updated_at < NOW() - @poll_lag` lag buffer**: prevents the classic CDC gap where an in-flight Postgres transaction with `updated_at = T` hasn't committed yet, but a later transaction with `updated_at = T+1` has. The poller would advance its watermark past `T` and never see the first transaction. Start with a conservative 30-second default (`DISTRIBUTED_KV_POLL_LAG_MS=30000`) and tune only if production data shows it is unnecessarily large.
- **Payload freshness and hotness are separate**: payload bytes are governed by `source_updated_at`, while `last_accessed_at` is merged independently with `GREATEST(...)` so hotness can propagate without a new payload write.
- **Inbound apply must not re-enqueue outbound work**: rows written by the poller update local SQLite and `Cachex` state directly and never set `replication_enqueued_at`, otherwise nodes would endlessly echo shared updates back to Postgres.
- **Shared rows must not clobber newer local pending writes**: alive-row materialization still applies LWW on `source_updated_at` and preserves newer local pending state, so an older shared row cannot roll back a newer local payload that is still waiting to ship.
- **Tombstones must not destroy pending shipments**: if the local row has `replication_enqueued_at IS NOT NULL`, the poller skips the tombstone delete. The shipper will ship the row to Postgres, where the newer `source_updated_at` will win over the tombstone's cutoff and revive the row. Once shipped, the next poll cycle will see the row is alive globally and leave it alone. Without this guard, a cleanup tombstone could delete a local row before the shipper has a chance to propagate a newer write, silently losing the update.
- **Global replication, local eviction**: every node sees global changes, but the local SQLite store is still bounded by the existing eviction worker. We do not try to predict a per-region subset in the poller.

Bootstrap rule for fresh nodes:

- A fresh distributed-mode node first captures a shared-store cutoff `(updated_at, key)` and then performs a one-time bootstrap query for live rows ordered by `last_accessed_at DESC`.
- Bootstrap copies rows until the estimated local KV footprint reaches the existing 25GB budget, then stops. This intentionally seeds the node with the hottest working set rather than the full historical dataset.
- After that bootstrap finishes, the normal poller resumes from the captured cutoff so rows that changed during bootstrap are still applied.
- Existing local SQLite rows do not need to be uploaded into Postgres before enablement; this bootstrap is shared-to-local only.

Convergence guarantee: all nodes eventually see globally touched rows (writes and replicated accesses), bounded by poll interval + lag buffer + query page size.

Watermark persistence: the poller persists `(updated_at, key)` to local SQLite after each successfully applied page. On restart it resumes from that stored watermark rather than from wall-clock time. If the last page is re-applied after a crash, the upserts are idempotent and therefore safe.

Cachex invalidation on inbound replication: when the poller applies a remote payload overwrite or a tombstone delete, it should delete that key from local `Cachex`. Access-only updates that only advance `last_accessed_at` do not need invalidation. This keeps Postgres off the hot path while preventing week-long stale in-memory values in distributed mode.

---

## Eviction and cleanup

See "Why `key_value_entry_hashes` is removed" and "Why local eviction must be decoupled from shared-store invalidation" in Decisions above for full rationale.

### Local eviction (both modes)

- Purpose: free local SQLite space.
- Runs via `KeyValueEvictionWorker` with time-based and size-based triggers (unchanged).
- Deletes local SQLite rows only. Does NOT enqueue `XcodeCleanupWorker` jobs or delete any artifacts. Local artifacts are reclaimed later by `DiskEvictionWorker` through `cache_artifacts`, and true no-metadata leftovers are handled by `OrphanCleanupWorker`.
- In distributed mode: must also skip rows where `replication_enqueued_at IS NOT NULL` so pending writes are not dropped before they reach Postgres. The entry still exists globally; other nodes and the poller can re-materialize it if it becomes active again.

### Shared-store invalidation (distributed mode only)

#### Shared-store deletes

- A tombstone is just a normal `kv_entries` row with `deleted_at` set.
- Only explicit invalidation flows create tombstones. The concrete example is a `tuist cache clean --remote` request, which fans out directly from the CLI to cache nodes today. Local eviction never does.
- `tuist cache clean --remote` fans out to all cache nodes, so the delete path must be explicitly race-safe and idempotent.
- We use a tombstone instead of an immediate hard delete so the delete can replicate through the same poller/watermark flow as any other change.
- Pollers observe the tombstone and remove the corresponding local SQLite row.
- While the tombstone exists, the key is globally considered deleted even if some node still had an old local copy before polling.
- This is metadata invalidation plus explicit cutoff-aware artifact cleanup for the same user-requested project clean. Background artifact expiration is still owned by `DiskEvictionWorker`, `OrphanCleanupWorker`, and S3 lifecycle policies.

Race-safe semantics for `tuist cache clean --remote`:

- No CLI changes are required. Instead, the cache service coordinates cleanup cutoffs in shared Postgres.
- Add a small shared coordination record keyed by `(account_handle, project_handle)` for active distributed cleanups.
- When a cache node receives `/api/cache/clean` in distributed mode, it looks up or creates the active cleanup record for that project inside a transaction and obtains the canonical `cleanup_started_at` from that row.
- The coordination record is active only while `lease_expires_at > NOW()`. Use a short lease window (5 minutes initially), which is long enough for a cleanup to finish but short enough to self-heal after node failure.
- Concurrent cleanup requests for the same project coalesce onto the same active cleanup operation only while that lease is active.
- Each node deletes its local SQLite rows for the target scope only where `source_updated_at <= cleanup_started_at`.
- Each node deletes local disk artifacts for the target scope only when the file still exists and its current `mtime <= cleanup_started_at`. Distributed cleanup must not call a whole-project `rm -rf`.
- Each node deletes S3 objects for the target scope only when the object's current `Last-Modified <= cleanup_started_at`. Distributed cleanup must not call a blind `delete_all_with_prefix`.
- Each node also writes Postgres tombstones (`deleted_at`) for the same scope and cutoff. Multiple nodes executing the same tombstone write is safe: the predicate `source_updated_at <= cleanup_started_at` is deterministic, so every node converges on the same set of tombstoned rows regardless of execution order.
- A write that happens after `cleanup_started_at` wins automatically: its KV row is not deleted locally, its local and S3 artifact bytes survive because their current timestamps are newer than the cutoff, it is not tombstoned in Postgres, and if it lands after an older tombstone it revives the row by clearing `deleted_at`.
- Repeating the same cleanup request on multiple nodes is therefore harmless: they all converge on the same cutoff and perform the same idempotent operations against both local SQLite and the shared Postgres.
- After the lease expires, the next cleanup request creates or refreshes the coordination record with a new `cleanup_started_at`, so later intentional cleans do not reuse an old cutoff forever.
- The tradeoff is intentional: overlapping remote cleans for the same project collapse into one cleanup operation while the coordination record lease is active. This preserves backward compatibility with existing CLIs.

Shared-store conflict rules:

- Tombstone writes set `deleted_at = cleanup_started_at` for rows in scope only when the row's current `source_updated_at <= cleanup_started_at`.
- Payload upserts still use LWW on `source_updated_at` (with `source_node` as the equal-timestamp tie-breaker), but they clear `deleted_at` only when the winning payload write has `source_updated_at > deleted_at`.
- Payload writes with `source_updated_at <= deleted_at` are stale relative to the cleanup cutoff and must not resurrect the row.
- Access-only shipments may advance `last_accessed_at` on live rows, but they never change `json_payload`, `source_updated_at`, or `deleted_at`.

Concrete lifecycle:

1. A user runs `tuist cache clean --remote`.
2. Each cache node participating in the fanout resolves the canonical `cleanup_started_at` from the shared cleanup coordination record for that project, creating it if needed.
3. Each node removes matching local rows only if `source_updated_at <= cleanup_started_at`, so newer writes are preserved.
4. Each node immediately invalidates matching local `Cachex` entries so the handling node cannot serve stale in-memory payloads after the clean returns.
5. Each node deletes local disk artifacts for that project only when the current file `mtime <= cleanup_started_at`; it never removes the whole project directory blindly.
6. Each node deletes matching S3 objects only when the current object `Last-Modified <= cleanup_started_at`; it never issues one blind project-prefix delete in distributed mode.
7. The shared-store cleanup sets `deleted_at` on matching Postgres rows using that same cutoff.
8. Those tombstoned rows appear in the normal replication stream, and pollers remove any remaining local copies.
9. Once the cleanup lease expires, a later cleanup request for the same project gets a fresh cutoff instead of reusing the prior one.
10. After a safety window, the tombstone can optionally be hard-deleted from Postgres.

Why the safety window matters:

- A node might miss one poll cycle, restart, or be temporarily unhealthy.
- If we hard-deleted the row immediately, a slow node could miss the delete entirely.
- Keeping the tombstone around for a few days makes delete propagation robust without adding a separate delete log.

#### Tombstone purging

- A simple purge worker can hard-delete tombstones older than a safety window (for example 7 days) if shared-table growth warrants it.
- This is not required for the initial implementation; it is an operational cleanup once we have real tombstone volume data.
- If the same key is written again after deletion, that new write simply upserts the row back to the live state by clearing `deleted_at` and setting a new payload / `source_updated_at`.

---

## New modules

| Module | Type | Responsibility |
|--------|------|----------------|
| `Cache.DistributedKV.Repo` | Ecto Repo | Connection to PlanetScale Postgres |
| `Cache.DistributedKV.Entry` | Ecto Schema | `kv_entries` schema |
| `Cache.DistributedKV.Cleanup` | Context/module | Coordinates distributed project cleanup cutoffs and short-lived cleanup leases in shared Postgres |
| `Cache.KeyValueReplicationShipper` | GenServer | Batches pending local rows to PlanetScale |
| `Cache.KeyValueReplicationPoller` | GenServer | Polls PlanetScale, persists inbound watermark locally, materializes global rows locally, and invalidates stale Cachex entries on remote overwrites/tombstones |
| `Cache.TombstonePurgeWorker` | Oban Worker | Optional hard-delete of old tombstones if shared-table growth warrants it |

## Changed modules

| Module | Change |
|--------|--------|
| `Cache.KeyValueStore` | Dispatch to local-only or distributed implementation based on mode; in distributed mode, local reads feed coalesced access bumps into the replication path for rows with shared lineage, while legacy local-only rows remain local until rewritten, cleaned, or evicted |
| `Cache.KeyValueBuffer` | Remove `replace_entry_hashes/1` call and the post-insert entry fetch from `write_batch(:key_values, ...)`. In distributed mode, set `source_updated_at` and `replication_enqueued_at` on local writes and mark access bumps for replication. `replication_enqueued_at` also acts as the compare-and-clear shipment token. |
| `Cache.KeyValueEvictionWorker` | Remove all `XcodeCleanupWorker` enqueueing and hash extraction (both modes). In distributed mode, also skip rows where `replication_enqueued_at IS NOT NULL`. |
| `Cache.KeyValueEntries` | Remove `replace_entry_hashes/1`, `unreferenced_hashes/3`, and all hash reference helpers. |
| `Cache.KeyValueEntryHash` | Delete module entirely. |
| `Cache.KeyValueEntry` | Add `source_updated_at` and `replication_enqueued_at` fields to schema |
| `Cache.CleanProjectWorker` | In distributed mode, also soft-delete corresponding `kv_entries` rows in PlanetScale for the cleaned project. The worker must obtain the canonical `cleanup_started_at` for `(account_handle, project_handle)` from the shared cleanup-coordination layer, then use that same cutoff for local SQLite deletes, local `Cachex` invalidation, cutoff-aware local disk artifact deletion, cutoff-aware S3 object deletion, and PlanetScale tombstones. Distributed cleanup must not use whole-project `rm -rf` or blind S3 prefix deletes. |
| `Cache.Disk` | Add a cutoff-aware project cleanup helper for distributed mode that walks a project subtree, re-stats each file, and deletes only files whose current `mtime <= cleanup_started_at` |
| `Cache.S3` | Add a cutoff-aware distributed cleanup helper that lists a project prefix and deletes objects individually only when the current object `Last-Modified <= cleanup_started_at` |
| `Cache.Application` | Conditionally start distributed-mode children (`DistributedKV.Repo`, `KeyValueReplicationShipper`, `KeyValueReplicationPoller`) and, in distributed mode, run shared-repo migrations at boot on every node using normal Ecto migration locking |
| `mix.exs` | Add `{:postgrex, "~> 0.19"}` dependency |

---

## Configuration

| Env var | Default | Description |
|---------|---------|-------------|
| `KEY_VALUE_MODE` | `local` | `local` or `distributed` |
| `DISTRIBUTED_KV_DATABASE_URL` | — | PlanetScale Postgres connection string |
| `DISTRIBUTED_KV_POOL_SIZE` | `5` | Connection pool size |
| `DISTRIBUTED_KV_DATABASE_TIMEOUT_MS` | `10000` | Shared-DB query timeout for shipper/poller operations |
| `DISTRIBUTED_KV_SYNC_INTERVAL_MS` | `30000` | Poller interval |
| `DISTRIBUTED_KV_POLL_LAG_MS` | `30000` | Safety lag before the poller reads recently updated shared rows |
| `DISTRIBUTED_KV_SHIP_INTERVAL_MS` | `200` | Shipper interval |
| `DISTRIBUTED_KV_SHIP_BATCH_SIZE` | `1000` | Max rows per ship batch |
| `DISTRIBUTED_KV_ACCESS_THROTTLE_MS` | `30000` | Minimum interval between replicated access bumps for the same key on one node |
| `DISTRIBUTED_KV_TOMBSTONE_RETENTION_DAYS` | `7` | How long to keep tombstones |
| `DISTRIBUTED_KV_NODE_NAME` | `HOSTNAME` | Identifier for this cache instance, written to `source_node` in PlanetScale. Must be unique per instance. Defaults to the runtime hostname / pod name, not the shared public load-balancer hostname. |

---

## Implementation phases

These are implementation phases, not separate production rollouts. The intent is to build the full feature behind `KEY_VALUE_MODE=distributed` and turn it on once the core pieces are ready.

Important gating rule: a build is not considered end-to-end safe for distributed mode until Phase 4 is complete. In particular, Phases 2-3 are allowed to exercise replicated writes and reads in development/staging, but they must not be treated as supporting `tuist cache clean --remote` semantics yet.

### Phase 1: Simplify eviction and add mode flag

- Drop `key_value_entry_hashes` table (SQLite migration in `priv/key_value_repo/migrations/`). Delete `Cache.KeyValueEntryHash` schema. Remove `replace_entry_hashes/1`, `unreferenced_hashes/3`, and hash reference helpers from `Cache.KeyValueEntries`. Remove `XcodeCleanupWorker` enqueueing from `Cache.KeyValueEvictionWorker`. Remove `replace_entry_hashes/1` call and post-insert entry fetch from `Cache.KeyValueBuffer.write_batch/2`.
- Add `KEY_VALUE_MODE` config.
- Add `{:postgrex, "~> 0.19"}` to `mix.exs`.
- Add `source_updated_at`, `replication_enqueued_at` columns and the `replication_enqueued_at IS NOT NULL` partial index to local `key_value_entries` (SQLite migration in `priv/key_value_repo/migrations/`). Add local `distributed_kv_state` for persisted poller watermark.
- Add mode-dispatch layer in `KeyValueStore`.
- Make `KeyValueEvictionWorker` skip rows where `replication_enqueued_at IS NOT NULL` so distributed-mode pending writes are non-evictable from day one.
- Update self-hosting documentation and deployment guidance to state that S3-backed artifact expiration now relies on lifecycle policies rather than eviction-triggered deletes.
- No behavior change in `local` mode beyond the eviction simplification above.
- No PlanetScale dependency yet.

### Phase 2: PlanetScale schema + shipper

- Create PlanetScale Postgres database in `us-east`.
- Add `Cache.DistributedKV.Repo` to `ecto_repos` conditionally (only when `KEY_VALUE_MODE=distributed`).
- Create PlanetScale migrations in `priv/distributed_kv_repo/migrations/` for `kv_entries` and `distributed_kv_project_cleanups`.
- Add distributed runtime plumbing: env validation for `DISTRIBUTED_KV_DATABASE_URL` / `DISTRIBUTED_KV_NODE_NAME`, startup behavior when distributed mode is misconfigured, and release/migration wiring for the second repo. Keep the current auto-migrate-on-boot model: every distributed node runs the shared repo migrator at startup, relying on Ecto/Postgres migration locking to serialize concurrent runners and failing startup if migration cannot complete.
- Implement `KeyValueReplicationShipper`.
- Emit shipper telemetry in the implementation itself so Phase 2 monitoring is real, not aspirational.
- Add focused tests for shipper batching, compare-and-clear shipment tokens, LWW tie-breaking, and delete-cutoff resurrection rules.
- Writes start flowing to PlanetScale but the read path is still fully local.
- Monitor pending-row depth, shipping latency, error rates, and cross-region timeout behavior.

### Phase 3: Inbound replication (poller)

- Implement `KeyValueReplicationPoller`.
- Implement coalesced access-bump replication so reads also advance shared `updated_at` / `last_accessed_at`.
- Existing nodes that already had local SQLite rows when distributed mode was enabled keep serving those rows locally until overwrite, explicit cleanup, or eviction; access-only reads on rows with `source_updated_at IS NULL` remain local-only and do not create shared rows.
- Add fresh-node bootstrap that backfills the hottest live rows from PlanetScale up to the existing 25GB local KV budget, then hands off to the normal poller from a captured cutoff.
- In distributed mode, invalidate local `Cachex` entries when inbound replication applies a remote payload overwrite or tombstone.
- Persist poller watermark to local SQLite and resume from it on restart.
- Emit poller and local-store telemetry in the implementation itself so convergence monitoring is available as soon as the poller ships.
- Add focused tests for watermark resume, idempotent re-processing, tombstone-vs-pending-write ordering, self-rehydration after local eviction, bootstrap handoff at the captured cutoff, legacy local rows staying local-only until rewritten, and Cachex invalidation on inbound overwrite/delete.
- Each node starts materializing globally touched rows locally.
- Cross-node KV entries start appearing after the poll interval, regardless of region.
- Access bumps and payload writes now flow through the same sync path.
- Monitor convergence lag, local SQLite growth.

### Phase 4: Delete propagation and operational hardening

- Update `CleanProjectWorker` to soft-delete rows in shared Postgres and to perform cutoff-aware local disk and S3 artifact cleanup using the same canonical `cleanup_started_at`.
- Add short-lease cleanup coordination semantics for project-scoped remote cleanups.
- Make distributed-mode cleanup semantics fully explicit: local eviction frees local space only, while `tuist cache clean --remote` is the only path that creates shared tombstones and the only path that performs cutoff-aware explicit artifact deletion.
- Add focused integration tests for cleanup lease coalescing, repeated fanout requests, cleanup/write races around `cleanup_started_at`, post-cutoff artifact survival on both local disk and S3, local `Cachex` invalidation on clean, and end-to-end delete propagation across nodes.
- Add alerts for pending-row depth, poll lag, shared-DB timeout rate, and local SQLite growth.

### Phase 5: Optional follow-ups only if metrics justify them

- Add remote miss fallback only if measured latency and hit-rate data show it is worth putting Postgres on the read path.
- Add `TombstonePurgeWorker` only if tombstones become a meaningful storage problem.

---

## Telemetry

All new components should emit telemetry events consistent with the existing patterns in `Cache.PromEx` and the codebase's `:telemetry.execute` usage.

| Event | Measurements | Metadata |
|-------|-------------|----------|
| `[:cache, :kv, :replication, :ship, :flush]` | `duration_ms`, `batch_size` | `status` (`:ok`, `:error`) |
| `[:cache, :kv, :replication, :ship, :pending_rows]` | `count` | — |
| `[:cache, :kv, :replication, :poll, :complete]` | `duration_ms`, `rows_materialized`, `rows_deleted` | — |
| `[:cache, :kv, :replication, :poll, :lag_ms]` | `lag_ms` | — (time between newest polled row's `updated_at` and now) |
| `[:cache, :kv, :replication, :ship, :timeout]` | `count` | `region` |
| `[:cache, :kv, :replication, :local_store, :size_bytes]` | `size_bytes` | `node`, `region` |
| `[:cache, :kv, :tombstone_purge, :complete]` | `entries_purged`, `duration_ms` | — |

---

## Implementation notes

### `json_payload` stored as `text`, not `jsonb`

The payload is treated as an opaque blob everywhere — the request path never queries into it, and Postgres never needs to index or filter by its contents. `text` avoids the parsing overhead of `jsonb` on every insert. If debugging queries against the payload become necessary, a one-time `ALTER COLUMN` to `jsonb` is non-breaking.

### No initial local-to-shared backfill

Distributed mode does not upload pre-existing local SQLite rows into shared Postgres before enablement. On nodes that already have local KV data, those rows continue to serve locally until they are overwritten, explicitly cleaned, or evicted. Access-only reads for rows with `source_updated_at IS NULL` stay local-only and do not create placeholder shared rows. Fresh nodes instead bootstrap from PlanetScale into their local 25GB budget as described in the poller section.

---

## Risks and mitigations

| Risk | Mitigation |
|------|------------|
| PlanetScale downtime | Local-first design: reads continue working from local state and pending rows accumulate in local SQLite while the shipper retries. If the outage outlasts local KV capacity, writes eventually fail until PlanetScale recovers. |
| Pending replication grows unbounded during outage | Monitor pending-row depth, alert aggressively, and keep unshipped rows non-evictable until Postgres recovers. |
| Shipper falls behind during sustained burst | Coalesce by key in local SQLite. Monitor pending-row depth. Alert on sustained growth. |
| Poller lag causes stale local state | Acceptable per requirements (minutes-level convergence). Nodes catch up on the next poll cycle as writes and access bumps continue to flow through Postgres. |
| First distributed rollout still has legacy local-only rows on existing nodes | Accepted by rollout choice. Those rows remain readable only on the nodes that already had them until overwrite, explicit clean, or eviction. Only distributed-mode writes and polled rows participate in global convergence. |
| Local eviction deletes entry that is still globally live | Correct by design: local eviction only frees local space. The shared row remains durable and the poller can re-materialize it later. |
| Every node trends toward the same hot SQLite dataset | Acceptable by design. The existing 25GB size cap still bounds local storage, and converging on the same hotset is preferable to load-balancer inconsistency. |
| Payload size grows (Xcode sends many entries per key) | No count cap. Byte-size cap at request level (existing 25MB). Payload stays opaque on the request path. |
| Cross-region latency to PlanetScale | Shared DB is never on the hot path. Local Cachex + SQLite serve reads. Writes ack locally. Async shipping amortizes RTT, with per-region timeout and batch tuning. |
| Distributed cleanup races with a fresh artifact upload | Use the canonical `cleanup_started_at` across KV, local disk, and S3 cleanup. Distributed cleanup never issues blind project-wide deletes; it deletes only candidates whose current file/object timestamp is still at or before the cutoff. |
| Split-brain / conflicting writes from two nodes | LWW with `source_updated_at` resolves deterministically. Equal timestamps break ties by `source_node` so the rule stays explicit. No coordination needed. |
| New node joins with empty local state | Bootstrap loads the hottest live rows up to the 25GB local KV budget, then normal polling keeps the node caught up from the captured cutoff. |
| Every distributed node runs shared Postgres migrations at boot | Keep the current operational model, but rely on Ecto/Postgres migration locking so only one node performs a migration at a time and fail node startup if migration does not complete cleanly. |
