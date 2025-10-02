---
{
  "title": "Cache",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Optimize your build times by caching compiled binaries and sharing them across different environments."
}
---
# 缓存 {#cache}

> [！重要]要求
> - 一个<LocalizedLink href="/guides/features/projects">生成的项目</LocalizedLink>
> - <LocalizedLink href="/guides/server/accounts-and-projects">图斯特账户和项目</LocalizedLink>

Xcode
的构建系统提供了[增量构建](https://en.wikipedia.org/wiki/Incremental_build_model)功能，可在正常情况下提高效率。然而，在[持续集成（CI）环境](https://en.wikipedia.org/wiki/Continuous_integration)中，这一功能就显得不足了，因为增量构建所需的数据无法在不同的构建过程中共享。此外，**，开发人员通常会在本地重置这些数据，以排除复杂的编译问题**
，从而导致更频繁的清理构建。这就导致团队花费过多时间等待本地构建完成或持续集成管道提供拉取请求反馈。此外，在这样的环境中，频繁的上下文切换也加剧了这种非生产性。

Tuist 的缓存功能有效地解决了这些难题。该工具通过缓存已编译的二进制文件来优化构建流程，从而显著缩短本地开发和 CI
环境中的构建时间。这种方法不仅加快了反馈循环，还最大限度地减少了上下文切换的需要，最终提高了工作效率。

## 变暖 {#warming｝

Tuist
可以高效地<LocalizedLink href="/guides/features/projects/hashing">利用依赖关系图中每个目标的哈希值</LocalizedLink>来检测变化。利用这些数据，Tuist
建立并为这些目标衍生的二进制文件分配唯一标识符。在生成图时，Tuist 会用相应的二进制版本无缝替换原始目标。

这一操作被称为*"预热"，* 生成二进制文件，供本地使用或通过 Tuist 与队友和 CI 环境共享。缓存预热的过程非常简单，只需一个简单的命令即可启动：


```bash
tuist cache
```

该命令重复使用二进制文件，以加快进程。

## 用法 {#usage｝

默认情况下，当 Tuist 命令需要生成项目时，它们会自动用缓存中的二进制文件（如果可用）替代依赖文件。此外，如果您指定了要关注的目标列表，Tuist
也会用缓存中的二进制文件替换任何依赖目标，前提是这些二进制文件可用。对于喜欢另一种方法的用户，还可以通过使用特定的标记来选择完全放弃这种行为：

代码组
```bash [Project generation]
tuist generate # Only dependencies
tuist generate Search # Dependencies + Search dependencies
tuist generate Search Settings # Dependencies, and Search and Settings dependencies
tuist generate --no-binary-cache # No cache at all
```

```bash [Testing]
tuist test
```
:::

> [二进制缓存是专为开发工作流设计的一项功能，例如在模拟器或设备上运行应用程序或运行测试。它不适用于发布版本。归档应用程序时，请使用`--no-binary-cache`
> 标志，生成包含源代码的项目。

## 支持的产品 {#supported-products}

Tuist 只能缓存以下目标产品：

- 不依赖于 [XCTest](https://developer.apple.com/documentation/xctest) 的框架（静态和动态）。
- 捆绑
- Swift 宏

我们正在努力为依赖 XCTest 的库和目标提供支持。

> [当目标不可缓存时，上游目标也不可缓存。例如，如果依赖关系图为`A &gt; B` ，其中 A 依赖于 B，如果 B 不可缓存，A 也将不可缓存。

## 效率 {#efficiency｝

二进制缓存所能达到的效率水平在很大程度上取决于图形结构。为达到最佳效果，我们建议采用以下方法：

1. 避免嵌套过多的依赖关系图。依赖关系图越浅越好。
2. 用协议/接口目标而不是实现目标来定义依赖关系，并从最顶层的目标开始依赖注入实现。
3. 将频繁修改的目标拆分成较小的目标，这些目标发生变化的可能性较低。

上述建议是<LocalizedLink href="/guides/features/projects/tma-architecture">模块化架构</LocalizedLink>的一部分，我们建议将其作为构建项目的一种方法，以最大限度地发挥二进制缓存和
Xcode 功能的优势。

## 推荐设置 {#recommended-setup}

我们建议在主分支** 的每次提交中运行**的 CI 作业，为缓存预热。这将确保缓存中始终包含`主` 中更改的二进制文件，以便本地和 CI
分支在它们的基础上进行增量构建。

> [提示] 使用二进制缓存进行缓存预热`tuist cache` 命令也使用二进制缓存加快预热。

下面是一些常见工作流程的示例：

### 开发人员开始开发新功能 {#a-developer-starts-to-work-on-a-new-feature}

1. 他们在`main` 上创建了一个新的分支。
2. 他们运行`tuist 生成` 。
3. Tuist 从`main` 提取最新的二进制文件，并用它们生成项目。

### 开发者向上游推送变更 {#a-developer-pushes-changes-upstream}

1. CI 管道将运行`tuist build` 或`tuist test` 来构建或测试项目。
2. 工作流程将从`main` 提取最新的二进制文件，并用它们生成项目。
3. 然后，它将逐步构建或测试项目。

## 故障排除 {#troubleshooting}

### 它不为我的目标使用二进制文件 {#it-doesnt-use-binaries-for-my-targets}

确保<LocalizedLink href="/guides/features/projects/hashing#debugging">散列在不同环境和运行中都是确定的</LocalizedLink>。如果项目有对环境的引用，例如通过绝对路径，可能会出现这种情况。您可以使用`diff`
命令比较连续两次调用`tuist generate` 或跨环境或跨运行生成的项目。

还要确保目标不直接或间接依赖于<LocalizedLink href="/guides/features/cache#supported-products">不可缓存目标</LocalizedLink>。
