---
{
  "title": "Struo 测试分片",
  "titleTemplate": ":title · 测试分片 · 功能 · 指南 · Tuist",
  "description": "通过 Tuist 规划 Struo 测试批次，将其分发到 CI 工作节点，并检查合并后的测试运行结果。"
}
---
# Struo 测试分片 {#struo-test-sharding}

<a id="once-test-sharding"></a>

当你的测试套件规模超出单台机器的承载能力时，Struo 可以请求 Tuist 将已发现的测试批次分发到 CI 工作节点。工作节点通过 Struo 执行分配的任务，Tuist 则将它们的报告合并为一次测试运行。

> [!IMPORTANT]
> **要求**
>
> - 完成<.localized_link href="/guides/get-started/struo-project">Struo 入门指南</.localized_link>。
> - 使用 [Struo 1.0.0](https://github.com/tuist/struo/releases/tag/1.0.0) 或更高版本，并配合 `struo query test-plan --shards` 和 `struo test --shard-plan`。
> - 确保对选定的测试目标进行完整发现，并且在工作节点上提供相同的代码检出和测试环境。

无需 Tuist CLI 包装器。Struo 使用其原生的 Tuist 提供程序和凭据。

## 发现你的测试 {#discover-your-tests}

在规划之前运行选定的测试以建立发现：

```bash
struo test MyTests --format json
```

可用的批次粒度取决于运行器。某些测试目标支持文件或用例级别的批次；其他则保持在目标级别。请参阅[Struo 测试指南](https://struo.run/docs/guide/graph/testing)了解发现和分批功能。

## 创建托管计划 {#create-a-hosted-plan}

在规划作业中，使用此次 CI 执行共享的引用：

```bash
struo query test-plan --shards 4 --reference "$CI_EXECUTION_ID" --format json
```

响应包含一个托管计划 ID 和实际的工作节点索引：

```json
{"shard_plan_id":"<UUID>","shards":[0,1,2,3]}
```

根据 `shards` 构建你的 CI 矩阵，而不是假设它包含四个条目。空计划会返回空的 ID 和数组，因此无需启动任何工作节点。传递 `--target` 以缩小计划范围，或重复 `--changed-path` 以使用 Struo 基于图的选择。

引用默认为 `TUIST_SHARD_REFERENCE` 或检测到的 CI 运行。当环境中没有受支持的 CI 标识符时，请显式传递它。

## 执行每个分片 {#execute-each-shard}

向每个工作节点提供返回的计划 ID 及其自身的索引：

```bash
struo test --shard-plan "$SHARD_PLAN_ID" --shard-index "$SHARD_INDEX" --jobs 4
```

或者，设置 `TUIST_SHARD_PLAN_ID` 和 `TUIST_SHARD_INDEX`。工作节点下载精确绑定 UUID 的计划，并仅执行分配给它们的批次。空分配不运行任何内容；缺失的结果、失败的进程和中断的工作无法通过分区。

这分发的是测试计划，而非预编译的测试构建归档。在工作节点上准备所需的源码、工具和发现；共享缓存可以避免重复符合条件的构建工作。

## 重跑和结果 {#reruns-and-results}

对于重跑，增加 `--shard-attempt`，或设置 `TUIST_SHARD_ATTEMPT`。否则，Struo 会使用 GitHub 运行尝试次数，然后默认为 1。`--shard-report-revision` 默认为 0，并在同一尝试内修正报告时可以增加。这些计数器与测试的重试是分开的。

打开**测试 → 分片**以检查计划、平衡情况和报告的工作节点，然后打开组合测试运行以查看个别结果。Struo 的调度单元标记为**批次**；用例保留其原生的目标、套件和测试名称。

请参阅<.localized_link href="/guides/features/test-insights/struo">Struo 测试洞察</.localized_link>了解报告详情和覆盖范围限制。
