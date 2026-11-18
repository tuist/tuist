---
{
  "title": "生成的 Xcode 项目",
  "titleTemplate": ":title · 代码覆盖率 · 功能 · 指南 · Tuist",
  "description": "按文件和提交测量 Tuist 生成的 Xcode 项目的代码覆盖率，包括二进制缓存和选择性测试跳过的代码。"
}
---
# 生成的 Xcode 项目 {#generated-xcode-project-code-coverage}

代码覆盖率会告诉你测试执行了代码中的哪些行。Tuist 会上传每次 `tuist test` 运行的行覆盖率，并将一次提交的所有运行合并为一个数值，分别展示在项目、每个 target 和每个文件层面。仪表板的 **代码覆盖率** 页面按提交显示该数值，并展示每个分支的趋势。

<!-- @snippet: ./_xcode-requirements -->

当 Tuist 跳过部分工作时，该数值依然准确。来自 <.localized_link href="/guides/features/cache/module-cache">二进制缓存</.localized_link> 的 target 在构建时会启用覆盖率计数器，因此其代码的测量方式与从源码构建的代码相同。当 <.localized_link href="/guides/features/selective-testing/generated-xcode-project">选择性测试</.localized_link> 跳过某个测试 target 时，该 target 会保留之前运行中的覆盖率数据，这得益于 Tuist 在每次运行中记录的 [target 级覆盖率](#target-level-coverage)。

## 设置 {#setup}

### 开启覆盖率 {#turn-coverage-on}

在 `Tuist.swift` 的生成选项中开启覆盖率，并启用默认关闭的覆盖率上传：

```swift
import ProjectDescription

let tuist = Tuist(
    testInsights: .testInsights(coverage: .coverage(upload: true)),
    project: .tuist(
        generationOptions: .options(
            coverage: .coverage(enabled: true)
        )
    )
)
```

开启生成选项后：

- Tuist 生成的每个 scheme 的测试操作都会收集覆盖率，你定义的且未设置 `coverage` 的 scheme 的测试操作也会收集覆盖率。设置了 `.options(coverage: false)` 或 `.options(coverage: true)` 的 scheme 会保留其设定值。测试计划自行决定覆盖率：对于 Tuist 生成的测试计划，向 `.testPlans(_:coverage:)` 传递 `coverage: true`。
- 你项目自身的 target 会在 Debug 配置下以启用覆盖率计数器的方式从二进制缓存中读取并预热。参见 [工作原理](#instrumented-binaries)。

环境变量 `TUIST_COVERAGE_ENABLED` 和 `TUIST_COVERAGE_UPLOAD`（值为 `1` 或 `0`）的优先级高于 `enabled` 和 `upload`。请为整个环境（例如 CI 工作流）设置这些变量，而不是为单个命令设置，以确保预热缓存的命令与读取缓存的命令保持一致。

> [!IMPORTANT] KEEP THE VALUE THE SAME EVERYWHERE
> 生成选项会改变项目 target 的缓存键以及测试 target 的选择性测试哈希值。在所有共享缓存的机器上使用相同的值，不要从环境中派生该值（例如从 `Environment.isCI` 派生）。关闭覆盖率运行的结果不会复用开启覆盖率运行的二进制文件或选择性测试结果。

### 排除 scheme {#leave-schemes-out}

有些测试套件不应纳入你的覆盖率统计。例如，从另一个进程驱动你的应用或 CLI 的验收测试或端到端测试，其执行的代码是覆盖率工具无法看到的，收集这些数据只会让它们变慢。在其 scheme 的测试操作中关闭覆盖率：

```swift
.scheme(
    name: "AcceptanceTests",
    testAction: .targets(
        ["AcceptanceTests"],
        options: .options(coverage: false)
    )
)
```

无论 `Tuist.swift` 选项或 `TUIST_COVERAGE_ENABLED` 如何设置，该 scheme 都会保持覆盖率关闭状态，其运行结果不计入提交的覆盖率。覆盖率是按 scheme 收集的，因此若要排除某个测试 target，请将其移至独立的 scheme 中。

### 运行测试 {#run-your-tests}

照常使用 `tuist test` 运行测试：

```sh
tuist test
```

Tuist 会将运行收集的覆盖率与测试结果一起上传。这包括 <.localized_link href="/guides/features/test-sharding/generated-xcode-project">分片运行</.localized_link> 以及使用 `--without-building` 在另一个 job 中构建的产品所进行的测试运行。若要将某次运行的覆盖率排除在 Tuist 之外（例如在运行来自 fork 的拉取请求的 job 中），请设置 `TUIST_COVERAGE_UPLOAD=0`。

### 在 CI 上完成每次提交 {#complete-each-commit}

一次提交的覆盖率通常来自多个 job：每个 scheme、每个分片或每个平台各一个。Tuist 无法判断最后一个 job 何时上报完毕，因此需要你明确告知。当一次提交的所有测试 job 完成后，在一个依赖于所有这些 job 的 job 中运行以下命令：

```sh
tuist coverage complete
```

该命令会从检出目录或你的 CI 提供商处读取提交信息；如需指定其他提交，请传递 `--commit <sha>`。在提交标记为完成之前，其覆盖率将显示为 **进行中**，且不会纳入分支趋势。

### 在默认分支上运行完整套件 {#full-runs}

> [!IMPORTANT] SET UP A FULL RUN
> 只有存在之前的运行来承载被跳过的 target 时，选择性测试才能保持提交的覆盖率完整。请在默认分支上安排一次不包含选择性测试的全量测试运行：
>
> ```sh
> tuist test --no-selective-testing
> ```
>
> 理想情况下每次合并都运行一次。对于变更较少的仓库，每天或每周运行一次可能已足够。记录的覆盖率会在 31 天后过期，因此运行频率应高于此间隔。

承载的覆盖率依赖于全量运行。全量运行会在覆盖率过期前刷新每个 target 的记录，并为 Tuist 提供选择性运行未构建的文件的最新状态。仓库在全量运行之间的变更越多，选择性运行就越常发现自上次全量运行以来发生变化的文件，从而导致其提交的覆盖率显示为 **不完整**。

## Target 级覆盖率 {#target-level-coverage}

一次运行的覆盖率反映的是整个运行执行的内容，而非每个测试 target 执行的内容。当选择性测试跳过某个 target 时，Tuist 需要知道该 target 在之前运行中执行了什么，以便延续其覆盖率数据。

因此，Tuist 会在每次运行中记录每个测试 target 执行了哪些文件和行。这些数据来自 Xcode 为每个测试进程写入的覆盖率报告，无需额外链接或配置。该记录仅在 macOS 和 iOS 模拟器上可用，不在真机上可用。UI 测试不会记录其所驱动应用的任何信息，因为应用的代码在独立进程中运行。

## 工作原理 {#how-it-works}

### 插桩二进制文件 {#instrumented-binaries}

来自二进制缓存的 target 是预构建的二进制文件，只有在该二进制文件构建时启用了覆盖率计数器，测试运行才能测量其代码。开启覆盖率后，二进制缓存会保留你项目自身 target 的插桩变体，所有命令都会读取并预热该变体：

- **Debug 配置** 使用插桩变体：`tuist cache` 负责预热，`tuist generate` 和 `tuist test` 负责读取。
- **Release 配置** 始终使用普通变体，因此你交付的软件永远不会包含覆盖率计数器。
- **外部包** 始终使用普通变体。Tuist 仅测量你仓库中的代码。

在与测试 job 相同的环境中开启覆盖率并预热缓存，以便 `tuist test` 能够找到插桩二进制文件。如果一次运行收集了覆盖率，但从缓存中获取的是普通二进制文件形式的 target，Tuist 会发出警告，且不会测量这些代码。<.localized_link href="/guides/features/cache/module-cache#code-coverage">模块缓存</.localized_link> 详细记录了这些变体。

### 跨机器的路径 {#paths-across-machines}

插桩二进制文件会记录相对于其构建时检出目录的源文件路径，因此在 CI 上预热的二进制文件可以在任何开发者的机器上正确测量对应的文件。

<.localized_link href="/guides/features/cache/xcode-cache">Xcode 缓存</.localized_link>通过前缀映射以相同方式工作。Tuist 默认在收集覆盖率的构建中关闭此功能，因为 Xcode 自身的覆盖率报告无法解析映射后的路径。在 Xcode 27 及更高版本中，开启 `enableCaching` 后，`prefixMapping: true` 会保持其启用状态，因此覆盖率构建也能在不同检出目录之间共享编译结果：

```swift
.options(coverage: .coverage(enabled: true, prefixMapping: true))
```

Tuist 的上传功能可以解析映射后的路径，但 Xcode 的覆盖率报告和 `xccov` 可能会遗漏这些文件。请参阅<.localized_link href="/guides/features/cache/xcode-cache#coverage-with-prefix-mapping">带前缀映射的覆盖率</.localized_link>。

### 跳过的测试 {#skipped-tests}

当之前的一次成功运行已使用相同的哈希值测试过某个测试 target 时，选择性测试会跳过该 target。该哈希值涵盖 target 的源代码、其测试及其所有依赖项，因此相同的哈希值意味着对相同代码运行相同的测试。Tuist 会复用之前运行中为该 target 记录的[Target 级覆盖率](#target-level-coverage)。如果之前未记录任何数据（例如当时覆盖率已关闭，或该运行超过 31 天），则无法延续数据，该提交的状态将为**不完整**。

选择性运行也不会构建每个文件。对于未编译的文件，只要自上次完整运行以来文件未发生更改，Tuist 就会从最近的一次完整运行中提取行数据。这就是为什么默认分支上的[完整运行](#full-runs)至关重要。

你自行跳过的测试（通过 `--skip-test-targets` 或 `-skip-testing`）不会被延续：如果某次提交的运行排除了这些测试，且该提交的其他运行也未执行它们，则该提交的状态为**不完整**。被隔离跳过的测试完全不计入覆盖率：Tuist 既不会延续这些数据，也不会因此将提交标记为**不完整**。

### 完整和不完整的提交 {#commit-status}

仪表板上的每个提交都有一个状态：

| 状态 | 含义 |
| --- | --- |
| 进行中 | 已有运行上报了覆盖率，但该提交尚未运行 `tuist coverage complete`。 |
| 完整 | 该提交所属 scheme 的所有测试均已运行或被延续。 |
| 不完整 | 部分覆盖率无法确定，因此该数值仅为下限。 |
| 未测量 | 没有运行上报该提交的覆盖率。 |

分支的趋势仅包含完整的提交。在以下情况下，提交会被视为不完整：

- 选择性测试跳过了一个无法延续数据的 target：之前的运行未记录其覆盖率，选择性运行未构建的文件自上次完整运行以来发生了更改，或者提交更改了影响所有 target 的文件，例如 `Package.resolved`、`Project.swift` 或 `.xcconfig`。
- 某次运行使用 `--skip-test-targets` 或 `-skip-testing` 跳过了测试，且该提交的其他运行也未执行这些测试。
- 某次运行从二进制缓存中获取的是普通二进制文件形式的 target。
- 某个 scheme 的每次运行都通过 `-only-testing` 进行了限制。
- 某个 scheme 的覆盖率仅来自包含未提交更改的检出目录中的 CI 运行。

## 性能影响 {#performance-impact}

收集覆盖率会增加开销，主要发生在测试结束后，此时 Xcode 正在写入覆盖率报告，Tuist 正在导出覆盖率数据。构建和运行测试所需的时间与不开启覆盖率时大致相同。插桩构建还会占用更多磁盘空间，包括 DerivedData 和 Debug 二进制缓存。Release 构建和归档不受影响。

## 局限性 {#limitations}

### 收集覆盖率的 scheme 的 Release 构建 {#release-builds}

当某个 scheme 的测试操作收集覆盖率时，Xcode 还会对该 scheme 下由 `xcodebuild build` 从源码编译的所有 target 进行插桩，涵盖所有配置（包括 Release）。`xcodebuild archive` 会忽略该设置，因此归档文件永远不会被插桩。请分发归档文件，或使用包含 `.options(coverage: false)` 的 scheme 来构建 Release 产品。

### 其他覆盖率工具 {#other-coverage-tools}

`-enableCodeCoverage YES` 仅决定运行是否收集覆盖率（与 Xcode 行为一致）。它不会让 Tuist 从缓存中读取插桩二进制文件，因此请改用 `Tuist.swift` 选项或 `TUIST_COVERAGE_ENABLED`。

若要为其他覆盖率工具提供数据，可以让 `tuist test` 将每次运行的覆盖率写入 LCOV 格式。这与 Tuist 上传的覆盖率数据相同，包含相对于仓库的路径以及来自二进制缓存的代码：

```sh
tuist test --coverage-output-path coverage
```

每次运行都会写入 `coverage/<result bundle name>.lcov`。使用 `lcov -a` 合并分片运行的文件。该选项需要开启覆盖率上传。

Xcode 自身的覆盖率报告及其读取工具仅包含 Xcode 在该次运行中构建的 target，从不包含来自二进制缓存的代码。Tuist 的上传则会测量两者。如果你希望在 Xcode 的报告中看到某个 target 的覆盖率，请在生成项目时将该 target 设为从源代码构建：`tuist generate MyTarget` 会将 `MyTarget` 保留为源代码构建，其余部分则从缓存中获取。

## 查询覆盖率 {#querying}

`tuist coverage` 命令读取仪表板显示的数据。如果不指定 `--commit`，它们将读取 `--branch` 或你的默认分支的最新完整提交：

```sh
tuist coverage show                          # the project's coverage and its targets
tuist coverage files --commit <sha>          # files, least covered first
tuist coverage file Sources/Cart.swift --lines  # a file's functions, with per-line counts
tuist coverage targets                       # targets, least covered first, then those taken from the binary cache without coverage
tuist coverage commits --branch main         # a branch's commits with their status and change, newest first
tuist coverage runs --commit <sha>           # the test runs behind a commit, marked full, partial or discarded
tuist coverage branches                      # the branches with coverage
```

测试运行自身的覆盖率显示在 `tuist test show <test-run-id>` 中。

所有命令都支持 `--json` 以便用于脚本编写。代理也可以通过<.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol 服务器</.localized_link>访问相同的数据。
