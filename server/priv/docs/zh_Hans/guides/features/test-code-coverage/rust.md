---
{
  "title": "Rust 代码覆盖率",
  "titleTemplate": ":title · 代码覆盖率 · 功能 · 指南 · Tuist",
  "description": "上传 Rust 项目 Cargo 测试的行覆盖率，并按文件、包和提交跟踪。"
}
---
# Rust 代码覆盖率 {#rust-code-coverage}

代码覆盖率告诉你测试执行了代码中的哪些行。Tuist 使用 LLVM 的基于源码的覆盖率测量每次 `cargo test` 运行的行覆盖率，并将一个提交的多次运行合并为一个数据，涵盖项目、每个包和每个文件。仪表板的 **代码覆盖率** 页面按提交显示该数据，并展示每个分支的趋势。

> [!IMPORTANT]
> **要求**
>
> - 遵循 <.localized_link href="/guides/get-started/rust-project">Rust 项目设置</.localized_link>
> - 你的 Rust 工具链中的 LLVM 工具（`llvm-tools`）。Tuist 会在 rustup 管理的工具链上安装这些工具。
> - 你的项目位于 Git 仓库中

## 设置 {#setup}

### 开启覆盖率 {#turn-coverage-on}

将此添加到工作区根目录的 `Cargo.toml`：

```toml
[workspace.metadata.tuist.test_insights.coverage]
upload = true
```

如果你改为在 `tuist.toml` 中配置 Tuist，请在那里添加 `[test_insights.coverage]` 并设置 `upload = true`。

然后照常运行测试：

```sh
tuist cargo test --workspace
```

Tuist 使用 `-C instrument-coverage` 构建你仓库中的 crate，运行测试，并将覆盖率连同运行的测试结果一起上传。测试的输出和退出代码不会改变。要覆盖单次运行的设置，请设置 `TUIST_COVERAGE_UPLOAD=1` 或 `TUIST_COVERAGE_UPLOAD=0`。

覆盖率依赖于 Tuist 在每次收集覆盖率的运行时上传的 Git 历史记录，这会将提交关联到其分支。在非 Git 仓库中的运行会上传测试结果，但不会上传覆盖率。从提交检出而非分支检出的运行没有分支，也不会将提交关联到分支；在 Tuist 无法识别的 CI 系统上，请使用 `TUIST_GIT_BRANCH` 指定分支名称，如 <.localized_link href="/guides/features/test-insights/rust#continuous-integration">持续集成</.localized_link> 所述。

### 分片运行 {#sharded-runs}

当你 <.localized_link href="/guides/features/test-sharding/rust">分片运行测试</.localized_link> 时，每个开启覆盖率的分片都会报告其自身目标的覆盖率，Tuist 会将一次运行的各个分片合并为一个数据。分片有意只运行套件的一部分，因此不会导致提交的覆盖率不完整。

### 在 CI 上完成每个提交 {#complete-each-commit}

一个提交的覆盖率通常来自多个作业：每个分片或每组功能一个作业。Tuist 无法判断最后一个作业何时报告完成，因此需要你告知它。当某个提交的所有测试作业完成后，在一个依赖于所有这些作业的作业中运行以下命令：

```sh
tuist coverage complete
```

该命令从检出的 `HEAD` 读取提交，即你的测试所运行的提交；传递 `--commit <sha>` 以指定其他提交。在提交完成之前，其覆盖率显示为 **进行中**，且不计入分支趋势。

## 工作原理 {#how-it-works}

### Tuist 测量的内容 {#what-tuist-measures}

- **包。** 每个 Cargo 包都是仪表板上的一个目标，拥有自己的覆盖率数据。
- **仅产品代码。** 集成测试、基准测试和示例（`tests/`、`benches/` 和 `examples/` 目录，以及此类目标）属于测试代码。Tuist 会存储它们，但不将其计入任何数据。`#[cfg(test)]` 模块中的单元测试是其源文件的一部分，因此它们的行会与源文件一起计数，如同在 `cargo llvm-cov` 中一样。
- **函数。** 每一行归属于其上方最近的函数。无论实例化了多少种类型，泛型函数只计数一次。
- **文档测试** 照常运行，但不进行测量。

Tuist 还会记录每个测试二进制文件执行了哪些代码，以便后续进行基于覆盖率的测试选择。`cargo test` 在一个进程中运行二进制文件的测试，因此该记录属于整个二进制文件，而非其单个测试。

### 跳过的测试 {#skipped-tests}

当运行自身的参数排除了某些测试时，例如测试名称过滤器、`--skip`、`--ignored`、`-p`、`--exclude`、`--lib` 或 `--test`，提交的覆盖率将显示为 **不完整**，除非该提交还有另一个未排除任何内容的运行也已完成。如果在所有测试二进制文件运行之前，`cargo test` 因失败而停止，也会产生相同的效果。添加 `--no-fail-fast` 以继续运行剩余的二进制文件。

有些测试是有意排除的，不会导致提交不完整：

- **被 <.localized_link href="/guides/features/test-insights/flaky-tests/rust">隔离</.localized_link> 跳过的测试。** 它们被视为已移除，因此仅由它们覆盖的行计为未覆盖。
- **其他分片的目标**，当你分片运行测试时。
- **忽略的测试**（`#[ignore]`），默认情况下不运行。

### 未提交的更改 {#uncommitted-changes}

如果检出的跟踪文件存在未提交的更改，则运行测量的是非提交状态的代码，因此其覆盖率不计入该提交。运行时会发出警告并列出更改的文件。CI 作业在源代码旁边写入的文件（如构建输出或覆盖率报告），只要 Git 未跟踪它们，就不算作更改。如果只有此类运行测量了某个提交，其覆盖率将显示为 **不完整**，且 `tuist coverage complete` 会说明原因。

### 完整和不完整的提交 {#commit-status}

仪表板上的每个提交都有一个状态：

| 状态 | 含义 |
| --- | --- |
| 进行中 | 已有运行报告了覆盖率，但尚未对该提交运行 `tuist coverage complete`。 |
| 完整 | 该提交的所有运行中的测试均已执行，或是有意排除。 |
| 不完整 | 部分覆盖率无法确定，因此该数值为下限。 |
| 未测量 | 没有运行报告该提交的覆盖率。 |

分支的趋势仅包含完整的提交。

## 性能影响 {#performance-impact}

插桩后的代码运行速度会稍慢。Tuist 仅对你仓库中的 crate 进行插桩：依赖项的构建方式与常规构建完全相同，并继续从缓存中获取。Tuist 会在目标目录中保留你自己 crate 的两种变体，因此在开启和关闭覆盖率的运行之间切换时，除非代码发生更改，否则不会重新构建它们。

## 限制 {#limitations}

- **带有特定目标 `rustflags` 的自定义 `rustc-wrapper`**。当你的项目设置了自己的 `rustc-wrapper` 时，Tuist 会将 `-C instrument-coverage` 添加到 Cargo 的 `build.rustflags` 中。Cargo 配置文件中的 `target.<triple>.rustflags` 条目会替换它们，因此请自行在那里添加该标志。如果运行的测试未写入任何覆盖率数据，系统会予以提示。
- **已配置的目标运行器。** Tuist 通过其自身的运行器启动测试二进制文件。Cargo 配置文件中的 `target.<triple>.runner` 会取代它：运行的覆盖率仍会被上传，但 Tuist 无法得知哪个测试二进制文件执行了哪些内容。通过 `CARGO_TARGET_<TRIPLE>_RUNNER` 环境变量设置的运行器仍可正常工作。
- **来自 Fork 的拉取请求无覆盖率数据。** 只有经过 Tuist 身份验证的运行才会上传覆盖率，而 CI 通常会扣留来自 Fork 的拉取请求的秘密信息和身份令牌。

## 查询覆盖率 {#querying}

仪表板的 **代码覆盖率** 页面显示每个提交的数值、其包和文件，以及每个文件包含的函数。代理可以通过 <.localized_link href="/guides/features/agentic-coding/mcp">模型上下文协议服务器</.localized_link> 访问相同的数据。
