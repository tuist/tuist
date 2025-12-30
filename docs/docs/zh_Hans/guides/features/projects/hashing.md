---
{
  "title": "Hashing",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about Tuist's hashing logic upon which features like binary caching and selective testing are built."
}
---
# 散列 {#hashing}

<LocalizedLink href="/guides/features/cache">缓存</LocalizedLink>或选择性测试执行等功能需要一种方法来确定目标是否已发生变化。Tuist
会为依赖关系图中的每个目标计算哈希值，以确定目标是否已发生变化。哈希值的计算基于以下属性：

- 目标的属性（如名称、平台、产品等）
- 目标文件
- 目标依赖项的哈希值

### 缓存属性 {#cache-attributes}

此外，在计算 <LocalizedLink href="/guides/features/cache">caching</LocalizedLink>
的哈希值时，我们还会对以下属性进行哈希处理。

#### Swift 版本 {#swift-version}

我们散列了通过运行命令`/usr/bin/xcrun swift --version` 获得的 Swift 版本，以防止由于目标和二进制文件之间的 Swift
版本不匹配而导致编译错误。

模块稳定性信息
<!-- -->
以前版本的二进制缓存依赖`BUILD_LIBRARY_FOR_DISTRIBUTION`
构建设置来启用[模块稳定性](https://www.swift.org/blog/library-evolution#enabling-library-evolution-support)，并在任何版本的编译器中使用二进制文件。然而，在使用不支持模块稳定性的目标的项目中，这会导致编译问题。生成的二进制文件与用于编译它们的
Swift 版本绑定，而 Swift 版本必须与用于编译项目的版本一致。
<!-- -->
:::

#### 配置 {#configuration}

使用`-configuration`
标志的目的是确保调试二进制文件不被用于发布版本的构建，反之亦然。然而，我们仍然缺少一种机制来从项目中移除其他配置，以防止它们被使用。

## 调试 {#debugging}

如果在跨环境或调用中使用缓存时发现非确定性行为，这可能与环境差异或散列逻辑中的错误有关。我们建议按照以下步骤调试问题：

1. 运行`tuist hash cache` 或`tuist hash selective-testing`
   （哈希值用于<LocalizedLink href="/guides/features/cache">二进制缓存</LocalizedLink>或<LocalizedLink href="/guides/features/selective-testing">选择性测试</LocalizedLink>），复制哈希值，重命名项目目录，然后再次运行命令。哈希值应该匹配。
2. 如果哈希值不匹配，很可能是生成的项目依赖于环境。在两种情况下运行`tuist graph --format json` 并比较图形。或者，生成项目并使用
   [Diffchecker](https://www.diffchecker.com) 等差分工具比较它们的`project.pbxproj` 文件。
3. 如果哈希值相同，但在不同环境（例如 CI 和本地环境）中有所不同，请确保在所有环境中使用相同的
   [configuration](#configuration) 和 [Swift version](#swift-version)。Swift 版本与
   Xcode 版本绑定，因此请确认 Xcode 版本是否匹配。

如果哈希值仍然是非确定的，请告诉我们，我们可以帮助调试。


信息 更好的调试体验计划
<!-- -->
改善调试体验已列入我们的路线图。print-hashes 命令缺乏理解差异的上下文，将被一个更友好的命令所取代，该命令使用树状结构来显示哈希值之间的差异。
<!-- -->
:::
