---
{
  "title": "迁移 Bazel 项目",
  "titleTemplate": ":title · 迁移 · 采用 · 项目 · 功能 · 指南 · Tuist",
  "description": "了解如何将项目从 Bazel 迁移到 Tuist。"
}
---
# 迁移 Bazel 项目 {#migrate-a-bazel-project}

[Bazel](https://bazel.build) 是 Google 于 2015 年开源的构建系统。它是一款功能强大的工具，可让你快速、可靠地构建和测试任意规模的软件。[Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/)、[Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae) 或 [Lyft](https://semaphoreci.com/blog/keith-smiley-bazel) 等大型组织都在使用它，但引入和维护它需要前期投入（即学习该技术）以及持续投入（即跟进 Xcode 更新）。虽然对于一些将其视为跨领域事项的组织来说这很有效，但对于希望专注于产品开发的其他组织而言，这可能并非最佳选择。例如，我们见过一些组织的 iOS 平台团队引入了 Bazel，但在主导该工作的工程师离职后不得不放弃。Apple 对 Xcode 与构建系统之间强耦合的立场，也是导致 Bazel 项目难以长期维护的另一个因素。

> [!TIP]
> **Tuist 的独特之处在于其精妙设计**
>
> Tuist 不与 Xcode 及 Xcode 项目对抗，而是拥抱它们。它采用相同的概念（例如 target、scheme、构建设置）、熟悉的语言（即 Swift），并提供简单愉悦的体验，让维护和扩展项目成为每个人的职责，而不仅仅是 iOS 平台团队的工作。


## 规则 {#rules}

Bazel 使用规则来定义如何构建和测试软件。这些规则使用 [Starlark](https://github.com/bazelbuild/starlark)（一种类似 Python 的语言）编写。Tuist 使用 Swift 作为配置语言，为开发者提供利用 Xcode 自动补全、类型检查和验证功能的便利。例如，以下规则描述了如何在 Bazel 中构建 Swift 库：

::: code-group
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

下面是另一个示例，比较在 Bazel 和 Tuist 中如何定义单元测试：

::: code-group
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


## Swift Package Manager 依赖 {#swift-package-manager-dependencies}

在 Bazel 中，你可以使用 [`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager) [Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md) 插件将 Swift Packages 用作依赖。该插件需要一个 `Package.swift` 作为依赖的真实来源。在这方面，Tuist 的接口与 Bazel 类似。你可以使用 `tuist install` 命令来解析并拉取包的依赖。解析完成后，你可以使用 `tuist generate` 命令生成项目。

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## 项目生成 {#project-generation}

社区提供了一组规则 [rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj)，用于从 Bazel 声明的项目生成 Xcode 项目。与 Bazel 不同（在 Bazel 中你需要向 `BUILD` 文件添加一些配置），Tuist 完全不需要任何配置。你可以在项目的根目录运行 `tuist generate`，Tuist 就会为你生成一个 Xcode 项目。
