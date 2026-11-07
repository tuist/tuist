---
{
  "title": "生成的 Xcode 项目",
  "titleTemplate": ":title · 选择性测试 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 选择性测试，仅运行受最近更改影响的 Xcode 和生成项目测试，让持续集成在数秒内提供反馈。"
}
---
# 生成的 Xcode 项目 {#generated-xcode-project}

随着项目规模增长，每次推送都运行所有测试的做法不再具备可扩展性。Tuist 的选择性测试仅运行自上次成功测试运行以来目标发生变化的测试，其依据是 Tuist 的 <.localized_link href="/guides/features/projects/hashing">哈希算法</.localized_link>。

要在你的 <.localized_link href="/guides/features/projects">生成的项目</.localized_link> 中选择性运行测试，请使用 `tuist test` 命令。该命令会像处理 <.localized_link href="/guides/features/cache/module-cache">模块缓存</.localized_link> 一样对你的项目进行 <.localized_link href="/guides/features/projects/hashing">哈希计算</.localized_link>，并在成功后持久化这些哈希值，以便在后续运行中确定哪些内容发生了变化。在后续运行中，`tuist test` 会透明地利用这些哈希值筛选测试，仅运行自上次成功测试运行以来发生变化的测试。

`tuist test` 直接与 <.localized_link href="/guides/features/cache/module-cache">模块缓存</.localized_link> 集成，尽可能使用本地或远程存储中的二进制文件，以缩短运行测试套件时的构建时间。将选择性测试与模块缓存结合使用，可以大幅减少在 CI 上运行测试所需的时间。

如果你的测试仅针对模拟器目标，请传入 `--destination simulator`，这样 `tuist test` 就只会使用和下载缓存二进制文件的模拟器切片。请参阅 <.localized_link href="/guides/features/cache/module-cache#destination-selection">目标选择</.localized_link>。对于每个 `--destination` 值，选择性测试的哈希值都是相同的。

## 分离构建和测试任务 {#separate-build-and-test-jobs}

选择性测试支持分离的构建和测试任务。在构建任务中运行 `tuist test --build-only`，以便 Tuist 能够将 `selective-testing-graph.json` 文件与构建产物一起持久化。该图携带了选择性测试所需的哈希值，因此测试任务无需重新生成项目或解析 Swift Package 依赖项即可确定要运行哪些目标。

在 `--build-only` 期间，Tuist 会将图写入两个位置：

- 当你传入 `-testProductsPath` 时，位于 `.xctestproducts` bundle 内部。
- 位于派生数据的 `Build/Products/` 目录下每个 `.xctestrun` 文件旁边。

将任一输出与构建产物一起缓存，并在测试任务中将相同路径传递给 `--without-building`。两种形式均可正常工作：

```sh
# Build job — writes an .xctestproducts bundle with the graph inside it.
tuist test MyScheme \
  --build-only \
  -- \
  -testProductsPath artifacts/MyScheme.xctestproducts \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER'

# Test job — restores the same bundle.
tuist test MyScheme \
  --without-building \
  -- \
  -testProductsPath artifacts/MyScheme.xctestproducts \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER'
```

```sh
# Build job — writes the graph as a sibling of each xctestrun in derived data.
tuist test MyScheme \
  --build-only \
  -- \
  -derivedDataPath artifacts/derived-data

# Test job — points --without-building at any of those xctestrun files.
tuist test MyScheme \
  --without-building \
  -- \
  -derivedDataPath artifacts/derived-data \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER' \
  -xctestrun artifacts/derived-data/Build/Products/MyScheme_iphonesimulator.xctestrun
```

当 Tuist 无法在输入旁边找到该图时（例如，当构建任务使用了普通的 `xcodebuild build-for-testing` 而非 `tuist test --build-only`），它会回退到重新生成项目，以便仍能计算受影响的目标。这种回退需要在测试任务上解析 Swift Package 依赖项，因此请先运行 `tuist install`，或在任务之间缓存 `Tuist/.build`。

该图反映的是构建时的源代码树状态。请针对与构建任务相同的提交运行测试任务——如果两者之间的源代码发生偏移，哈希值将不再与源代码匹配，选择性测试可能会跳过那些在新源代码下实际会失败的测试。

### 我应该使用哪个标志？ {#which-flag-should-i-use}

`.xctestrun` 和 `.xctestproducts` 是两种不同的 Xcode 输出格式，它们在可移植性与流水线便利性之间各有取舍：

- **`-testProductsPath` (`.xctestproducts`) — 推荐用于新流水线。** 它是一个自包含目录：构建好的 `.xctest` 二进制文件及其 `.xctestrun` 文件都位于其中，路径相对于 bundle 根目录，因此无论移动到何处都保持有效。
- **`-xctestrun` (原始 `.xctestrun`) — 如果你已有基于派生数据构建的流水线，请使用此选项。** `xcodebuild build-for-testing` 默认会在 `<derivedData>/Build/Products/` 的顶部写入一个 `.xctestrun`，并将其指向位于该树其他位置的测试 bundle。在另一个任务中重用它意味着要保持 `Build/Products/` 中的路径不变。

如果你是全新开始，请优先使用 `-testProductsPath`。如果你要将 Tuist 接入已缓存派生数据的现有流水线，只要构建任务通过 `tuist test --build-only` 运行，`-xctestrun` 就能获得同样的快速路径。

任一输入模式都与 `-workspace`/`-project`/`-scheme` 互斥，因此当透传参数包含 `-xctestrun` 或 `-testProductsPath` 时，Tuist 会跳过这些标志，并通过 `-only-testing` 转发所选目标。

> [!WARNING]
> **模块级与文件级粒度**
>
> 由于无法检测测试与源代码之间的代码内依赖关系，默认选择性测试的最大粒度为目标级别。[覆盖率策略](#coverage-based-test-selection) 将其细化到单个 XCTest 测试。因此，我们建议保持目标小巧且专注，以最大化选择性测试的收益。


## 基于覆盖率的测试选择 {#coverage-based-test-selection}

> [!NOTE]
> **早期访问**
>
> 基于覆盖率的测试选择处于早期访问阶段。请联系我们为你的账户启用该功能。在启用之前，该策略的行为与默认选择性测试相同。

默认情况下，选择性测试会跳过哈希值已通过验证的整个测试目标。`.coverage()` 策略更进一步：在剩余的测试目标中，它还会跳过那些在 earlier 运行中的代码覆盖率未涵盖你更改所触及的任何文件的 XCTest 和 XCUITest 测试。在 `Tuist.swift` 中启用它：

```swift
import ProjectDescription

let tuist = Tuist(
    fullHandle: "{account-handle}/{project-handle}",
    testInsights: .testInsights(
        coverage: .coverage(upload: true),
        selectiveTesting: .selectiveTesting(strategy: .coverage())
    ),
    project: .tuist()
)
```

该策略要求：

- **覆盖率上传。** Tuist 根据 earlier 运行上传的覆盖率来选择测试，因此如果清单将 `.coverage()` 设置为 `upload: false`，`tuist test` 将无法加载该清单。
- 由你的测试目标链接的 **[TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) 0.3.0 或更高版本**。它会记录每个测试执行了哪些文件，并跳过 Tuist 未选择的测试。没有它的目标只能像默认情况那样被整体跳过。
- **在你的默认分支上运行不进行选择的测试。** 在该分支以及不应跳过测试的任何其他分支上运行 `tuist test --no-selective-testing`。这些运行会执行所有测试，并成为后续运行进行比较的基线。

启用该策略后，`tuist test` 会跳过哈希值已通过验证的目标，然后向 Tuist 查询你的更改可能影响剩余目标中的哪些测试。没有受影响测试的目标不会被构建。新测试、上次失败的测试、位于已更改测试文件中的测试以及没有记录覆盖率的测试始终会运行。Swift Testing 测试在其目标运行时就会运行。

有时不会应用覆盖率，输出会说明原因：哈希值未通过验证的目标的所有测试都会运行，这与默认选择性测试相同。当同一平台上没有近期基线、更改触及超过 5,000 个文件，或可能影响任何测试的文件（例如 `Package.resolved`、`Project.swift` 或 `.xcconfig`）发生更改时，就会出现这种情况。要运行所有测试，请传入 `--no-selective-testing`。

> [!NOTE]
> **测试覆盖率**
>
> 读取单次运行报告（包括 Xcode）的覆盖率工具假定整个测试套件都已运行，因此选择性运行的报告会省略被跳过的测试。Tuist 的 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">代码覆盖率</.localized_link> 则会从较早的运行中延续被跳过测试目标的覆盖率，使用它在每次运行中记录的 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">目标级覆盖率</.localized_link>。


## 拉取/合并请求评论 {#pullmerge-request-comments}

> [!WARNING]
> **需要集成 Git 平台**
>
> 要获取自动拉取/合并请求评论，请将你的 <.localized_link href="/guides/server/accounts-and-projects">Tuist 项目</.localized_link> 与一个 <.localized_link href="/guides/server/authentication">Git 平台</.localized_link> 集成。


一旦你的 Tuist 项目连接到如 [GitHub](https://github.com) 等 Git 平台，并且你开始在 CI 工作流中使用 `tuist test`，Tuist 就会直接在拉取/合并请求中发布评论，其中包含已运行和已跳过的测试：![带有 Tuist Preview 链接的 GitHub 应用评论](/images/guides/features/selective-testing/github-app-comment.png)


## 在仪表板上调查未命中 {#investigating-misses-on-the-dashboard}

当之前缓存的测试目标显示为未命中时，测试运行页面上的 **选择性测试** 选项卡可让你深入查看生成哈希值的输入。展开一行会显示每个组件的子哈希值——源代码、依赖项、环境变量、项目和目标设置、Info.plist、权限、头文件等——从而帮助你准确定位两次运行之间发生变化的输入。

使用选择性测试卡片顶部的 **复制为 JSON** 按钮，导出每个选择性测试目标及其哈希值和子哈希值。比较两次运行之间的 JSON 是确认测试目标哈希值发生变化时哪个输入发生更改的最快方法。
