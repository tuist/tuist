---
{
  "title": "生成的 Xcode 项目",
  "titleTemplate": ":title · 代码覆盖率 · 功能 · 指南 · Tuist",
  "description": "按文件和提交测量 Tuist 生成的 Xcode 项目的代码覆盖率，包括被二进制缓存和选择性测试跳过的代码。"
}
---
# 生成的 Xcode 项目 {#generated-xcode-project-code-coverage}

代码覆盖率告诉你测试执行了代码中的哪些行。Tuist 会上传每次 `tuist test` 运行的行覆盖率，并将一个提交的所有运行合并为一个数据，涵盖项目、每个目标和每个文件。仪表板的 **代码覆盖率** 页面按提交显示该数据，并展示每个分支的趋势。

<!-- @snippet: ./_xcode-requirements -->

当 Tuist 跳过部分工作时，该数据依然准确。来自 <.localized_link href="/guides/features/cache/module-cache">二进制缓存</.localized_link> 的目标在构建时带有覆盖率计数器，因此其代码的测量方式与从源代码构建的代码相同。当 <.localized_link href="/guides/features/selective-testing/generated-xcode-project">选择性测试</.localized_link> 跳过某个测试目标时，该目标会保留其在之前运行中的覆盖率，这是通过 Tuist 在每次运行中记录的 [目标级覆盖率](#target-level-coverage) 实现的。

## 设置 {#setup}

### 开启覆盖率 {#turn-coverage-on}

在 `Tuist.swift` 的生成选项中开启覆盖率，并启用默认关闭的覆盖率上传功能：

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

启用生成选项后：

- Tuist 生成的每个方案的测试操作都会收集覆盖率，你定义的每个未设置 `coverage` 的方案也是如此。带有 `.options(coverage: false)` 或 `.options(coverage: true)` 的方案将保留其设定值。测试计划自行决定覆盖率：对于 Tuist 生成的测试计划，请将 `coverage: true` 传递给 `.testPlans(_:coverage:)`。
- 你项目的自有目标会在 Debug 配置下以带有覆盖率计数器的形式从二进制缓存中读取并预热。请参阅 [工作原理](#instrumented-binaries)。

`TUIST_COVERAGE_ENABLED` 和 `TUIST_COVERAGE_UPLOAD` 环境变量（`1` 或 `0`）的优先级高于 `enabled` 和 `upload`。请为整个环境（例如 CI 工作流）设置这些变量，而不是为单个命令设置，以确保预热缓存的命令与读取缓存的命令保持一致。

> [!IMPORTANT] KEEP THE VALUE THE SAME EVERYWHERE
> 生成选项会更改项目目标的缓存键以及其测试目标的选择性测试哈希值。在所有共享缓存的机器上使用相同的值，不要从环境中派生该值（例如从 `Environment.isCI` 派生）。关闭覆盖率的运行不会重用开启覆盖率运行的二进制文件或选择性测试结果。

### 排除方案 {#leave-schemes-out}

某些测试套件不应纳入你的覆盖率统计。例如，从另一个进程驱动你的应用或 CLI 的验收测试或端到端测试，其执行的代码是覆盖率工具无法看到的，收集这些数据只会降低它们的速度。在其方案的测试操作中关闭覆盖率：

```swift
.scheme(
    name: "AcceptanceTests",
    testAction: .targets(
        ["AcceptanceTests"],
        options: .options(coverage: false)
    )
)
```

无论 `Tuist.swift` 选项或 `TUIST_COVERAGE_ENABLED` 如何设置，该方案都保持关闭覆盖率，其运行不计入提交的覆盖率。覆盖率是按方案收集的，因此要排除某个测试目标，请将其移至独立的方案中。

### 运行测试 {#run-your-tests}

像往常一样使用 `tuist test` 运行测试：

```sh
tuist test
```

Tuist 会随测试结果一起上传运行收集的覆盖率。这包括 <.localized_link href="/guides/features/test-sharding/generated-xcode-project">分片运行</.localized_link> 和使用 `--without-building` 在另一个作业中构建的产品进行的测试运行。若要将某次运行的覆盖率排除在 Tuist 之外（例如在运行来自 fork 的拉取请求的作业中），请设置 `TUIST_COVERAGE_UPLOAD=0`。

### 在 CI 上完成每个提交 {#complete-each-commit}

一个提交的覆盖率通常来自多个作业：每个方案、每个分片或每个平台各一个。Tuist 无法判断最后一个作业何时报告完毕，因此需要你告知它。当某个提交的所有测试作业完成后，在一个依赖于所有这些作业的作业中运行以下命令：

```sh
tuist coverage complete
```

该命令从检出的 `HEAD` 中读取提交，即你的测试所运行的提交；传递 `--commit <sha>` 可指定其他提交。在提交完成之前，其覆盖率显示为 **进行中**，且不会计入其分支的趋势中。

### 在默认分支上运行完整套件 {#full-runs}

> [!IMPORTANT] SET UP A FULL RUN
> 只有存在之前的运行来承载被跳过的目标时，选择性测试才能保持提交的覆盖率完整。在你的默认分支上安排一次不含选择性测试的全量测试运行：
>
> ```sh
> tuist test --no-selective-testing
> ```
>
> 每次合并时运行一次是最理想的。对于变更较少的项目，每天或每周运行一次可能就够了。记录的覆盖率在 31 天后过期，因此运行频率应高于此间隔。

承载的覆盖率依赖于全量运行。它们会在覆盖率过期前刷新每个目标的记录覆盖率，并为 Tuist 提供选择性运行未构建的文件的最近期状态。项目在全量运行之间的变更越多，选择性运行就越频繁地发现自上次以来已变更的文件，从而导致其提交的覆盖率显示为 **不完整**。

## 目标级覆盖率 {#target-level-coverage}

一次运行的覆盖率说明的是整个运行执行的内容，而非每个测试目标执行的内容。当选择性测试跳过某个目标时，Tuist 需要知道该目标在之前运行中执行了什么，以便承载其覆盖率。

因此，在每次运行中，Tuist 还会记录每个测试目标执行了哪些文件和行。它从 Xcode 为每个测试进程写入的覆盖率中读取这些数据，因此无需额外链接或配置。这在 macOS 和 iOS 模拟器上进行记录，而非在真机上。UI 测试不会记录其所驱动应用的任何信息，因为应用的代码在其自身的进程中运行。

## 工作原理 {#how-it-works}

### 插桩二进制文件 {#instrumented-binaries}

来自二进制缓存的目标是预构建的二进制文件，只有在该二进制文件构建时带有覆盖率计数器的情况下，测试运行才能测量其代码。开启覆盖率后，二进制缓存会保留你项目自有目标的插桩变体，每个命令都会读取并预热该变体：

- **Debug 配置** 使用插桩变体：`tuist cache` 对其进行预热，`tuist generate` 和 `tuist test` 则读取它。
- **Release 配置** 始终使用普通变体，因此你交付的软件永远不会带有覆盖率计数器。
- **外部包** 始终使用普通变体。Tuist 仅测量你仓库中的代码。

在与测试作业相同的环境中开启覆盖率预热缓存，以便 `tuist test` 找到插桩二进制文件。当一次运行收集覆盖率但从缓存中获取的是普通二进制文件作为你的目标时，Tuist 会发出警告，且不会测量其代码。<.localized_link href="/guides/features/cache/module-cache#code-coverage">模块缓存</.localized_link> 详细记录了这些变体。

### 跨机器路径 {#paths-across-machines}

插桩二进制文件记录的是相对于其构建所在检出目录的源路径，因此在 CI 上预热的二进制文件可以在任何开发者的机器上正确测量文件。

<.localized_link href="/guides/features/cache/xcode-cache">Xcode 缓存</.localized_link> 通过前缀映射以相同方式工作。Tuist 在收集覆盖率的构建中默认关闭此功能，因为 Xcode 自身的覆盖率报告无法解析映射后的路径。在 Xcode 27 及更高版本中，开启 `enableCaching` 后，`prefixMapping: true` 会保持其开启状态，因此覆盖率构建也能在不同检出目录之间共享编译结果：

```swift
.options(coverage: .coverage(enabled: true, prefixMapping: true))
```

Tuist 的上传会解析映射后的路径，但 Xcode 的覆盖率报告和 `xccov` 可能会遗漏这些文件。请参阅 <.localized_link href="/guides/features/cache/xcode-cache#coverage-with-prefix-mapping">带前缀映射的覆盖率</.localized_link>。

### 跳过的测试 {#skipped-tests}

当之前的成功运行已使用相同的哈希值测试过某个测试目标时，选择性测试会跳过该目标。哈希值涵盖目标的源代码、其测试以及所有依赖项，因此相同的哈希值意味着对相同代码运行相同的测试。Tuist 会复用之前运行中为该目标记录的 [目标级覆盖率](#target-level-coverage)。如果未记录任何数据（例如因为当时覆盖率已关闭，或该运行超过 31 天），则无法承载覆盖率，该提交将标记为 **不完整**。

选择性运行也不会构建每个文件。对于未编译的文件，只要自上次完整运行以来文件未发生变化，Tuist 就会从最近的一次完整运行中获取行覆盖率。这就是为什么默认分支上的 [完整运行](#full-runs) 很重要。

你自行跳过的测试（使用 `--skip-test-targets` 或 `-skip-testing`）不会被承载：如果某次运行遗漏了它们，且该提交的其他运行也未执行它们，则该提交标记为 **不完整**。被隔离跳过的测试完全不计入覆盖率：Tuist 既不会承载它们，也不会因此将提交标记为 **不完整**。

### 完整和不完整的提交 {#commit-status}

仪表板上的每个提交都有一个状态：

| 状态 | 含义 |
| --- | --- |
| 进行中 | 已有运行报告了覆盖率，但尚未对该提交运行 `tuist coverage complete`。 |
| 完整 | 该提交方案中的所有测试均已运行或被承载。 |
| 不完整 | 部分覆盖率无法确定，因此该数值为下限。 |
| 未测量 | 没有运行报告该提交的覆盖率。 |

分支的趋势仅包含完整的提交。提交在不完整时，例如：

- 选择性测试跳过了一个无法承载的目标：之前的运行未为其记录覆盖率，选择性运行未构建的文件自上次完整运行以来发生了变化，或者提交更改了影响每个目标的文件，例如 `Package.resolved`、`Project.swift` 或 `.xcconfig`。
- 某次运行使用 `--skip-test-targets` 或 `-skip-testing` 跳过了测试，且该提交的其他运行也未执行它们。
- 某次运行从二进制缓存中获取了你的目标作为普通二进制文件。
- 方案的每次运行都使用 `-only-testing` 进行了缩小范围。
- 方案的覆盖率仅来自包含未提交更改的检出目录上的 CI 运行。

## 性能影响 {#performance-impact}

收集覆盖率会增加开销，主要发生在测试结束后，此时 Xcode 正在写入其覆盖率报告，而 Tuist 正在导出覆盖率。构建和运行测试的时间与不开启覆盖率时大致相同。插桩构建还会占用更多磁盘空间，包括在 DerivedData 和 Debug 二进制缓存中。Release 构建和归档不受影响。

## 限制 {#limitations}

### 收集覆盖率的方案的 Release 构建 {#release-builds}

当方案的测试操作收集覆盖率时，Xcode 还会对该方案在任何配置（包括 Release）下从源代码编译的目标进行插桩，即 `xcodebuild build` 编译的目标。`xcodebuild archive` 会忽略此设置，因此归档永远不会被插桩。请分发归档，或使用带有 `.options(coverage: false)` 的方案构建 Release 产品。

### 其他覆盖率工具 {#other-coverage-tools}

`-enableCodeCoverage YES` 仅决定运行是否收集覆盖率，如同在 Xcode 中一样。它不会让 Tuist 从缓存中读取插桩二进制文件，因此请改用 `Tuist.swift` 选项或 `TUIST_COVERAGE_ENABLED`。

要为其他覆盖率工具提供数据，可以让 `tuist test` 将每次运行的覆盖率写入为 LCOV 格式。这与 Tuist 上传的覆盖率相同，包含相对于仓库的路径以及来自二进制缓存的代码：

```sh
tuist test --coverage-output-path coverage
```

每次运行会写入 `coverage/<result bundle name>.lcov`。使用 `lcov -a` 合并分片运行的文件。该选项需要开启覆盖率上传。

Xcode 自身的覆盖率报告及其读取工具仅包含 Xcode 在该运行中构建的目标，从不包含来自二进制缓存的代码。Tuist 的上传会测量两者。如果你希望在 Xcode 的报告中看到某个目标的覆盖率，请生成该项目并让该目标从源代码构建：`tuist generate MyTarget` 会将 `MyTarget` 保留为源代码，并从缓存中获取其余部分。

## 查询覆盖率 {#querying}

`tuist coverage` 命令读取仪表板显示的内容。如果不使用 `--commit`，它们会读取 `--branch` 的最新完整提交，或你的默认分支的最新完整提交：

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

所有命令都接受 `--json` 以便进行脚本编写。代理可以通过 <.localized_link href="/guides/features/agentic-coding/mcp">模型上下文协议服务器</.localized_link> 访问相同的数据。
