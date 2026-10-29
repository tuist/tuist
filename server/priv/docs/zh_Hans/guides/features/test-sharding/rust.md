---
{
  "title": "Rust Test Sharding",
  "titleTemplate": ":title · Test Sharding · Features · Guides · Tuist",
  "description": "Distribute Cargo test targets across CI workers using historical test durations."
}
---
# Rust 测试分片 {#rust-test-sharding}

Tuist 使用历史目标耗时，将 Cargo 测试目标分配到 CI 工作节点上。单元测试目标、集成测试目标以及每个库的文档测试都是独立的模块。同一目标内的测试保持在一起。

> [!IMPORTANT] Requirements
> - 配置 <.localized_link href="/guides/features/test-insights/rust">Rust Test Insights</.localized_link>，并在规划任务和工作节点上对 CLI 进行身份验证。
> - 在工作区中使用 `-p <package>` 选择一个包。不支持多包分片。
> - 在每个任务中使用相同的修订版本、Rust 工具链、包选择、特性以及测试过滤器。

## 创建计划 {#create-a-plan}

向 `--no-run` 添加分片数量，以编译和枚举目标而不执行测试：

```sh
TUIST_SHARD_REFERENCE=my-ci-run tuist cargo test -p store --no-run --shard-max 4
```

该命令会打印包含 `shard_plan_id` 和从零开始的 `shards` 数组的 JSON。在 GitHub Actions 中，它还会将 `shard-plan-id` 和 `shards` 写入 `GITHUB_OUTPUT`。如果没有显式引用，Tuist 会从受支持的 CI 环境中派生一个引用。

| 选项 | 描述 |
| --- | --- |
| `--shard-max N` | 最大分片数 |
| `--shard-min N` | 最小分片数 |
| `--shard-total N` | 精确数量，最多为可用目标数 |
| `--shard-max-duration N` | 目标最大分片持续时间（毫秒） |

单独使用 `--shard-total`，或组合使用 `--shard-min` 和 `--shard-max`。如果没有历史耗时数据，规划器会使用默认的目标估算值。不带分片选项的普通 `--no-run` 仍然是仅构建命令。

## 执行每个分片 {#execute-each-shard}

在每个工作节点上设置计划 ID 和分片索引，然后使用相同的 Cargo 测试参数：

```sh
TUIST_SHARD_PLAN_ID=<plan-id> TUIST_SHARD_INDEX=0 tuist cargo test -p store
```

或者，将 `TUIST_SHARD_REFERENCE` 设置为规划任务的引用，而不是传递计划 ID。Tuist 会获取分配结果，并要求 Cargo 仅执行这些目标。无效或不兼容的分配会导致命令失败，而不会运行所有测试。空分配不执行任何测试。来自工作节点的结果会在 Test Insights 中与计划关联，并且 <.localized_link href="/guides/features/test-insights/flaky-tests/rust#quarantine">隔离</.localized_link> 适用于每个分片内。

## 限制 {#limits}

这是目标级别的分片，而非一次构建分发。每个工作节点都需要源代码检出并构建自己的目标；<.localized_link href="/guides/features/cache/rust">Cargo 编译缓存</.localized_link> 可以复用符合条件的编译输出。Tuist 不会上传测试可执行文件，也不需要其他 Rust 测试运行器。

分片需要选择一个包。缩小多包命令的范围可能会改变 Cargo 的统一依赖特性，因此 Tuist 会拒绝该操作，而不是使用不同的特性图运行测试。在支持多包分片之前，请分别规划每个包。

分片需要标准的 libtest 测试 harness 和捕获的默认输出。静默、详细、备用格式、未捕获输出和自定义 harness 命令会被拒绝。如果 Cargo 无法唯一标识某个目标，请使用 `-p <package>` 选择确切的工作区包。依赖包、带版本限定符的选择器、包/目标名称通配符以及 Cargo 的夜间版 `-C` 选项不支持用于分片。在规划和执行之间保持测试选择一致。
