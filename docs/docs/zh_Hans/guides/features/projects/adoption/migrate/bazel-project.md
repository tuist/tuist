---
{
  "title": "Migrate a Bazel project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from Bazel to Tuist."
}
---
# 迁移 Bazel 项目{#migrate-a-bazel-project}

[Bazel](https://bazel.build)是谷歌于2015年开源的一个构建系统。它是一款功能强大的工具，可以快速、可靠地构建和测试任何规模的软件。Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/)、[Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae)或[Lyft](https://semaphoreci.com/blog/keith-smiley-bazel)等一些大型组织都在使用它，但它需要前期投入（即学习技术）和持续投入（即跟上
Xcode
更新）来引入和维护。虽然这对一些将其作为横向关注点的组织来说是可行的，但对于其他希望专注于产品开发的组织来说，这可能并不是最合适的。例如，我们曾见过一些组织，他们的
iOS 平台团队引入了 Bazel，但在领导这项工作的工程师离开公司后，他们不得不放弃这项工作。苹果公司对 Xcode 和构建系统之间强耦合的立场也是导致
Bazel 项目难以长期维护的另一个因素。

::: tip TUIST UNIQUENESS LIES IN ITS FINESSE
<!-- -->
Tuist 与其与 Xcode 和 Xcode 项目对抗，不如拥抱它。相同的概念（如目标、方案、构建设置），熟悉的语言（如
Swift），简单而愉快的体验，让维护和扩展项目成为每个人的工作，而不仅仅是 iOS 平台团队的工作。
<!-- -->
:::

## 规则{#rules}

Bazel 使用规则来定义如何构建和测试软件。这些规则是用类似 Python 的语言
[Starlark](https://github.com/bazelbuild/starlark) 编写的。Tuist 使用 Swift
作为配置语言，为开发人员提供了使用 Xcode 自动完成、类型检查和验证功能的便利。例如，以下规则描述了如何在 Bazel 中构建 Swift 库：

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

下面是另一个例子，但比较的是如何在 Bazel 和 Tuist 中定义单元测试：

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


## Swift 软件包管理器依赖项{#swift-package-manager-dependencies}

在 Bazel 中，您可以使用
[`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager)
[Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md)
插件。[Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md)
插件来使用 Swift 包作为依赖项。该插件需要`Package.swift` 作为依赖关系的真实来源。从这个意义上讲，Tuist 的界面与 Bazel
的界面类似。您可以使用`tuist install` 命令来解析和提取软件包的依赖关系。解析完成后，可以使用`tuist generate` 命令生成项目。

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## 项目生成{#project-generation}

社区提供了一组规则
[rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj)，用于从
Bazel 声明的项目中生成 Xcode 项目。与需要在`BUILD` 文件中添加一些配置的 Bazel 不同，Tuist
完全不需要任何配置。您可以在项目根目录下运行`tuist generate` ，Tuist 就会为您生成一个 Xcode 项目。
