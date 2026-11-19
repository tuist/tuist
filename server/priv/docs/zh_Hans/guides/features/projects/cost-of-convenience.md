---
{
  "title": "便利的代价",
  "titleTemplate": ":title · 项目 · 功能 · 指南 · Tuist",
  "description": "Xcode 的隐式行为如何引发问题，以及 Tuist 如何防止这些问题。"
}
---
# 便捷的代价 {#the-cost-of-convenience}

设计一款能够胜任**各种规模项目，从小型到大型**的代码编辑器是一项艰巨的任务。许多工具通过分层架构和提供可扩展性来解决这一问题。最底层非常接近底层构建系统，而最顶层则是易于使用但灵活性较低的高级抽象。通过这种方式，它们让简单的事情变得容易，也让其他一切成为可能。

然而，**[Apple](https://www.apple.com) 决定为 Xcode 采取不同的方法**。原因尚不明确，但很可能优化大规模项目的挑战从来不是他们的目标。他们在小型项目的便捷性上投入过多，提供的灵活性很少，并将工具与底层构建系统紧密耦合。为了实现这种便捷，他们提供了合理的默认值（你可以轻松替换），并添加了许多在构建时隐式解析的行为，这些行为正是导致大规模项目中出现许多问题的根源。

## 明确性与规模 {#explicitness-and-scale}

在大规模开发中，**明确性至关重要**。它允许构建系统提前分析和理解项目结构及依赖关系，并执行否则无法实现的优化。同样的明确性对于确保诸如 [SwiftUI previews](https://developer.apple.com/documentation/swiftui/previews-in-xcode) 或 [Swift Macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/) 等编辑器功能可靠且可预测地工作也至关重要。由于 Xcode 和 Xcode 项目将隐式性作为一种实现便捷的有效设计选择——这一原则也被 Swift Package Manager 所继承——因此使用 Xcode 的困难同样存在于 Swift Package Manager 中。

> [!NOTE]
> **Tuist 的角色**
>
> 我们可以将 Tuist 的角色总结为：一款防止隐式定义项目并利用明确性来提供更好的开发者体验（例如验证、优化）的工具。像 [Bazel](https://bazel.build) 这样的工具则更进一步，将其下沉到构建系统层面。


这是一个在社区中很少被讨论但却非常重要的问题。在使用 Tuist 的过程中，我们注意到许多组织和开发者认为他们当前面临的挑战将由 [Swift Package Manager](https://www.swift.org/documentation/package-manager/) 解决，但他们没有意识到的是，由于它建立在相同的原则之上，尽管它缓解了众所周知的 Git 冲突，却在其他方面降低了开发者体验，并继续使项目难以优化。

在接下来的部分中，我们将讨论一些真实案例，说明隐式性如何影响开发者体验和项目健康。这份列表并不详尽，但应该能让你很好地了解在使用 Xcode 项目或 Swift Packages 时可能面临的挑战。

## 便捷带来的阻碍 {#convenience-getting-in-your-way}

### 共享构建产物目录 {#shared-built-products-directory}

Xcode 为每个产品在派生数据目录中使用一个子目录。在其中，它存储构建产物，如编译后的二进制文件、dSYM 文件和日志。由于项目的所有产品都进入同一个目录，而其他目标默认可以看到该目录并进行链接，**你可能会得到相互隐式依赖的目标。** 虽然这在只有少数几个目标时可能不是问题，但随着项目增长，它可能表现为难以调试的构建失败。

这种设计决策的后果是，许多项目意外地使用了一个定义不明确的依赖图进行编译。

> [!TIP]
> **Tuist 对隐式依赖的检测**
>
> Tuist 提供了一个<.localized_link href="/guides/features/projects/inspect/implicit-dependencies">命令</.localized_link>来检测隐式依赖。你可以使用该命令在 CI 中验证所有依赖都是显式的。


### 在 Scheme 中查找隐式依赖 {#find-implicit-dependencies-in-schemes}

随着项目增长，在 Xcode 中定义和维护依赖图变得更加困难。难点在于它们以构建阶段和构建设置的形式编码在 `.pbxproj` 文件中，没有工具可以可视化和管理该图，并且图中的更改（例如添加新的动态预编译框架）可能需要上游配置更改（例如添加新的构建阶段以将框架复制到 bundle 中）。

Apple 在某个时刻决定，与其将图模型演变为更易于管理的形式，不如添加一个选项在构建时解析隐式依赖。这再次是一个值得商榷的设计选择，因为你可能最终面临更慢的构建速度或不可预测的构建结果。例如，由于派生数据中的某些状态（其作用类似于 [单例](https://en.wikipedia.org/wiki/Singleton_pattern)），构建可能在本地通过，但由于状态不同而在 CI 上编译失败。

> [!TIP]
> 我们建议在你的项目 Scheme 中禁用此选项，并使用像 Tuist 这样简化依赖图管理的工具。


### SwiftUI Previews 与静态库/框架 {#swiftui-previews-and-static-librariesframeworks}

某些编辑器功能（如 SwiftUI Previews 或 Swift Macros）需要从正在编辑的文件编译依赖图。这种编辑器与构建系统的集成要求构建系统解析任何隐式性，并输出这些功能正常工作所需的正确产物。可想而知，**图越隐式，构建系统的任务就越具有挑战性**，因此许多这些功能无法可靠工作也就不足为奇了。我们经常听到开发者说，他们很久以前就停止使用 SwiftUI previews，因为它们太不可靠了。相反，他们要么使用示例应用，要么避免某些事情，比如使用静态库或脚本构建阶段，因为这些会导致该功能失效。

### 可合并库 {#mergeable-libraries}

动态框架虽然更灵活、更易于使用，但会对应用的启动时间产生负面影响。另一方面，静态库启动更快，但会影响编译时间，并且在复杂的依赖图场景中更难处理。*如果能根据配置在两者之间切换，那不是很好吗？* 这大概就是 Apple 决定开发可合并库时的想法。但再一次，他们将更多的构建时推断移到了构建阶段。试想一下，如果需要在构建时根据某些目标的构建设置来解析目标是静态还是动态的，那么推理依赖图将变得多么困难。要想让这种机制可靠运行，同时确保 SwiftUI previews 等功能不失效，恐怕并非易事。

**许多用户找到 Tuist 时希望使用可合并库，而我们的回答始终如一：你不需要这样做。** 你可以在生成时控制目标的静态或动态属性，从而得到一个在编译前就已明确依赖图的项目。无需在构建时解析任何变量。

```bash
# The value of TUIST_DYNAMIC can be read from the project {#the-value-of-tuist_dynamic-can-be-read-from-the-project}
# to set the product as static or dynamic based on the value.
TUIST_DYNAMIC=1 tuist generate
```

## 显式，显式，还是显式 {#explicit-explicit-and-explicit}

如果说有一条重要的不成文原则，我们建议每一位希望借助 Xcode 实现规模化开发的开发者或组织都应当遵循，那就是拥抱显式性。如果在使用原生 Xcode 项目时难以管理显式性，那么你应该考虑其他方案，比如 [Tuist](https://tuist.dev) 或 [Bazel](https://bazel.build)。**只有这样，可靠性、可预测性和优化才成为可能。**

## 未来 {#future}

Apple 是否会采取措施防止上述所有问题尚不得而知。他们持续在 Xcode 和 Swift Package Manager 中做出的决策并未显示出这种迹象。一旦你将隐式配置视为有效状态，**就很难在不引入破坏性变更的情况下摆脱这种局面。** 回归第一性原理并重新思考工具的设计，可能会导致多年来偶然能够编译的许多 Xcode 项目失效。想象一下，如果这种情况发生，社区将会引起多大的轰动。

Apple 发现自己陷入了一个类似“鸡生蛋还是蛋生鸡”的困境。便利性有助于开发者快速上手并为他们的生态系统构建更多应用。但是，他们为了在这种规模上提供便利体验而做出的决策，使得他们难以确保某些 Xcode 功能可靠运行。

由于未来充满不确定性，我们努力**尽可能贴近行业标准和 Xcode 项目**。我们避免上述问题，并利用我们所掌握的知识提供更好的开发者体验。理想情况下，我们本不必为此诉诸项目生成，但 Xcode 和 Swift Package Manager 缺乏可扩展性，使得项目生成成为唯一可行的选择。这也是一个安全的选择，因为他们必须破坏 Xcode 项目才能破坏 Tuist 项目。

理想情况下，**构建系统应具有更强的可扩展性**，但如果插件/扩展需要与一个充满隐式性的世界打交道，这难道不是一个糟糕的主意吗？这似乎并不是一个好主意。因此，看来我们需要像 Tuist 或 [Bazel](https://bazel.build) 这样的外部工具来提供更好的开发者体验。或者也许 Apple 会给我们带来惊喜，让 Xcode 更具可扩展性和显式性……

在那之前，你必须做出选择：是接受 Xcode 的便利性并承担随之而来的技术债务，还是信任我们在这段旅程中为你提供更好的开发者体验。我们不会让你失望。
