---
{
  "title": "哈希",
  "titleTemplate": ":title · 项目 · 功能 · 指南 · Tuist",
  "description": "Tuist 哈希如何驱动二进制缓存和选择性测试。"
}
---
# 哈希计算 {#hashing}

<.localized_link href="/guides/features/cache">缓存</.localized_link>或选择性测试执行等功能需要一种方法来确定目标是否已更改。Tuist 会为依赖关系图中的每个目标计算一个哈希值，以判断目标是否发生了变化。哈希值基于以下属性计算：

- 目标的属性（例如名称、平台、产品等）
- 目标包含的文件
- 目标依赖项的哈希值

### 缓存属性 {#cache-attributes}

此外，在计算 <.localized_link href="/guides/features/cache">缓存</.localized_link>的哈希值时，我们还会对以下属性进行哈希处理。

#### Swift 版本 {#swift-version}

我们会对运行命令 `/usr/bin/xcrun swift --version` 获取的 Swift 版本进行哈希处理，以防止因目标与二进制文件之间的 Swift 版本不匹配而导致编译错误。

> [!NOTE]
> **模块稳定性**
>
> 早期版本的二进制缓存依赖于 `BUILD_LIBRARY_FOR_DISTRIBUTION` 构建设置来启用 [模块稳定性](https://www.swift.org/blog/library-evolution#enabling-library-evolution-support)，从而允许使用任意编译器版本的二进制文件。然而，这在包含不支持模块稳定性的目标的项目中引发了编译问题。生成的二进制文件绑定到用于编译它们的 Swift 版本，因此该 Swift 版本必须与用于编译项目的 Swift 版本一致。


#### 配置 {#configuration}

在计算缓存哈希值时，Tuist 会将每个项目和目标的设置限定为已解析的构建配置。即通过 `--configuration` 指定的配置；若未指定，则使用项目的 `defaultConfiguration`；若仍未指定，则使用第一个调试配置。Tuist 会对该配置的名称、变体、构建设置以及配置文件内容进行哈希处理，并结合适用于它的共享基础设置。添加、移除或更改其他配置不会影响已解析配置的缓存哈希值。由于只有已解析的配置才起作用，因此通过显式传递 `--configuration` 填充的缓存可以被解析到相同配置但未传递该标志的命令读取。

## 调试 {#debugging}

如果你在不同环境或多次调用中使用缓存时发现非确定性行为，这可能与环境的差异或哈希逻辑中的缺陷有关。我们建议按照以下步骤调试此问题：

1. 运行 `tuist hash cache` 或 `tuist hash selective-testing`（分别用于 <.localized_link href="/guides/features/cache">二进制缓存</.localized_link> 或 <.localized_link href="/guides/features/selective-testing">选择性测试</.localized_link> 的哈希值），复制哈希值，重命名项目目录，然后再次运行该命令。哈希值应当一致。
2. 如果哈希值不一致，则生成的项目很可能依赖于环境。在这两种情况下都运行 `tuist graph --format json` 并比较生成的图。或者，生成项目并使用 [Diffchecker](https://www.diffchecker.com) 等差异比较工具对比它们的 `project.pbxproj` 文件。
3. 如果哈希值相同但在不同环境（例如 CI 和本地）之间存在差异，请确保所有地方都使用了相同的 [配置](#configuration) 和 [Swift 版本](#swift-version)。Swift 版本与 Xcode 版本绑定，因此请确认 Xcode 版本一致。

如果哈希值仍然表现出非确定性，请告知我们，我们可以协助调试。


> [!NOTE]
> **计划改进调试体验**
>
> 改进我们的调试体验已在路线图中。当前的 print-hashes 命令缺乏理解差异所需的上下文，将被一个更友好的命令取代，该命令将使用树状结构来展示哈希值之间的差异。
