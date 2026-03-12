# Distributed KV Learnings

- Keeping `local` mode as the default is much easier when distributed behavior is additive: local SQLite writes stay unchanged unless `KEY_VALUE_MODE=distributed` is enabled.
- Access replication needs its own lightweight in-memory state. A tiny ETS-backed tracker is enough to remember shared lineage and throttle hot-key access bumps without adding more SQLite tables.
- Cleanup correctness depends on using one cutoff everywhere. Reusing the same `cleanup_started_at` for local KV deletes, disk deletes, S3 deletes, and shared-store tombstones keeps races understandable.
- The easiest safe way to preserve last-write-wins semantics in the first implementation is to merge rows in Elixir inside a transaction instead of trying to encode every rule in one giant SQL upsert.
- Poller bootstrap is easier to reason about when it seeds the hottest rows first and then hands off to a normal watermark-based poll loop.
- Removing `key_value_entry_hashes` simplifies the KV subsystem a lot, but it also means tests must stop assuming eviction has side effects on artifact deletion.
- Documentation and tests both need explicit local-vs-distributed mode resets because application config is global shared state.
