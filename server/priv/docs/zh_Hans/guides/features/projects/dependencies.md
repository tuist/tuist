---
{
  "title": "依赖",
  "titleTemplate": ":title · 项目 · 功能 · 指南 · Tuist",
  "description": "了解如何在 Tuist 项目中声明依赖。"
}
---
# 依赖 {#dependencies}

随着项目规模增长，通常会将项目拆分为多个 target，以共享代码、界定边界并提升构建速度。多个 target 意味着需要定义它们之间的依赖关系，从而形成**依赖图**，其中也可能包含外部依赖。

## XcodeProj 编码的图 {#xcodeprojcodified-graphs}

由于 Xcode 和 XcodeProj 的设计，维护依赖图可能是一项繁琐且容易出错的工作。以下是一些你可能会遇到的问题示例：

- 因为 Xcode 的构建系统会将项目的所有产物输出到派生数据中的同一目录，target 可能会导入本不应导入的产物。在 CI 环境中（更常进行干净构建）或稍后使用不同配置时，编译可能会失败。
- target 的传递性动态依赖需要被复制到属于 `LD_RUNPATH_SEARCH_PATHS` 构建设置的任何目录中。如果没有复制，target 在运行时将无法找到这些依赖。当依赖图较小时，这很容易考虑和设置，但随着图的扩大，它会成为一个问题。
- 当 target 链接静态 [XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle) 时，该 target 需要额外的构建阶段，以便 Xcode 处理 bundle 并提取适用于当前平台和架构的正确二进制文件。此构建阶段不会自动添加，很容易被遗漏。

以上只是少数几个例子，我们在过去几年中还遇到过更多问题。想象一下，如果需要一支工程师团队来维护依赖图并确保其有效性会怎样。更糟糕的是，这些复杂细节由一个你无法控制或定制的闭源构建系统在构建时解决。听起来很熟悉？这正是 Apple 对 Xcode 和 XcodeProj 采取的方法，也是 Swift Package Manager 所继承的方式。

我们坚信依赖图应当是**显式**且**静态**的，因为只有这样才能对其进行**验证**和**优化**。使用 Tuist 时，你只需描述依赖关系，其余工作由我们处理。复杂性和实现细节对你而言已被抽象化。

在接下来的部分中，你将学习如何在项目中声明依赖。

> [!TIP]
> **图验证**
>
> Tuist 在生成项目时会验证图，以确保没有循环且所有依赖均有效。因此，任何团队都可以参与演进依赖图，而无需担心破坏它。


## 本地依赖 {#local-dependencies}

Target 可以依赖于同一项目或不同项目中的其他 target，以及二进制文件。实例化 `Target` 时，你可以为 `dependencies` 参数传入以下任意选项：

- `Target`：声明与同一项目中某个 target 的依赖。
- `Project`：声明与不同项目中某个 target 的依赖。
- `Framework`：声明与二进制 framework 的依赖。
- `Library`：声明与二进制库的依赖。
- `XCFramework`：声明与二进制 XCFramework 的依赖。
- `SDK`：声明与系统 SDK 的依赖。
- `XCTest`：声明与 XCTest 的依赖。
- `Macro`：声明与在同一项目中定义的 Swift macro target 的依赖（参见 [Swift Macros](#swift-macros)）。

> [!NOTE]
> **依赖条件**
>
> 每种依赖类型都接受 `condition` 选项，以根据平台有条件地链接依赖。默认情况下，它会为目标支持的所有平台链接该依赖。


## 外部依赖 {#external-dependencies}

Tuist 还允许你在项目中声明外部依赖。

### Swift Packages {#swift-packages}

Swift Packages 是我们推荐的在项目中声明依赖的方式。你可以使用 Xcode 的默认集成机制或使用 Tuist 基于 XcodeProj 的集成来集成它们。

#### Tuist 基于 XcodeProj 的集成 {#tuists-xcodeprojbased-integration}

Xcode 的默认集成虽然最为便捷，但缺乏中型和大型项目所需的灵活性与控制力。为解决这一问题，Tuist 提供了基于 XcodeProj 的集成，允许你使用 XcodeProj 的 target 将 Swift Packages 集成到项目中。借此，我们不仅能让你对集成拥有更多控制权，还能使其与<.localized_link href="/guides/features/cache">缓存</.localized_link>和<.localized_link href="/guides/features/selective-testing">选择性测试运行</.localized_link>等工作流兼容。

XcodeProj 的集成可能需要更多时间来支持新的 Swift Package 功能或处理更多的包配置。然而，Swift Packages 与 XcodeProj target 之间的映射逻辑是开源的，社区可以为之贡献代码。这与 Xcode 的默认集成相反，后者是闭源的并由 Apple 维护。

要添加外部依赖，你需要在 `Tuist/` 下或项目根目录创建 `Package.swift`。

::: code-group
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

> [!TIP]
> **包设置**
>
> 包裹在编译器指令中的 `PackageSettings` 实例允许你配置包的集成方式。例如，在上面的示例中，它用于覆盖包使用的默认产品类型。通常情况下，你不需要使用它。你也可以通过 `expectedSignatures` 使用它来配置 SwiftPM 二进制 target 的预期签名。


### 二进制 Target 签名

如果本地或远程 Swift 包暴露了二进制 XCFramework target，你可以使用 `PackageSettings.expectedSignatures` 配置其预期签名：

```swift
#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        expectedSignatures: [
            "SelfSignedXCFramework": .selfSigned(
                fingerprint: "EF61C3C0339FC84805357AFEC2E0BB0E6A0D5EE64165B333F934BF9E282785BC"
            ),
        ]
    )
#endif
```

> [!IMPORTANT] CUSTOM BUILD CONFIGURATIONS
> 如果你的项目使用自定义构建配置（除标准 `Debug` 和 `Release` 之外的配置），你必须在 `PackageSettings` 中使用 `baseSettings` 指定它们。外部依赖需要了解项目的配置才能正确构建。例如：
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
> 详见 [#8345](https://github.com/tuist/tuist/issues/8345)。

`Package.swift` 文件仅用于声明外部依赖，别无他用。这就是为什么你不在包中定义任何 target 或产品。定义好依赖后，你可以运行以下命令来解析并将依赖拉取到 `Tuist/Dependencies` 目录：

```bash
tuist install
# Resolving and fetching dependencies.
# Installing Swift Package Manager dependencies.
```

正如你可能已经注意到的，我们采用了与 [CocoaPods](https://cocoapods.org) 类似的方法，其中依赖解析是一个独立的命令。这让用户可以控制何时解析和更新依赖，并允许在 Xcode 中打开项目并使其准备好编译。我们认为，随着项目规模的增长，Apple 与 Swift Package Manager 集成所提供的开发者体验会逐渐下降，而这一领域正是其短板。

然后，你可以从项目的 target 中使用 `TargetDependency.external` 依赖类型来引用这些依赖：

::: code-group
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
                .external(name: "Alamofire"),
            ]
        ),
    ]
)
```
<!-- -->
:::

> [!NOTE]
> **不为外部包生成 Scheme**
>
> 为了保持 Scheme 列表整洁，不会为 Swift Package 项目自动创建 **Scheme**。你可以通过 Xcode 的界面手动创建它们。


#### Xcode 的默认集成 {#xcodes-default-integration}

如果你想使用 Xcode 的默认集成机制，可以在实例化项目时传入 `packages` 列表：

```swift
let project = Project(name: "MyProject", packages: [
    .package(url: "https://github.com/krzyzanowskim/CryptoSwift", .exact("1.8.0"))
])
```

然后从你的 target 中引用它们：

```swift
let target: Target = .target(name: "MyTarget", destinations: .iOS, product: .framework, bundleId: "dev.tuist.MyTarget", dependencies: [
    .package(product: "CryptoSwift", type: .runtime)
])
```

当通过 Xcode 的默认集成从外部 Swift Package 集成 Swift Macro 或 Build Tool Plugin 时，应分别使用类型 `.macro` 和 `.plugin` 进行声明。Macro 也可以通过 [Tuist 基于 XcodeProj 的集成](#tuists-xcodeprojbased-integration) 使用，如果你想定义自己的 Swift Macro 而不是使用包中的 Macro，请参阅 [Swift Macros](#swift-macros)。

> [!WARNING]
> **SPM 构建工具插件**
>
> 即使你的项目依赖使用 Tuist 的 [基于 XcodeProj 的集成](#tuists-xcodeprojbased-integration)，SPM 构建工具插件也必须使用 [Xcode 的默认集成](#xcodes-default-integration) 机制进行声明。

SPM 构建工具插件是 Swift 程序，由 Xcode 和 SwiftPM 执行，用于发现应为 target 运行的具体构建命令。这些命令可能依赖于包图、target 文件、插件工作目录、已解析的插件工具以及插件声明的输出。某些插件还会生成必须成为同一 target 构建一部分的文件。

Tuist 基于 XcodeProj 的集成在映射是静态的情况下（例如库、二进制文件、可执行文件和 macro），将包产品映射为本机 Xcode target。构建工具插件在 Xcode 的 SwiftPM 集成之外没有等效的本机 Xcode 项目基元。虽然插件最终可以运行可执行文件，但从常规脚本构建阶段调用该可执行文件并不等同于运行插件：Tuist 首先需要评估插件的 Swift 代码，重现 SwiftPM 的插件上下文，发现命令，对声明的输入和输出进行建模，并在 Xcode 规划构建之前将任何生成的文件添加到 target 图中。

因此，不支持仅在 `Tuist/Package.swift` 中声明插件包并通过 `.external(name:)` 使用它。支持的替代方案是在 `Project.packages` 中声明包，并使用 `.package(product:type: .plugin)` 将插件产品添加到消费 target 中。这样可以将插件作为 Swift Package 产品依赖附加到生成的 Xcode 项目中，以便 Xcode 和 SwiftPM 可以使用本机插件上下文运行它。

权衡之处在于，该插件集成由 Xcode 主导：

- Xcode 通过其 SwiftPM 集成解析并构建插件包。
- 该包在生成的项目中显示为 Swift Package 引用，而不是 Tuist 生成的外部 target。
- Tuist 无法为插件提供与静态映射的包产品相同级别的控制、验证、缓存和选择性测试行为。
- CI 和本地构建必须允许 Xcode 对这些插件包进行包解析。

鉴于这些影响，我们通常不建议在 Tuist 项目中使用 SPM 构建工具插件。如果可能，更倾向于使用在 target 中声明的构建阶段脚本，或在调用 Tuist 或 Xcode 之前从生成的 Xcode 项目之外的脚本中运行该工具。

SPM 构建工具插件的一个实际应用是在 Xcode 的“Run Build Tool Plug-ins”构建阶段执行代码 linting。要生成包含构建工具插件的 Xcode 项目，请在项目清单的 `packages` 数组中声明包，然后在 target 的依赖项中包含类型为 `.plugin` 的包。

```swift
import ProjectDescription

let project = Project(
    name: "Framework",
    packages: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.56.1"),
    ],
    targets: [
        .target(
            name: "Framework",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.Framework",
            dependencies: [
                .package(product: "SwiftLintBuildToolPlugin", type: .plugin),
            ]
        ),
    ]
)
```

### Carthage {#carthage}

由于 [Carthage](https://github.com/carthage/carthage) 输出 `frameworks` 或 `xcframeworks`，你可以运行 `carthage update` 将依赖项输出到 `Carthage/Build` 目录，然后使用 `.framework` 或 `.xcframework` target 依赖类型在 target 中声明依赖。你可以将其封装在一个脚本中，在生成项目之前运行。

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

> [!WARNING]
> **构建和测试**
>
> 如果你通过 `xcodebuild build` 和 `tuist test` 构建和测试项目，同样需要在构建或测试之前运行 `carthage update` 命令，以确保 Carthage 解析的依赖项存在。


### CocoaPods {#cocoapods}

[CocoaPods](https://cocoapods.org) 期望有一个 Xcode 项目来集成依赖。你可以使用 Tuist 生成项目，然后运行 `pod install` 通过创建一个包含你的项目和 Pods 依赖的工作区来集成依赖。你可以将其封装在一个脚本中，在生成项目之前运行。

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

> [!WARNING]
> CocoaPods 依赖与在生成项目后立即运行 `xcodebuild` 的工作流（如 `build` 或 `test`）不兼容。它们也与二进制缓存和选择性测试不兼容，因为指纹逻辑未考虑 Pods 依赖。


## Swift Macros {#swift-macros}

在 Tuist 项目中使用 [Swift Macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/) 时有两种不同的场景，明确你处于哪种场景很重要：

- **使用外部 Swift Package 中定义的 macro。** 两种集成机制都支持 macro。使用 [Tuist 基于 XcodeProj 的集成](#tuists-xcodeprojbased-integration) 时，你在 `Tuist/Package.swift` 中声明包并使用 `.external(name:)` 依赖它——Tuist 将 macro 产品映射为本机 target。使用 [Xcode 的默认集成](#xcodes-default-integration) 时，你使用 `.package(product:type: .macro)` 声明依赖。与构建工具插件不同，macro 不受限于 Xcode 的默认集成。
- 将 **定义你自己的 macro** 作为项目的一部分——例如在 monorepo 中的共享库中。你不需要为此使用 `Package.swift`：Tuist 提供了一流的 `.macro` 产品类型，因此你可以直接在清单中声明 macro target。

### 定义你自己的 macro {#defining-your-own-macro}

Swift macro 是一个编译器插件：一个由 Swift 编译器在编译时加载并运行的可执行文件。Tuist 通过 `.macro` 产品类型原生地对此进行建模。虽然 Apple 未在 Xcode 项目中公开 Swift Macro target 类型，但 Tuist 通过生成命令行工具 target、将其连接为使用 macro 的 target 的依赖项，并将 `-load-plugin-executable` 标志注入其 Swift 编译器设置来启用它。所有这些底层工作都由 Tuist 为你处理。

典型的 macro 分为两个 target：实现 macro 的 **plugin** target（`product: .macro`），以及声明 macro 公共接口（`@attached`/`@freestanding` 声明）并通过 `.macro(name:)` 依赖 plugin 的 **library** target。由于 plugin 在构建机器上运行，其 target 仅限主机（macOS）。

macro 实现依赖于 [swift-syntax](https://github.com/swiftlang/swift-syntax)，你可以在 `Tuist/Package.swift` 中将其声明为常规外部依赖：

```swift [Tuist/Package.swift]
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "600.0.0"),
    ]
)
```

然后，你可以直接在项目中定义 macro plugin 和 library target：

```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyLibrary",
    targets: [
        // The compiler plugin that implements the macro. macOS-only, since it
        // runs on the build machine at compile time.
        .target(
            name: "MyMacrosImplementation",
            destinations: [.mac],
            product: .macro,
            bundleId: "dev.tuist.MyMacrosImplementation",
            sources: ["Sources/MyMacrosImplementation/**"],
            dependencies: [
                .external(name: "SwiftSyntax"),
                .external(name: "SwiftSyntaxMacros"),
                .external(name: "SwiftCompilerPlugin"),
            ]
        ),
        // The library that exposes the macro declarations to consumers and
        // depends on the plugin via `.macro(name:)`.
        .target(
            name: "MyLibrary",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.MyLibrary",
            sources: ["Sources/MyLibrary/**"],
            dependencies: [
                .macro(name: "MyMacrosImplementation"),
            ]
        ),
    ]
)
```

任何链接 `MyLibrary` 的 target 现在都可以使用该 macro——Tuist 会传播 plugin，以便编译器可以加载它。


## 静态或动态 {#static-or-dynamic}

框架和库可以静态或动态链接，**这一选择对应用大小和启动时间等方面有重大影响**。尽管很重要，但这一决定往往未经深思熟虑。

**一般经验法则**是：在 release 构建中尽可能多地静态链接以实现快速启动，而在 debug 构建中尽可能多地动态链接以实现快速迭代。

在项目图中更改静态和动态链接的挑战在于，这在 Xcode 中并不简单，因为更改会对整个图产生级联影响（例如，库不能包含资源，静态框架不需要嵌入）。Apple 尝试通过编译时解决方案来解决这个问题，例如 Swift Package Manager 在静态和动态链接之间的自动决策，或 [Mergeable Libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)。然而，这为编译图增加了新的动态变量，引入了新的非确定性来源，并可能导致某些依赖编译图的功能（如 Swift Previews）变得不可靠。

幸运的是，Tuist 在概念上简化了与静态和动态切换相关的复杂性，并合成了跨链接类型标准的 <.localized_link href="/guides/features/projects/synthesized-files#bundle-accessors">bundle 访问器</.localized_link>。结合 <.localized_link href="/guides/features/projects/dynamic-configuration">通过环境变量的动态配置</.localized_link>，你可以在调用时传递链接类型，并在清单中使用该值来设置 target 的产品类型。

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

请注意，Tuist <.localized_link href="/guides/features/projects/cost-of-convenience">出于成本考虑，不会默认通过隐式配置提供便利</.localized_link>。这意味着我们需要你设置链接类型以及有时需要的其他构建设置，例如 [`-ObjC` 链接器标志](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184)，以确保生成的二进制文件正确无误。因此，我们的立场是为你提供资源（通常是文档形式），以帮助你做出正确的决策。

> [!TIP]
> **示例：The Composable Architecture**
>
> 许多项目集成的一个 Swift Package 是 [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture)。详见 [本节](#the-composable-architecture)。


### 场景 {#scenarios}

在某些场景下，将链接完全设置为静态或动态并不可行或不是好主意。以下是可能需要混合使用静态和动态链接的非详尽场景列表：

- **带有扩展的应用：** 由于应用及其扩展需要共享代码，你可能需要将这些 target 设为动态。否则，应用和扩展中将重复相同的代码，导致二进制文件大小增加。
- **预编译的外部依赖：** 有时你会获得预编译的二进制文件，它们可能是静态的或动态的。静态二进制文件可以封装在动态框架或库中以实现动态链接。

当对图进行更改时，Tuist 会进行分析，如果检测到“静态副作用”，则会显示警告。此警告旨在帮助你识别因通过动态 target 传递依赖静态 target 而静态链接 target 可能引发的问题。这些副作用通常表现为二进制文件大小增加，在最坏的情况下会导致运行时崩溃。

## 故障排除 {#troubleshooting}

### Objective-C 依赖 {#objectivec-dependencies}

集成 Objective-C 依赖时，可能需要在消费 target 中包含某些标志以避免运行时崩溃，详见 [Apple Technical Q&A QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html)。

由于构建系统和 Tuist 无法推断是否需要该标志，且该标志可能带来不良副作用，Tuist 不会自动应用这些标志。此外，由于 Swift Package Manager 认为 `-ObjC` 是通过 `.unsafeFlag` 包含的，大多数包在需要时无法将其作为默认链接设置的一部分。

Objective-C 依赖的消费者（或内部 Objective-C target）应在需要时通过在消费 target 上设置 `OTHER_LDFLAGS` 来应用 `-ObjC` 或 `-force_load` 标志。

### Firebase 和其他 Google 库 {#firebase-other-google-libraries}

Google 的开源库虽然功能强大，但在 Tuist 中集成可能比较困难，因为它们的构建方式通常采用非标准架构和技术。

以下是一些集成 Firebase 和 Google 其他 Apple 平台库时可能需要遵循的建议：

#### 确保将 `-ObjC` 添加到 `OTHER_LDFLAGS` {#ensure-objc-is-added-to-other_ldflags}

Google 的许多库都是用 Objective-C 编写的。因此，任何消费 target 都需要在其 `OTHER_LDFLAGS` 构建设置中包含 `-ObjC` 标志。这可以在 `.xcconfig` 文件中设置，也可以在 Tuist 清单中的 target 设置中手动指定。示例：

```swift
Target.target(
    ...
    settings: .settings(
        base: ["OTHER_LDFLAGS": "$(inherited) -ObjC"]
    )
    ...
)
```

有关更多详细信息，请参阅上面的 [Objective-C 依赖](#objectivec-dependencies) 部分。

#### 将 `FBLPromises` 的产品类型设置为动态框架 {#set-the-product-type-for-fblpromises-to-dynamic-framework}

某些 Google 库依赖于 Google 的另一个库 `FBLPromises`。你可能会遇到提及 `FBLPromises` 的崩溃，类似于以下内容：

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

在 `Package.swift` 文件中将 `FBLPromises` 的产品类型显式设置为 `.framework` 应该可以解决此问题：

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

### The Composable Architecture {#the-composable-architecture}

如 [此处](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184) 和 [故障排除部分](#troubleshooting) 所述，当静态链接包时（这是 Tuist 的默认链接类型），你需要将 `OTHER_LDFLAGS` 构建设置为 `$(inherited) -ObjC`。或者，你可以将包的产品类型覆盖为动态。静态链接时，测试和应用 target 通常可以正常工作，但 SwiftUI 预览会失效。这可以通过将所有内容动态链接来解决。在下面的示例中，[Sharing](https://github.com/pointfreeco/swift-sharing) 也被添加为依赖项，因为它经常与 The Composable Architecture 一起使用，并且有其自身的 [配置陷阱](https://github.com/pointfreeco/swift-sharing/issues/150#issuecomment-2797107032)。

以下配置将所有内容动态链接，因此应用 + 测试 target 和 SwiftUI 预览都能正常工作。

> [!TIP]
> **静态或动态**
>
> 并不总是推荐动态链接。有关更多详细信息，请参阅 [静态或动态](#static-or-dynamic) 部分。在此示例中，为了简单起见，所有依赖项都无条件地动态链接。


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

> [!WARNING]
> 你将不得不使用 `import SwiftSharing` 而不是 `import Sharing`。


### 通过 `.swiftmodule` 泄漏的传递性静态依赖 {#transitive-static-dependencies-leaking-through-swiftmodule}

当动态框架或库通过 `import StaticSwiftModule` 依赖于静态库时，符号会被包含在动态框架或库的 `.swiftmodule` 中，可能 <.localized_link href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1">导致编译失败</.localized_link>。为防止这种情况，你必须使用 <.localized_link href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`internal import`</.localized_link> 导入静态依赖：

```swift
internal import StaticModule
```

> [!NOTE]
> Swift 6 中包含了导入的访问级别。如果你使用的是较旧版本的 Swift，则需要改用 <.localized_link href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_implementationOnly`</.localized_link>：


```swift
@_implementationOnly import StaticModule
```

## 相关 {#related}

阅读 [monday.com 如何采用 Tuist 实现模块化项目图](https://tuist.dev/customers/monday)，从依赖项最少的 target 开始。
