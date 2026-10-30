---
{
  "title": "最佳实践",
  "titleTemplate": ":title · 项目 · 功能 · 指南 · Tuist",
  "description": "了解使用 Tuist 生成项目的最佳实践。"
}
---
# 最佳实践 {#best-practices}

在与不同团队和项目合作的多年中，我们总结了一套在使用 Tuist 和 Xcode 项目时推荐遵循的最佳实践。这些实践并非强制要求，但可以帮助你以更易维护和扩展的方式组织项目结构。

## Xcode {#xcode}

### 不推荐的模式 {#discouraged-patterns}

#### 用配置项建模远程环境 {#configurations-to-model-remote-environments}

许多组织使用构建配置来建模不同的远程环境（例如 `Debug-Production` 或 `Release-Canary`），但这种方法存在一些缺点：

- **不一致性：** 如果依赖图中存在配置不一致的情况，构建系统可能会为某些目标使用错误的配置。
- **复杂性：** 项目可能会积累一长串难以理解和维护的本地配置与远程环境。

构建配置的设计初衷是体现不同的构建设置，而项目通常只需要 `Debug` 和 `Release` 两种配置即可。建模不同环境的需求可以通过其他方式实现：

- **在 Debug 构建中：** 你可以将开发环境中需要访问的所有配置（例如接口端点）包含在应用中，并在运行时进行切换。切换可以通过 Scheme 的启动环境变量完成，也可以通过应用内的 UI 实现。
- **在 Release 构建中：** 对于发布版本，你可以只包含与该发布构建绑定的配置，并通过编译器指令排除用于切换配置的运行时逻辑。

> [!NOTE]
> **非标准配置**
>
> 虽然 Tuist 支持非标准配置，并且相比原生 Xcode 项目更易于管理，但如果依赖图中的配置不一致，你将会收到警告。这有助于确保构建的可靠性并防止与配置相关的问题。


## 生成的项目

### 可构建文件夹

Tuist 4.62.0 增加了对**可构建文件夹**（Xcode 的同步组）的支持，这是 Xcode 16 引入的一项旨在减少合并冲突的功能。

虽然 Tuist 的通配符模式（例如 `Sources/**/*.swift`）已经消除了生成项目中的合并冲突，但可构建文件夹提供了额外的好处：

- **自动同步**：你的项目结构与文件系统保持同步——添加或删除文件时无需重新生成
- **对 AI 友好的工作流**：编程助手和代理可以修改你的代码库，而不会触发项目重新生成
- **更简单的配置**：定义文件夹路径，而不是管理显式的文件列表

我们建议采用可构建文件夹，而不是传统的 `Target.sources` 和 `Target.resources` 属性，以获得更流畅的开发体验。

::: code-group

```swift [With buildable folders]
let target = Target(
  name: "App",
  buildableFolders: ["App/Sources", "App/Resources"]
)
```

```swift [Without buildable folders]
let target = Target(
  name: "App",
  sources: ["App/Sources/**"],
  resources: ["App/Resources/**"]
)
```
<!-- -->
:::

### 依赖

#### 在 CI 上强制使用已解析的版本

在 CI 上安装 Swift Package Manager 依赖时，我们建议使用 `--force-resolved-versions` 标志以确保构建的确定性：

```bash
tuist install --force-resolved-versions
```

该标志确保依赖项使用 `Package.resolved` 中锁定的确切版本进行解析，从而消除因依赖解析的非确定性导致的问题。这在需要可重现构建的 CI 环境中尤为重要。

#### 在 GitHub Actions 上缓存依赖安装 {#dependency-cache-volumes}

对于生成的项目，使用 [tuist/install](https://github.com/tuist/install) 安装 `Package.resolved` 中锁定的依赖项，并在多次运行之间缓存它们。它会在 Tuist Runners 上自动使用 <.localized_link href="/guides/features/runners/cache-volumes">缓存卷</.localized_link>，在其他 Runner 上使用 GitHub 的缓存。

```yaml
name: Generate project
on:
  push:
    branches: [main]
  pull_request:

permissions:
  contents: read

jobs:
  generate:
    runs-on: tuist-macos
    steps:
      - uses: actions/checkout@v4
      - uses: jdx/mise-action@v4
      - uses: tuist/install@v1
      - run: tuist generate --no-open
```

对于位于子目录中的项目，传递其相对于检出目录的路径：

```yaml
- uses: tuist/install@v1
  with:
    path: apps/ios
```

查看 [操作参考](https://github.com/tuist/install#usage) 以获取更多选项。

### 代理式编程与工作树 {#agentic-coding-and-worktrees}

编程代理和人类贡献者越来越多地并行工作：开发者保持一个工作树打开以审查功能，而一个或多个代理在兄弟工作树的各自分支上进行迭代。一些项目选择可以使这一过程更加顺畅。

#### 使用可构建文件夹处理代理驱动的编辑 {#worktrees-buildable-folders}

当代理添加或删除文件时，任何依赖于 `Project.swift` 中文件列表的内容都需要在再次构建项目之前运行 `tuist generate`。[可构建文件夹](#buildable-folders)将这一责任下放到 Xcode 的同步组，因此文件树编辑不再触发重新生成。

将其与 `generated-projects` <.localized_link href="/guides/features/agentic-coding/skills">技能</.localized_link>结合使用，后者教会代理 Tuist 项目的日常工作流。

#### 不要按工作树隔离缓存 {#worktrees-shared-cache}

Tuist 遵循 <.localized_link href="/cli/directories">XDG 基础目录规范</.localized_link>，因此默认情况下，同一台机器上的每个工作树共享 `~/.cache/tuist` 和 `~/.local/state/tuist`。这正是你所期望的：在一个工作树中编译的辅助工具、在另一个工作树中下载的插件，以及由第三个工拉取的模块缓存二进制文件都可以复用。

跨工作树的并发 `tuist` 调用可以安全地并行运行。除非你确实需要隔离，否则避免将 `TUIST_XDG_CACHE_HOME` 指向工作树本地的路径；这样做会迫使每个工作树重新预热辅助工具、插件和二进制文件。

#### 为每个工作树保留独立的 SwiftPM 临时目录 {#worktrees-swiftpm-scratch}

Swift Package Manager 有自己的路径控制。`--scratch-path` 是可变的工作状态，默认为 `.build`，而 `--cache-path` 是共享缓存目录。当多个工作树处于活动状态时，不应将这两个路径同等对待。

Tuist 默认的 `tuist install` 行为已将 SwiftPM 临时目录保留在包目录下，因此每个工作树都有自己的 `.build`。保持这种隔离。单个共享的 SwiftPM 临时目录可能会混合来自不相关分支的检出内容、构建中间产物、插件、宏和锁文件。

如果你通过 `tuist install -- ...` 或通过 `Tuist.swift` 中的 `installOptions` 传递 SwiftPM 参数，在希望更快获取依赖项时共享 `--cache-path`，但将 `--scratch-path` 留空或指向工作树本地的目录：

```swift
import ProjectDescription

let tuist = Tuist(
    project: .tuist(
        installOptions: .options(
            passthroughSwiftPackageManagerArguments: [
                "--cache-path",
                "/Users/Shared/swiftpm/cache/xcode-16-macos",
            ]
        )
    )
)
```

如果缓存路径需要根据 Xcode、Swift 工具链或平台而变化，请使用包装脚本或 CI 环境变量。避免将共享的 `--scratch-path` 提交到代码库。

如果只有一个工作树中的依赖状态看起来已损坏，请删除该工作树的 `.build` 目录并再次运行 `tuist install`。如果跨工作树的共享 SwiftPM 缓存本身看起来有问题，请在重新安装依赖项之前使用 `swift package purge-cache`。

#### 依靠模块缓存 {#worktrees-module-cache}

<.localized_link href="/guides/features/cache/module-cache">模块缓存</.localized_link>使得并行工作树变得可行。由于 Tuist 为每个目标计算确定性的 <.localized_link href="/guides/features/projects/hashing">哈希</.localized_link>，指向共享大部分历史记录的分支的两个工作树将命中相同的二进制文件。在 CI 上每次向 `main` 提交时运行 `tuist cache`；在本地，每个工作树中的 `tuist generate` 会从缓存中拉取尽可能多的内容，并仅构建你的分支实际更改的部分。

如果工作树在你预期缓存命中时回退到源码构建，请遵循 <.localized_link href="/guides/features/projects/hashing#debugging">哈希调试步骤</.localized_link>；非确定性哈希（通常由项目中的绝对路径引起）是最常见的原因，并且在比较两个工作树时会明显显现。

#### 使用注册表加速 Swift Package 解析 {#worktrees-registry}

每个工作树独立解析 Swift 包。在具有大型依赖图的项目中，这会迅速累积。切换到 <.localized_link href="/guides/features/package-registries/swift">Tuist Registry</.localized_link> 可以避免重新克隆 git 历史记录，并将解析时间从几分钟缩短到几秒。

#### 让代理访问项目洞察 {#worktrees-mcp}

一旦构建和测试在许多工作树中运行，代理最有用的事情就是推断 *哪些*运行出现了回归、哪些测试不稳定，或者包大小如何变化。Tuist 通过 <.localized_link href="/guides/features/agentic-coding/mcp">MCP 服务器</.localized_link> 和 <.localized_link href="/guides/features/agentic-coding/skills">Skills</.localized_link> 包公开这些数据。每个工作流选择一个并坚持使用；在同一任务中混合使用两者往往会导致代理行为不一致。
