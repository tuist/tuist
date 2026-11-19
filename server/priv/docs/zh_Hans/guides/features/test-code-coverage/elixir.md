---
{
  "title": "Elixir 代码覆盖率",
  "titleTemplate": ":title · 代码覆盖率 · 功能 · 指南 · Tuist",
  "description": "使用 mix test --cover 上传 Elixir 项目的行覆盖率，并按文件、按应用和按提交跟踪。"
}
---
# Elixir 代码覆盖率 {#elixir-code-coverage}

代码覆盖率告诉你测试执行了代码中的哪些行。Hex 包会上传每次 `mix test --cover` 运行的行覆盖率，Tuist 会将一个提交的所有运行合并为一个数值，涵盖整个项目、每个 OTP 应用以及每个文件。仪表板的 **代码覆盖率** 页面按提交展示该数据，并显示每个分支的趋势。

> [!IMPORTANT]
> **要求**
>
> - 完成 <.localized_link href="/guides/get-started/elixir-project">共享的 Elixir 设置</.localized_link>，该设置会将 `mix test` 通过包进行路由

## 设置 {#setup}

### 带覆盖率运行测试 {#run-your-tests}

传递 `--cover`，就像在没有 Tuist 的情况下对 `mix test` 所做的那样：

```sh
mix test --cover
```

该包会随运行的测试结果一起上传覆盖率。当套件完成后，它还会执行 Mix 覆盖率工具的操作，并使用相同的 `test_coverage` 选项进行配置：

- **摘要。** 它会打印每个模块的覆盖率和总计。`summary: false` 可将其关闭。
- **阈值。** 当总计低于阈值时，运行将以退出状态 3 失败；除非你另行设置，否则阈值为 90%：

```elixir
def project do
  [
    test_coverage: [summary: [threshold: 80]]
  ]
end
```

与 Mix 一样，阈值属于摘要部分，因此 `summary: false` 会同时关闭两者。要在不导致运行失败的情况下打印摘要，请设置 `threshold: 0`。`test_coverage: [ignore_modules: [...]]` 中列出的模块将从摘要和上传中排除。

Tuist 按提交跟踪覆盖率，因此需要你的项目位于 Git 仓库中：在非 Git 环境中的运行会上报测试结果，但不会上报覆盖率。

覆盖率依赖于包上传的 <.localized_link href="/guides/features/test-insights/elixir#git-history">Git 历史</.localized_link>，这会将提交放置在其分支上。持续集成上的运行始终会上报它，而 `--cover` 运行会在任何机器上上报它。使用 `--cover` 时，包还会查找拉取请求的分叉点：它会获取基础分支并根据需要加深浅克隆。在持续集成中，浅检出也会被加深（不包含文件内容），直到达到 Tuist 已拥有的提交，因此提交绝不会在没有其父提交的情况下上传。设置 `TUIST_GIT_UNSHALLOW_ENABLED=false` 以防止其联系远程仓库。

### 分片运行 {#sharded-runs}

当你 <.localized_link href="/guides/features/test-sharding/elixir">对测试进行分片</.localized_link> 时，请使用 `--cover` 运行每个分片：

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix tuist.test --cover
```

在全新的运行器上，使用分片指南中 <.localized_link href="/guides/features/test-sharding/elixir#test-phase">测试阶段</.localized_link> 的引导命令，这可以防止 Mix 在分片下载其构建之前编译所有依赖项，并向其中添加 `--cover`。

分片仅报告其自身的覆盖率，且不检查阈值，因为它只运行套件的一部分。Tuist 会将一次运行的各个分片合并为一个数值。

每个分片都会将覆盖率计数器添加到其下载的构建中。若要改为只执行一次，请将 `--cover` 也传递给构建阶段：

```sh
MIX_ENV=test mix tuist.test.build --shard-max 5 --cover
```

当你在流水线运行之间保留构建目录，并在不收集覆盖率的运行中重用它时，请关闭此选项，以便该构建保持不含计数器。

### 在 CI 上完成每个提交 {#complete-each-commit}

提交的覆盖率通常来自多个作业：每个分片、每个数据库版本或每个应用各一个。Tuist 无法判断最后一个作业何时已上报，因此需要你告知。一旦某个提交的所有测试作业完成，请在依赖于所有这些作业的作业中运行以下命令：

```sh
MIX_ENV=test mix tuist.coverage.complete
```

该任务从 `GIT_COMMIT` 或检出的 `HEAD` 读取提交；传递 `--commit <sha>` 以指定另一个提交。在提交完成之前，其覆盖率显示为 **进行中**，且不会纳入其分支的趋势中。

## 工作原理 {#how-it-works}

### 原生行计数器 {#native-line-counters}

Mix 的覆盖率工具会在每次运行开始时为 Erlang 的 `cover` 重新编译每个模块，这在大型项目中会变慢。该包改用运行时的原生行计数器进行计数。它仅重新编译自上次运行以来由编译写入的模块，将运行时切换到这些计数器，并在套件结束时读取它们。Mix 的覆盖率工具被排除在外，但其摘要和阈值得以保留。

对于以下情况，该包会回退到 Mix 的覆盖率工具，并保持相同的上传行为：

- Umbrella 项目的根目录。在每个应用内部运行测试以进行原生计数。
- 设置了自身 `test_coverage: [tool: ...]` 的项目。
- 没有 JIT 的运行时，无法进行原生计数。

### Tuist 测量什么 {#what-tuist-measures}

- **应用。** 每个 OTP 应用在仪表板上都是一个目标，拥有各自的覆盖率。
- **仅限产品代码。** 测试路径下的文件属于测试代码。Tuist 会存储它们，但将其从所有数值中排除。
- **每文件的行数。** 无论一行属于多少个模块，它在每个文件中只计数一次。
- **函数。** 每一行都属于其上方最近的子句所在的函数。编译器或宏生成的函数（如 `__info__/1` 或 `__schema__/1`）不会列出，但其行仍计入所属文件。

因此，Tuist 的数值与 Mix 自身的覆盖率报告在几个方面有所不同：它排除了测试代码，并按文件而非按模块计算行数。原生计数还能看到应用启动时运行的代码，并排除编译器证明永远无法运行的行，而 Mix 的工具将这些行报告为从未覆盖。

### 跳过的测试 {#skipped-tests}

Tuist 无法延续运行所排除的测试的覆盖率：包记录的是整个运行执行的内容，而不是每个测试执行的内容。因此，当运行自身的参数排除某些测试时（使用 `--only`、`--exclude`、`--failed`、`--stale`、`--name-pattern`、`--max-failures`，或指定测试文件或行），提交的覆盖率将显示为 **不完整**，除非同时也运行了一个未排除任何内容的相同变体运行。两个各自排除部分测试的运行（例如 `--exclude slow` 和 `--only slow`）仍会导致提交不完整，即使它们合起来运行了所有测试。

某些测试是故意排除的，不会导致提交不完整：

- **测试助手的排除项。**`ExUnit.start(exclude: [...])` 默认排除的测试是你项目对默认运行套件的选择，因此 Tuist 不将它们视为缺失。在另一个作业中使用 `--include` 或 `--only` 运行它们，以将其覆盖率添加到提交中。
- **代码中跳过的测试**，使用 `@tag :skip`。
- **<.localized_link href="/guides/features/test-insights/flaky-tests/elixir#quarantining">隔离</.localized_link>跳过的测试。** 它们被排除在外，如同已被移除，因此仅由它们覆盖的行计为未覆盖。

### 完整和不完整的提交 {#commit-status}

仪表板上的每个提交都有一个状态：

| 状态 | 含义 |
| --- | --- |
| 进行中 | 运行已报告覆盖率，但尚未为该提交运行 `mix tuist.coverage.complete`。 |
| 完整 | 提交的每次运行中的所有测试都已运行，或是故意排除的。 |
| 不完整 | 部分覆盖率无法确定，因此该数值为下限。 |
| 未测量 | 没有运行为该提交报告覆盖率。 |

分支的趋势仅包含完整的提交。例如，在以下情况下提交不完整：

- 变体的每次运行都使用其自身参数排除了某些测试。
- 变体的每次运行都缺少部分分片。
- 变体的覆盖率仅来自具有未提交更改的检出上的 CI 运行。

变体是你通过 `--scheme` 传递的标签，例如数据库版本。没有标签的运行属于同一个变体。提交的数值合并了所有运行，但 Tuist 会单独检查每个变体的完整性，因此每个变体都需要一次未排除任何内容的运行。

## 性能影响 {#performance-impact}

收集覆盖率会增加开销，因此带有 `--cover` 的运行比不带它的运行耗时更长。首次运行会使用行计数器重新编译你的模块；后续运行仅重新编译发生变化的部分，因此开销大幅降低。在大型项目中，原生计数也比 Mix 的覆盖率工具快得多。

## 限制 {#limitations}

- **无 HTML 报告。** 原生计数不会向 `test_coverage: [output: ...]` 目录写入报告，且在设置该目录时运行会发出警告。仪表板的文件页面会显示已覆盖的行作为替代。
- **重试不会增加覆盖率。** 使用<.localized_link href="/guides/features/test-insights/flaky-tests/elixir#test-retries">测试重试</.localized_link>时，覆盖率为第一次尝试的结果。该次尝试已运行失败的测试，因此缺失的行仅限于不稳定测试在重试时触及但在第一次尝试中未触及的那些行。
- **来自 Fork 的拉取请求无覆盖率。** 覆盖率仅由通过 Tuist 身份验证的运行上传，而 CI 通常会扣留来自 Fork 的拉取请求的秘密信息和身份令牌，因此这些运行不会报告覆盖率。合并后，该提交将在你的分支上使用凭据运行，并照常报告其覆盖率。

## 查询覆盖率 {#querying}

仪表板的**代码覆盖率**页面显示每个提交的数值、其应用及其文件，以及每次运行覆盖的行。代理可以通过<.localized_link href="/guides/features/agentic-coding/mcp">模型上下文协议服务器</.localized_link>获取相同的数据。
