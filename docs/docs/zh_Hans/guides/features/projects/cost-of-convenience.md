---
{
  "title": "The cost of convenience",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the cost of convenience in Xcode and how Tuist helps you prevent the issues that come with it."
}
---
# 便利的代价{#the-cost-of-convenience}

**
设计一个从小型项目到大型项目都能使用的代码编辑器**是一项具有挑战性的任务。许多工具通过分层解决方案和提供可扩展性来解决这一问题。最底层是非常低级的，与底层构建系统非常接近，而最上层是高级抽象层，使用方便，但灵活性较差。通过这种方式，他们让简单的事情变得简单，让其他一切成为可能。

然而，**[Apple](https://www.apple.com) 决定在 Xcode**
中采用不同的方法。原因尚不清楚，但很可能是针对大型项目的挑战进行优化从来不是他们的目标。他们对小型项目的便利性投入过多，提供的灵活性较低，并将工具与底层构建系统强耦合。为了实现便利性，他们提供了合理的默认设置，而这些默认设置很容易被替换，他们还添加了许多隐式的构建时间解决行为，而这些行为正是大规模项目中许多问题的罪魁祸首。

## 明确性和规模{#explicitness-and-scale}

在大规模工作时，**明确性是关键** 。它允许构建系统提前分析和理解项目结构和依赖关系，并执行否则不可能实现的优化。同样的明确性也是确保[SwiftUI
预览](https://developer.apple.com/documentation/swiftui/previews-in-xcode)或[Swift
宏](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/)等编辑器功能可靠、可预测运行的关键。由于
Xcode 和 Xcode 项目将隐式作为实现便利性的有效设计选择，而 Swift 包管理器也继承了这一原则，因此使用 Xcode 时遇到的困难在 Swift
包管理器中也同样存在。

::: info THE ROLE OF TUIST
<!-- -->
我们可以将 Tuist 的作用概括为防止隐式定义项目并利用显式性提供更好的开发体验（如验证、优化）的工具。像
[Bazel](https://bazel.build) 这样的工具则更进一步，将其深入到构建系统层面。
<!-- -->
:::

这个问题在社区中鲜有讨论，但却意义重大。在开发 Tuist 的过程中，我们注意到许多组织和开发人员都认为 [Swift
包管理器](https://www.swift.org/documentation/package-manager/)
可以解决他们当前面临的挑战，但他们没有意识到的是，由于 [Swift
包管理器](https://www.swift.org/documentation/package-manager/) 基于相同的原则，即使它能缓解众所周知的
Git 冲突，也会降低开发人员在其他方面的体验，并继续使项目无法优化。

在下面的章节中，我们将讨论一些隐含性如何影响开发人员体验和项目健康的真实示例。该列表并不详尽，但可以让您很好地了解在使用 Xcode 项目或 Swift
包时可能面临的挑战。

## 方便妨碍你{#convenience-getting-in-your-way}

### 共享内置产品目录{#shared-built-products-directory}

Xcode 会在每个产品的派生数据目录内使用一个目录。其中存储了编译后的二进制文件、dSYM
文件和日志等构建工件。由于一个项目中的所有产品都存放在同一目录中，而其他目标链接默认情况下也能看到该目录，因此**，最终可能会出现目标相互隐式依赖的情况。**
虽然这在只有几个目标时可能不是问题，但当项目扩大时，可能会出现难以调试的构建失败。

这一设计决定的后果是，许多项目在编译时都会出现定义不清的图形。

::: tip TUIST DETECTION OF IMPLICIT DEPENDENCIES
<!-- -->
Tuist 提供了一个用于检测隐式依赖关系的
<LocalizedLink href="/guides/features/inspect/implicit-dependencies"> 命令</LocalizedLink>。您可以使用该命令在 CI 中验证所有依赖关系都是显式的。
<!-- -->
:::

### 查找方案中的隐式依赖关系{#find-implicit-dependencies-in-schemes}

随着项目的增长，在 Xcode 中定义和维护依赖关系图变得越来越困难。之所以困难，是因为它们被编译在`.pbxproj`
文件中，作为构建阶段和构建设置，没有工具来可视化和处理该图，而且图中的变化（例如添加一个新的动态预编译框架）可能需要上游的配置更改（例如添加一个新的构建阶段以将框架复制到
bundle 中）。

Apple
在某一时刻决定，与其将图模型演化成更易于管理的东西，不如在构建时添加一个解决隐式依赖关系的选项。这又是一个值得商榷的设计选择，因为最终可能会导致较慢的构建时间或不可预测的构建。例如，在本地编译时，可能会因为派生数据中的某些状态而通过，派生数据就像一个
[单例](https://en.wikipedia.org/wiki/Singleton_pattern)，但在 CI 上却会因为状态不同而编译失败。

::: tip
<!-- -->
我们建议在项目方案中禁用此功能，并使用 Tuist 等可简化依赖关系图管理的工具。
<!-- -->
:::

### SwiftUI 预览和静态库/框架{#swiftui-previews-and-static-librariesframeworks}

某些编辑器功能（如 SwiftUI 预览或 Swift
宏）需要从正在编辑的文件中编译依赖关系图。编辑器之间的这种集成要求构建系统解决任何隐含问题，并输出这些功能运行所需的正确工件。可以想象，**，图的隐含性越高，构建系统的任务就越具有挑战性**
，因此许多功能无法可靠运行也就不足为奇了。我们经常听到开发人员说，他们很久以前就停止使用 SwiftUI
预览版了，因为它们太不可靠。相反，他们要么使用示例应用程序，要么避免使用静态库或脚本构建阶段等特定功能，因为这些功能会导致功能崩溃。

### 可合并的图书馆{#mergeable-libraries}

动态框架虽然更灵活、更易于使用，但对应用程序的启动时间有负面影响。另一方面，静态库的启动速度更快，但会影响编译时间，而且有点难以操作，特别是在复杂的图形场景中。*如果能根据配置在二者之间做出选择，岂不美哉？*
当苹果公司决定开发可合并库时，他们肯定也是这么想的。但他们再次将更多的构建时推理转移到了构建时。如果要对依赖关系图进行推理，那么想象一下，当目标的静态或动态性质将在构建时根据某些目标的某些构建设置来解决时，我们就必须这样做。祝你好运，在确保
SwiftUI 预览等功能不被破坏的同时，还能让它可靠地工作。

**许多用户来到 Tuist，希望使用可合并库，而我们的回答始终如一。您不需要。**
您可以在生成时控制目标的静态或动态性质，从而在编译前就知道项目的图形。编译时无需解决变量问题。

```bash
# The value of TUIST_DYNAMIC can be read from the project {#the-value-of-tuist_dynamic-can-be-read-from-the-project}
# to set the product as static or dynamic based on the value. {#to-set-the-product-as-static-or-dynamic-based-on-the-value}
TUIST_DYNAMIC=1 tuist generate
```

## 明确、明确、再明确{#explicit-explicit-and-explicit}

如果说我们建议每一位希望使用 Xcode 进行开发的开发人员或组织能够扩展开发规模的重要非书面原则是什么的话，那就是他们应该接受明确性。如果明确性在原始
Xcode
项目中很难管理，那么他们就应该考虑其他方法，比如[Tuist](https://tuist.io)或[Bazel](https://bazel.build)。**只有这样，可靠性、可预测性和优化才有可能实现。**

## 未来{#future}

苹果公司是否会采取措施防止上述所有问题的发生，目前还不得而知。嵌入到 Xcode 和 Swift
软件包管理器中的持续决策并不表明他们会这样做。一旦允许将隐式配置作为有效状态，**，就很难在不引入破坏性更改的情况下继续前进。**
回到最初的原则并重新思考工具的设计可能会导致许多多年来意外编译的 Xcode 项目被破坏。试想一下，如果出现这种情况，社区会有多大的反响。

苹果公司发现自己陷入了一个 "先有鸡还是先有蛋
"的问题。便利性可以帮助开发者快速上手，并为其生态系统构建更多应用程序。但是，他们决定在这种规模下提供便利的体验，却使他们难以确保 Xcode
的某些功能能够可靠地运行。

因为未来是未知的，所以我们尝试**，尽可能接近行业标准和 Xcode 项目**
。我们防止出现上述问题，并利用我们所掌握的知识为开发人员提供更好的体验。理想情况下，我们不需要借助项目生成来实现这一点，但由于 Xcode 和 Swift
包管理器缺乏可扩展性，因此这是唯一可行的选择。这也是一个安全的选择，因为他们必须破坏 Xcode 项目才能破坏 Tuist 项目。

理想情况下，**，构建系统的可扩展性会更强** ，但让插件/扩展与一个隐含的世界签订合同不是个好主意吗？这似乎不是个好主意。因此，我们似乎需要 Tuist 或
[Bazel](https://bazel.build) 这样的外部工具来提供更好的开发体验。或者，也许苹果会给我们带来惊喜，让 Xcode
变得更加可扩展和显式...

在此之前，您必须选择是接受 Xcode 的信念并承担随之而来的债务，还是相信我们在提供更好的开发者体验的旅程中。我们不会让您失望的。
