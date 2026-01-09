# Registry on Cache Nodes - Learnings

## Task 7: Integration into Router and Application

### Patterns Discovered

1. **Supervision Tree Structure**: Cache app uses a `base_children` list that can be conditionally extended (e.g., for analytics). Registry Metadata Cachex fits naturally in the base children list.

2. **Oban Configuration Pattern**: 
   - Queues are defined as keyword list: `queues: [queue_name: concurrency]`
   - Crontab uses tuple format: `{"cron_expression", WorkerModule}`
   - SyncWorker runs hourly (`"0 * * * *"`) to respect GitHub rate limits

3. **Router Scope Pattern**: Registry routes use `/api/registry/swift` prefix with `pipe_through [:api_json]` - no auth required for public registry endpoints.

4. **Cachex child_spec Pattern**: The `Cache.Registry.Metadata` module defines its own `child_spec/1` that starts Cachex with a named cache (`:registry_metadata_cache`).

### Key Files Modified

- `cache/lib/cache/application.ex` - Added `Cache.Registry.Metadata` to supervision tree
- `cache/config/config.exs` - Added `registry_sync: 1` queue and SyncWorker crontab entry

### Integration Points

- Router already had registry routes (from Task 6)
- Metadata module provides `child_spec/1` for Cachex supervision
- SyncWorker uses `queue: :registry_sync` in its `use Oban.Worker` declaration
