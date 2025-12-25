---
{
  "title": "Dependencies",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to declare dependencies in your Tuist project."
}
---
# 依赖项 {#dependencies｝

当一个项目发展壮大时，通常会将其拆分为多个目标，以共享代码、定义边界并缩短构建时间。多个目标意味着要定义它们之间的依赖关系，形成**依赖关系图**
，其中可能还包括外部依赖关系。

## XcodeProj 代码化图形 {#xcodeprojcodified-graphs}

由于 Xcode 和 XcodeProj 的设计，维护依赖关系图可能是一项繁琐且容易出错的任务。以下是您可能会遇到的问题的一些示例：

- 由于 Xcode 的构建系统会将项目的所有产品输出到派生数据的同一目录中，因此目标可能会导入不该导入的产品。编译可能会在 CI 上失败，而在 CI
  上，干净的编译更为常见，或者以后使用不同的配置时，编译可能会失败。
- 目标的传递动态依赖项需要复制到`LD_RUNPATH_SEARCH_PATHS`
  联编设置中的任何目录。否则，目标将无法在运行时找到它们。当图形较小时，这很容易考虑和设置，但当图形增大时就会成为问题。
- 当目标链接静态
  [XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle)
  时，目标需要一个额外的构建阶段，以便 Xcode 处理捆绑包并为当前平台和架构提取正确的二进制文件。该构建阶段不会自动添加，而且很容易忘记添加。

以上只是几个例子，多年来我们遇到过的例子还有很多。想象一下，如果你需要一个工程师团队来维护依赖关系图并确保其有效性。更糟糕的是，这些错综复杂的问题在构建时由一个你无法控制或定制的闭源构建系统来解决。听起来耳熟吗？这就是
Apple 在 Xcode 和 XcodeProj 中采用的方法，也是 Swift 包管理器所继承的方法。

我们坚信，依赖关系图应该是**显式的** 和**静态的** ，因为只有这样，依赖关系图才能被**验证** 和**优化** 。有了
Tuist，您只需描述什么依赖于什么，剩下的就交给我们吧。错综复杂的实现细节将被抽象出来。

在以下章节中，您将学习如何在项目中声明依赖关系。

提示图形验证
<!-- -->
Tuist 在生成项目时会对图形进行验证，以确保不存在循环，并且所有依赖关系都是有效的。正因为如此，任何团队都可以参与依赖关系图的演进，而不必担心会破坏它。
<!-- -->
:::

## 本地依赖项 {#local-dependencies}

目标可以依赖同一项目或不同项目中的其他目标，也可以依赖二进制文件。在实例化`Target` 时，可以通过`dependencies` 参数和以下任一选项：

- `目标` ：声明同一项目中目标的依赖关系。
- `项目` ：声明目标位于不同项目中的依赖关系。
- `框架` ：声明与二进制框架的依赖关系。
- `库` ：声明与二进制库的依赖关系。
- `XCFramework` ：声明与二进制 XCFramework 的依赖关系。
- `SDK` ：声明与系统 SDK 的依赖关系。
- `XCTest` ：声明与 XCTest 的依赖关系。

信息依赖条件
<!-- -->
每种依赖关系类型都接受`condition` 选项，用于根据平台有条件地链接依赖关系。默认情况下，它会为目标支持的所有平台链接依赖关系。
<!-- -->
:::

## 外部依赖性 {#external-dependencies}

Tuist 还允许您在项目中声明外部依赖关系。

### Swift 软件包 {#swift-packages}

Swift 包是我们推荐的在项目中声明依赖关系的方式。您可以使用 Xcode 的默认集成机制或 Tuist 基于 XcodeProj 的集成来集成它们。

#### 基于 XcodeProj 的 Tuist 集成 {#tuists-xcodeprojbased-integration}

Xcode 的默认集成虽然是最方便的集成，但缺乏大中型项目所需的灵活性和控制性。为了克服这一问题，Tuist 提供了基于 XcodeProj 的集成，允许您使用
XcodeProj 的目标在您的项目中集成 Swift
包。因此，我们不仅可以让您对集成进行更多控制，还可以使其与<LocalizedLink href="/guides/features/cache">缓存</LocalizedLink>和<LocalizedLink href="/guides/features/test/selective-testing">选择性测试运行</LocalizedLink>等工作流兼容。

XcodeProj 的集成更有可能需要更多时间来支持新的 Swift 包功能或处理更多的包配置。不过，Swift 包和 XcodeProj
目标之间的映射逻辑是开源的，可以由社区贡献。这与 Xcode 的默认集成相反，后者是闭源的，由 Apple 维护。

要添加外部依赖项，必须在`Tuist/` 或项目根目录下创建`Package.swift` 。

代码组
```swift [Tuist/Package.swift]
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription
    import ProjectDescriptionHelpers

    let packageSettings = PackageSettings(
        productTypes: [
            "Alamofire": .framework, // default is .staticFramework
        ]
    )

#endif

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
    ],
    targets: [
        .binaryTarget(
            name: "Sentry",
            url: "https://github.com/getsentry/sentry-cocoa/releases/download/8.40.1/Sentry.xcframework.zip",
            checksum: "db928e6fdc30de1aa97200576d86d467880df710cf5eeb76af23997968d7b2c7"
        ),
    ]
)
```
<!-- -->
:::

提示软件包设置
<!-- -->
`PackageSettings`
实例封装在编译器指令中，允许你配置软件包的集成方式。例如，在上面的示例中，它用于覆盖用于软件包的默认产品类型。默认情况下，您不需要它。
<!-- -->
:::

> [！重要] 自定义编译配置 如果您的项目使用自定义编译配置（除标准的`Debug` 和`Release`
> 之外的配置），您必须在`PackageSettings` 中使用`baseSettings` 指定它们。外部依赖项需要了解项目的配置才能正确构建。例如
> 
> ```swift
> #if TUIST
>     import ProjectDescription
> 
>     let packageSettings = PackageSettings(
>         productTypes: [:],
>         baseSettings: .settings(configurations: [
>             .debug(name: "Base"),
>             .release(name: "Production")
>         ])
>     )
> #endif
> ```
> 
> 更多详情，请参见 [#8345](https://github.com/tuist/tuist/issues/8345) 。

`Package.swift`
文件只是一个用于声明外部依赖关系的接口，仅此而已。这就是为什么在软件包中不定义任何目标或产品的原因。一旦定义了依赖关系，就可以运行以下命令来解析依赖关系并将其拉入`Tuist/Dependencies`
目录：

```bash
tuist install
# Resolving and fetching dependencies. {#resolving-and-fetching-dependencies}
# Installing Swift Package Manager dependencies. {#installing-swift-package-manager-dependencies}
```

正如您可能已经注意到的，我们采用的方法与
[CocoaPods](https://cocoapods.org)'类似，将依赖关系的解析作为自己的命令。这让用户可以控制何时解决和更新依赖关系，并允许在项目中打开
Xcode 并准备编译。我们认为，随着项目的增长，苹果与 Swift 软件包管理器的集成所提供的开发人员体验也会随时间的推移而下降。

然后，您可以在项目目标中使用`TargetDependency.external` 依赖关系类型引用这些依赖关系：

代码组
```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "App",
    organizationName: "tuist.io",
    targets: [
        .target(
            name: "App",
            destinations: [.iPhone],
            product: .app,
            bundleId: "dev.tuist.app",
            deploymentTargets: .iOS("13.0"),
            infoPlist: .default,
            sources: ["Targets/App/Sources/**"],
            dependencies: [
                .external(name: "Alamofire"), // [!code ++]
            ]
        ),
    ]
)
```
<!-- -->
:::

::: 信息 不为外部软件包生成程序
<!-- -->
**schemes** 不会为 Swift Package 项目自动创建，以保持方案列表的整洁。您可以通过 Xcode 的用户界面创建它们。
<!-- -->
:::

#### Xcode 的默认集成 {#xcodes-default-integration}

如果想使用 Xcode 的默认集成机制，可以在实例化项目时通过`软件包列表` ：

```swift
let project = Project(name: "MyProject", packages: [
    .remote(url: "https://github.com/krzyzanowskim/CryptoSwift", requirement: .exact("1.8.0"))
])
```

然后从目标中引用它们：

```swift
let target = .target(name: "MyTarget", dependencies: [
    .package(product: "CryptoSwift", type: .runtime)
])
```

对于 Swift 宏和构建工具插件，您需要分别使用`.macro` 和`.plugin` 类型。

警告SPM构建工具插件
<!-- -->
必须使用 [Xcode 的默认集成](#xcode-s-default-integration)机制声明 SPM 构建工具插件，即使在使用 Tuist 的
[基于 XcodeProj 的集成](#tuist-s-xcodeproj-based-integration)来声明项目依赖关系时也是如此。
<!-- -->
:::

SPM 构建工具插件的一个实际应用是在 Xcode 的 "运行构建工具插件 "构建阶段执行代码检查。在软件包清单中的定义如下：

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Framework",
    products: [
        .library(name: "Framework", targets: ["Framework"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", .upToNextMajor(from: "0.56.1")),
    ],
    targets: [
        .target(
            name: "Framework",
            plugins: [
                .plugin(name: "SwiftLint", package: "SwiftLintPlugin"),
            ]
        ),
    ]
)
```

要生成一个不含构建工具插件的 Xcode 项目，必须在项目清单的`packages` 数组中声明软件包，然后在目标的依赖项中包含一个类型为`.plugin`
的软件包。

```swift
import ProjectDescription

let project = Project(
    name: "Framework",
    packages: [
        .remote(url: "https://github.com/SimplyDanny/SwiftLintPlugins", requirement: .upToNextMajor(from: "0.56.1")),
    ],
    targets: [
        .target(
            name: "Framework",
            dependencies: [
                .package(product: "SwiftLintBuildToolPlugin", type: .plugin),
            ]
        ),
    ]
)
```

### 迦太基

由于 [Carthage](https://github.com/carthage/carthage) 会输出`frameworks`
或`xcframeworks` ，因此可以运行`carthage update` 输出`Carthage/Build`
目录中的依赖关系，然后使用`.framework` 或`.xcframework` target
依赖关系类型在目标中声明依赖关系。您可以在生成项目前运行脚本来实现这一点。

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

警告：构建和测试
<!-- -->
如果通过`tuist build` 和`tuist test` 来构建和测试项目，同样需要在运行`tuist build` 或`tuist test`
命令之前，运行`carthage update` 命令，以确保存在已解决的 Carthage 依赖项。
<!-- -->
:::

### 可可拼盘 {#cocoapods}

[CocoaPods](https://cocoapods.org)需要一个 Xcode 项目来集成依赖项。您可以使用 Tuist 生成项目，然后运行`pod
install` ，通过创建包含项目和 Pods 依赖项的工作区来集成依赖项。您可以在生成项目前运行脚本来实现这一点。

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

:: 警告
<!-- -->
CocoaPods 依赖关系与`build` 或`test` 等工作流不兼容，这些工作流会在生成项目后立即运行`xcodebuild`
。它们还与二进制缓存和选择性测试不兼容，因为指纹识别逻辑没有考虑 Pods 依赖关系。
<!-- -->
:::

## 静态或动态 {#static-or-dynamic}

框架和库可以静态或动态链接，**，这一选择对应用程序大小和启动时间等方面有重大影响** 。尽管这一选择很重要，但人们在做出这一决定时往往并没有过多考虑。

**一般经验法则** 是，在发布版本中，尽可能多的东西要静态链接，以实现快速启动；在调试版本中，尽可能多的东西要动态链接，以实现快速迭代。

在项目图中改变静态链接和动态链接之间的关系在 Xcode
中并非易事，因为改变会对整个项目图产生连带影响（例如，库不能包含资源，静态框架无需嵌入）。苹果试图通过编译时解决方案来解决这一问题，例如 Swift
包管理器自动决定静态链接和动态链接，或 [Mergeable
Libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)。但是，这样会在编译图中添加新的动态变量，增加新的非确定性来源，并可能导致一些依赖于编译图的功能（如
Swift 预览）变得不可靠。

幸运的是，Tuist
从概念上压缩了在静态和动态之间切换的复杂性，并合成了跨链接类型的标准<LocalizedLink href="/guides/features/projects/synthesized-files#bundle-accessors">捆绑访问器</LocalizedLink>。结合<LocalizedLink href="/guides/features/projects/dynamic-configuration">通过环境变量进行的动态配置</LocalizedLink>，你可以在调用时传递链接类型，并在清单中使用该值来设置目标的产品类型。

```swift
// Use the value returned by this function to set the product type of your targets.
func productType() -> Product {
    if case let .string(linking) = Environment.linking {
        return linking == "static" ? .staticFramework : .framework
    } else {
        return .framework
    }
}
```

请注意，由于成本问题，Tuist <LocalizedLink href="/guides/features/projects/cost-of-convenience">并不会通过隐式配置默认为便捷型</LocalizedLink>。这意味着，我们需要您设置链接类型，以及有时需要的其他构建设置（如[`-ObjC` linker flag](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184)），以确保生成的二进制文件正确无误。因此，我们的立场是为您提供资源，通常是以文档的形式，让您做出正确的决定。

::: tip EXAMPLE: THE COMPOSABLE ARCHITECTURE
<!-- -->
许多项目都集成了[可组合架构](https://github.com/pointfreeco/swift-composable-architecture)这个 Swift 软件包。更多详情，请参阅 [本节](#the-composable-architecture)。
<!-- -->
:::

### 情景 {#scenarios}

在某些情况下，将链接完全设置为静态或动态是不可行的，也不是一个好主意。下面列出了可能需要混合使用静态和动态链接的一些情况，但并非详尽无遗：

- **带有扩展的应用程序：**
  由于应用程序及其扩展需要共享代码，因此可能需要将这些目标设为动态目标。否则，应用程序和扩展会重复使用相同的代码，导致二进制文件增大。
- **预编译外部依赖：** 有时，系统会提供预编译的静态或动态二进制文件。静态二进制文件可以封装在动态框架或库中，以便动态链接。

对图形进行更改时，Tuist 会对其进行分析，如果检测到
"静态副作用"，则会显示警告。该警告旨在帮助您识别静态链接目标时可能出现的问题，因为该目标通过动态目标过渡依赖于静态目标。这些副作用通常表现为二进制文件大小增大，最严重的情况是运行时崩溃。

## 故障排除 {#troubleshooting}

### Objective-C 依赖项 {#objectivec-dependencies}

在集成 Objective-C 依赖项时，可能需要在消费目标上包含某些标志，以避免运行时崩溃，详见[Apple 技术问答
QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html)。

由于构建系统和 Tuist 无法推断该标记是否必要，而且该标记可能会带来不良的副作用，因此 Tuist 不会自动应用这些标记，而且由于 Swift
软件包管理器认为`-ObjC` 是通过`.unsafeFlag` 包含的，因此大多数软件包在需要时无法将其作为默认链接设置的一部分。

在需要时，Objective-C 依赖项（或内部 Objective-C 目标）的消费者应通过在消费目标上设置`OTHER_LDFLAGS`
来应用`-ObjC` 或`-force_load` 标志。

### Firebase 和其他 Google 库 {#firebase-other-google-libraries}

谷歌的开源库虽然功能强大，但很难集成到 Tuist 中，因为它们在构建过程中通常使用非标准的架构和技术。

以下是集成 Firebase 和谷歌其他苹果平台库时可能需要遵循的一些提示：

#### 确保`-ObjC` 添加至`OTHER_LDFLAGS` {#ensure-objc-is-added-to-other_ldflags}

Google 的许多库都是用 Objective-C 编写的。因此，任何消费目标都需要在其`OTHER_LDFLAGS` 构建设置中包含`-ObjC`
标签。这可以在`.xcconfig` 文件中设置，也可以在 Tuist 清单中的目标设置中手动指定。举例说明

```swift
Target.target(
    ...
    settings: .settings(
        base: ["OTHER_LDFLAGS": "$(inherited) -ObjC"]
    )
    ...
)
```

有关详情，请参阅上文 [Objective-C Dependencies](#objective-c-dependencies) 部分。

#### 将`FBLPromises` 的产品类型设置为动态框架 {#set-the-product-type-for-fblpromises-to-dynamic-framework}

某些 Google 库依赖于`FBLPromises` ，这是 Google 的另一个库。您可能会遇到这样的崩溃：`FBLPromises` ，看起来像这样：

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

在`Package.swift` 文件中，将`FBLPromises` 的产品类型明确设置为`.framework` ，应该可以解决问题：

```swift [Tuist/Package.swift]
// swift-tools-version: 5.10

import PackageDescription

#if TUIST
import ProjectDescription
import ProjectDescriptionHelpers

let packageSettings = PackageSettings(
    productTypes: [
        "FBLPromises": .framework,
    ]
)
#endif

let package = Package(
...
```

### 可组合架构 {#the-composable-architecture}

如[此处](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184)和[故障排除部分](#troubleshooting)所述，在静态链接软件包（Tuist
默认的链接类型）时，需要将`OTHER_LDFLAGS` 构建设置设置为`$(inherited) -ObjC`
。或者，也可以覆盖产品类型，将软件包设置为动态。静态链接时，测试和应用程序目标通常可以正常工作，但 SwiftUI
预览会被破坏。这可以通过动态链接来解决。在下面的示例中，[Sharing](https://github.com/pointfreeco/swift-sharing)也被添加为依赖关系，因为它经常与可组合架构（The
Composable
Architecture）一起使用，并且有自己的[配置陷阱](https://github.com/pointfreeco/swift-sharing/issues/150#issuecomment-2797107032)。

以下配置将动态链接所有内容，因此应用程序 + 测试目标和 SwiftUI 预览都能正常工作。

静态或动态提示
<!-- -->
并不总是建议使用动态链接。详见 [静态还是动态](#static-or-dynamic) 部分。在本例中，为简单起见，所有依赖关系都是无条件动态链接的。
<!-- -->
:::

```swift [Tuist/Package.swift]
// swift-tools-version: 6.0
import PackageDescription

#if TUIST
import enum ProjectDescription.Environment
import struct ProjectDescription.PackageSettings

let packageSettings = PackageSettings(
    productTypes: [
        "CasePaths": .framework,
        "CasePathsCore": .framework,
        "Clocks": .framework,
        "CombineSchedulers": .framework,
        "ComposableArchitecture": .framework,
        "ConcurrencyExtras": .framework,
        "CustomDump": .framework,
        "Dependencies": .framework,
        "DependenciesTestSupport": .framework,
        "IdentifiedCollections": .framework,
        "InternalCollectionsUtilities": .framework,
        "IssueReporting": .framework,
        "IssueReportingPackageSupport": .framework,
        "IssueReportingTestSupport": .framework,
        "OrderedCollections": .framework,
        "Perception": .framework,
        "PerceptionCore": .framework,
        "Sharing": .framework,
        "SnapshotTesting": .framework,
        "SwiftNavigation": .framework,
        "SwiftUINavigation": .framework,
        "UIKitNavigation": .framework,
        "XCTestDynamicOverlay": .framework
    ],
    targetSettings: [
        "ComposableArchitecture": .settings(base: [
            "OTHER_SWIFT_FLAGS": ["-module-alias", "Sharing=SwiftSharing"]
        ]),
        "Sharing": .settings(base: [
            "PRODUCT_NAME": "SwiftSharing",
            "OTHER_SWIFT_FLAGS": ["-module-alias", "Sharing=SwiftSharing"]
        ])
    ]
)
#endif
```

:: 警告
<!-- -->
您将不得不`导入 SwiftSharing` ，而不是`导入 Sharing` 。
<!-- -->
:::

### Transitive static dependencies-leaking through`.swiftmodule` {#transitive-static-dependencies-leaking-through-swiftmodule}

当动态框架或库通过`import StaticSwiftModule` 来依赖静态框架或库时，动态框架或库的`.swiftmodule`
中就会包含这些符号，从而可能<LocalizedLink href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1">导致编译失败</LocalizedLink>。为了避免这种情况，您必须使用
<LocalizedLink href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`internal import`</LocalizedLink> 来导入静态依赖关系：

```swift
internal import StaticModule
```

信息
<!-- -->
Swift 6 中包含了导入的访问级别。如果您使用的是旧版本的 Swift，则需要使用
<LocalizedLink href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_implementationOnly`</LocalizedLink>
代替：
<!-- -->
:::

```swift
@_implementationOnly import StaticModule
```
