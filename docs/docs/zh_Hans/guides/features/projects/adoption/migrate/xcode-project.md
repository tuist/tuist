---
{
  "title": "Migrate an Xcode project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate an Xcode project to a Tuist project."
}
---
# 迁移 Xcode 项目{#migrate-an-xcode-project}

除非您 <LocalizedLink href="/guides/features/projects/adoption/new-project">使用
Tuist 创建新项目</LocalizedLink>（此时所有配置都会自动完成），否则您需要使用 Tuist 的基础组件来定义 Xcode
项目。这个过程有多繁琐，取决于您的项目有多复杂。

想必您也知道，Xcode
项目随着时间推移可能会变得杂乱无章且复杂：与目录结构不匹配的组、在多个目标间共享的文件，或是指向不存在的文件的引用（仅举几例）。所有这些累积的复杂性使得我们难以提供一个能够可靠地迁移项目的命令。

此外，手动迁移是清理和简化项目的绝佳机会。这不仅会让项目中的开发者受益，还能让 Xcode 更快地处理和索引这些内容。一旦您完全采用
Tuist，它将确保项目定义的一致性，并保持其简洁性。

为了减轻您的工作负担，我们根据用户反馈为您提供了一些指南。

## 创建项目框架{#create-project-scaffold}

首先，使用以下 Tuist 文件为您的项目创建一个框架：

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

`Project.swift` 是用于定义项目的清单文件，而`Package.swift` 是用于定义依赖项的清单文件。`Tuist.swift`
文件用于定义项目范围内的 Tuist 设置。

::: tip PROJECT NAME WITH -TUIST SUFFIX
<!-- -->
为避免与现有 Xcode 项目发生冲突，建议在项目名称后添加后缀`-Tuist` 。待项目完全迁移至 Tuist 后，即可移除此后缀。
<!-- -->
:::

## 在 CI 中构建并测试 Tuist 项目{#build-and-test-the-tuist-project-in-ci}

为确保每次更改的迁移有效，我们建议扩展您的持续集成，以构建并测试 Tuist 根据您的清单文件生成的项目：

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## 将项目构建设置提取到`.xcconfig和` 文件中{#extract-the-project-build-settings-into-xcconfig-files}

将项目的构建设置提取到`.xcconfig` 文件中，以使项目更精简且更易于迁移。您可以使用以下命令将项目的构建设置提取到`.xcconfig` 文件中：


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

然后更新您的`Project.swift` 文件，使其指向您刚刚创建的`.xcconfig` 文件：

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

然后扩展您的持续集成管道，运行以下命令，以确保对构建设置的更改直接应用到` 的 .xcconfig` 文件中：

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## 提取包依赖项{#extract-package-dependencies}

将项目中的所有依赖项提取到`Tuist/Package.swift` 文件中：

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
您可以通过将特定包添加到`PackageSettings` 结构中的`productTypes` 字典中，来覆盖该包的产品类型。默认情况下，Tuist
会将所有包视为静态框架。
<!-- -->
:::


## 确定迁移顺序{#determine-the-migration-order}

我们建议按依赖关系从高到低迁移目标。您可以使用以下命令按依赖项数量排序，列出项目的目标：

```bash
tuist migration list-targets -p Project.xcodeproj
```

请从列表顶部开始迁移目标，因为这些是依赖性最高的。


## 迁移目标{#migrate-targets}

请逐个迁移目标。我们建议为每个目标提交一个拉取请求，以确保在合并更改之前，这些更改已通过审核和测试。

### 将目标构建设置提取到`.xcconfig和` 文件中{#extract-the-target-build-settings-into-xcconfig-files}

如同处理项目构建设置那样，将目标的构建设置提取到`.xcconfig`
文件中，以使目标更精简且更易于迁移。您可以使用以下命令将构建设置从目标提取到`.xcconfig` 文件中：

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### 在`Project.swift` 文件中定义目标{#define-the-target-in-the-projectswift-file}

在`Project.targets 中定义目标：`:

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
如果目标对象关联了测试目标，您还应在`Project.swift` 文件中定义该测试目标，并重复相同的步骤。
<!-- -->
:::

### 验证目标迁移{#validate-the-target-migration}

运行`tuist generate` ，随后执行`xcodebuild build` 以确保项目能成功构建，并运行`tuist test`
以确保测试通过。此外，您可以使用 [xcdiff](https://github.com/bloomberg/xcdiff) 比较生成的 Xcode
项目与现有项目，以确保更改正确无误。

### 重复{#repeat}

重复此操作直至所有目标完全迁移完成。完成后，建议更新您的 CI 和 CD 管道，使用以下命令构建和测试项目：`tuist generate`
，随后执行`xcodebuild build` 以及`tuist test` 。

## 故障排除 {#troubleshooting}

### 因文件缺失导致的编译错误。{#compilation-errors-due-to-missing-files}

如果与您的 Xcode 项目目标相关的文件并未全部包含在代表该目标的文件系统目录中，您的项目可能无法编译。请确保使用 Tuist 生成项目后的文件列表与
Xcode 项目中的文件列表一致，并借此机会将文件结构与目标结构保持一致。
