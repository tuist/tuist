### Build options {#build-options}

| Flag | Environment variable | Description |
|------|---------------------|-------------|
| `--shard-max <N>` | `TUIST_TEST_SHARD_MAX` | Maximum number of shards. Used with `--shard-max-duration` to cap the shard count |
| `--shard-min <N>` | `TUIST_TEST_SHARD_MIN` | Minimum number of shards |
| `--shard-total <N>` | `TUIST_TEST_SHARD_TOTAL` | Exact number of shards (mutually exclusive with `--shard-min`/`--shard-max`). With suite granularity, the final shard is the catch-all |
| `--shard-max-duration <MS>` | `TUIST_TEST_SHARD_MAX_DURATION` | Target maximum duration per shard in milliseconds |
| `--shard-granularity <LEVEL>` | `TUIST_TEST_SHARD_GRANULARITY` | `module` (default) distributes entire test modules across shards; `suite` distributes individual test classes for finer-grained balancing |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | Unique identifier for the shard plan (auto-derived on supported CI providers) |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | Path where Tuist writes the optimized shard archive instead of uploading test products to remote storage |
