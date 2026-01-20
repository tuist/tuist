---
{
  "title": "Projects",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Learn about Tuist's DSL for defining Xcode projects."
}
---
# 生成的项目 {#generated-projects}

Generated 是一种可行的替代方案，有助于克服这些挑战，同时将复杂性和成本保持在可接受的水平。它将 Xcode 项目视为基本要素，确保对未来 Xcode
更新的适应性，并利用 Xcode 项目生成为团队提供以模块化为重点的声明式 API。Tuist
利用项目声明来简化模块化**的复杂性，优化跨各种环境的构建或测试等工作流程，并促进 Xcode 项目的发展和民主化。

## 它是如何工作的？{#how-does-it-work}

要开始使用生成的项目，您只需使用**Tuist 的特定域语言 (DSL)** 定义您的项目。这需要使用清单文件，如`Workspace.swift`
或`Project.swift` 。如果您以前使用过 Swift 包管理器，那么使用方法也非常相似。

定义好项目后，Tuist 提供各种工作流程来管理项目并与之互动：

- **生成：** 这是一个基础工作流程。使用它可以创建一个与 Xcode 兼容的 Xcode 项目。
- **<LocalizedLink href="/guides/features/build">编译</LocalizedLink>：**
  此工作流程不仅会生成 Xcode 项目，还会使用`xcodebuild` 对其进行编译。
- **<LocalizedLink href="/guides/features/test">测试</LocalizedLink>：**
  操作方式与构建工作流程类似，它不仅生成 Xcode 项目，还利用`xcodebuild` 对其进行测试。

## Xcode 项目面临的挑战 {#challenges-with-xcode-projects}

随着 Xcode 项目的增长，**，组织可能会面临生产率下降的问题** ，这是由多种因素造成的，包括不可靠的增量构建、开发人员遇到问题时频繁清除 Xcode
的全局缓存以及脆弱的项目配置。为了保持快速的功能开发，企业通常会探索各种策略。

一些企业选择绕过编译器，使用基于 JavaScript 的动态运行时（如 React
Native）对平台进行抽象(https://reactnative.dev/)。这种方法虽然有效，但[使平台原生功能的访问变得复杂](https://shopify.engineering/building-app-clip-react-native)。其他组织则选择**，将代码库模块化**
，这有助于建立清晰的边界，使代码库更易于使用，并提高构建时间的可靠性。然而，Xcode
项目格式并非为模块化而设计，其结果是隐含的配置很少有人能理解，冲突也很频繁。这就导致了不良的总线因素，尽管增量构建可能会有所改善，但当构建失败时，开发人员可能仍会频繁清除
Xcode 的构建缓存（即派生数据）。为了解决这个问题，一些企业选择**放弃 Xcode 的构建系统** ，并采用
[Buck](https://buck.build/) 或 [Bazel](https://bazel.build/)
等替代方案。然而，这也带来了[高复杂性和维护负担](https://bazel.build/migrate/xcode)。


## 替代品 {#alternatives}

### Swift 软件包管理器 {#swift-package-manager}

Swift 软件包管理器（SPM）主要关注依赖关系，而 Tuist 提供了一种不同的方法。使用 Tuist，您不仅可以定义用于 SPM
集成的软件包，还可以使用项目、工作区、目标和方案等熟悉的概念来构建您的项目。

### XcodeGen {#xcodegen}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) 是一个专用的项目生成器，旨在减少协作 Xcode
项目中的冲突，并简化 Xcode 内部工作的一些复杂性。不过，项目是使用 [YAML](https://yaml.org/) 等可序列化格式定义的。与
Swift 不同的是，这不允许开发人员在不使用其他工具的情况下在抽象或检查的基础上进行构建。虽然 XcodeGen
确实提供了一种将依赖关系映射到内部表示以进行验证和优化的方法，但它仍然会让开发人员接触到 Xcode 的细微差别。这可能会使 XcodeGen 成为 Bazel
社区中[构建工具](https://github.com/MobileNativeFoundation/rules_xcodeproj)的合适基础，但对于旨在维护健康和富有成效的环境的包容性项目演进而言，它并不是最佳选择。

### 巴泽尔 {#bazel｝

[Bazel](https://bazel.build)是一款先进的构建系统，以其远程缓存功能而闻名，在 Swift
社区中广受欢迎也主要是因为它的这一功能。然而，鉴于 Xcode 及其构建系统的可扩展性有限，用 Bazel
的系统取而代之需要付出巨大的努力和维护。只有少数资源丰富的公司才能承受这种开销，这一点从精选出的投入巨资将 Bazel 与 Xcode
集成的公司名单中可见一斑。有趣的是，社区创建了一个[工具](https://github.com/MobileNativeFoundation/rules_xcodeproj)，利用
Bazel 的 XcodeGen 生成 Xcode 项目。这就产生了一个复杂的转换链：从 Bazel 文件到 XcodeGen YAML，最后到 Xcode
项目。这种分层间接往往会使故障排除复杂化，使问题的诊断和解决更具挑战性。
