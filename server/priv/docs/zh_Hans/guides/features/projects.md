---
{
  "title": "项目",
  "titleTemplate": ":title · 功能 · 指南 · Tuist",
  "description": "使用 Swift 描述 Xcode 项目，并通过 Tuist 一致地生成它们。消除合并冲突，将依赖关系建模为图，并解锁模块缓存。"
}
---
# 生成项目 {#generated-projects}

Tuist 生成项目是一种可行的替代方案，有助于克服这些挑战，同时将复杂性和成本控制在可接受的水平。它将 Xcode 项目视为基本要素，确保对未来 Xcode 更新的韧性，并利用 Xcode 项目生成为团队提供以模块化为重点的声明式 API。Tuist 使用项目声明来简化模块化的复杂性，优化跨各种环境的构建或测试等工作流，并促进和普及 Xcode 项目的演进。

## 工作原理 {#how-does-it-work}

要开始使用生成项目，你只需使用 **Tuist 的领域特定语言 (DSL)** 定义项目。这需要使用清单文件，例如 `Workspace.swift` 或 `Project.swift`。如果你之前使用过 Swift Package Manager，这种方法非常相似。

定义项目后，Tuist 提供多种工作流来管理和与之交互：

- **生成：** 这是基础工作流。使用它来创建与 Xcode 兼容的 Xcode 项目。
- **<.localized_link href="/cli/build">构建</.localized_link>：** 此工作流不仅生成 Xcode 项目，还使用 `xcodebuild` 进行编译。
- **<.localized_link href="/cli/test">测试</.localized_link>：** 与构建工作流类似，此工作流不仅生成 Xcode 项目，还利用 `xcodebuild` 对其进行测试。

## Xcode 项目的挑战 {#challenges-with-xcode-projects}

随着 Xcode 项目规模扩大，**组织可能会面临生产力下降**，原因包括增量构建不可靠、开发人员遇到问题时频繁清除 Xcode 的全局缓存，以及项目配置脆弱。为了保持快速的功能开发，组织通常会探索各种策略。

一些组织选择通过使用基于 JavaScript 的动态运行时（如 [React Native](https://reactnative.dev/)）抽象平台来绕过编译器。虽然这种方法可能有效，但它 [使访问平台的原生功能变得复杂](https://shopify.engineering/building-app-clip-react-native)。其他组织选择 **模块化代码库**，这有助于建立清晰的边界，使代码库更易于处理并提高构建时间的可靠性。然而，Xcode 项目格式并非为模块化而设计，会导致隐式配置，很少有人理解且经常发生冲突。这导致人员依赖风险较高，尽管增量构建可能会有所改善，但当构建失败时，开发人员仍可能频繁清除 Xcode 的构建缓存（即派生数据）。为了解决这个问题，一些组织选择 **放弃 Xcode 的构建系统** 并采用 [Buck](https://buck.build/) 或 [Bazel](https://bazel.build/) 等替代方案。然而，这会带来 [高复杂性和维护负担](https://bazel.build/migrate/xcode)。


## 替代方案 {#alternatives}

### Swift Package Manager {#swift-package-manager}

虽然 Swift Package Manager (SPM) 主要关注依赖项，但 Tuist 提供了不同的方法。使用 Tuist，你不仅定义用于 SPM 集成的包；你还使用熟悉的概念（如项目、工作区、目标和方案）来塑造你的项目。

### XcodeGen {#xcodegen}

[XcodeGen](https://github.com/yonaskolb/XcodeGen) 是一个专用的项目生成器，旨在减少协作 Xcode 项目中的冲突并简化 Xcode 内部运作的一些复杂性。但是，项目是使用可序列化格式（如 [YAML](https://yaml.org/)）定义的。与 Swift 不同，如果不引入其他工具，这不允许开发人员基于抽象或检查进行构建。虽然 XcodeGen 确实提供了一种将依赖项映射到内部表示以进行验证和优化的方法，但它仍然使开发人员暴露于 Xcode 的细微差别中。这可能使 XcodeGen 成为 [构建工具](https://github.com/MobileNativeFoundation/rules_xcodeproj) 的合适基础，正如在 Bazel 社区中所见，但它对于旨在维持健康和富有成效的环境的包容性项目演进来说并不是最优的。

### Bazel {#bazel}

[Bazel](https://bazel.build) 是一种先进的构建系统，以其远程缓存功能而闻名，主要在 Swift 社区中因这一能力而受到欢迎。然而，鉴于 Xcode 及其构建系统的可扩展性有限，用 Bazel 的系统替换它需要大量的努力和维护。只有少数拥有丰富资源的公司才能承担这种开销，从那些投入大量资金将 Bazel 与 Xcode 集成的公司名单中可以看出。有趣的是，社区创建了一个 [工具](https://github.com/MobileNativeFoundation/rules_xcodeproj)，该工具使用 Bazel 的 XcodeGen 来生成 Xcode 项目。这导致了一个复杂的转换链：从 Bazel 文件到 XcodeGen YAML，最后到 Xcode 项目。这种分层间接性通常会使故障排除复杂化，使问题更难诊断和解决。
