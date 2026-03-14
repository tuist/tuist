---
{
  "title": "Migrate a Bazel project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from Bazel to Tuist."
}
---
# 迁移 Bazel 项目{#migrate-a-bazel-project}

[Bazel](https://bazel.build) 是 Google 于 2015
年开源的构建系统。这是一个功能强大的工具，可让您快速、可靠地构建和测试任何规模的软件。 一些大型组织如
[Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/)、[Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae)
或 [Lyft](https://semaphoreci.com/blog/keith-smiley-bazel) 都在使用它，但引入和维护 Bazel
需要前期投入（即学习该技术）和持续投入（即跟进 Xcode 的更新）。
虽然对于将此视为跨领域关注点的某些组织而言这可行，但对于希望专注于产品开发的其他组织来说，这可能并非最佳选择。例如，我们曾看到某些组织的 iOS 平台团队引入
Bazel 后，因负责该项目的工程师离职而不得不放弃它。苹果对 Xcode 与构建系统之间强耦合的立场，是导致 Bazel 项目难以长期维护的另一个因素。

::: tip TUIST UNIQUENESS LIES IN ITS FINESSE
<!-- -->
Tuist 并非与 Xcode 及其项目作对，而是将其纳入怀抱。它采用相同的概念（例如目标、方案、构建设置），使用熟悉的语言（即
Swift），并提供简单愉悦的体验，使项目的维护和扩展成为每个人的职责，而不仅仅是 iOS 平台团队的任务。
<!-- -->
:::

## 规则{#rules}

Bazel 使用规则来定义如何构建和测试软件。这些规则使用 [Starlark](https://github.com/bazelbuild/starlark)
编写，这是一种类似 Python 的语言。Tuist 采用 Swift 作为配置语言，这为开发者提供了使用 Xcode
自动补全、类型检查和验证功能的便利。例如，以下规则描述了如何在 Bazel 中构建一个 Swift 库：

代码组
```txt [BUILD (Bazel)]
swift_library(
    name = "MyLibrary.library",
    srcs = glob(["**/*.swift"]),
    module_name = "MyLibrary"
)
```

```swift [Project.swift (Tuist)]
let project = Project(
    // ...
    targets: [
        .target(name: "MyLibrary", product: .staticLibrary, sources: ["**/*.swift"])
    ]
)
```
<!-- -->
:::

以下是另一个示例，对比了在 Bazel 和 Tuist 中如何定义单元测试：

代码组
```txt [BUILD (Bazel)]
ios_unit_test(
    name = "MyLibraryTests",
    bundle_id = "dev.tuist.MyLibraryTests",
    minimum_os_version = "16.0",
    test_host = "//MyApp:MyLibrary",
    deps = [":MyLibraryTests.library"],
)
```
```swift [Project.swift (Tuist)]
let project = Project(
    // ...
    targets: [
        .target(
            name: "MyLibraryTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.MyLibraryTests",
            sources: "Tests/MyLibraryTests/**",
            dependencies: [
                .target(name: "MyLibrary"),
            ]
        )
    ]
)
```
<!-- -->
:::


## Swift Package Manager 依赖项{#swift-package-manager-dependencies}

在 Bazel 中，您可以使用
[`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager)
[Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md) 插件将
Swift Packages 作为依赖项。该插件需要一个`Package.swift` 文件作为依赖项的权威来源。从这个角度来看，Tuist 的接口与
Bazel 类似。 您可以使用`tuist install` 命令解析并拉取包的依赖项。解析完成后，您可以使用`tuist generate` 命令生成项目。

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## 项目生成{#project-generation}

社区提供了一套规则
[rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj)，用于根据
Bazel 声明的项目生成 Xcode 项目。与 Bazel 不同，在 Bazel 中你需要在`BUILD` 文件中添加一些配置，而 Tuist
则完全不需要任何配置。你可以在项目的根目录下运行`tuist generate` ，Tuist 就会为你生成一个 Xcode 项目。
