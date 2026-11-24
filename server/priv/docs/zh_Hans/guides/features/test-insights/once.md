---
{
  "title": "Once 测试洞察",
  "titleTemplate": ":title · 测试洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 仪表盘中检查 Once 测试套件、单个结果、失败情况和耗时。"
}
---
# Once 测试洞察 {#once-test-insights}

Once 将测试结果上报给 Tuist，以便你在本地和 CI 运行中跟踪测试套件、排查失败并找出缓慢的测试，而无需从各个工作节点收集报告。

> [!IMPORTANT]
> **要求**
>
> - 完成<.localized_link href="/guides/get-started/once-project">开始使用 Once</.localized_link>。
> - 使用能够报告结构化结果的测试目标。可用详细程度取决于目标类型和测试运行器。

## 上报你的测试运行 {#report-your-test-runs}

运行整个测试套件或选择某个目标：

```bash
once test
once test MyTests
```

Once 流式传输原生测试事件，并将已完成的结果发布到 Tuist 的共享测试模型中。**测试**和**测试运行**会显示这些运行；单个用例也有共享的测试历史。<.localized_link href="/guides/features/test-sharding/once">托管分片运行</.localized_link>会将每个工作节点的报告合并为一次运行，而不是再次统计其诊断事件流。

## 跟踪内容 {#what-is-tracked}

- 已上报的测试目标、套件和单个用例。
- 通过、失败和跳过的结果，以及在运行器提供时的耗时。
- 在托管分片报告中由运行器提供的失败消息。
- 当测试先失败后通过时，有序的重试尝试和不稳定测试结果。
- 由 Once 提供的分支、提交和 CI 上下文。

测试标识使用原生的目标、套件和用例名称。分片批次 ID 是调度单元，而非测试名称。

普通的 `once test` 上报会保留结果和重试尝试，但目前不会在共享测试历史中包含失败消息。托管分片报告可以包含失败消息，但两种上报路径都不提供源代码位置。请保留你的 CI 日志，以获取 Tuist 中不可用的诊断信息。

并非每个测试目标都提供相同的详细信息。有些运行器会报告单个用例，有些仅报告摘要；精确的文件或用例执行是单独的功能。在依赖按用例分析或细粒度调度之前，请参阅[Once 的测试生态系统覆盖范围](https://buildonce.dev/docs/guide/graph/testing#understand-current-ecosystem-coverage)。

## 不稳定测试 {#flaky-tests}

Tuist 使用上报的尝试次数和 CI 历史记录来识别不一致的结果。上报尝试并不等同于启用重试：请在支持重试的运行器中配置重试。有关检测和当前的隔离边界，请参阅<.localized_link href="/guides/features/test-insights/flaky-tests/once">Once 不稳定测试</.localized_link>。

## 选择与代码覆盖率 {#selection-and-code-coverage}

Once 可以使用 `--changed-path` 从其本地图中保守地选择测试。这是 Once 自身的选择，而非 Tuist 的基于覆盖率的托管测试选择：

```bash
once test --changed-path src/library.rs
```

原生 Once 上报目前不会将代码覆盖率上传到 Tuist。成功的测试报告或分片计划不会填充“代码覆盖率”仪表板。

## 故障排除 {#troubleshooting}

如果缺少某次运行，请检查有效的缓存提供者是否指向你的 Tuist 项目，并使用 `once auth login --provider tuist` 重新进行身份验证。实时上报尽力而为，当上报服务不可用时，不会将原本成功的测试命令变为失败。

运行摘要和结构化测试失败并不是完整的进程日志。此服务器目前不会摄取 Once 的原始操作日志流；请保留你的 CI 日志，以获取未包含在结构化结果中的输出。
