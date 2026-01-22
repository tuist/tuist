---
{
  "title": "Migrate a Bazel project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from Bazel to Tuist."
}
---
# 迁移 Bazel 项目{#migrate-a-bazel-project}

[Bazel](https://bazel.build) 是谷歌于2015年开源的构建系统。这款强大工具能快速可靠地构建和测试任意规模的软件。
尽管[Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/)、[Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae)或[Lyft](https://semaphoreci.com/blog/keith-smiley-bazel)等大型机构采用该系统，但其引入与维护需前期投入（即学习技术）及持续投入（即跟进Xcode更新）。
对于将Bazel视为横切关注点的组织而言，这种模式可行；但对专注产品开发的团队则未必适用。例如我们曾观察到，某些企业的iOS平台团队引入Bazel后，因主导项目的工程师离职而被迫放弃。苹果公司坚持Xcode与构建系统强耦合的立场，也成为Bazel项目长期维护的另一阻碍因素。

::: tip TUIST UNIQUENESS LIES IN ITS FINESSE
<!-- -->
Tuist 并非与 Xcode 及 Xcode 项目对抗，而是与之协同。相同的开发理念（如目标、方案、构建设置）、熟悉的语言（即
Swift），以及简单愉悦的体验，使项目维护与扩展成为全体成员的职责，而非仅限于 iOS 平台团队。
<!-- -->
:::

## 规则{#rules}

Bazel 通过规则定义软件的构建与测试流程。这些规则采用类似 Python 的
[Starlark](https://github.com/bazelbuild/starlark) 语言编写。Tuist 则将 Swift
作为配置语言，使开发者能便捷使用 Xcode 的自动补全、类型检查及验证功能。例如以下规则描述了如何在 Bazel 中构建 Swift 库：

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

以下是另一个示例，对比Bazel和Tuist中单元测试的定义方式：

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

在 Bazel 中，可通过
[`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager)
[Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md) 插件将
Swift 包作为依赖项使用。该插件要求以`Package.swift` 作为依赖项的权威数据源。Tuist 的接口在此方面与 Bazel 类似。
可通过命令`tuist install` 解析并拉取包的依赖项。解析完成后，使用命令`tuist generate` 即可生成项目。

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## 项目生成{#project-generation}

社区提供了一套规则集[rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj)，用于从Bazel声明的项目生成Xcode项目。与Bazel需要在`的BUILD文件`
中添加配置不同，Tuist完全无需任何配置。您只需在项目根目录运行`tuist generate` ，Tuist便会为您生成Xcode项目。
