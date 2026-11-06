---
{
  "title": "生成的 Xcode 项目",
  "titleTemplate": ":title · 选择性测试 · 功能 · 指南 · Tuist",
  "description": "使用 Tuist 选择性测试，仅运行受最近更改影响的 Xcode 和生成项目测试，让持续集成在数秒内提供反馈。"
}
---
# 生成的 Xcode 项目 {#generated-xcode-project}

随着项目规模扩大，测试数量也会随之增加。长期以来，在每次 PR 或向 `main` 推送时运行所有测试都需要数十秒。但这种方案无法扩展到团队可能拥有的数千个测试。

在 CI 上的每次测试运行中，无论代码是否有变更，你很可能都会重新运行所有测试。Tuist 的选择性测试通过仅运行自上次成功测试运行以来发生变化的测试，帮助你大幅加快测试执行速度，这基于我们的 <.localized_link href="/guides/features/projects/hashing">哈希算法</.localized_link>。

要在使用 <.localized_link href="/guides/features/projects">生成的项目</.localized_link> 时有选择地运行测试，请使用 `tuist test` 命令。该命令会以与 <.localized_link href="/guides/features/cache/module-cache">模块缓存</.localized_link> 相同的方式对您的项目进行 <.localized_link href="/guides/features/projects/hashing">哈希处理</.localized_link>，并在成功后持久化这些哈希值，以便确定未来运行中哪些内容发生了变化。在未来的运行中，`tuist test` 会透明地使用这些哈希值来筛选测试，仅运行自上次成功测试运行以来发生变化的测试。

`tuist test` 直接与 <.localized_link href="/guides/features/cache/module-cache">模块缓存</.localized_link> 集成，利用本地或远程存储中的尽可能多的二进制文件，以缩短运行测试套件时的构建时间。将选择性测试与模块缓存结合使用，可以显著减少在 CI 上运行测试所需的时间。

如果你的测试仅针对模拟器，请传递 `--destination simulator`，这样 `tuist test` 就只会使用和下载缓存二进制文件的模拟器切片。请参阅 <.localized_link href="/guides/features/cache/module-cache#destination-selection">目标选择</.localized_link>。对于每个 `--destination` 值，选择性测试的哈希值是相同的。

## 分离构建和测试任务 {#separate-build-and-test-jobs}

选择性测试支持分离构建和测试任务。在构建任务中运行 `tuist test --build-only`，以便 Tuist 能够将 `selective-testing-graph.json` 文件与构建生成的产物一起持久化。该图携带了选择性测试所需的哈希值，因此测试任务无需重新生成项目或解析 Swift Package 依赖项即可确定要运行哪些目标。

在 `--build-only` 期间，Tuist 会将图写入两个位置：

- 当你传递 `-testProductsPath` 时，位于 `.xctestproducts` bundle 内部。
- 位于派生数据的 `Build/Products/` 目录下的每个 `.xctestrun` 文件旁边。

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
  --derived-data-path artifacts/derived-data

# Test job — points --without-building at any of those xctestrun files.
tuist test MyScheme \
  --without-building \
  --derived-data-path artifacts/derived-data \
  -- \
  -destination 'platform=iOS Simulator,id=SIMULATOR_IDENTIFIER' \
  -xctestrun artifacts/derived-data/Build/Products/MyScheme_iphonesimulator.xctestrun
```

当 Tuist 无法在输入旁边找到该图时（例如，当构建任务使用普通的 `xcodebuild build-for-testing` 而不是 `tuist test --build-only` 时），它会回退到重新生成项目，以便仍然能够计算受影响的目标。这种回退需要在测试任务上解析 Swift Package 依赖项，因此请先运行 `tuist install` 或在任务之间缓存 `Tuist/.build`。

该图反映了构建时的源代码树状态。请针对与构建任务相同的提交运行测试任务——如果两者之间的源代码发生漂移，哈希值就会过时，导致选择性测试跳过那些实际上会在较新源代码下失败的测试。

### 我应该使用哪个标志？ {#which-flag-should-i-use}

`.xctestrun` 和 `.xctestproducts` 是两种不同的 Xcode 输出格式，它们在可移植性与流水线便利性之间各有取舍：

- **`-testProductsPath` (`.xctestproducts`) — 推荐用于新流水线。** 它是一个自包含的目录：构建好的 `.xctest` 二进制文件及其 `.xctestrun` 文件都位于其中，路径相对于 bundle 根目录，因此无论将其移动到哪里都保持有效。此外，该格式拥有选择性测试快速路径的时间最长，因此是经过最充分验证的路径。
- **`-xctestrun` (原始 `.xctestrun`) — 如果你已有围绕派生数据构建的流水线，请使用此选项。** `xcodebuild build-for-testing` 默认会在 `<derivedData>/Build/Products/` 的顶部写入一个 `.xctestrun`，并将其指向位于该树其他位置的测试 bundle。在另一个任务中重用它意味着要保持 `Build/Products/` 中的路径不变。

如果是从头开始，首选 `-testProductsPath`。如果你正在将 Tuist 接入已缓存派生数据的现有流水线，只要构建任务通过 `tuist test --build-only` 运行，`-xctestrun` 现在也能获得相同的快速路径。

任一输入模式都与 `-workspace`/`-project`/`-scheme` 互斥，因此当透传参数包含 `-xctestrun` 或 `-testProductsPath` 时，Tuist 会跳过这些标志，并通过 `-only-testing` 转发所选目标。

> [!WARNING]
> **模块级与文件级粒度**
>
> 由于无法检测测试与源代码之间的代码内依赖关系，选择性测试的最大粒度为目标级别。因此，我们建议保持目标小巧且专注，以最大化选择性测试的收益。


> [!NOTE]
> **测试覆盖率**
>
> 读取单次运行报告的覆盖率工具（包括 Xcode 自带的工具）假设整个测试套件都已运行，因此选择性运行的报告会省略其跳过的测试。Tuist 的 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project">代码覆盖率</.localized_link> 则会从之前的运行中继承被跳过测试目标的覆盖率，使用的是它在每次运行中记录的 <.localized_link href="/guides/features/test-code-coverage/generated-xcode-project#target-level-coverage">目标级覆盖率</.localized_link>。


## Pull/Merge Request 评论 {#pullmerge-request-comments}

> [!WARNING]
> **需要与 Git 平台集成**
>
> 要获取自动的 Pull/Merge Request 评论，请将你的 <.localized_link href="/guides/server/accounts-and-projects">Tuist 项目</.localized_link> 与 <.localized_link href="/guides/server/authentication">Git 平台</.localized_link> 集成。


一旦你的 Tuist 项目连接到 GitHub 等 Git 平台（如 [GitHub](https://github.com)），并且你开始在 CI 工作流中使用 `tuist test`，Tuist 就会直接在 Pull/Merge Request 中发布评论，其中包括哪些测试已运行以及哪些被跳过：![带有 Tuist Preview 链接的 GitHub 应用评论](/images/guides/features/selective-testing/github-app-comment.png)


## 在仪表板上调查未命中 {#investigating-misses-on-the-dashboard}

当之前缓存的测试目标显示为未命中时，测试运行页面上的 **选择性测试** 标签页允许你深入查看生成哈希值的输入。展开一行会显示每个组件的子哈希值——源代码、依赖项、环境变量、项目和目标设置、Info.plist、entitlements、头文件等——从而帮助你准确定位两次运行之间发生漂移的输入。

使用选择性测试卡片顶部的 **复制为 JSON** 按钮，导出每个选择性测试目标及其哈希值和子哈希值。比较两次运行之间的 JSON 是确认测试目标哈希值漂移时哪个输入发生变化的最快方法。
