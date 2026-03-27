---
{
  "title": "The Modular Architecture (TMA)",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about The Modular Architecture (TMA) and how to structure your projects using it."
}
---
# 模块化架构（TMA）{#the-modular-architecture-tma}

TMA 是一种架构方法，用于构建 Apple OS
应用程序，以实现可扩展性、优化构建和测试周期，并确保团队的良好实践。它的核心理念是通过构建独立的功能来构建应用程序，这些功能通过简洁明了的应用程序接口相互连接。

这些指南介绍了架构的原则，帮助您识别和组织不同层中的应用程序功能。如果您决定使用这种架构，它还会介绍提示、工具和建议。

::: info µFEATURES
<!-- -->
该架构以前称为 µFeatures。我们已将其更名为模块化架构 (TMA)，以更好地反映其目的和背后的原则。
<!-- -->
:::

## 核心原则{#core-principle}

开发人员应该能够**，独立于主应用程序，快速构建、测试和尝试** 他们的功能，同时确保 Xcode 的 UI 预览、代码自动补全和调试等功能能够可靠地工作。

## 什么是模块{#what-is-a-module}

模块代表一种应用程序功能，是以下五个目标的组合（其中目标指的是 Xcode 目标）：

- **源代码：** 包含功能源代码（Swift、Objective-C、C++、JavaScript...）及其资源（图片、字体、故事板、xibs）。
- **接口：** 它是一个配套目标，包含公共界面和功能模型。
- **测试：** 包含功能单元测试和集成测试。
- **测试** 提供可用于测试和示例应用程序的测试数据。它还为模块类和协议提供模拟，这些模拟可用于其他功能，我们稍后会看到。
- **示例：** 包含一个示例应用程序，开发人员可在特定条件（不同语言、屏幕尺寸、设置）下使用该示例应用程序试用功能。

我们建议您遵循目标的命名约定，通过 Tuist 的 DSL，您可以在项目中执行该约定。

| 目标     | 依赖          | 内容        |
| ------ | ----------- | --------- |
| `特点`   | `功能接口`      | 源代码和资源    |
| `功能接口` | -           | 公共界面和模型   |
| `功能测试` | `功能`,`功能测试` | 单元测试和集成测试 |
| `功能测试` | `功能接口`      | 测试数据和模拟   |
| `功能示例` | `功能测试`,`功能` | 应用程序示例    |

::: tip UI Previews
<!-- -->
`功能` 可以使用`FeatureTesting` 作为开发资产，以便进行用户界面预览
<!-- -->
:::

::: warning COMPILER DIRECTIVES INSTEAD OF TESTING TARGETS
<!-- -->
或者，在编译`Debug` 时，可以使用编译器指令在`Feature` 或`FeatureInterface`
目标中包含测试数据和模拟。这样可以简化图表，但最终编译的代码在运行应用程序时可能用不上。
<!-- -->
:::

## 为什么需要模块{#why-a-module}

### 清晰简洁的应用程序接口{#clear-and-concise-apis}

当所有应用程序的源代码都在同一个目标中时，就很容易在代码中建立隐含的依赖关系，最终形成众所周知的意大利面条代码。所有东西都是强耦合的，状态有时是不可预测的，引入新的变化就成了一场噩梦。当我们在独立目标中定义功能时，我们需要设计公共应用程序接口作为功能实现的一部分。我们需要决定哪些应该是公共的，我们的功能应该如何被使用，哪些应该保持私有。我们可以更好地控制功能客户端如何使用功能，并通过设计安全的应用程序接口来执行良好的实践。

### 小型模块{#small-modules}

[分而治之](https://en.wikipedia.org/wiki/Divide_and_conquer)。在小模块中工作可以让你更加专注，并单独测试和尝试功能。此外，由于我们的编译更具选择性，只编译功能运行所需的组件，因此开发周期会更快。只有在工作的最后阶段，当我们需要将功能集成到应用程序中时，才有必要编译整个应用程序。

### 可重用性{#reusability}

我们鼓励使用框架或库在应用程序和其他产品（如扩展）之间重复使用代码。通过构建模块，重复使用它们非常简单。我们只需组合现有模块并添加_ （必要时）_ 特定平台的
UI 层，就能构建 iMessage 扩展、Today 扩展或 watchOS 应用程序。

## 依赖项 {#dependencies｝

当一个模块依赖于另一个模块时，它会针对其接口目标声明依赖关系。这样做有两个好处。它可以防止一个模块的实现与另一个模块的实现耦合，还可以加快简洁构建，因为它们只需编译我们功能的实现，以及直接和传递依赖关系的接口。这种方法的灵感来自
SwiftRock 提出的 [使用接口模块缩短 iOS
构建时间](https://swiftrocks.com/reducing-ios-build-times-by-using-interface-targets)。

依赖接口要求应用程序在运行时构建实现图，并将其依赖注入到需要的模块中。虽然 TMA
对如何做到这一点不持任何意见，但我们建议使用依赖注入解决方案或模式，或者使用不添加构建时间接性或使用非为此目的而设计的平台 API 的解决方案。

## 产品类型{#product-types}

构建模块时，可以在**库和框架** ，以及**静态和动态链接** 之间选择目标。在没有 Tuist
的情况下，做出这一决定要复杂一些，因为您需要手动配置依赖关系图。不过，有了 Tuist 项目，这不再是问题。

我们建议在开发过程中使用动态库或框架，并使用
<LocalizedLink href="/guides/features/projects/synthesized-files#bundle-accessors">捆绑访问器</LocalizedLink>将捆绑访问逻辑与目标库或框架的性质解耦。这是快速编译和确保
[SwiftUI
预览版](https://developer.apple.com/documentation/swiftui/previews-in-xcode)可靠运行的关键。而静态库或框架用于发布构建，可确保应用快速启动。您可以利用<LocalizedLink href="/guides/features/projects/dynamic-configuration#configuration-through-environment-variables">动态配置</LocalizedLink>在生成时更改产品类型：

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


::: warning MERGEABLE LIBRARIES
<!-- -->
苹果试图通过引入[可合并库](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)来减轻在静态库和动态库之间切换的麻烦。不过，这引入了构建时的非确定性，使你的构建不可重现，也更难优化，因此我们不建议使用。
<!-- -->
:::

## 代码{#code}

TMA 对模块的代码架构和模式不持任何意见。不过，我们还是想根据自己的经验与大家分享一些技巧：

- **利用编译器是件好事。** 过度使用编译器可能会适得其反，并导致某些 Xcode
  功能（如预览）无法可靠运行。我们建议使用编译器来执行良好的实践并及早捕获错误，但不要让代码变得更难阅读和维护。
- **少用 Swift 宏。** 它们可以非常强大，但也会增加代码的阅读和维护难度。
- **拥抱平台和语言，不要抽象它们。**
  试图建立复杂的抽象层可能会适得其反。平台和语言已经足够强大，无需额外的抽象层就能构建出色的应用程序。使用良好的编程和设计模式作为构建功能的参考。

## 资源 {#resources｝

- [建筑 µFeatures](https://speakerdeck.com/pepibumur/building-ufeatures)
- [面向框架的程序设计](https://speakerdeck.com/pepibumur/framework-oriented-programming-mobilization-dot-pl).
- [进入框架和斯威夫特的旅程](https://speakerdeck.com/pepibumur/a-journey-into-frameworks-and-swift)。
- [利用框架加速 iOS 开发 -
  第一部分](https://developers.soundcloud.com/blog/leveraging-frameworks-to-speed-up-our-development-on-ios-part-1)。
- [面向库的程序设计](https://academy.realm.io/posts/justin-spahr-summers-library-oriented-programming/).
- [构建现代框架](https://developer.apple.com/videos/play/wwdc2014/416/)。
- [xcconfig 文件非官方指南](https://pewpewthespells.com/blog/xcconfig_guide.html)。
- [静态图书馆和动态图书馆](https://pewpewthespells.com/blog/static_and_dynamic_libraries.html)。
