---
{
  "title": "Rust 测试洞察",
  "titleTemplate": ":title · 测试洞察 · 功能 · 指南 · Tuist",
  "description": "在 Tuist 仪表板中跟踪 Cargo 测试结果，包括 Rust 文档测试。"
}
---
# Rust 测试洞察 {#rust-test-insights}

Tuist 会报告来自 `cargo test` 的单个测试结果，包括单元测试、集成测试和文档测试。无需任何 Rust 依赖或额外的测试运行器。

> [!IMPORTANT]
> **要求**
>
> - 请按照 <.localized_link href="/guides/get-started/rust-project">Rust 项目设置</.localized_link> 进行操作。

## 报告你的测试运行 {#report-your-test-runs}

```sh
tuist cargo test --workspace
```

配置好 mise Cargo 包装器后，你可以继续输入 `cargo test`。Cargo 仍会使用其常规参数、输出和退出码来编译并运行你的测试。报告失败不会改变你的测试结果。

你可以像往常一样选择包或过滤测试：

```sh
tuist cargo test -p store
tuist cargo test authentication
```

## Tuist 跟踪的内容 {#what-is-tracked}

- 已完成测试套件中通过、失败和被忽略的测试。
- 单元测试、集成测试和文档测试。
- 整个套件的持续时间。
- 可用的分支、提交、CI 和运行器元数据。

被过滤的测试以及在失败后未执行的测试永远不会被报告为通过。结果会显示在仪表板的 **测试** 下。

## 持续集成 {#continuous-integration}

Tuist 可识别 GitHub Actions、GitLab CI、Bitrise、CircleCI、Buildkite 和 Codemagic，并将每次运行链接到其 CI 作业。在任何其他 CI 系统上，当设置了 `CI` 环境变量时，一次运行会被计为 CI 运行。大多数 CI 系统都会设置它；在未设置的系统（例如 Fly.io Machines）上，你需要自行设置。不稳定测试检测仅比较 CI 运行。

如果作业检出的是提交而不是分支，Git 将没有可命名的分支，因此其运行没有分支信息。在 Tuist 识别的 CI 系统上，分支信息由提供商提供。在其他情况下，请使用 `TUIST_GIT_BRANCH` 指定分支名称：

```sh
CI=true TUIST_GIT_BRANCH=main tuist cargo test --workspace
```

## 包、模块和测试用例 {#test-hierarchy}

Tuist 按 Cargo 包和目标对结果进行分组。Rust 模块路径将目标内的单个测试分组：

| 仪表板标签 | Rust 含义 | 示例 |
| --- | --- | --- |
| 模块 | Cargo 包和目标 | `store::api` |
| 测试套件 | Rust 模块路径 | `api::authentication` |
| 测试用例 | 单个测试 | `rejects_invalid_token` |

文档测试使用单独的模块，例如 `store::doctest/store`。它们的名称包含源位置，因此移动示例可能会改变其标识。

## 文档测试和持续时间 {#cargo-test}

文档测试随你常用的测试命令一起运行，包括 `compile_fail`、`should_panic` 和 `no_run` 示例。要仅运行文档测试：

```sh
tuist cargo test --doc
```

稳定的 libtest 报告整个套件的时间，但不报告单个测试的持续时间。不可用的计时数据会从每个用例的持续时间历史记录和持续时间分析中排除，而测试结果仍会贡献于可靠性和运行次数统计。

## 报告限制 {#reporting-limits}

单个结果是从 Cargo/libtest 的默认输出中收集的。使用 `--no-run`、`--list`、静默或 Cargo 详细输出、替代格式或未捕获的测试输出的命令会正常运行，但不会报告单个测试。自定义测试 harness、不完整的摘要、模糊的目标归属以及过大的报告不会被上传。

如果工作区包具有同名的集成目标，请使用 `-p <package>` 选择其中一个。报告支持精确的工作区包名称；依赖包、带版本限定符的选择器和通配符会正常执行，但不会被报告。绝对文档测试路径会被省略，以避免将检出路径纳入测试标识。

Tuist 在收集结果时会流式传输输出。这可能会影响自动颜色检测。在 Cargo 退出后仍保持输出管道打开的后台进程可能导致报告被省略，但不会改变 Cargo 的退出状态。

## 可靠性和选择 {#reliability-and-selection}

使用 <.localized_link href="/guides/features/test-insights/flaky-tests/rust">不稳定测试检测和隔离</.localized_link> 来调查不稳定的测试，并将其静音或跳过。<.localized_link href="/guides/features/test-sharding/rust">测试分片</.localized_link> 会将整个 Cargo 目标分布到 CI 工作节点上。开启 <.localized_link href="/guides/features/test-code-coverage/rust">代码覆盖率</.localized_link> 以跟踪测试运行的行覆盖率。基于覆盖率的测试选择和一次性构建分布不适用于普通的 Cargo 测试运行。

## 故障排除 {#troubleshooting}

如果测试运行未出现在仪表板中，请启用调试输出以查看其报告未发送的原因：

```sh
TUIST_DEBUG=1 tuist cargo test --workspace
```
