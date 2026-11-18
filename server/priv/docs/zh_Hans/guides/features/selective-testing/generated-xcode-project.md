---
{
  "title": "生成的 Xcode 项目",
  "titleTemplate": ":title · 选择性测试 · 功能 · 指南 · Tuist",
  "description": "借助 Tuist 选择性测试，仅运行受最新更改影响的 Xcode 和生成项目测试，让持续集成在数秒内返回反馈。"
}
---
# 生成的 Xcode 项目 {#generated-xcode-project}

随着项目规模增长，在每次推送时运行所有测试将不再具备可扩展性。Tuist 的选择性测试仅运行自上次成功测试运行以来目标发生变化的测试，其依据是 Tuist 的 <.localized_link href="/guides/features/projects/hashing">哈希算法</.localized_link>。

要在你的 <.localized_link href="/guides/features/projects">生成项目</.localized_link> 中选择性运行测试，请使用 `tuist test` 命令。该命令会以与 <.localized_link href="/guides/features/cache/module-cache">模块缓存</.localized_link> 相同的方式对你的项目进行 <.localized_link href="/guides/features/projects/hashing">哈希处理</.localized_link>，并在成功后持久化这些哈希值，以便在未来的运行中确定哪些内容发生了变化。在未来的运行中，`tuist test` 会透明地使用这些哈希值来筛选测试，仅运行自上次成功测试运行以来发生变化的测试。

`tuist test` 直接与 <.localized_link href="/guides/features/cache/module-cache">模块缓存</.localized_link> 集成，利用本地或远程存储中的二进制文件来缩短运行测试套件时的构建时间。将选择性测试与模块缓存结合使用，可以显著减少在 CI 上运行测试所需的时间。

如果你的测试仅针对模拟器，请传递 `--destination simulator`，这样 `tuist test` 就只会使用和下载缓存二进制文件的模拟器切片。请参阅 <.localized_link href="/guides/features/cache/module-cache#destination-selection">目标选择</.localized_link>。对于每个 `--destination` 值，选择性测试的哈希值都是相同的。

## 分离构建和测试任务 {#separate-build-and-test-jobs}

选择性测试支持分离的构建和测试任务。在构建任务中运行 `tuist test --build-only`，以便 Tuist 能够将 `selective-testing-graph.json` 文件与构建生成的产物一起持久化。该图包含了选择性测试所需的哈希值，因此测试任务无需重新生成项目或解析 Swift Package 依赖项即可确定要运行哪些目标。

在 `--build-only` 期间，Tuist 会将图写入两个位置：

- 当你传递 `-testProductsPath` 时，位于 `.xctestproducts` bundle 内部。
- 位于派生数据的 `Build/Products/` 目录下每个 `.xctestrun` 文件旁边。

将任一输出与构建产物一起缓存，并在测试任务中将相同的路径传递给 `--without-building`。两种形式均有效：

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

当 Tuist 无法在输入旁边找到该图时（例如，当构建任务使用了普通的 `xcodebuild build-for-testing` 而不是 `tuist test --build-only`），它会回退到重新生成项目，以便仍然能够计算受影响的目标。这种回退需要在测试任务上解析 Swift Package 依赖项，因此请先运行 `tuist install` 或在任务之间缓存 `Tuist/.build`。

该图反映了构建时的源代码树状态。请针对与构建任务相同的提交运行测试任务——如果两者之间的源代码发生漂移，哈希值将不再与源代码匹配，选择性测试可能会跳过那些针对较新源代码实际上会失败的测试。

### 我应该使用哪个标志？ {#which-flag-should-i-use}

`.xctestrun` 和 `.xctestproducts` 是两种不同的 Xcode 输出格式，它们在可移植性与流水线便利性之间各有取舍：

- **`-testProductsPath` (`.xctestproducts`) — 推荐用于新的流水线。** 它是一个自包含目录：构建好的 `.xctest` 二进制文件及其 `.xctestrun` 文件都位于其中，路径相对于 bundle 根目录，因此无论将其移至何处都保持有效。
- **`-xctestrun` (原始 `.xctestrun`) — 如果你已有基于派生数据构建的流水线，请使用此选项。** `xcodebuild build-for-testing` 默认会在 `<derivedData>/Build/Products/` 的顶部写入一个 `.xctestrun`，并将其指向位于该树其他位置的测试 bundle。在另一个任务中重用它意味着要保持 `Build/Products/` 中的路径完整无缺。

如果你是从头开始，首选 `-testProductsPath`。如果你正在将 Tuist 接入已缓存派生数据的现有流水线，只要构建任务通过 `tuist test --build-only` 运行，`-xctestrun` 就能获得同样的快速路径。

任一输入模式都与 `-workspace`/`-project`/`-scheme` 互斥，因此当透传参数包含 `-xctestrun` 或 `-testProductsPath` 时，Tuist 会跳过这些标志，并通过 `-only-testing` 转发所选目标。

> [!WARNING]
> **模块级与文件级粒度**
>
> 由于无法检测测试与源代码之间的代码内依赖关系，默认选择性测试的最大粒度为目标级别。[覆盖策略](#coverage-based-test-selection) 将其细化到单个测试。因此，我们建议保持目标小巧且专注，以最大化选择性测试的收益。


## 基于覆盖率的测试选择 {#coverage-based-test-selection}

> [!NOTE]
> **早期访问**
>
> 基于覆盖率的测试选择处于早期访问阶段。请联系我们以为你的账户启用此功能。在启用之前，该策略的行为与默认选择性测试相同。

默认情况下，选择性测试会跳过哈希值已通过验证的整个测试目标。`.coverage()` 策略更进一步：在剩余的测试目标中，它还会跳过那些在 earlier 运行中代码覆盖率未涵盖任何受你更改影响的文件的测试。它适用于 XCTest 和 XCUITest 测试，以及配置了该功能的 [Swift Testing](#swift-testing) 测试套件中的测试。在 `Tuist.swift` 中启用它：

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
- **[TestCoverageAttribution](https://github.com/tuist/TestCoverageAttribution) 0.5.1 或更高版本**，并由你的测试目标 [链接](#linking-testcoverageattribution)。它会记录每个测试执行了哪些文件，并跳过 Tuist 未选择的测试。没有它的目标只能像默认情况那样被整体跳过。
- **足够频繁的全量测试运行。** 使用 `tuist test --no-selective-testing` 的运行会执行每个测试并成为基线。选择性运行会与同一平台上其提交历史中的近期运行进行比较，如果没有基线则不应用覆盖率。在哪里以及多久运行一次取决于团队的工作方式，例如在默认分支的每次提交、每晚或在发布分支上。我们推荐使用默认分支：在那里的全量运行还能在更改交付之前发现覆盖率无法看到的问题，例如测试所依赖的 fixture 或服务。

启用该策略后，`tuist test` 会跳过哈希值已通过验证的目标，然后询问 Tuist 你的更改可能影响剩余目标中的哪些测试。没有受影响测试的目标不会被构建。新测试、上次失败的测试、位于已更改测试文件中的测试以及没有记录覆盖率的测试始终会运行。

有时不会应用覆盖率，输出会说明原因：哈希值未通过验证的目标中的所有测试都会运行，这与默认选择性测试的行为相同。这种情况发生在同一平台上没有近期基线时、当更改涉及超过 5,000 个文件时，或者当可能影响任何测试的文件发生更改时，例如 `Package.resolved`、`Project.swift` 或 `.xcconfig`。要运行每个测试，请传递 `--no-selective-testing`。

> [!NOTE]
> **测试覆盖率**
>
> 读取单次运行报告的覆盖率工具（包括 Xcode 的工具）假定整个测试套件都已运行，因此选择性运行的报告会省略它跳过的测试。Tuist 的 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">代码覆盖率</.localized_link> 则会利用每次运行记录的 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">目标级覆盖率</.localized_link>，将跳过测试目标的覆盖率从 earlier 运行中延续下来。

### 链接 TestCoverageAttribution {#linking-testcoverageattribution}

将该包添加到 `Tuist/Package.swift`，并锁定其次要版本，因为 0.x 次要版本的发布可能会改变其记录的内容：

```swift
import PackageDescription

let package = Package(
    name: "MyApp",
    dependencies: [
        .package(
            url: "https://github.com/tuist/TestCoverageAttribution",
            .upToNextMinor(from: "0.5.1")
        ),
    ]
)
```

然后将其添加到你的测试目标中，切勿添加到应用目标中：

```swift
.target(
    name: "CheckoutTests",
    destinations: .iOS,
    product: .unitTests,
    bundleId: "dev.tuist.CheckoutTests",
    sources: ["CheckoutTests/**"],
    dependencies: [
        .target(name: "Checkout"),
        .external(name: "TestCoverageAttribution"),
    ]
)
```

默认情况下，Tuist 将包作为静态框架链接。仅包含 XCTest 的目标不引用包中的任何内容，因此链接器会将其丢弃，连同记录和跳过功能一起丢失。要么向测试目标的 `OTHER_LDFLAGS` 添加 `-ObjC`，要么在 `Tuist/Package.swift` 中动态链接该包：

```swift
#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        productTypes: ["TestCoverageAttribution": .framework]
    )
#endif
```

### Swift Testing {#swift-testing}

Swift Testing 没有可供库接入的观察 API，因此其测试需要在套件上使用 TestCoverageAttribution 的 `.coverageAttribution` 特性。该特性适用于嵌套在拥有它的套件中的其他套件。没有该特性的套件中的测试不会记录每个测试的覆盖率，因此只要其目标运行，它们就会运行。

```swift
import TestCoverageAttribution
import Testing

@Suite(.coverageAttribution)
struct DiscountTests {
    @Test func appliesDiscount() { … }
}
```

- **测试不得重叠。** Swift Testing 默认并行运行进程中的测试，而覆盖率计数器无法区分同时运行的测试，因此这些测试不会记录自己的覆盖率并始终运行。`.serialized` 仅对套件自身的测试进行排序，因此只有当目标只有一个套件时才足够。XCTest 无需任何特殊配置：并行测试会在各自的进程中运行每个测试克隆。
- **按测试目标关闭并行化。** Xcode 将设置应用于每个测试目标，因此你可以仅针对希望逐个选择测试的目标关闭它，而方案中的其他目标继续保持并行运行。无需单独的方案。在可测试目标上设置它，`.testableTarget(target: "CheckoutTests", parallelization: .disabled)`，这也会在没有克隆的情况下运行该目标的 XCTest 测试。Tuist 生成的方案从项目的 `testingOptions` 获取此设置，除非它们包含 `.parallelizable` 或 `.swiftTestingOnlyParallelizable`，否则默认为关闭。向 `tuist test` 传递 `-parallel-testing-enabled YES` 或 `NO` 会覆盖该次运行中每个目标的设置。
- **跳过功能需要 Swift 6.3（Xcode 26.4）或更高版本。** 该特性会取消 Tuist 未选择的测试并将其报告为已跳过。在较早的版本中，测试仍然记录覆盖率，但 Tuist 未选择的测试仍会运行。

### 始终运行的测试 {#tests-that-always-run}

覆盖率只能看到测试执行的代码。如果测试的真实输入是 fixture、资源、网络或环境，即使没有任何受覆盖的代码发生更改，测试也可能失败。将其标记为不可跳过，即使 Tuist 未选择它，它也会运行：

```swift
// Swift Testing: on a test or a suite.
// `.skippable` opts a nested test or suite back in.
@Suite(.coverageAttribution, .unskippable)
struct FixtureTests {
    @Test func parsesTheFixtures() { … }
}

// XCTest: list the class's tests, or set `isUnskippable` for all of them.
final class NetworkTests: XCTestCase {
    @objc static let unskippableTests = ["testParsesTheFixtures"]
}
```

它仅适用于运行的测试目标。哈希值已通过验证的目标，或 Tuist 未选择其中任何测试的目标，会被整体跳过且永远不会启动，因此其不可跳过的测试也不会运行。

查看所有选项，请参阅 [TestCoverageAttribution README](https://github.com/tuist/TestCoverageAttribution#unskippable-tests)。

### 检查选择结果 {#inspecting-a-selection}

测试运行的“选择性测试”标签页显示了覆盖率选择了哪些测试以及原因。相同的数据也可通过 CLI 获取，使用 `--json` 进行脚本编写，并通过 <.localized_link href="/guides/features/agentic-coding/mcp">Model Context Protocol 服务器</.localized_link> 提供给代理：

```sh
tuist test list --selective-testing coverage           # the runs coverage-based selection decided
tuist test show <test-run-id>                          # a run's strategy, baseline and test counts
tuist test selective-testing list <test-run-id>        # each test selected or skipped, with its reason and the file that matched
tuist test selective-testing changed-files <test-run-id>  # the files that changed since the baseline
tuist test case run show <test-case-run-id>            # why a test ran
```

当未应用覆盖率时，测试仍被视为基于覆盖率的选择：其原因会说明覆盖率无法做出决定的原因，例如 `tracked_file_changed`。


## 拉取/合并请求评论 {#pullmerge-request-comments}

> [!WARNING]
> **需要 Git 平台集成**
>
> 要获得自动拉取/合并请求评论，请将你的 <.localized_link href="/guides/server/accounts-and-projects">Tuist 项目</.localized_link> 与 Git 平台集成：<.localized_link href="/guides/integrations/gitforge/github">GitHub</.localized_link>、<.localized_link href="/guides/integrations/gitforge/origin">Cursor Origin</.localized_link> 或 <.localized_link href="/guides/integrations/gitforge/entire">Entire</.localized_link>。


一旦你的 Tuist 项目与 [GitHub](https://github.com) 等 Git 平台连接，并且你开始在 CI 工作流中使用 `tuist test`，Tuist 就会直接在拉取请求或合并请求中发布评论，其中包含已运行和已跳过的测试：![带有 Tuist Preview 链接的 GitHub 应用评论](/images/guides/features/selective-testing/github-app-comment.png)


## 在仪表板上调查未命中 {#investigating-misses-on-the-dashboard}

当以前缓存的测试目标显示为未命中时，测试运行页面上的 **选择性测试** 标签页允许你深入查看生成哈希值的输入。展开一行会显示每个组件的子哈希值——源代码、依赖项、环境变量、项目和目标设置、Info.plist、权限、头文件等——从而让你能够精确定位在两次运行之间发生漂移的输入。

使用选择性测试卡片顶部的 **复制为 JSON** 按钮导出每个选择性测试目标及其哈希值和子哈希值。比较两次运行之间的 JSON 是确认测试目标哈希值漂移时哪个输入发生变化的最快方法。
