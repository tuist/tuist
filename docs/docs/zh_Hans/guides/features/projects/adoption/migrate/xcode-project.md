---
{
  "title": "Migrate an Xcode project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate an Xcode project to a Tuist project."
}
---
# 迁移 Xcode 项目{#migrate-an-xcode-project}

除非您使用 Tuist<LocalizedLink href="/guides/features/projects/adoption/new-project"> 创建一个新项目</LocalizedLink>，在这种情况下，您将自动获得所有配置，否则您必须使用 Tuist 的基元来定义您的 Xcode
项目。这个过程有多繁琐，取决于您的项目有多复杂。

您可能知道，随着时间的推移，Xcode
项目会变得杂乱而复杂：与目录结构不匹配的组、跨目标共享的文件或指向不存在文件的文件引用（仅举几例）。所有这些累积起来的复杂性使得我们很难提供一个能可靠迁移项目的命令。

此外，手动迁移也是清理和简化项目的绝佳方法。不仅您项目中的开发人员会因此而感激不尽，Xcode 也会因此而加快处理和索引速度。一旦您完全采用
Tuist，它将确保项目定义的一致性，并保持项目的简洁性。

为了简化这项工作，我们将根据从用户那里收到的反馈意见为您提供一些指导。

## 创建项目脚手架{#create-project-scaffold}

首先，用以下 Tuist 文件为项目创建一个脚手架：

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

`Project.swift` 是定义项目的清单文件，而`Package.swift` 则是定义依赖项的清单文件。`Tuist.swift`
文件是为项目定义项目范围 Tuist 设置的文件。

::: tip PROJECT NAME WITH -TUIST SUFFIX
<!-- -->
为防止与现有 Xcode 项目发生冲突，我们建议在项目名称中添加`-Tuist` 后缀。当您将项目完全迁移到 Tuist 后，就可以去掉后缀。
<!-- -->
:::

## 在 CI 中构建和测试 Tuist 项目{#build-and-test-the-tuist-project-in-ci}

为确保每次变更的迁移都是有效的，我们建议扩展持续集成，以构建和测试 Tuist 根据清单文件生成的项目：

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## 将项目构建设置提取到`.xcconfig` 文件中{#extract-the-project-build-settings-into-xcconfig-files}

将项目中的构建设置提取到`.xcconfig` 文件中，使项目更精简、更易于迁移。可以使用以下命令将项目中的构建设置提取到`.xcconfig` 文件中：


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

然后更新`Project.swift` 文件，指向刚刚创建的`.xcconfig` 文件：

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

然后扩展持续集成管道，运行以下命令，确保对构建设置的更改直接进入`.xcconfig` 文件：

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## 提取软件包依赖关系{#extract-package-dependencies}

将项目的所有依赖项提取到`Tuist/Package.swift` 文件中：

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
您可以将特定软件包的产品类型添加到`PackageSettings` struct 中的`productTypes`
字典，从而覆盖该类型。默认情况下，Tuist 假定所有软件包都是静态框架。
<!-- -->
:::


## 确定迁移顺序{#determine-the-migration-order}

我们建议从依赖程度最高的目标迁移到依赖程度最低的目标。您可以使用以下命令列出项目的目标，按依赖关系的数量排序：

```bash
tuist migration list-targets -p Project.xcodeproj
```

从列表顶端的目标开始迁移，因为它们是最依赖的目标。


## 迁移目标{#migrate-targets}

逐个迁移目标。我们建议为每个目标提交一个拉取请求，以确保在合并之前对更改进行审核和测试。

### 将目标构建设置提取到`.xcconfig` 文件中{#extract-the-target-build-settings-into-xcconfig-files}

像处理项目构建设置一样，将目标构建设置提取到`.xcconfig`
文件中，以使目标更精简，更易于迁移。可以使用以下命令将目标机的构建设置提取到`.xcconfig` 文件中：

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### 在`Project.swift` 文件中定义目标{#define-the-target-in-the-projectswift-file}

在`Project.targets` 中定义目标：

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
如果目标有关联的测试目标，则应在`Project.swift` 文件中定义该目标，并重复相同的步骤。
<!-- -->
:::

### 验证目标迁移{#validate-the-target-migration}

运行`tuist generate` ，然后运行`xcodebuild build` 以确保项目构建完成，并运行`tuist test`
以确保测试通过。此外，您还可以使用 [xcdiff](https://github.com/bloomberg/xcdiff) 将生成的 Xcode
项目与现有项目进行比较，以确保更改正确无误。

### 重复{#repeat}

重复上述步骤，直到所有目标都迁移完毕。完成后，我们建议更新您的 CI 和 CD 管道，使用`tuist generate`
来构建和测试项目，然后使用`xcodebuild build` 和`tuist test` 。

## 故障排除 {#troubleshooting}

### 由于文件丢失导致编译错误。{#compilation-errors-due-to-missing-files}

如果与您的 Xcode 项目目标相关联的文件没有全部包含在代表目标的文件系统目录中，您可能会得到一个无法编译的项目。请确保使用 Tuist
生成项目后的文件列表与 Xcode 项目中的文件列表一致，并借此机会将文件结构与目标结构对齐。
