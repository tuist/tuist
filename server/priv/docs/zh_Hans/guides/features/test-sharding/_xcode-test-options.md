### 测试选项 {#test-options}

| 标志 | 环境变量 | 描述 |
|------|---------------------|-------------|
| `--shard-index <N>` | `TUIST_SHARD_INDEX` | 要执行的分片的从零开始索引 |
| `--shard-plan-id <IDENTIFIER>` | `TUIST_SHARD_PLAN_ID` | 构建阶段发出的确切分片计划标识符。生成的提供程序输出会自动包含此值 |
| `--shard-reference <REF>` | `TUIST_SHARD_REFERENCE` | 分片计划的唯一标识符（在支持的 CI 提供程序上自动派生） |
| `--shard-archive-path <PATH>` | `TUIST_TEST_SHARD_ARCHIVE_PATH` | 本地管理的分片归档文件路径；Tuist 会提取该文件，而不是从远程存储下载测试产品 |

Tuist 下载 `.xctestproducts` 捆绑包并对其进行过滤，仅包含分配给该分片的测试。
