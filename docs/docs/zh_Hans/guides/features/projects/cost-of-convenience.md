---
{
  "title": "The cost of convenience",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about the cost of convenience in Xcode and how Tuist helps you prevent the issues that come with it."
}
---
# 便利的代价{#the-cost-of-convenience}

设计一款适用于从小型到大型项目（**）的代码编辑器（**
）是项艰巨任务。许多工具通过分层解决方案和提供可扩展性来应对这一挑战：底层非常低级且贴近底层构建系统，顶层则是便于使用但灵活性较低的高级抽象。通过这种方式，它们让简单的事情变得容易，同时使其他一切成为可能。

然而，**[Apple](https://www.apple.com) 在 Xcode**
中选择了不同方案。具体原因虽不明确，但很可能优化大型项目挑战从未是他们的目标。他们过度追求小型项目的便利性，提供极少灵活性，并将工具与底层构建系统强耦合。
为实现便捷性，他们提供了可轻松替换的合理默认值，并添加了大量隐式构建时解析的行为——这些正是大规模项目中诸多问题的根源。

## 明确性与规模{#explicitness-and-scale}

在处理大规模项目时，**的显式性至关重要** 。它使构建系统能够预先分析和理解项目结构及依赖关系，从而实现其他方式无法实现的优化。
这种明确性同样是确保编辑器功能（如[SwiftUI预览](https://developer.apple.com/documentation/swiftui/previews-in-xcode)或[Swift宏](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/)）稳定可靠运作的关键。由于Xcode及其项目采用隐式设计以提升便捷性——这一原则被Swift
Package Manager继承——因此Xcode的使用难题同样存在于Swift Package Manager中。

::: info THE ROLE OF TUIST
<!-- -->
Tuist
的核心作用可概括为：通过防止隐式定义项目并强化显式化设计（如验证机制、优化方案），从而提升开发者体验。诸如[Bazel](https://bazel.build)等工具则将此理念深化至构建系统层面。
<!-- -->
:::

这是社区鲜少讨论却至关重要的问题。 在开发Tuist的过程中，我们发现许多组织和开发者认为[Swift Package
Manager](https://www.swift.org/documentation/package-manager/)能解决当前面临的挑战，但他们未意识到：由于该工具基于相同原理构建，尽管它缓解了众所周知的Git冲突问题，却在其他方面降低了开发体验，并持续导致项目无法优化。

在后续章节中，我们将通过实际案例探讨隐含性如何影响开发者体验及项目健康度。以下列举虽非穷尽，但足以让你了解在处理Xcode项目或Swift包时可能面临的挑战。

## 便利性妨碍了你{#convenience-getting-in-your-way}

### 共享构建产品目录{#shared-built-products-directory}

Xcode 为每个产品在衍生数据目录内创建独立目录。
该目录用于存储构建产物，包括编译后的二进制文件、dSYM文件及日志。由于项目所有产物均存放于同一目录（默认情况下其他目标可见），**这可能导致目标间产生隐式依赖关系。**
当项目规模较小时此问题尚不明显，但随着项目增长，可能引发难以调试的构建失败。

此设计决策的后果是，许多项目会意外地使用未明确定义的图进行编译。

::: tip TUIST DETECTION OF IMPLICIT DEPENDENCIES
<!-- -->
Tuist提供<LocalizedLink href="/guides/features/inspect/implicit-dependencies">命令</LocalizedLink>用于检测隐式依赖关系。您可在CI环境中使用该命令验证所有依赖项是否已显式声明。
<!-- -->
:::

### 在方案中查找隐含依赖关系{#find-implicit-dependencies-in-schemes}

随着项目规模扩大，在Xcode中定义和维护依赖关系图变得越来越困难。 其复杂性在于：依赖关系被固化在` 的.pbxproj和`
文件中，以构建阶段和构建设置的形式存在。目前缺乏可视化工具来处理该图，且图结构的变更（如新增动态预编译框架）可能需要上游配置调整（例如添加新构建阶段将框架复制到程序包）。

苹果公司曾决定，与其将图模型演进为更易管理的形态，不如在构建时添加解决隐式依赖的选项。这再次是个值得商榷的设计选择——可能导致构建速度变慢或出现不可预测的构建结果。例如：由于派生数据中某个充当[单例](https://en.wikipedia.org/wiki/Singleton_pattern)的状态，本地构建可能通过，但因状态差异导致CI环境编译失败。

::: tip
<!-- -->
建议在项目方案中禁用此功能，并采用Tuist等工具来简化依赖关系图的管理。
<!-- -->
:::

### SwiftUI 预览与静态库/框架{#swiftui-previews-and-static-librariesframeworks}

某些编辑器功能（如SwiftUI预览或Swift宏）需要从编辑文件中构建依赖关系图。这种编辑器集成要求构建系统解析所有隐式依赖并输出正确工件以支持功能运行。正如您所知，**关系图隐式程度越高，**
构建系统的任务难度就越大，因此这些功能难以稳定运行也就不足为奇了。
我们常听到开发者反馈，他们早已因预览功能过于不可靠而放弃使用SwiftUI预览。取而代之的是，他们要么依赖示例应用，要么刻意规避某些操作——例如静态库或脚本构建阶段的使用，因为这些操作会导致功能失效。

### 可合并库{#mergeable-libraries}

动态框架虽更灵活易用，却会影响应用启动速度。静态库则能加快启动速度，但会延长编译时间且操作稍显复杂，尤其在复杂图场景中。*若能根据配置在二者间切换岂不美妙？*
这正是苹果开发可合并库时的初衷。
但他们再次将更多构建时推理推向了构建阶段。试想分析依赖关系图时，目标库的静态/动态属性需根据某些目标的构建设置在构建时动态解析——要确保SwiftUI预览等功能不被破坏的同时实现可靠运行，这简直是场硬仗。

**许多用户来到Tuist希望使用可合并库，而我们的回答始终如一：您无需如此。**
您可在生成时控制目标的静态或动态特性，从而构建出在编译前即可确定图结构的项目。构建时无需解析任何变量。

```bash
# The value of TUIST_DYNAMIC can be read from the project {#the-value-of-tuist_dynamic-can-be-read-from-the-project}
# to set the product as static or dynamic based on the value. {#to-set-the-product-as-static-or-dynamic-based-on-the-value}
TUIST_DYNAMIC=1 tuist generate
```

## 明确、明确、再明确{#explicit-explicit-and-explicit}

对于希望通过Xcode实现可扩展开发的每位开发者或组织，我们建议遵循一项重要的非书面原则：务必坚持显式编程。若原始Xcode项目难以实现显式编程，则应考虑采用其他方案，如[Tuist](https://tuist.io)或[Bazel](https://bazel.build)。**唯有如此，才能实现可靠性、可预测性和优化效果。**

## 未来{#future}

苹果是否会采取措施解决上述所有问题尚不可知。其持续嵌入Xcode和Swift Package
Manager的决策并未显示出这种意图。一旦默认配置被视为有效状态（**），要避免引入破坏性变更就难以回溯。**
若回归基本原则重新设计工具，可能导致大量多年来意外编译成功的Xcode项目失效。试想若真发生这种情况，社区将掀起何等轩然大波。

苹果公司正面临一个先有鸡还是先有蛋的困境。便捷性虽能帮助开发者快速入门并为其生态系统构建更多应用，但这种大规模追求便捷性的决策，却使其难以确保某些Xcode功能的稳定运行。

由于未来充满未知，我们努力**尽可能贴近行业标准和Xcode项目规范** 。我们规避上述问题，并运用现有知识提供更优质的开发者体验。
理想情况下我们不应依赖项目生成机制，但Xcode与Swift Package
Manager的扩展性不足使其成为唯一可行方案。这也是最稳妥的选择——因为破坏Tuist项目将必然导致Xcode项目失效。

理想情况下，**构建系统本应更具可扩展性**
，但若插件/扩展需与隐含逻辑交互，岂非弊大于利？这似乎并非良策。因此我们可能需要借助Tuist或[Bazel](https://bazel.build)等外部工具来提升开发体验。当然，苹果或许会带来惊喜，让Xcode变得更具可扩展性且更显式化...

在此之前，您需要权衡：是选择Xcode带来的便利并承担随之而来的技术债务，还是信任我们在这段旅程中为您打造更优质的开发体验。我们绝不会让您失望。
