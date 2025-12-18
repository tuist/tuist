---
{
  "title": "Best practices",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the best practices for working with Tuist and Xcode projects."
}
---
# 最佳做法 {#best-practices}

在多年与不同团队和项目的合作中，我们总结出了一套最佳实践，建议您在使用 Tuist 和 Xcode
项目时加以遵循。这些实践并不是强制性的，但它们可以帮助您以更易于维护和扩展的方式构建项目。

## Xcode {#xcode}

### 灰心丧气的模式 {#discouraged-patterns}

#### 模拟远程环境的配置 {#configurations-to-model-remote-environments}

许多组织使用构建配置来模拟不同的远程环境（如`Debug-Production` 或`Release-Canary` ），但这种方法有一些缺点：

- **不一致：** 如果整个图形中存在配置不一致的情况，那么构建系统最终可能会对某些目标使用错误的配置。
- **复杂性：** 项目最终会产生一长串本地配置和远程环境，难以推理和维护。

构建配置是为了体现不同的构建设置而设计的，项目需要的配置很少超过`Debug` 和`Release` 。模拟不同环境的需求可以通过不同方式实现：

- **在调试构建中：**
  您可以在应用程序中包含开发过程中应可访问的所有配置（如端点），并在运行时进行切换。切换可以使用方案启动环境变量，也可以使用应用程序内的用户界面。
- **在发布版构建中：** 在发行版中，只能包含发行版构建绑定的配置，而不能包含使用编译器指令切换配置的运行时逻辑。

信息 非标准配置
<!-- -->
Tuist 支持非标准配置，与普通 Xcode
项目相比更易于管理，但如果整个依赖关系图中的配置不一致，您将收到警告。这有助于确保构建的可靠性，并防止出现与配置相关的问题。
<!-- -->
:::

## 生成的项目

### 可构建文件夹

Tuist 4.62.0 添加了对**可构建文件夹** （Xcode 的同步组）的支持，该功能在 Xcode 16 中引入，以减少合并冲突。

Tuist 的通配符模式（如`Sources/**/*.swift` ）已经消除了生成项目中的合并冲突，而可构建文件夹则提供了额外的好处：

- **自动同步** ：项目结构与文件系统保持同步--添加或删除文件时无需再生
- **人工智能友好型工作流** ：编码助手和代理可以修改您的代码库，而不会触发项目再生
- **更简单的配置** ：定义文件夹路径，而不是管理明确的文件列表

我们建议采用可构建文件夹，而不是传统的`Target.sources` 和`Target.resources` 属性，以获得更简化的开发体验。

代码组

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

#### 在 CI 上强制已解决版本

在 CI 上安装 Swift 包管理器依赖项时，我们建议使用`--force-resolved-versions` 标志，以确保编译的确定性：

```bash
tuist install --force-resolved-versions
```

此标记可确保使用`Package.resolved` 中的准确版本来解析依赖关系，从而消除依赖关系解析中的非确定性所导致的问题。这对 CI
尤为重要，因为可重现的构建至关重要。
