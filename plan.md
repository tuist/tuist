Refactoring plan: rename module cache events

Goals
- Keep two ClickHouse tables: cas_events and module_cache_events.
- Rename schema/module to ModuleCacheEvent and update all references.

Steps
1) Migration
- Add a ClickHouse migration to rename module_cache_hit_events to module_cache_events (preserve existing data).
- Ensure the migration uses RENAME TABLE so data is preserved.

2) Schema + context
- Rename Tuist.Cache.ModuleCacheHitEvent to Tuist.Cache.ModuleCacheEvent.
- Update the schema table name to module_cache_events.
- Update Tuist.Cache.create_module_cache_events/1 to insert into ModuleCacheEvent.
- Update Tuist.Cache.count_module_cache_hit_runs/3 to query ModuleCacheEvent.

3) Webhook ingestion
- Update TuistWeb.Webhooks.CacheController to build module cache events for the new schema (no payload changes).

4) Billing + analytics
- Update CommandEvents module to use ModuleCacheEvent in queries.
- Update any analytics code that references module_cache_events if needed.

5) Tests + support utilities
- Update tests using ModuleCacheHitEvent to ModuleCacheEvent.
- Update ClickHouse table truncation to include module_cache_events.

6) Data + billing fixes
- Add module_cache_events to ClickHouse table truncation in tests.
- Update server/data-export.md to document module cache hit storage.
- Keep billing semantics consistent: both disk and s3 module hits count as remote cache hits.
- Document ingestion timestamp behavior (inserted_at is ingest time) and assess if event-time should be added later.
- Missing run_id is acceptable for now (log + drop).

7) Verification
- Run targeted tests for CommandEvents analytics and webhook ingestion if needed.
