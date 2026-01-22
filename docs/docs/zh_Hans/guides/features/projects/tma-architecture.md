---
{
  "title": "The Modular Architecture (TMA)",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about The Modular Architecture (TMA) and how to structure your projects using it."
}
---
# 模块化架构（TMA）{#the-modular-architecture-tma}

TMA是一种架构方法，用于构建Apple操作系统应用程序，以实现可扩展性、优化构建和测试周期，并确保团队遵循良好实践。其核心理念是通过构建相互独立的功能模块来开发应用程序，这些模块通过清晰简洁的API相互连接。

这些指南阐述了架构设计原则，帮助您识别并组织应用程序的不同功能层级。同时提供实用技巧、工具建议及采用此架构时的注意事项。

::: info µFEATURES
<!-- -->
该架构此前称为µFeatures。现将其更名为模块化架构（TMA），以更准确地体现其宗旨及背后的设计原则。
<!-- -->
:::

## 核心原则{#core-principle}

开发者应能快速构建、测试并尝试其功能，独立于主应用程序，同时确保Xcode功能（如UI预览、代码补全和调试）可靠运行。****

## 什么是模块{#what-is-a-module}

模块代表应用程序功能，由以下五个目标组合而成（此处目标指Xcode目标）：

- **源文件：** 包含功能源代码（Swift、Objective-C、C++、JavaScript...）及其资源（图片、字体、故事板、xib文件）。
- **接口：** 这是一个配套目标，包含该功能的公共接口和模型。
- **测试：** 包含功能单元测试和集成测试。
- **测试：** 提供可用于测试和示例应用的测试数据。同时为模块类和协议提供模拟对象，后续功能将使用这些模拟对象。
- **示例：** 包含一个示例应用程序，开发者可在特定条件下（不同语言、屏幕尺寸、设置）使用该应用程序尝试该功能。

我们建议遵循目标对象的命名规范，借助Tuist的DSL，您可在项目中强制执行此规范。

| 目标文本           | 依赖                         | 内容        |
| -------------- | -------------------------- | --------- |
| `功能`           | `功能接口`                     | 源代码与资源    |
| `功能接口`         | -                          | 公共接口与模型   |
| `FeatureTests` | `功能` 、`功能测试`               | 单元测试与集成测试 |
| `功能测试`         | `功能接口`                     | 测试数据与模拟数据 |
| `功能示例`         | `FeatureTesting`,`Feature` | 示例应用      |

::: tip UI Previews
<!-- -->
`功能` 可使用`功能测试` 作为开发资源，支持UI预览
<!-- -->
:::

::: warning COMPILER DIRECTIVES INSTEAD OF TESTING TARGETS
<!-- -->
或者，您可以在编译时使用编译器指令，将测试数据和模拟对象包含在以下目标中：`功能` 或`功能接口` 当编译为`调试`
时。这样可以简化代码结构，但最终编译出的代码可能包含运行应用程序时不需要的部分。
<!-- -->
:::

## 为何需要模块{#why-a-module}

### 清晰简洁的API{#clear-and-concise-apis}

当所有应用源代码位于同一目标中时，代码极易形成隐性依赖，最终演变成众所周知的意大利面代码。此时系统各部分强耦合，状态时常不可预测，引入新变更将变成噩梦。若将功能定义在独立目标中，则需在功能实现过程中设计公共API。
我们需要明确哪些内容应公开、功能应如何被调用、哪些部分应保持私有。通过设计安全的API，我们既能掌控功能客户端的使用方式，又能强制执行良好的编程规范。

### 小型模块{#small-modules}

[分而治之](https://en.wikipedia.org/wiki/Divide_and_conquer)。采用小模块化开发能提升专注度，并支持在隔离环境中测试功能。此外，由于采用选择性编译（仅编译实现功能所需的组件），开发周期大幅缩短。整套应用的编译仅在工作尾声阶段进行——即需要将功能集成到应用时。

### 可复用性{#reusability}

_鼓励通过框架或库在应用程序和扩展等其他产品间复用代码。构建模块后，复用过程将变得相当简单。只需组合现有模块，并根据需要添加平台专属的用户界面层（如_
），即可构建 iMessage 扩展、今日扩展或 watchOS 应用程序。

## 依赖项 {#dependencies｝

当模块依赖于另一个模块时，它会声明对该模块接口目标的依赖关系。此方法具有双重优势：既能避免模块实现与其他模块实现的耦合，又能加速干净构建——因为编译时只需处理本功能的实现代码及直接/传递依赖的接口代码。此方法灵感源自SwiftRock提出的[通过接口模块缩短iOS构建时间](https://swiftrocks.com/reducing-ios-build-times-by-using-interface-targets)方案。

基于接口的实现要求应用在运行时构建实现图，并将依赖项注入到需要它们的模块中。虽然TMA对具体实现方式不作强制规定，但我们建议采用依赖注入解决方案或模式，避免添加编译时间接层，或使用非为此目的设计的平台API。

## 产品类型{#product-types}

** 构建模块时，可为目标选择库与框架（**）、静态与动态链接（**
）及库类型（**）。若不使用Tuist，此决策较为复杂，需手动配置依赖关系图。但借助Tuist项目功能，该问题已迎刃而解。

在开发阶段，建议使用动态库或框架，通过<LocalizedLink href="/guides/features/projects/synthesized-files#bundle-accessors">包访问器</LocalizedLink>将包访问逻辑与目标库/框架的特性解耦。此举对实现快速编译和确保[SwiftUI预览功能](https://developer.apple.com/documentation/swiftui/previews-in-xcode)稳定运行至关重要。发布构建时则应采用静态库或框架，以保障应用启动速度。
可通过<LocalizedLink href="/guides/features/projects/dynamic-configuration#configuration-through-environment-variables">动态配置</LocalizedLink>在生成时更改产品类型：

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
苹果公司曾试图通过引入[可合并库](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)来缓解静态库与动态库切换的繁琐性。然而这会引入构建时的不确定性，导致构建过程不可复现且难以优化，因此我们不建议使用该方案。
<!-- -->
:::

## 代码{#code}

TMA对模块的代码架构和模式不作强制要求。但基于经验，我们仍愿分享几点建议：

- **充分利用编译器固然很好。**
  过度依赖编译器可能导致效率低下，并使Xcode的预览等功能运行不稳定。我们建议利用编译器来强制执行良好实践并及早发现错误，但不要过度依赖到影响代码的可读性和可维护性。
- **谨慎使用Swift宏。** 它们功能强大，但也可能降低代码的可读性和可维护性。
- **拥抱平台与语言，切勿抽象化处理。**
  过度设计抽象层反而可能适得其反。平台与语言本身已具备强大能力，无需额外抽象层即可构建卓越应用。请以优质的编程与设计模式为参考来开发功能。

## 资源 {#resources｝

- [构建微特征](https://speakerdeck.com/pepibumur/building-ufeatures)
- [面向框架的编程](https://speakerdeck.com/pepibumur/framework-oriented-programming-mobilization-dot-pl)
- [框架与Swift之旅](https://speakerdeck.com/pepibumur/a-journey-into-frameworks-and-swift)
- [利用框架加速iOS开发 -
  第一部分](https://developers.soundcloud.com/blog/leveraging-frameworks-to-speed-up-our-development-on-ios-part-1)
- [面向库的编程](https://academy.realm.io/posts/justin-spahr-summers-library-oriented-programming/)
- [构建现代框架](https://developer.apple.com/videos/play/wwdc2014/416/)
- [非官方 xcconfig 文件指南](https://pewpewthespells.com/blog/xcconfig_guide.html)
- [静态库与动态库](https://pewpewthespells.com/blog/static_and_dynamic_libraries.html)
