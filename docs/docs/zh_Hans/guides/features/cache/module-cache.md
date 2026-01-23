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
- 一个 <LocalizedLink href="/guides/features/projects">生成的项目</LocalizedLink>
- 一个 <LocalizedLink href="/guides/server/accounts-and-projects">Tuist
  账户和项目</LocalizedLink>
<!-- -->
:::

Tuist模块缓存通过将模块缓存为二进制文件（`.xcframework`）并在不同环境间共享，提供了一种强大的构建时间优化方案。此功能可复用先前生成的二进制文件，减少重复编译需求，从而加速开发流程。

## 温馨提示{#warming}

Tuist高效利用<LocalizedLink href="/guides/features/projects/hashing">哈希值</LocalizedLink>来检测依赖关系图中每个目标的变更。基于这些数据，它为衍生自目标的二进制文件构建并分配唯一标识符。在生成依赖关系图时，Tuist会无缝替换原始目标及其对应的二进制版本。

此操作称为*"预热"，* 会生成二进制文件供本地使用，或通过Tuist与团队成员及CI环境共享。缓存预热过程简单明了，只需执行一条命令即可启动：


```bash
tuist cache
```

该命令通过复用二进制文件来加速处理过程。

## 用法 {#usage｝

默认情况下，当 Tuist 命令需要生成项目时，会自动用缓存中的二进制等效文件替换依赖项（若可用）。此外，若指定需重点处理的目标列表，Tuist
也会用缓存的二进制文件替换所有依赖目标（前提是这些文件可用）。若用户希望采用不同方式，可通过特定标志完全禁用此行为：

代码组
```bash [Project generation]
tuist generate # Only dependencies
tuist generate Search # Dependencies + Search dependencies
tuist generate Search Settings # Dependencies, and Search and Settings dependencies
tuist generate --cache-profile none # No cache at all
```

```bash [Testing]
tuist test
```
<!-- -->
:::

:: 警告
<!-- -->
二进制缓存是为开发工作流设计的特性，适用于在模拟器或设备上运行应用程序或执行测试等场景。该功能不适用于发布构建。归档应用程序时，请通过以下命令生成包含源代码的项目：`--cache-profile
none`
<!-- -->
:::

## 缓存配置文件{#cache-profiles}

Tuist支持缓存配置文件，用于控制生成项目时目标文件被缓存二进制文件替换的激进程度。

- 内置函数：
  - `仅外部依赖项`: 仅替换外部依赖项（系统默认）
  - `all-possible`: 尽可能替换所有目标（包括内部目标）
  - `none`: 绝不替换为缓存二进制文件

使用`--cache-profile` 在`上选择配置文件 tuist generate`:

```bash
# Built-in profiles
tuist generate --cache-profile all-possible

# Custom profiles (defined in Tuist Config)
tuist generate --cache-profile development

# Use config default (no flag)
tuist generate

# Focus on specific targets (implies all-possible)
tuist generate MyModule AnotherTarget

# Disable binary replacement entirely
tuist generate --cache-profile none
```

::: info DEPRECATED FLAG
<!-- -->
`--no-binary-cache` 标志已弃用。请改用`--cache-profile none` 。该弃用标志仍为向后兼容而保留。
<!-- -->
:::

确定实际行为的优先级（从高到低）：

1. `--cache-profile none`
2. 目标聚焦（将目标传递给`生成` ）→ 配置文件`所有可能`
3. `--cache-profile <value>`</value>
4. 配置默认值（若已设置）
5. 系统默认设置（仅限`-external` ）

## 支持的产品{#supported-products}

Tuist仅支持缓存以下目标产品：

- 不依赖于[XCTest](https://developer.apple.com/documentation/xctest)的框架（静态和动态）
- Bundles
- Swift 宏

我们正在努力支持依赖于 XCTest 的库和目标。

::: info UPSTREAM DEPENDENCIES
<!-- -->
当目标不可缓存时，其上游目标也将不可缓存。例如，若存在依赖关系图：`A &gt; B` ，其中A依赖于B。若B不可缓存，则A同样不可缓存。
<!-- -->
:::

## 效率{#efficiency}

二进制缓存能达到的效率水平在很大程度上取决于图结构。为获得最佳效果，我们建议采取以下措施：

1. 避免过度嵌套的从属句式。句式结构越简洁越好。
2. 使用协议/接口目标而非实现目标定义依赖关系，并从最顶层目标注入依赖实现。
3. 将频繁修改的目标拆分为更小的目标，以降低其变更概率。

上述建议属于<LocalizedLink href="/guides/features/projects/tma-architecture">模块化架构</LocalizedLink>的一部分，我们建议采用这种方式组织项目结构，以充分利用二进制缓存和Xcode功能带来的优势。

## 推荐设置{#recommended-setup}

建议在主分支（** ）的每次提交中运行**的CI任务以预热缓存。这将确保缓存始终包含`主分支（`
）变更对应的二进制文件，从而使本地和CI分支的构建能基于这些文件增量进行。

::: tip CACHE WARMING USES BINARIES
<!-- -->
`tuist cache` 命令同样利用二进制缓存来加速预热过程。
<!-- -->
:::

以下是一些常见工作流程示例：

### 一位开发者开始着手开发新功能{#a-developer-starts-to-work-on-a-new-feature}

1. 他们从`main` 创建了一个新分支。
2. 他们运行`tuist generate` 。
3. Tuist 从`main` 拉取最新二进制文件，并用其生成项目。

### 开发者将变更推送到上游{#a-developer-pushes-changes-upstream}

1. CI管道将执行以下命令构建或测试项目：`xcodebuild build` 或`tuist test`
2. 工作流将从`main` 拉取最新二进制文件，并用其生成项目。
3. 随后将增量构建或测试该项目。

## 配置 {#configuration}

### 缓存并发限制{#cache-concurrency-limit}

默认情况下，Tuist下载和上传缓存文件时不设并发限制，以实现最大吞吐量。您可通过环境变量`或` 控制此行为：

```bash
# Set a specific concurrency limit
export TUIST_CACHE_CONCURRENCY_LIMIT=10
tuist generate

# Use "none" for no limit (default behavior)
export TUIST_CACHE_CONCURRENCY_LIMIT=none
tuist generate
```

这在网络带宽受限的环境中或缓存操作期间可有效降低系统负载。

## 故障排除 {#troubleshooting}

### 它不使用二进制文件作为我的目标{#it-doesnt-use-binaries-for-my-targets}

确保<LocalizedLink href="/guides/features/projects/hashing#debugging">哈希值在不同环境和运行中具有确定性</LocalizedLink>。若项目存在环境引用（例如通过绝对路径），可能导致此问题。可使用`diff`
命令比较连续两次调用`tuist generate` 生成的项目，或跨环境/运行进行对比。

同时确保目标既不直接也不间接依赖于<LocalizedLink href="/guides/features/cache/generated-project#supported-products">不可缓存的目标</LocalizedLink>。

### 缺失符号{#missing-symbols}

使用源文件时，Xcode的构建系统可通过派生数据解析未显式声明的依赖关系。但若依赖二进制缓存，则必须显式声明依赖项；否则当符号无法被找到时，很可能出现编译错误。为调试此问题，建议使用
<LocalizedLink href="/guides/features/projects/inspect/implicit-dependencies">`tuist
inspect dependencies --only implicit`</LocalizedLink>
命令，并在持续集成中配置该命令以防止隐式链接的回归问题。

### 旧版模块缓存{#legacy-module-cache}

在 Tuist`4.128.0`
中，我们已将模块缓存的新基础设施设为默认配置。若您在使用新版时遇到问题，可通过设置环境变量`TUIST_LEGACY_MODULE_CACHE`
恢复旧版缓存行为。

此遗留模块缓存为临时替代方案，将在未来更新中从服务器端移除。请规划迁移方案。

```bash
export TUIST_LEGACY_MODULE_CACHE=1
tuist generate
```
