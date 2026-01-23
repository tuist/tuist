---
{
  "title": "Migrate an Xcode project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate an Xcode project to a Tuist project."
}
---
# 迁移Xcode项目{#migrate-an-xcode-project}

除非您<LocalizedLink href="/guides/features/projects/adoption/new-project">使用Tuist创建新项目</LocalizedLink>（此时所有配置将自动完成），否则您需要通过Tuist的原始元素来定义Xcode项目。该过程的繁琐程度取决于项目复杂度。

您可能已知晓，Xcode项目随时间推移会变得混乱复杂：组结构与目录结构不匹配、文件在不同目标间共享、文件引用指向不存在的文件（仅举几例）。这些累积的复杂性使得我们难以提供可靠迁移项目的命令。

此外，手动迁移是清理和简化项目的绝佳练习。不仅项目开发者会因此感激，Xcode的处理和索引速度也将显著提升。当您完全采用Tuist后，它将确保项目定义始终如一且保持简洁。

为减轻工作负担，我们根据用户反馈提供以下指南：

## 创建项目框架{#create-project-scaffold}

首先，使用以下 Tuist 文件为项目创建框架：

代码组

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

`Project.swift` 是用于定义项目配置的清单文件，而`Package.swift` 则是用于定义依赖项的清单文件。`Tuist.swift`
文件用于定义项目范围内的 Tuist 设置。

::: tip PROJECT NAME WITH -TUIST SUFFIX
<!-- -->
为避免与现有Xcode项目冲突，建议在项目名称后添加`-Tuist` 后缀。待项目完全迁移至Tuist后即可移除此后缀。
<!-- -->
:::

## 在持续集成环境中构建并测试 Tuist 项目{#build-and-test-the-tuist-project-in-ci}

为确保每次变更的迁移有效，建议扩展您的持续集成流程，对Tuist根据清单文件生成的项目进行构建和测试：

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## 将项目构建设置提取至` 目录下的.xcconfig文件` 文件{#extract-the-project-build-settings-into-xcconfig-files}

`` 将项目中的构建设置提取到`.xcconfig文件中，使项目更精简且易于迁移。可使用以下命令将构建设置提取到`.xcconfig文件中：


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

然后更新您的`Project.swift文件，将` 指向您刚创建的`.xcconfig文件` ：

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

然后扩展您的持续集成管道，运行以下命令以确保构建设置的更改直接应用于`.xcconfig` 文件：

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## 提取包依赖项{#extract-package-dependencies}

`将项目所有依赖项提取至 Tuist/Package.swift 文件（位于` 目录下）：

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

::: tip PRODUCT TYPES
<!-- -->
` 可通过在`的PackageSettings结构体中，向`的productTypes字典（`
）添加条目，覆盖特定包的产品类型。默认情况下，Tuist将所有包视为静态框架。
<!-- -->
:::


## 确定迁移顺序{#determine-the-migration-order}

建议按依赖程度从高到低迁移目标。可使用以下命令按依赖数量排序列出项目目标：

```bash
tuist migration list-targets -p Project.xcodeproj
```

请从列表顶部的目标开始迁移，因为这些目标依赖性最强。


## 迁移目标{#migrate-targets}

请逐个迁移目标语言。建议为每个目标语言提交独立的拉取请求，确保合并前完成代码审查与测试。

### 将目标构建设置提取至`.xcconfig` 文件中{#extract-the-target-build-settings-into-xcconfig-files}

`` 如同处理项目构建设置那样，将目标构建设置提取到独立的 .xcconfig 文件中（例如`
），这样既能精简目标文件，也便于后续迁移。可通过以下命令将目标构建设置提取到独立的 .xcconfig 文件中（例如` ）：

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### 在`的Project.swift文件中定义目标` {#define-the-target-in-the-projectswift-file}

在`的Project.targets文件中定义目标：` ：

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

::: info TEST TARGETS
<!-- -->
若目标关联有测试目标，需在`的Project.swift文件中重复相同步骤进行定义。`
<!-- -->
:::

### 验证目标迁移{#validate-the-target-migration}

运行`tuist generate` 随后执行`xcodebuild build` 确保项目能构建，并执行`tuist test` 验证测试通过。此外，可使用
[xcdiff](https://github.com/bloomberg/xcdiff) 比较生成的Xcode项目与现有项目，确保变更正确。

### 重复{#repeat}

重复操作直至所有目标完全迁移。完成后，建议更新您的持续集成（CI）和持续交付（CD）管道，使用以下命令构建并测试项目：`tuist generate`
随后执行：`xcodebuild build` 以及：`tuist test`

## 故障排除 {#troubleshooting}

### 因文件缺失导致的编译错误。{#compilation-errors-due-to-missing-files}

若Xcode项目目标关联的文件未全部存放在代表该目标的文件系统目录中，可能导致项目无法编译。请确保使用Tuist生成项目后，生成的文件列表与Xcode项目中的文件列表一致，并借此机会使文件结构与目标结构保持一致。
