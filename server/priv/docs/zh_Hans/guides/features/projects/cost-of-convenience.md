---
{
  "title": "便利的代价",
  "titleTemplate": ":title · 项目 · 功能 · 指南 · Tuist",
  "description": "Xcode 的隐式行为如何引发问题，以及 Tuist 如何避免这些问题。"
}
---
# 便利的代价 {#the-cost-of-convenience}

设计一款能够覆盖**从小型到大型项目**的代码编辑器是一项极具挑战的任务。许多工具通过分层架构和提供可扩展性来解决这一问题。最底层非常低级，贴近底层构建系统；而最顶层则是高层抽象，虽然使用方便，但灵活性较差。通过这种方式，它们让简单的事情变得容易，也让其他一切成为可能。

然而，**[Apple](https://www.apple.com) 决定为 Xcode 采取不同的方法**。原因尚不清楚，但很可能优化大规模项目的挑战从来都不是他们的目标。他们在小型项目的便利性上投入过多，提供的灵活性很少，并将工具与底层构建系统紧密耦合。为了实现这种便利，他们提供了合理的默认值（你可以轻松替换），并添加了许多在构建时隐式解析的行为，这些行为正是导致大规模项目中出现许多问题的罪魁祸首。

## 明确性与规模 {#explicitness-and-scale}

在大规模开发中，**明确性至关重要**。它允许构建系统提前分析和理解项目结构及依赖关系，并执行否则无法实现的优化。同样的明确性也是确保编辑器功能（如 [SwiftUI 预览](https://developer.apple.com/documentation/swiftui/previews-in-xcode) 或 [Swift 宏](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/)）可靠且可预测运行的关键。由于 Xcode 及其项目将隐式性作为一种有效的设计选择以实现便利，而 Swift Package Manager 继承了这一原则，因此使用 Xcode 的困难也存在于 Swift Package Manager 中。

> [!NOTE]
> **Tuist 的角色**
>
> 我们可以将 Tuist 的角色总结为：一种防止隐式定义项目并利用明确性来提供更佳开发者体验（例如验证、优化）的工具。像 [Bazel](https://bazel.build) 这样的工具则更进一步，将其深入到了构建系统层面。


这是一个在社区中很少被讨论但却非常重要的问题。在使用 Tuist 的过程中，我们注意到许多组织和开发者认为他们当前面临的挑战将由 [Swift Package Manager](https://www.swift.org/documentation/package-manager/) 解决，但他们没有意识到的是，由于它建立在相同的原则之上，尽管它缓解了众所周知的 Git 冲突，却在其他方面降低了开发者体验，并继续使项目难以优化。

在接下来的部分中，我们将讨论一些真实案例，说明隐式性如何影响开发者体验和项目健康。这份清单并不详尽，但应该能让你很好地了解在使用 Xcode 项目或 Swift Packages 时可能面临的挑战。

## 便利带来的阻碍 {#convenience-getting-in-your-way}

### 共享构建产物目录 {#shared-built-products-directory}

Xcode 为每个产品在派生数据目录中使用一个专用目录。在其中，它存储构建产物，如编译后的二进制文件、dSYM 文件和日志。由于项目的所有产品都进入同一个目录，而其他目标默认可以看到该目录以进行链接，**你可能会得到相互隐式依赖的目标。** 虽然在只有少数几个目标时这可能不是问题，但随着项目增长，它可能会表现为难以调试的构建失败。

这种设计决策的后果是，许多项目意外地使用未良好定义的依赖图进行编译。

> [!TIP]
> **Tuist 对隐式依赖的检测**
>
> Tuist 提供了一个 <.localized_link href="/guides/features/projects/inspect/implicit-dependencies">命令</.localized_link> 来检测隐式依赖。你可以使用该命令在 CI 中验证所有依赖都是显式的。


### 在 Scheme 中查找隐式依赖 {#find-implicit-dependencies-in-schemes}

随着项目增长，在 Xcode 中定义和维护依赖图变得更加困难。难点在于它们以构建阶段和构建设置的形式编码在 `.pbxproj` 文件中，没有工具可以可视化和管理该图，并且图中的更改（例如添加新的动态预编译框架）可能需要上游配置更改（例如添加新的构建阶段以将框架复制到包中）。

Apple 曾在某个时刻决定，与其将图模型演变为更易于管理的形式，不如添加一个选项在构建时解析隐式依赖。这再次是一个值得商榷的设计选择，因为你可能会导致构建速度变慢或构建结果不可预测。例如，由于派生数据中的某些状态（充当 [单例](https://en.wikipedia.org/wiki/Singleton_pattern)），构建可能在本地通过，但由于状态不同，在 CI 上编译失败。

> [!TIP]
> 我们建议在你的项目 Scheme 中禁用此选项，并使用像 Tuist 这样的工具来简化依赖图的管理。


### SwiftUI 预览与静态库/框架 {#swiftui-previews-and-static-librariesframeworks}

某些编辑器功能（如 SwiftUI 预览或 Swift 宏）需要从正在编辑的文件编译依赖图。这种编辑器集成要求构建系统解析任何隐式性，并输出这些功能正常工作所需的正确产物。可想而知，**图越隐式，构建系统的任务就越具有挑战性**，因此许多这些功能无法可靠运行也就不足为奇了。我们经常听到开发者说，他们很久以前就停止使用 SwiftUI 预览，因为它们太不可靠了。相反，他们要么使用示例应用，要么避免某些事情，比如使用静态库或脚本构建阶段，因为这些会导致该功能失效。

### 可合并库 {#mergeable-libraries}

动态框架虽然更灵活且易于使用，但会对应用的启动时间产生负面影响。另一方面，静态库启动更快，但会影响编译时间，并且在复杂的依赖图场景中更难处理。*如果能根据配置在两者之间切换，那不是很好吗？* 这一定是 Apple 决定开发可合并库时的想法。但再一次，他们将更多的构建时推理移到了构建阶段。试想一下，如果目标的静态或动态性质将根据某些目标中的构建设置在构建时解析，那么对依赖图进行推理会有多困难。要想让这种方式可靠运行，同时确保 SwiftUI 预览等功能不失效，祝你好运。

**许多用户找到 Tuist 希望使用可合并库，而我们的回答始终如一：你不需要这样做。** 你可以在生成时控制目标的静态或动态性质，从而得到一个在编译前就已明确依赖图的项目。无需在构建时解析任何变量。

```bash
# The value of TUIST_DYNAMIC can be read from the project {#the-value-of-tuist_dynamic-can-be-read-from-the-project}
# to set the product as static or dynamic based on the value. {#to-set-the-product-as-static-or-dynamic-based-on-the-value}
TUIST_DYNAMIC=1 tuist generate
```

## 显式、显式、还是显式 {#explicit-explicit-and-explicit}

如果我们建议每个希望借助 Xcode 实现规模化开发的开发者或组织遵循一条重要的不成文原则，那就是拥抱显式性。如果原生 Xcode 项目难以管理显式性，他们应该考虑其他方案，比如 [Tuist](https://tuist.io) 或 [Bazel](https://bazel.build)。**只有这样，可靠性、可预测性和优化才成为可能。**

## 未来 {#future}

Apple 是否会采取措施防止上述所有问题尚不清楚。他们持续嵌入到 Xcode 和 Swift Package Manager 中的决策并未表明他们会这样做。一旦你将隐式配置视为有效状态，**就很难在不引入破坏性变更的情况下改变现状。** 回归第一性原理并重新思考工具的设计，可能会导致许多多年来偶然编译通过的 Xcode 项目失效。想象一下如果发生这种情况，社区会有多么哗然。

Apple 发现自己陷入了一个鸡生蛋、蛋生鸡的困境。便利性有助于开发者快速上手并为他们的生态系统构建更多应用。但他们为了在该规模上提供便利体验所做的决策，使得他们难以确保某些 Xcode 功能可靠运行。

由于未来未知，我们试图 **尽可能贴近行业标准和 Xcode 项目**。我们避免上述问题，并利用我们的知识提供更好的开发者体验。理想情况下，我们不必为此诉诸项目生成，但 Xcode 和 Swift Package Manager 缺乏可扩展性，使其成为唯一可行的选择。这也是一个安全的选择，因为他们必须破坏 Xcode 项目才能破坏 Tuist 项目。

理想情况下，**构建系统应具有更高的可扩展性**，但如果插件/扩展需要与一个充满隐式性的世界打交道，这难道不是一个坏主意吗？这似乎不是个好主意。因此，我们似乎需要像 Tuist 或 [Bazel](https://bazel.build) 这样的外部工具来提供更好的开发者体验。或者也许 Apple 会给我们带来惊喜，让 Xcode 更具可扩展性和显式性……

在那之前，你必须选择是接受 Xcode 的便利并承担随之而来的技术债务，还是信任我们在这段旅程中提供更好的开发者体验。我们不会让你失望。
