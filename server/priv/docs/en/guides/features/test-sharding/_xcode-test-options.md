### Test options {#test-options}

| Flag | Environment variable | Description |
|------|---------------------|-------------|
| `--shard-index <N>` | `TUIST_SHARD_INDEX` | Zero-based index of the shard to execute |
| `--shard-plan-id <IDENTIFIER>` | `TUIST_SHARD_PLAN_ID` | Exact shard plan identifier emitted by the build phase. Generated provider outputs include this value automatically |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | Unique identifier for the shard plan (auto-derived on supported CI providers) |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | Path to a locally managed shard archive; Tuist extracts it instead of downloading test products from remote storage |

Tuist downloads the `.xctestproducts` bundle and filters it to include only the tests assigned to that shard.
