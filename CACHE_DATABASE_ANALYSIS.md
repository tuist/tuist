# Tuist Cache Service - Database Setup & Architecture Analysis

## 1. SQLite Migrations

### Location
`/home/cschmatzler/Projects/Work/tuist/cache/priv/key_value_repo/migrations/`

### 1.1 Migration: CreateKeyValueEntries (20260309190000)

```sql
CREATE TABLE key_value_entries (
  id INTEGER PRIMARY KEY,
  key TEXT NOT NULL,
  json_payload TEXT NOT NULL,
  last_accessed_at DATETIME(6),
  inserted_at DATETIME(6) NOT NULL,
  updated_at DATETIME(6) NOT NULL
)

CREATE UNIQUE INDEX key_value_entries_key_index ON key_value_entries(key)
CREATE INDEX key_value_entries_last_accessed_id_index ON key_value_entries(last_accessed_at, id)
```

**Purpose**: Stores key-value pairs with JSON payloads. The `last_accessed_at` index is critical for LRU eviction strategies. The unique constraint on `key` ensures no duplicate entries.

### 1.2 Migration: CreateKeyValueEntryHashes (20260309190100)

```sql
CREATE TABLE key_value_entry_hashes (
  id INTEGER PRIMARY KEY,
  key_value_entry_id INTEGER NOT NULL REFERENCES key_value_entries(id) ON DELETE CASCADE,
  account_handle TEXT NOT NULL,
  project_handle TEXT NOT NULL,
  cas_hash TEXT NOT NULL
)

CREATE UNIQUE INDEX key_value_entry_hashes_unique_index ON key_value_entry_hashes(key_value_entry_id, cas_hash)
CREATE INDEX key_value_entry_hashes_lookup_index ON key_value_entry_hashes(account_handle, project_handle, cas_hash)
```

**Purpose**: Maps key-value entries to accounts, projects, and CAS (Content Addressable Storage) hashes for quick lookup. The lookup index enables rapid queries by (account_handle, project_handle, cas_hash) triplet.

---

## 2. KeyValueRepo Configuration

### Module Location
`/home/cschmatzler/Projects/Work/tuist/cache/lib/cache/key_value_repo.ex`

### Definition
```elixir
defmodule Cache.KeyValueRepo do
  use Ecto.Repo,
    otp_app: :cache,
    adapter: Ecto.Adapters.SQLite3
end
```

A minimal Ecto Repo module that delegates all configuration to application environment settings.

### Database Files
- **Development**: `dev_key_value.sqlite3`
- **Test**: `test_key_value.sqlite3` (located in config directory)
- **Production**: `/data/key_value.sqlite` (configurable via `KEY_VALUE_DATABASE_PATH` env var)

---

## 3. Configuration Files Deep Dive

### 3.1 config/config.exs (Main Configuration)

**KeyValueRepo Configuration:**
```elixir
config :cache, Cache.KeyValueRepo,
  busy_timeout: 30_000,           # 30 seconds max wait for locks
  journal_mode: :wal,             # Write-Ahead Logging for concurrency
  synchronous: :normal,           # Balance safety/performance
  temp_store: :memory,            # Temporary tables in memory
  cache_size: -64_000,            # 64MB page cache
  auto_vacuum: :incremental,      # Incremental vacuum (not full)
  journal_size_limit: 67_108_864,  # 64MB max WAL file size
  queue_target: 1_000,            # Queue optimization
  queue_interval: 1_000,          # Queue optimization interval (ms)
  custom_pragmas: [mmap_size: 268_435_456],  # 256MB memory-mapped I/O
  priv: "priv/key_value_repo"    # Location of migrations
```

**Key Strategy**: Optimized for high concurrency with WAL mode, generous memory allocation, and incremental vacuuming.

**Cache Repo Configuration:**
Same SQLite pragmas as KeyValueRepo, but no `priv` setting (uses default).

**PromEx Configuration:**
```elixir
config :cache, Cache.PromEx,
  disabled: false,
  manual_metrics_start_delay: :no_delay,
  drop_metrics_groups: [],
  grafana: :disabled
```

**SQLiteBuffer Configuration:**
```elixir
config :cache, Cache.SQLiteBuffer,
  flush_interval_ms: 500,      # Flush every 500ms
  flush_timeout_ms: 30_000,    # 30 second flush timeout
  max_batch_size: 1_000,       # Max 1000 rows per flush
  shutdown_ms: 30_000          # 30 second graceful shutdown
```

**Oban Job Queue Configuration:**
```elixir
config :cache, Oban,
  repo: Cache.Repo,
  engine: Oban.Engines.Lite,  # SQLite-based job queue
  notifier: Oban.Notifiers.PG, # PostgreSQL notifier (fallback for postgres)
  queues: [
    clean: 10,
    maintenance: 1,
    s3_transfers: 1,
    registry_sync: 1,
    registry_release: 5
  ],
  plugins: [
    {Oban.Plugins.Pruner, interval: to_timeout(minute: 5), max_age: to_timeout(day: 1)},
    {Oban.Plugins.Cron, crontab: [
      {"*/10 * * * *", Cache.DiskEvictionWorker},
      {"0 * * * *", Cache.OrphanCleanupWorker},
      {"*/15 * * * *", Cache.KeyValueEvictionWorker},
      {"* * * * *", Cache.S3TransferWorker},
      {"*/10 * * * *", Cache.Registry.SyncWorker},
      {"*/15 * * * *", Cache.SQLiteMaintenanceWorker}
    ]}
  ]
```

**Ecto Repos Declaration:**
```elixir
config :cache, ecto_repos: [Cache.Repo, Cache.KeyValueRepo]
```

### 3.2 config/runtime.exs (Production Runtime Configuration)

**KeyValueRepo Runtime:**
```elixir
config :cache, Cache.KeyValueRepo,
  database: System.get_env("KEY_VALUE_DATABASE_PATH") || "/data/key_value.sqlite",
  pool_size: String.to_integer(System.get_env("KEY_VALUE_POOL_SIZE") || System.get_env("POOL_SIZE") || "2"),
  show_sensitive_data_on_connection_error: false
```

**Cache Repo Runtime:**
```elixir
config :cache, Cache.Repo,
  database: "/data/repo.sqlite",
  pool_size: String.to_integer(System.get_env("POOL_SIZE") || "2"),
  show_sensitive_data_on_connection_error: false
```

**Guardian (JWT) Configuration:**
```elixir
config :cache, Cache.Guardian,
  issuer: "tuist",
  secret_key: System.get_env("GUARDIAN_SECRET_KEY")
```

**Oban Web Dashboard:**
```elixir
config :cache, :oban_web_basic_auth,
  username: System.get_env("OBAN_WEB_USERNAME"),
  password: System.get_env("OBAN_WEB_PASSWORD")
```

**S3 Configuration:**
```elixir
config :cache, :s3,
  bucket: System.get_env("S3_BUCKET") || raise("environment variable S3_BUCKET is missing"),
  xcode_cache_bucket: System.get_env("S3_XCODE_CACHE_BUCKET"),
  registry_bucket: System.get_env("S3_REGISTRY_BUCKET"),
  protocols: s3_protocol
```

**Key-Value Eviction Configuration:**
```elixir
config :cache,
  server_url: System.get_env("SERVER_URL") || "https://tuist.dev",
  storage_dir: System.get_env("STORAGE_DIR") || raise("environment variable STORAGE_DIR is missing"),
  disk_usage_high_watermark_percent: Cache.Config.float_env("DISK_HIGH_WATERMARK_PERCENT", 85.0),
  disk_usage_target_percent: Cache.Config.float_env("DISK_TARGET_PERCENT", 70.0),
  api_key: System.get_env("TUIST_CACHE_API_KEY"),
  registry_github_token: System.get_env("REGISTRY_GITHUB_TOKEN"),
  registry_sync_allowlist: Cache.Config.list_env("REGISTRY_SYNC_ALLOWLIST"),
  key_value_max_db_size_bytes: String.to_integer(System.get_env("KEY_VALUE_MAX_DB_SIZE_BYTES") || "26843545600"),  # 25GB
  key_value_eviction_min_retention_days: String.to_integer(System.get_env("KEY_VALUE_EVICTION_MIN_RETENTION_DAYS") || "1"),
  key_value_read_busy_timeout_ms: String.to_integer(System.get_env("KEY_VALUE_READ_BUSY_TIMEOUT_MS") || "2000"),
  key_value_maintenance_busy_timeout_ms: String.to_integer(System.get_env("KEY_VALUE_MAINTENANCE_BUSY_TIMEOUT_MS") || "50"),
  key_value_eviction_max_duration_ms: String.to_integer(System.get_env("KEY_VALUE_EVICTION_MAX_DURATION_MS") || "300000"),
  key_value_eviction_hysteresis_release_bytes: String.to_integer(System.get_env("KEY_VALUE_EVICTION_HYSTERESIS_RELEASE_BYTES") || "24696061952")
```

**OpenTelemetry Configuration:**
```elixir
if otel_endpoint do
  config :opentelemetry,
    traces_exporter: :otlp,
    span_processor: :batch,
    resource: [
      service: [name: "tuist-cache", namespace: "tuist"],
      deployment: [environment: System.get_env("DEPLOY_ENV") || "production"]
    ]

  config :opentelemetry_exporter,
    otlp_protocol: :grpc,
    otlp_endpoint: otel_endpoint
end
```

### 3.3 config/dev.exs (Development Configuration)

```elixir
config :cache, Cache.Guardian,
  issuer: "tuist",
  secret_key: "development_guardian_secret_key_at_least_64_characters_long_for_dev"

config :cache, Cache.KeyValueRepo,
  database: "dev_key_value.sqlite3",
  pool_size: 10,
  show_sensitive_data_on_connection_error: true

config :cache, Cache.Repo,
  database: "dev.sqlite3",
  pool_size: 10,
  show_sensitive_data_on_connection_error: true

config :cache, CacheWeb.Endpoint,
  http: [ip: {0, 0, 0, 0}, port: 8087],
  check_origin: false,
  code_reloader: true,
  debug_errors: true,
  secret_key_base: "development_secret_key_base_at_least_64_characters_long_for_security",
  watchers: []

config :cache, :oban_web_basic_auth, username: "admin", password: "admin"

config :cache,
  server_url: "http://localhost:8080",
  storage_dir: System.get_env("STORAGE_DIR") || "/tmp/cache",
  api_key: System.get_env("TUIST_CACHE_API_KEY")
```

### 3.4 config/test.exs (Test Configuration)

```elixir
alias Ecto.Adapters.SQL.Sandbox

config :cache, Cache.KeyValueRepo,
  database: Path.expand("../test_key_value.sqlite3", __DIR__),
  pool: Sandbox,
  pool_size: System.schedulers_online() * 2 + 10,
  busy_timeout: 30_000,
  timeout: 45_000,
  queue_target: 45_000,
  queue_interval: 45_000,
  show_sensitive_data_on_connection_error: false

config :cache, Cache.Repo,
  database: Path.expand("../test.sqlite3", __DIR__),
  pool: Sandbox,
  pool_size: System.schedulers_online() * 2 + 10,
  busy_timeout: 30_000,
  timeout: 45_000,
  queue_target: 45_000,
  queue_interval: 45_000,
  show_sensitive_data_on_connection_error: false

config :cache, Cache.SQLiteBuffer, shutdown_ms: 0, flush_interval_ms: to_timeout(hour: 1), flush_timeout_ms: 50_000

config :cache, Oban,
  queues: false,
  plugins: false,
  testing: :manual
```

**Key Features**:
- Uses `Ecto.Adapters.SQL.Sandbox` for concurrent test isolation
- Aggressive timeout settings (45 seconds) to avoid race conditions
- Disables Oban queues for manual testing control

### 3.5 config/prod.exs (Production)

```elixir
import Config

config :logger, level: :info
```

Minimal - all production config is in `runtime.exs` for environment variable support.

---

## 4. Distributed & Replication Architecture

### 4.1 No Distributed Erlang Clustering

**Key Finding**: The Tuist Cache service does NOT use Erlang distributed clustering. There is no:
- `Node` clustering setup
- Inter-node communication
- Distributed ETS tables
- Mnesia replication

### 4.2 S3-Based Distributed Locking for Registry

**Location**: `Cache.Registry.Lock` module

Registry sync operations use S3 objects as distributed locks to coordinate between multiple cache nodes:

```elixir
def try_acquire(key, ttl_seconds) when is_integer(ttl_seconds) and ttl_seconds > 0 do
  lock_key = lock_key(key)
  now = System.system_time(:second)
  expires_at = now + ttl_seconds
  body = Jason.encode!(%{acquired_at: now, expires_at: expires_at, node: to_string(node())})

  case put_lock(lock_key, body, if_none_match: "*") do
    {:ok, _} ->
      {:ok, :acquired}

    {:error, {:http_error, 412, _}} ->
      maybe_replace_expired(lock_key, body, now)

    {:error, reason} ->
      Logger.warning("Failed to acquire registry lock #{lock_key}: #{inspect(reason)}")
      {:error, :already_locked}
  end
end
```

**Lock Types**:
1. **Sync Lock** (`key: :sync`) - 3000 second TTL
   - Ensures only one cache node syncs registry metadata from GitHub
   - Path: `registry/locks/sync.json`

2. **Package Lock** (`key: {:package, scope, name}`) - 900 second TTL
   - Per-package coordination
   - Path: `registry/locks/packages/{scope}/{name}.json`

3. **Release Lock** (`key: {:release, scope, name, version}`) - 900 second TTL
   - Per-release coordination
   - Path: `registry/locks/releases/{scope}/{name}/{version}.json`

**Lock Implementation Details**:
- Uses S3 `if_none_match: "*"` for atomic create-if-not-exists
- Uses `if_match` with ETag for conditional updates of expired locks
- Includes consistency header: `X-Tigris-Consistent: true` for Tigris S3 backend
- Expired locks are automatically replaced if lock holder is unreachable

### 4.3 No Data Replication Between Nodes

Each cache node:
- Has its own independent SQLite databases (`Cache.Repo` and `Cache.KeyValueRepo`)
- Does NOT replicate data to other cache nodes
- Stores artifacts locally on disk
- Uses S3 as authoritative source for artifacts

---

## 5. PromEx & Telemetry Setup

### 5.1 Main PromEx Module

**Location**: `Cache.PromEx`

```elixir
defmodule Cache.PromEx do
  use PromEx, otp_app: :cache

  @impl true
  def plugins do
    [
      PromEx.Plugins.Beam,
      {PromEx.Plugins.Phoenix,
       router: CacheWeb.Router,
       endpoint: CacheWeb.Endpoint,
       duration_buckets: [10, 100, 500, 1000, 5000, 10_000, 30_000]},
      PromEx.Plugins.Oban,
      Cache.CAS.PromExPlugin,
      Cache.KeyValue.PromExPlugin,
      Cache.Module.PromExPlugin,
      Cache.Finch.PromExPlugin,
      Cache.SQLiteBuffer.PromExPlugin,
      Cache.S3Transfers.PromExPlugin,
      Cache.S3.PromExPlugin,
      Cache.Authentication.PromExPlugin
    ]
  end
end
```

**Built-in Plugins**:
- `PromEx.Plugins.Beam` - Erlang VM metrics (memory, process count, etc.)
- `PromEx.Plugins.Phoenix` - HTTP request metrics
- `PromEx.Plugins.Oban` - Job queue metrics

**Custom Plugins**: 8 domain-specific metrics plugins (see details below)

**Metrics Endpoint**: `/metrics` (via `PromEx.Plug` in router)

### 5.2 Custom PromEx Plugins

#### 5.2.1 Cache.KeyValue.PromExPlugin

**Event Metrics**:
- **GET Operations**:
  - `cache_kv_get_total` - Total GET requests
  - `cache_kv_get_hit_total` - GET hits
  - `cache_kv_get_miss_total` - GET misses
  - `cache_kv_get_contention_total` - Read-through SQLite contention events
  - `cache_kv_get_bytes` - Total bytes returned
  - `cache_kv_get_payload_size_bytes` (distribution) - Payload size distribution (256B to 256MB buckets, exponential)

- **PUT Operations**:
  - `cache_kv_put_total` - Total PUT requests
  - `cache_kv_put_success_total` - Successful PUTs
  - `cache_kv_put_errors_total` - PUT errors (tagged by reason)
  - `cache_kv_put_entries` - Total entries stored
  - `cache_kv_put_entries_distribution` - Distribution of entries per PUT (buckets: 1, 2, 4, 8, 16, 32, 64, 128)

- **Eviction**:
  - `cache_kv_eviction_entries_total` - Total entries evicted
  - `cache_kv_eviction_duration_milliseconds` (distribution) - Eviction duration (tagged by trigger, status)
  - `cache_kv_sqlite_poll_errors_total` - Failed SQLite metrics polling (tagged by reason)

**Polling Metrics** (15-second intervals):
- `cache_kv_db_file_size_bytes` - SQLite database file size
- `cache_kv_wal_file_size_bytes` - Write-Ahead Log file size
- `cache_kv_sqlite_page_count` - Total SQLite pages
- `cache_kv_sqlite_freelist_pages` - Free pages available
- `cache_kv_sqlite_page_size_bytes` - Page size
- `cache_kv_sqlite_in_use_bytes` - In-use bytes (page_count - freelist) * page_size
- `cache_kv_sqlite_reclaimable_bytes` - Reclaimable bytes (freelist * page_size)

#### 5.2.2 Cache.CAS.PromExPlugin

**Downloads**:
- `tuist_cache_cas_download_hits_total`
- `tuist_cache_cas_download_disk_hits_total`
- `tuist_cache_cas_download_disk_misses_total`
- `tuist_cache_cas_download_s3_hits_total`
- `tuist_cache_cas_download_s3_misses_total`
- `tuist_cache_cas_download_s3_bytes` (sum)
- `tuist_cache_cas_download_bytes` (sum)
- `tuist_cache_cas_download_artifact_size_bytes` (distribution, exponential 1KB-1MB)
- `tuist_cache_cas_download_errors_total`

**Uploads**:
- `tuist_cache_cas_upload_attempts_total`
- `tuist_cache_cas_upload_success_total`
- `tuist_cache_cas_upload_exists_total`
- `tuist_cache_cas_upload_cancelled_total`
- `tuist_cache_cas_upload_errors_total` (tagged by reason)
- `tuist_cache_cas_upload_bytes` (sum)
- `tuist_cache_cas_upload_artifact_size_bytes` (distribution, exponential 1KB-1MB)

#### 5.2.3 Cache.Module.PromExPlugin

**Downloads**:
- `tuist_cache_module_download_hits_total`
- `tuist_cache_module_download_disk_hits_total`
- `tuist_cache_module_download_disk_bytes` (sum)
- `tuist_cache_module_download_artifact_size_bytes` (distribution)
- `tuist_cache_module_download_disk_misses_total`
- `tuist_cache_module_download_s3_hits_total`
- `tuist_cache_module_download_s3_bytes` (sum)
- `tuist_cache_module_download_s3_misses_total`
- `tuist_cache_module_download_errors_total` (tagged by reason)

**Multipart Uploads**:
- `tuist_cache_module_multipart_starts_total`
- `tuist_cache_module_multipart_parts_total`
- `tuist_cache_module_multipart_parts_bytes` (sum)
- `tuist_cache_module_multipart_part_size_bytes` (distribution, exponential)
- `tuist_cache_module_multipart_completions_total`
- `tuist_cache_module_multipart_completed_bytes` (sum)
- `tuist_cache_module_multipart_artifact_size_bytes` (distribution)
- `tuist_cache_module_multipart_parts_count_distribution` (buckets: 1, 2, 4, 8, 16, 32, 64, 128)

#### 5.2.4 Cache.S3.PromExPlugin

Tracks S3 operations with result-based tags and duration distributions:

**HEAD Operations**:
- `cache_s3_head_requests_total` (tagged by result)
- `cache_s3_head_duration_milliseconds` (distribution, tagged by result)
- Buckets: [1, 5, 10, 25, 50, 100, 250, 500, 1000, 2000, 5000] ms

**Upload Operations**:
- `cache_s3_upload_requests_total` (tagged by result)
- `cache_s3_upload_duration_milliseconds` (distribution, tagged by result)
- Buckets: [10, 50, 100, 500, 1000, 5000, 10_000, 30_000, 60_000, 120_000] ms

**Download Operations**:
- `cache_s3_download_requests_total` (tagged by result)
- `cache_s3_download_duration_milliseconds` (distribution, tagged by result)
- Buckets: [10, 50, 100, 500, 1000, 5000, 10_000, 30_000, 60_000, 120_000] ms

**Delete Operations**:
- `cache_s3_delete_requests_total` (tagged by result)
- `cache_s3_delete_duration_milliseconds` (distribution, tagged by result)
- Buckets: [10, 50, 100, 500, 1000, 5000, 10_000, 30_000, 60_000] ms

#### 5.2.5 Cache.Authentication.PromExPlugin

- `cache_auth_cache_hit_total`
- `cache_auth_cache_miss_total`
- `cache_auth_server_request_total`
- `cache_auth_server_error_total` (tagged by reason)
- `cache_auth_server_duration_milliseconds` (distribution)
  - Buckets: [10, 25, 50, 100, 250, 500, 1000, 2500, 5000] ms
- `cache_auth_authorized_total` (tagged by method)

#### 5.2.6 Cache.Finch.PromExPlugin

Polls pool status every 15 seconds:

- `cache_prom_ex_finch_pool_available_connections` (tagged by url)
- `cache_prom_ex_finch_pool_in_use_connections` (tagged by url)
- `cache_prom_ex_finch_pool_size` (tagged by url)

#### 5.2.7 Cache.SQLiteBuffer.PromExPlugin

**Event Metrics**:
- `tuist_cache_sqlite_buffer_flush_duration_ms` (distribution)
  - Tagged by: operation, buffer
  - Buckets: [1, 5, 10, 25, 50, 100, 250, 500, 1000, 2000, 5000] ms
- `tuist_cache_sqlite_buffer_flush_batch_size` (sum)
  - Tagged by: operation, buffer

**Polling Metrics** (15-second intervals):
- `tuist_cache_sqlite_buffer_pending_total`
- `tuist_cache_sqlite_buffer_pending_key_values`
- `tuist_cache_sqlite_buffer_pending_cache_artifacts`
- `tuist_cache_sqlite_buffer_pending_s3_transfers`

#### 5.2.8 Cache.S3Transfers.PromExPlugin

Polls S3 transfer queue every 15 seconds:

- `tuist_cache_s3_transfers_pending_uploads`
- `tuist_cache_s3_transfers_pending_downloads`
- `tuist_cache_s3_transfers_pending_total`

### 5.3 Telemetry Handlers

**Location**: `Cache.Telemetry` module

Attaches handlers to specific telemetry events and pushes to event pipelines:

```elixir
def attach do
  cas_events = [
    [:cache, :cas, :download, :disk_hit],
    [:cache, :cas, :download, :s3_hit],
    [:cache, :cas, :upload, :success]
  ]

  gradle_events = [
    [:cache, :gradle, :download, :disk_hit],
    [:cache, :gradle, :upload, :success]
  ]

  :telemetry.attach_many(
    "cache-analytics-handler",
    cas_events ++ gradle_events,
    &Cache.Telemetry.handle_event/4,
    nil
  )
end
```

**Pipelines**:
- `Cache.CASEventsPipeline` - Processes CAS events
- `Cache.GradleCacheEventsPipeline` - Processes Gradle cache events
- `Cache.RegistryDownloadEventsPipeline` - Processes registry download events

### 5.4 OpenTelemetry Integration

**Location**: `Cache.Application.start_opentelemetry/0`

Auto-instruments when `OTEL_EXPORTER_OTLP_ENDPOINT` is configured:

```elixir
defp start_opentelemetry do
  if Application.get_env(:opentelemetry, :traces_exporter) != :none do
    OpentelemetryLoggerMetadata.setup()
    OpentelemetryBandit.setup()
    OpentelemetryPhoenix.setup(adapter: :bandit)
    OpentelemetryEcto.setup(event_prefix: [:cache, :repo])
    OpentelemetryFinch.setup()
    OpentelemetryBroadway.setup()
  end
end
```

**Instrumentation**:
- **Bandit** - HTTP server metrics
- **Phoenix** - Web request/response metrics
- **Ecto** - Database query metrics (both Repo and KeyValueRepo)
- **Finch** - HTTP client metrics
- **Broadway** - Message pipeline metrics

---

## 6. Database Size & Performance Settings

### KeyValue Database Constraints
```
Key Value Database Limits:
- Max size: 25GB (key_value_max_db_size_bytes)
- High watermark: 85% (disk_usage_high_watermark_percent)
- Target capacity: 70% (disk_usage_target_percent)
- Min retention: 1 day (key_value_eviction_min_retention_days)
- Max eviction duration: 300 seconds (key_value_eviction_max_duration_ms)
- Hysteresis release: 23GB (key_value_eviction_hysteresis_release_bytes)
```

### SQLite Performance Tuning
```
WAL Mode:          Enabled (write-ahead logging)
Synchronous:       NORMAL (fsync on commit)
Temp Store:        MEMORY (faster temporary tables)
Page Cache:        64MB (-64_000 pages)
Memory-Mapped I/O: 256MB (mmap_size pragma)
Journal Limit:     64MB (max WAL file size)
Auto Vacuum:       INCREMENTAL (not FULL)
Busy Timeout:      30 seconds (lock wait)
Queue Target:      1000ms (optimization)
```

### Connection Pool Sizing

| Environment | Pool Size | Notes |
|------------|-----------|-------|
| Development | 10 | High for developer iteration |
| Test | `schedulers * 2 + 10` | Scales with CPU cores |
| Production | 2 (default) | Minimal, uses QUEUE_TARGET |

---

## 7. Application Startup

**Location**: `Cache.Application` module

Startup sequence (with migration auto-running):

1. **Migrations** - Auto-run unless `SKIP_MIGRATIONS=true`
2. **Telemetry Handlers** - Attach if analytics enabled
3. **Oban Telemetry** - Default logger for job queue
4. **Sentry Logger** - Optional error tracking
5. **Loki Logger** - Optional centralized logging
6. **OpenTelemetry** - Optional distributed tracing

Supervisor children:
1. `Cache.Repo` - Main SQLite repo
2. `Cache.KeyValueRepo` - Key-value SQLite repo
3. `Cache.KeyValueBuffer` - Key-value buffering
4. `Cache.CacheArtifactsBuffer` - Cache artifacts buffering
5. `Cache.S3TransfersBuffer` - S3 transfer buffering
6. `Cache.PubSub` - Phoenix pub/sub
7. `Cache.Authentication` - Auth services
8. `Cache.S3` - S3 operations
9. `Cache.KeyValueStore` - Key-value store
10. `Cache.MultipartUploads` - Multipart upload tracking
11. `Cache.Registry.Metadata` - Registry metadata
12. `CacheWeb.Endpoint` - HTTP endpoint
13. `Cache.SocketLinker` - Socket linking
14. `Cache.Finch` - HTTP client pools
15. `Cache.PromEx` - Prometheus metrics
16. `Oban` - Job queue
17. (Optional) Analytics pipelines if enabled

---

## Summary

The Tuist Cache service uses:
- **Two independent SQLite databases** (Repo, KeyValueRepo) for local state
- **S3-based distributed locks** for registry synchronization (no Erlang clustering)
- **No data replication between cache nodes** - each node is independent
- **PromEx with 8 custom plugins** for comprehensive metrics
- **Extensive telemetry** via Telemetry and OpenTelemetry
- **SQLite optimizations** for WAL mode, memory caching, and concurrent access
- **Oban.Lite** (SQLite-backed) for job queue instead of full PostgreSQL

This architecture prioritizes simplicity and independent operation of cache nodes while providing extensive observability.
