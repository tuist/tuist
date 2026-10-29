---
{
  "title": "Rust Test Insights",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Track Cargo test results, including Rust doctests, in the Tuist dashboard."
}
---
# Rust 测试洞察 {#rust-test-insights}

Tuist 报告来自 `cargo test` 的单个测试结果，包括单元测试、集成测试和文档测试。无需任何 Rust 依赖项或额外的测试运行器。

> [!IMPORTANT] Requirements
> - 遵循 <.localized_link href="/guides/get-started/rust-project">Rust 项目设置</.localized_link>。

## 报告您的测试运行 {#report-your-test-runs}

```sh
tuist cargo test --workspace
```

配置好 mise Cargo 包装器后，您可以继续输入 `cargo test`。Cargo 仍会使用其常规参数、输出和退出代码来编译并运行您的测试。报告失败不会改变您的测试结果。

您可以像往常一样选择包或过滤测试：

```sh
tuist cargo test -p store
tuist cargo test authentication
```

## Tuist 跟踪的内容 {#what-is-tracked}

- 已完成测试套件中通过、失败和忽略的测试。
- 单元测试、集成测试和文档测试。
- 整个套件的持续时间。
- 可用的分支、提交、CI 和运行器元数据。

经过过滤的测试以及在失败后未执行的测试永远不会被报告为通过。结果会显示在仪表板的 **测试** 下。

## 包、模块和测试用例 {#test-hierarchy}

Tuist 按 Cargo 包和目标对结果进行分组。Rust 模块路径将目标内的各个测试分组：

| 仪表板标签 | Rust 含义 | 示例 |
| --- | --- | --- |
| 模块 | Cargo 包和目标 | `store::api` |
| 测试套件 | Rust 模块路径 | `api::authentication` |
| 测试用例 | 单个测试 | `rejects_invalid_token` |

文档测试使用单独的模块，例如 `store::doctest/store`。它们的名称包含源位置，因此移动示例可能会更改其标识。

## 文档测试和持续时间 {#cargo-test}

文档测试随您常用的测试命令一起运行，包括 `compile_fail`、`should_panic` 和 `no_run` 示例。要仅运行文档测试：

```sh
tuist cargo test --doc
```

稳定的 libtest 报告整个套件的时间，但不报告单个测试的持续时间。不可用的计时信息将从每个用例的持续时间历史记录和持续时间分析中排除，而测试结果仍会影响可靠性和运行次数。

## 报告限制 {#reporting-limits}

单个结果是从 Cargo/libtest 的默认输出中收集的。使用 `--no-run`、`--list`、静默或 Cargo 详细输出、替代格式或未捕获的测试输出的命令会正常运行，但不会报告单个测试。自定义测试工具、不完整的摘要、模糊的目标归属以及过大的报告不会上传。

如果工作区包具有同名的集成目标，请使用 `-p <package>` 选择其中一个。报告支持精确的工作区包名称；依赖包、版本限定选择器和通配符会正常执行，但不会被报告。绝对文档测试路径会被省略，以避免将检出路径纳入测试标识。

Tuist 在收集结果时会流式传输输出。这可能会影响自动颜色检测。在 Cargo 退出后保持输出管道打开的后台进程可能导致报告被省略，但不会改变 Cargo 的退出状态。

## 可靠性和选择 {#reliability-and-selection}

使用 <.localized_link href="/guides/features/test-insights/flaky-tests/rust">不稳定测试检测和隔离</.localized_link> 来调查不稳定的测试并将其静音或跳过。<.localized_link href="/guides/features/test-sharding/rust">测试分片</.localized_link> 将整个 Cargo 目标分布到 CI 工作器上。覆盖率摄取、基于覆盖率的测试选择和一次构建分发不适用于普通的 Cargo 测试运行。

## 故障排除 {#troubleshooting}

如果测试运行未出现在仪表板中，请启用调试输出以查看其报告未发送的原因：

```sh
TUIST_DEBUG=1 tuist cargo test --workspace
```
