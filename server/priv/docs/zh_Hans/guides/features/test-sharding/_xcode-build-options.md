### 构建选项 {#build-options}

| 标志 | 环境变量 | 说明 |
|------|---------------------|-------------|
| `--shard-max <N>` | `TUIST_TEST_SHARD_MAX` | 最大分片数。与 `--shard-max-duration` 配合使用以限制分片数量 |
| `--shard-min <N>` | `TUIST_TEST_SHARD_MIN` | 最小分片数 |
| `--shard-total <N>` | `TUIST_TEST_SHARD_TOTAL` | 确切的分片数（与 `--shard-min`/`--shard-max` 互斥）。使用套件粒度时，最后一个分片为兜底分片 |
| `--shard-max-duration <MS>` | `TUIST_TEST_SHARD_MAX_DURATION` | 每个分片的目标最大持续时间（毫秒） |
| `--shard-granularity <LEVEL>` | `TUIST_TEST_SHARD_GRANULARITY` | `module`（默认）将整个测试模块分配到各个分片；`suite` 将单个测试类分配到各个分片，以实现更细粒度的平衡 |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | 分片计划的唯一标识符（在支持的 CI 提供商上自动派生） |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | Tuist 写入优化后的分片归档的路径，而非将测试产物上传到远程存储 |
