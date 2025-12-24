---
{
  "title": "Module cache",
  "titleTemplate": ":title · Cache · Features · Guides · Tuist",
  "description": "Optimize your build times by caching compiled binaries and sharing them across different environments."
}
---

# 模块缓存 {#module-cache}

警告要求
<!-- -->
- 一个<LocalizedLink href="/guides/features/projects">生成的项目</LocalizedLink>
- <LocalizedLink href="/guides/server/accounts-and-projects">图斯特账户和项目</LocalizedLink>
<!-- -->
:::

Tuist
模块缓存通过将模块缓存为二进制文件（`.xcframework`s）并在不同环境中共享，提供了优化构建时间的强大方法。通过这一功能，您可以利用以前生成的二进制文件，减少重复编译的需要，加快开发过程。

## 变暖{#warming}

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
<!-- -->
:::

:: 警告
<!-- -->
二进制缓存是专为开发工作流（如在模拟器或设备上运行应用程序或运行测试）而设计的功能。它不适用于发布版本。在归档应用程序时，请使用`--no-binary-cache`
标志生成包含源代码的项目。
<!-- -->
:::

## 缓存配置文件{#cache-profiles}

Tuist 支持缓存配置文件，以控制生成项目时如何用缓存二进制文件替换目标。

- 嵌入式家具：
  - `only-external`: 仅替换外部依赖关系（系统默认值）
  - `all-possible` ：替换尽可能多的目标（包括内部目标）
  - `none`: 绝不用缓存的二进制文件替换

使用`--cache-profile` 在`tuist 上选择一个配置文件，生成` ：

```bash
# Built-in profiles
tuist generate --cache-profile all-possible

# Custom profiles (defined in Tuist Config)
tuist generate --cache-profile development

# Use config default (no flag)
tuist generate

# Focus on specific targets (implies all-possible)
tuist generate MyModule AnotherTarget

# Disable binary replacement entirely (backwards compatible)
tuist generate --no-binary-cache  # equivalent to --cache-profile none
```

解决有效行为时的优先级（从高到低）：

1. `--无二进制缓存` → 配置文件`无`
2. 目标聚焦（将目标传递给`，生成` ） → 配置文件`所有可能的`
3. `--缓存配置文件 &lt;值`
4. 配置默认值（如果已设置）
5. 系统默认 (`only-external`)

## 支持的产品{#supported-products}

Tuist 只能缓存以下目标产品：

- 不依赖于 [XCTest](https://developer.apple.com/documentation/xctest) 的框架（静态和动态）。
- 捆绑
- Swift 宏

我们正在努力为依赖 XCTest 的库和目标提供支持。

::: info UPSTREAM DEPENDENCIES
<!-- -->
当目标不可缓存时，上游目标也将不可缓存。例如，如果依赖关系图为`A &gt; B` ，其中 A 依赖于 B，如果 B 不可缓存，A 也将不可缓存。
<!-- -->
:::

## 效率{#efficiency}

二进制缓存所能达到的效率水平在很大程度上取决于图形结构。为达到最佳效果，我们建议采用以下方法：

1. 避免嵌套过多的依赖关系图。依赖关系图越浅越好。
2. 用协议/接口目标而不是实现目标来定义依赖关系，并从最顶层的目标开始依赖注入实现。
3. 将频繁修改的目标拆分成较小的目标，这些目标发生变化的可能性较低。

上述建议是<LocalizedLink href="/guides/features/projects/tma-architecture">模块化架构</LocalizedLink>的一部分，我们建议将其作为构建项目的一种方法，以最大限度地发挥二进制缓存和
Xcode 功能的优势。

## 建议设置{#recommended-setup}

我们建议在主分支** 的每次提交中运行**的 CI 作业，为缓存预热。这将确保缓存中始终包含`主` 中更改的二进制文件，以便本地和 CI
分支在它们的基础上进行增量构建。

::: tip CACHE WARMING USES BINARIES
<!-- -->
`tuist cache` 命令也利用二进制缓存来加快暖机速度。
<!-- -->
:::

下面是一些常见工作流程的示例：

### 开发人员开始开发新功能{#a-developer-starts-to-work-on-a-new-feature}

1. 他们在`main` 上创建了一个新的分支。
2. 他们运行`tuist 生成` 。
3. Tuist 从`main` 提取最新的二进制文件，并用它们生成项目。

### 开发人员向上游推送变更{#a-developer-pushes-changes-upstream}

1. CI 管道将运行`xcodebuild build` 或`tuist test` 来构建或测试项目。
2. 工作流程将从`main` 提取最新的二进制文件，并用它们生成项目。
3. 然后，它将逐步构建或测试项目。

## 配置 {#configuration}

### 缓存并发限制{#cache-concurrency-limit}

默认情况下，Tuist
下载和上传缓存工件时没有任何并发限制，从而最大限度地提高了吞吐量。你可以使用`TUIST_CACHE_CONCURRENCY_LIMIT`
环境变量来控制这种行为：

```bash
# Set a specific concurrency limit
export TUIST_CACHE_CONCURRENCY_LIMIT=10
tuist generate

# Use "none" for no limit (default behavior)
export TUIST_CACHE_CONCURRENCY_LIMIT=none
tuist generate
```

这在网络带宽有限的环境中或在缓存操作过程中减少系统负载时非常有用。

## 故障排除 {#troubleshooting}

### 我的目标不使用二进制文件{#it-doesnt-use-binaries-for-my-targets}

确保<LocalizedLink href="/guides/features/projects/hashing#debugging">散列在不同环境和运行中都是确定的</LocalizedLink>。如果项目有对环境的引用，例如通过绝对路径，可能会出现这种情况。您可以使用`diff`
命令比较连续两次调用`tuist generate` 或跨环境或跨运行生成的项目。

还要确保目标不直接或间接依赖于<LocalizedLink href="/guides/features/cache/generated-project#supported-products">不可缓存目标</LocalizedLink>。

### 缺失的符号{#missing-symbols}

使用源代码时，Xcode 的构建系统可以通过衍生数据（Derived
Data）解决未明确声明的依赖关系。但是，当您依赖二进制缓存时，必须明确声明依赖关系；否则，当找不到符号时，您很可能会看到编译错误。要调试这种情况，我们建议使用
<LocalizedLink href="/guides/features/projects/inspect/implicit-dependencies">`tuist inspect implicit-imports`</LocalizedLink> 命令，并在 CI 中进行设置，以防止隐式链接中的回归。
