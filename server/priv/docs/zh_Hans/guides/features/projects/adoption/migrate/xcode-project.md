---
{
  "title": "迁移 Xcode 项目",
  "titleTemplate": ":title · 迁移 · 采用 · 项目 · 功能 · 指南 · Tuist",
  "description": "了解如何将 Xcode 项目迁移为 Tuist 项目。"
}
---
# 迁移 Xcode 项目 {#migrate-an-xcode-project}

除非你 <.localized_link href="/guides/features/projects/adoption/new-project">使用 Tuist 创建新项目</.localized_link>（这种情况下会自动完成所有配置），否则你需要使用 Tuist 的原语来定义 Xcode 项目。此过程的繁琐程度取决于项目的复杂性。

正如你可能所知，Xcode 项目随着时间的推移会变得混乱和复杂：组与目录结构不匹配、文件在多个 target 之间共享，或者文件引用指向不存在的文件（仅举几例）。所有这些累积的复杂性使得我们难以提供一个能够可靠迁移项目的命令。

此外，手动迁移是清理和简化项目的绝佳练习。不仅项目中的开发人员会对此表示感谢，Xcode 也会受益，因为它处理和索引项目的速度会更快。一旦你完全采用 Tuist，它将确保项目定义的一致性并保持简洁。

为了减轻这项工作，我们根据从用户那里收到的反馈提供了一些指南。

## 创建项目脚手架 {#create-project-scaffold}

首先，使用以下 Tuist 文件为你的项目创建脚手架：

::: code-group

```js [Tuist.swift]
import ProjectDescription

let tuist = Tuist()
```

```js [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyApp-Tuist",
    targets: [
        /** Targets will go here **/
    ]
)
```

```js [Tuist/Package.swift]
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        // Customize the product types for specific package product
        // Default is .staticFramework
        // productTypes: ["Alamofire": .framework,]
        productTypes: [:]
    )
#endif

let package = Package(
    name: "MyApp",
    dependencies: [
        // Add your own dependencies here:
        // .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
        // You can read more about dependencies here: https://docs.tuist.io/documentation/tuist/dependencies
    ]
)
```
<!-- -->
:::

`Project.swift` 是用于定义项目的清单文件，`Package.swift` 是用于定义依赖项的清单文件。`Tuist.swift` 文件用于定义项目范围内的 Tuist 设置。

> [!TIP]
> **项目名称添加 -tuist 后缀**
>
> 为了防止与现有的 Xcode 项目发生冲突，我们建议在项目名称中添加 `-Tuist` 后缀。一旦你完全将项目迁移到 Tuist，就可以去掉它。


## 在 CI 中构建和测试 Tuist 项目 {#build-and-test-the-tuist-project-in-ci}

为了确保每次更改的迁移都有效，我们建议扩展你的持续集成流程，以构建和测试由 Tuist 从清单文件生成的项目：

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## 将项目构建设置提取到 `.xcconfig` 文件中 {#extract-the-project-build-settings-into-xcconfig-files}

将项目的构建设置提取到 `.xcconfig` 文件中，以使项目更精简且更易于迁移。你可以使用以下命令将项目的构建设置提取到 `.xcconfig` 文件中：


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

然后更新你的 `Project.swift` 文件，使其指向你刚刚创建的 `.xcconfig` 文件：

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    settings: .settings(configurations: [
        .debug(name: "Debug", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"), // [!code ++]
        .release(name: "Release", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"), // [!code ++]
    ]),
    targets: [
        /** Targets will go here **/
    ]
)
```

然后扩展你的持续集成流水线以运行以下命令，确保对构建设置的更改直接应用于 `.xcconfig` 文件：

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## 提取包依赖项 {#extract-package-dependencies}

将项目的所有依赖项提取到 `Tuist/Package.swift` 文件中：

```swift
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        // Customize the product types for specific package product
        // Default is .staticFramework
        // productTypes: ["Alamofire": .framework,]
        productTypes: [:]
    )
#endif

let package = Package(
    name: "MyApp",
    dependencies: [
        // Add your own dependencies here:
        // .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
        // You can read more about dependencies here: https://docs.tuist.io/documentation/tuist/dependencies
        .package(url: "https://github.com/onevcat/Kingfisher", .upToNextMajor(from: "7.12.0")) // [!code ++]
    ]
)
```

> [!TIP]
> **产品类型**
>
> 你可以通过将其添加到 `PackageSettings` 结构体中的 `productTypes` 字典来覆盖特定包的产品类型。默认情况下，Tuist 假设所有包都是静态框架。


## 确定迁移顺序 {#determine-the-migration-order}

我们建议按照依赖程度从高到低的顺序迁移 target。你可以使用以下命令列出项目的 target，并按依赖数量排序：

```bash
tuist migration list-targets -p Project.xcodeproj
```

从列表顶部开始迁移 target，因为它们是被依赖最多的。


## 迁移 target {#migrate-targets}

逐个迁移 target。我们建议为每个 target 创建一个拉取请求，以确保在合并之前对更改进行审查和测试。

### 将 target 构建设置提取到 `.xcconfig` 文件中 {#extract-the-target-build-settings-into-xcconfig-files}

就像处理项目构建设置一样，将 target 的构建设置提取到 `.xcconfig` 文件中，以使 target 更精简且更易于迁移。你可以使用以下命令将 target 的构建设置提取到 `.xcconfig` 文件中：

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### 在 `Project.swift` 文件中定义 target {#define-the-target-in-the-projectswift-file}

在 `Project.targets` 中定义 target：

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    settings: .settings(configurations: [
        .debug(name: "Debug", xcconfig: "./xcconfigs/Project.xcconfig"),
        .release(name: "Release", xcconfig: "./xcconfigs/Project.xcconfig"),
    ]),
    targets: [
        .target( // [!code ++]
            name: "TargetX", // [!code ++]
            destinations: .iOS, // [!code ++]
            product: .framework, // [!code ++] // or .staticFramework, .staticLibrary...
            bundleId: "dev.tuist.targetX", // [!code ++]
            sources: ["Sources/TargetX/**"], // [!code ++]
            dependencies: [ // [!code ++]
                /** Dependencies go here **/ // [!code ++]
                /** .external(name: "Kingfisher") **/ // [!code ++]
                /** .target(name: "OtherProjectTarget") **/ // [!code ++]
            ], // [!code ++]
            settings: .settings(configurations: [ // [!code ++]
                .debug(name: "Debug", xcconfig: "./xcconfigs/TargetX.xcconfig"), // [!code ++]
                .debug(name: "Release", xcconfig: "./xcconfigs/TargetX.xcconfig"), // [!code ++]
            ]) // [!code ++]
        ), // [!code ++]
    ]
)
```

> [!NOTE]
> **测试 Target**
>
> 如果该 target 有关联的测试 target，你也应该在 `Project.swift` 文件中定义它，并重复相同的步骤。


### 验证 target 迁移 {#validate-the-target-migration}

运行 `tuist generate`，然后运行 `xcodebuild build` 以确保项目可以构建，并运行 `tuist test` 以确保测试通过。此外，你可以使用 [xcdiff](https://github.com/bloomberg/xcdiff) 将生成的 Xcode 项目与现有项目进行比较，以确保更改正确无误。

### 重复 {#repeat}

重复此过程，直到所有 target 完全迁移。完成后，我们建议更新你的 CI 和 CD 流水线，使用 `tuist generate` 生成项目，然后运行 `xcodebuild build` 和 `tuist test` 来构建和测试项目。

## 故障排除 {#troubleshooting}

### 由于缺少文件导致的编译错误。{#compilation-errors-due-to-missing-files}

如果你的 Xcode 项目 target 关联的文件并非全部包含在代表该 target 的文件系统目录中，最终可能会导致项目无法编译。请确保使用 Tuist 生成项目后的文件列表与 Xcode 项目中的文件列表匹配，并利用此机会使文件结构与 target 结构保持一致。
