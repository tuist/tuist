---
{
  "title": "Xcode 代码覆盖率",
  "titleTemplate": ":title · 代码覆盖率 · 功能 · 指南 · Tuist",
  "description": "将 Xcode 项目的代码覆盖率上传到 Tuist，并按文件和提交跟踪。"
}
---
# Xcode 代码覆盖率 {#xcode-code-coverage}

代码覆盖率会告诉你测试执行了代码中的哪些行。Tuist 会上传每次测试运行的行覆盖率，并将一次提交的所有运行合并为一个数值，分别针对项目、每个 target 和每个文件。仪表板的**代码覆盖率**页面会按提交展示该数据，并显示每个分支的趋势。

<!-- @snippet: ./_xcode-requirements -->

> [!TIP]
> 如果你使用 Tuist 生成项目，请转而参考<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">生成的项目指南</.localized_link>：它会测量来自二进制缓存的代码，并延续选择性测试跳过的测试 target 的覆盖率。

## 设置 {#setup}

### 收集覆盖率 {#collect-coverage}

在你的 `Tuist.swift` 中开启覆盖率上传。默认情况下它是关闭的：

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "my-account/my-project",
    testInsights: .testInsights(coverage: .coverage(upload: true)),
    project: .xcode()
)
```

`TUIST_COVERAGE_UPLOAD` 环境变量（`1` 或 `0`）优先于该选项，例如可以在运行来自 fork 的拉取请求的任务中关闭上传。

然后在你的 scheme 的测试操作中开启**代码覆盖率**（**Edit Scheme › Test › Options**），或在运行时传入 `-enableCodeCoverage YES`，并通过 `tuist xcodebuild test` 运行你的测试：

```sh
tuist xcodebuild test \
  -scheme MyScheme \
  -enableCodeCoverage YES
```

Tuist 会将运行收集的覆盖率与其测试结果一并上传。

### 在 CI 上完成每次提交 {#complete-each-commit}

一次提交的覆盖率通常来自多个任务：每个 scheme、每个分片或每个平台各一个。Tuist 无法判断最后一个任务何时上报，因此需要你告知它。当某次提交的所有测试任务都完成后，在一个依赖于所有这些任务的任务中运行以下命令：

```sh
tuist coverage complete
```

该命令从检出仓库的 `HEAD` 读取提交，即你的测试所运行的提交；传入 `--commit <sha>` 可指定其他提交。在提交完成之前，其覆盖率将显示为**进行中**，并且不会纳入其分支的趋势统计。<.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#commit-status">生成的项目指南</.localized_link>描述了每种状态。

## 跳过的测试 {#skipped-tests}

当一次运行使用 `-skip-testing` 跳过测试时，它测量的覆盖范围少于该提交的测试所覆盖的范围，且 Tuist 无法从之前的运行中延续这些测试。除非该提交的其他运行执行了这些测试，否则该提交的覆盖率将标记为**不完整**。为了保持提交完整，请在每次提交中至少有一次运行执行所有测试。

被隔离跳过的测试完全不计入覆盖率，因此它们永远不会使提交变为**不完整**。

## 性能影响 {#performance-impact}

收集覆盖率会增加开销，主要发生在测试结束后，此时 Xcode 正在写入覆盖率报告，而 Tuist 正在导出覆盖率。构建和运行测试所需的时间与未开启覆盖率时大致相同。

## 查询覆盖率 {#querying}

`tuist coverage` 命令会读取仪表板显示的内容。如果不使用 `--commit`，它们会读取 `--branch` 的最新已完成提交，或者你的默认分支的最新已完成提交：

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
tuist coverage targets                       # targets, least covered first, then those taken from the binary cache without coverage
tuist coverage commits --branch main         # a branch's commits with their status and change, newest first
tuist coverage runs --commit <sha>           # the test runs behind a commit, marked full, partial or discarded
tuist coverage branches                      # the branches with coverage
```

测试运行自身的覆盖率会在 `tuist test show <test-run-id>` 中显示。

所有命令都接受 `--json` 以便用于脚本。
