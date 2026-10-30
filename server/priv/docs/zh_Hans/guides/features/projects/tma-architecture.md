---
{
  "title": "模块化架构（TMA）",
  "titleTemplate": ":title · 项目 · 功能 · 指南 · Tuist",
  "description": "了解模块化架构（TMA）以及如何使用它来组织你的项目。"
}
---
# 模块化架构（TMA）{#the-modular-architecture-tma}

TMA 是一种架构方法，用于构建应用程序以实现可扩展性、优化构建和测试周期，并确保团队遵循良好实践。其核心理念是通过构建相互独立的功能模块来开发应用，这些模块通过清晰简洁的 API 进行互联。

本指南介绍了该架构的原则，帮助你识别并将应用功能组织到不同层级中。如果你决定采用此架构，它还会提供相关提示、工具和建议。

> [!NOTE]
> **Μfeatures**
>
> 此架构此前被称为 µFeatures。我们将其重命名为“模块化架构（TMA）”，以更准确地反映其目的和背后的原则。


## 核心原则 {#core-principle}

开发者应能够**快速构建、测试和试用**其功能，且独立于主应用，同时确保 Xcode 功能（如 UI 预览、代码补全和调试）可靠运行。

## 什么是模块 {#what-is-a-module}

模块代表一个应用功能，由以下五个目标组成（其中“目标”指 Xcode 目标）：

- **Source：** 包含功能源代码（Swift、Objective-C、C++、JavaScript...）及其资源（图片、字体、故事板、xib 文件）。
- **Interface：** 这是一个配套目标，包含功能的公共接口和模型。
- **Tests：** 包含功能的单元测试和集成测试。
- **Testing：** 提供可用于测试和示例应用的测试数据。它还为模块类和协议提供模拟对象，其他功能可以使用这些模拟对象，我们将在后文看到。
- **Example：** 包含一个示例应用，开发者可以在特定条件下（不同语言、屏幕尺寸、设置）试用该功能。

我们建议对目标遵循命名规范，借助 Tuist 的 DSL，你可以在项目中强制执行这一规范。

| 目标 | 依赖 | 内容 |
| ---- | ---- | ---- |
| `Feature` | `FeatureInterface` | 源代码和资源 |
| `FeatureInterface` | - | 公共接口和模型 |
| `FeatureTests` | `Feature`, `FeatureTesting` | 单元测试和集成测试 |
| `FeatureTesting` | `FeatureInterface` | 测试数据和模拟对象 |
| `FeatureExample` | `FeatureTesting`, `Feature` | 示例应用 |

> [!TIP]
> **UI 预览**
>
> `Feature`可以将`FeatureTesting`用作开发资源，以支持 UI 预览


> [!WARNING]
> **使用编译器指令而非测试目标**
>
> 或者，你也可以在针对`Debug`编译时，使用编译器指令将测试数据和模拟对象包含在`Feature`或`FeatureInterface`目标中。这样可以简化依赖图，但最终会编译一些运行应用时并不需要的代码。


## 为何使用模块 {#why-a-module}

### 清晰简洁的 API {#clear-and-concise-apis}

当所有应用源代码都位于同一个目标中时，很容易在代码中形成隐式依赖，最终导致众所周知的“面条代码”。各部分紧密耦合，状态有时不可预测，引入新变更会成为噩梦。当我们在独立的目标中定义功能时，需要将设计公共 API 作为功能实现的一部分。我们需要决定哪些内容应该公开、如何消费我们的功能、哪些内容应该保持私有。我们可以更好地控制功能客户端如何使用该功能，并通过设计安全的 API 来推行良好实践。

### 小型模块 {#small-modules}

[分而治之](https://en.wikipedia.org/wiki/Divide_and_conquer)。在小型模块中工作可以让你更专注，并隔离地测试和试用功能。此外，开发周期会更快，因为我们进行了更有选择性的编译，只编译使功能运行所需的组件。只有在工作的最后阶段，当我们需要将功能集成到应用中时，才需要编译整个应用。

### 可复用性 {#reusability}

鼓励使用框架或库在应用和其他产品（如扩展）之间复用代码。通过构建模块，复用变得非常简单。我们可以通过组合现有模块并添加 _（必要时）_ 平台特定的 UI 层，来构建 iMessage 扩展、Today Extension 或 watchOS 应用。

## 依赖 {#dependencies}

当一个模块依赖另一个模块时，它会声明对其接口目标的依赖。这样做有两个好处。它可以防止一个模块的实现与另一个模块的实现耦合，并且可以加速干净构建，因为它们只需编译我们功能的实现以及直接和传递依赖的接口。这种方法受到 SwiftRock 关于[通过使用接口模块减少 iOS 构建时间](https://swiftrocks.com/reducing-ios-build-times-by-using-interface-targets)的想法的启发。

依赖接口要求应用在运行时构建实现图，并将其依赖注入到需要的模块中。虽然 TMA 对如何实现这一点没有固定意见，但我们建议使用不会增加构建时间接性或使用并非为此目的设计的平台 API 的依赖注入解决方案或模式。

## 产品类型 {#product-types}

在构建模块时，你可以为目标选择**库和框架**，以及**静态和动态链接**。如果没有 Tuist，做出这个决定会稍微复杂一些，因为你需要手动配置依赖图。不过，得益于 Tuist Projects，这不再是个问题。

我们建议在开发期间使用动态库或框架，并利用<.localized_link href="/guides/features/projects/synthesized-files#bundle-accessors">bundle 访问器</.localized_link>将 bundle 访问逻辑与目标的库或框架性质解耦。这对于快速编译时间和确保[SwiftUI 预览](https://developer.apple.com/documentation/swiftui/previews-in-xcode)可靠运行至关重要。而对于发布构建，则使用静态库或框架以确保应用快速启动。你可以利用<.localized_link href="/guides/features/projects/dynamic-configuration#configuration-through-environment-variables">动态配置</.localized_link>在生成时更改产品类型：

```bash
# You'll have to read the value of the variable from the manifest {#youll-have-to-read-the-value-of-the-variable-from-the-manifest}
# and use it to change the linking type {#and-use-it-to-change-the-linking-type}
TUIST_PRODUCT_TYPE=static-library tuist generate
```

```swift
// You can place this in your manifest files or helpers
// and use the returned value when instantiating targets.
func productType() -> Product {
    if case let .string(productType) = Environment.productType {
        return productType == "static-library" ? .staticLibrary : .framework
    } else {
        return .framework
    }
}
```


> [!WARNING]
> **可合并库**
>
> Apple 试图通过引入[可合并库](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)来缓解在静态库和动态库之间切换的繁琐。然而，这会引入构建时的非确定性，导致构建不可重现且更难优化，因此我们不建议使用它。


## 代码 {#code}

TMA 对模块的代码架构和模式没有固定意见。不过，我们希望分享一些基于我们经验的建议：

- **善用编译器是很好的。** 过度依赖编译器可能会适得其反，并导致某些 Xcode 功能（如预览）工作不稳定。我们建议使用编译器来强制执行良好实践并尽早捕获错误，但不要达到使代码难以阅读和维护的程度。
- **谨慎使用 Swift 宏。** 它们非常强大，但也可能使代码难以阅读和维护。
- **拥抱平台和语言，不要对其进行抽象。** 试图设计复杂的抽象层可能会适得其反。平台和语言本身已经足够强大，无需额外的抽象层就能构建出色的应用。参考良好的编程和设计模式来构建你的功能。


## 资源 {#resources}

- [构建 µFeatures](https://speakerdeck.com/pepibumur/building-ufeatures)
- [面向框架的编程](https://speakerdeck.com/pepibumur/framework-oriented-programming-mobilization-dot-pl)
- [深入框架与 Swift 之旅](https://speakerdeck.com/pepibumur/a-journey-into-frameworks-and-swift)
- [利用框架加速 iOS 开发 - 第 1 部分](https://developers.soundcloud.com/blog/leveraging-frameworks-to-speed-up-our-development-on-ios-part-1)
- [面向库的编程](https://academy.realm.io/posts/justin-spahr-summers-library-oriented-programming/)
- [构建现代框架](https://developer.apple.com/videos/play/wwdc2014/416/)
- [xcconfig 文件非官方指南](https://pewpewthespells.com/blog/xcconfig_guide.html)
- [静态库和动态库](https://pewpewthespells.com/blog/static_and_dynamic_libraries.html)
