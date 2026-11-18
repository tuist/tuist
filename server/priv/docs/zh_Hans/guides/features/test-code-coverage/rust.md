---
{
  "title": "Rust 代码覆盖率",
  "titleTemplate": ":title · 代码覆盖率 · 功能 · 指南 · Tuist",
  "description": "上传 Rust 项目 Cargo 测试的行覆盖率，并按文件、包和提交跟踪。"
}
---
# Rust 代码覆盖率 {#rust-code-coverage}

代码覆盖率告诉你测试执行了代码中的哪些行。Tuist 使用 LLVM 的基于源代码的覆盖率来测量每次 `cargo test` 运行的行覆盖率，并将一次提交的所有运行合并为一个数值，涵盖整个项目、每个包以及每个文件。仪表板的 **代码覆盖率** 页面按提交展示该数据，并显示每个分支的趋势。

> [!IMPORTANT]
> **要求**
>
> - 遵循 <.localized_link href="/guides/get-started/rust-project">Rust 项目设置</.localized_link>
> - 你的 Rust 工具链中的 LLVM 工具（`llvm-tools`）。Tuist 会在由 rustup 管理的工具链上安装这些工具。
> - 你的项目位于 Git 仓库中

## 设置 {#setup}

### 开启覆盖率 {#turn-coverage-on}

将此内容添加到仓库根目录下的 `tuist.toml` 中：

```toml
[test_insights.coverage]
upload = true
```

然后照常运行测试：

```sh
tuist cargo test --workspace
```

Tuist 会使用 `-C instrument-coverage` 构建你仓库中的 crate，运行测试，并将覆盖率数据与运行的测试结果一起上传。测试的输出和退出码不会改变。若要覆盖单次运行的设置，请设置 `TUIST_COVERAGE_UPLOAD=1` 或 `TUIST_COVERAGE_UPLOAD=0`。

覆盖率依赖于 Tuist 在每次收集覆盖率的运行时上传的 Git 历史记录，这会将提交关联到其所在的分支。在非 Git 仓库中运行的任务会上传测试结果，但不会上传覆盖率。

### 分片运行 {#sharded-runs}

当你 <.localized_link href="/guides/features/test-sharding/rust">对测试进行分片</.localized_link> 时，每个开启覆盖率的分片都会报告其自身目标的覆盖率，Tuist 会将一次运行的所有分片合并为一个数值。分片有意只运行套件的一部分，因此不会导致提交的覆盖率不完整。

### 在 CI 上完成每次提交 {#complete-each-commit}

一次提交的覆盖率通常来自多个作业：每个分片或每个功能集一个作业。Tuist 无法判断最后一个作业何时完成报告，因此需要你告知它。当一次提交的所有测试作业完成后，在一个依赖于所有这些作业的作业中运行以下命令：

```sh
tuist cargo coverage-complete
```

该命令会从检出内容中读取提交，或者读取你的 CI 提供商在拉取请求中报告的提交；传递 `--commit <sha>` 以指定其他提交。在提交完成之前，其覆盖率将显示为 **进行中**，且不会计入其分支的趋势中。

## 工作原理 {#how-it-works}

### Tuist 测量的内容 {#what-tuist-measures}

- **包。** 每个 Cargo 包都是仪表板上的一个目标，拥有自己的覆盖率。
- **仅产品代码。** 集成测试、基准测试和示例（`tests/`、`benches/` 和 `examples/` 目录，以及此类目标）属于测试代码。Tuist 会存储它们，但在所有统计数值中将其排除。`#[cfg(test)]` 模块中的单元测试是其源文件的一部分，因此它们的行会与该文件一起计数，如同在 `cargo llvm-cov` 中一样。
- **函数。** 每一行都属于其上方最近的函数。无论实例化了多少种类型，泛型函数只计数一次。
- **文档测试** 照常运行，但不进行测量。

Tuist 还会记录每个测试二进制文件执行了哪些代码，以便后续进行基于覆盖率的测试选择。`cargo test` 在一个进程中运行二进制文件的测试，因此该记录属于整个二进制文件，而非其单独的测试。

### 跳过的测试 {#skipped-tests}

当运行自身的参数排除了某些测试时，例如测试名称过滤器、`--skip`、`--ignored`、`-p`、`--exclude`、`--lib` 或 `--test`，提交的覆盖率将标记为 **不完整**，除非该提交还有另一个未排除任何内容的运行也已完成。如果在每个测试二进制文件运行之前，故障就导致 `cargo test` 停止，也会产生相同的效果。添加 `--no-fail-fast` 以继续运行剩余的二进制文件。

某些测试是有意排除的，不会导致提交不完整：

- **被 <.localized_link href="/guides/features/test-insights/flaky-tests/rust">隔离</.localized_link> 跳过的测试。** 它们被排除在外，如同已被删除，因此仅由它们覆盖的行将被计为未覆盖。
- **其他分片的目标**，当你对测试进行分片时。
- **被忽略的测试**（`#[ignore]`），默认情况下不运行。

### 完整和不完整的提交 {#commit-status}

仪表板上的每个提交都有一个状态：

| 状态 | 含义 |
| --- | --- |
| 进行中 | 运行已报告覆盖率，但尚未针对该提交运行 `tuist cargo coverage-complete`。 |
| 完整 | 该提交的所有运行中的每个测试都已运行，或是有意排除。 |
| 不完整 | 部分覆盖率无法确定，因此该数值为下限。 |
| 未测量 | 没有运行报告该提交的覆盖率。 |

分支的趋势仅包含完整的提交。

## 性能影响 {#performance-impact}

插桩代码的运行速度会稍慢一些。Tuist 仅对你的仓库中的 crate 进行插桩：依赖项的构建方式与常规构建完全相同，并继续从缓存中获取。Tuist 会在目标目录中保留你自己 crate 的两种变体，因此在有无覆盖率的运行之间切换时，除非代码发生更改，否则不会重新构建它们。

## 限制 {#limitations}

- **带有特定目标 `rustflags` 的自定义 `rustc-wrapper`。** 当你的项目设置自己的 `rustc-wrapper` 时，Tuist 会将 `-C instrument-coverage` 添加到 Cargo 的 `build.rustflags` 中作为替代。Cargo 配置文件中的 `target.<triple>.rustflags` 条目会替换它们，因此请自行在那里添加该标志。如果运行的测试未写入任何覆盖率数据，系统会相应提示。
- **已配置的目标运行器。** Tuist 通过其自身的运行器启动测试二进制文件。Cargo 配置文件中的 `target.<triple>.runner` 会取代它：运行的覆盖率仍会被上传，但 Tuist 无法确定哪个测试二进制文件执行了哪些内容。通过 `CARGO_TARGET_<TRIPLE>_RUNNER` 环境变量设置的运行器仍可正常工作。
- **来自 fork 的拉取请求不提供覆盖率。** 只有经过 Tuist 身份验证的运行才会上传覆盖率，而 CI 通常会阻止来自 fork 的拉取请求访问密钥和身份令牌。

## 查询覆盖率 {#querying}

仪表板的 **代码覆盖率** 页面显示每个提交的数值、其包及其文件，以及每个文件包含的函数。代理可以通过 <.localized_link href="/guides/features/agentic-coding/mcp">模型上下文协议服务器</.localized_link> 访问相同的数据。
