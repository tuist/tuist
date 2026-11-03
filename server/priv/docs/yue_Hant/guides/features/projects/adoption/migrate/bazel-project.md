---
{
  "title": "遷移 Bazel 專案",
  "titleTemplate": ":title · 遷移 · 採用 · 專案 · 功能 · 指南 · Tuist",
  "description": "學習如何將你的專案從 Bazel 遷移至 Tuist。"
}
---
# 遷移 Bazel 項目 {#migrate-a-bazel-project}

[Bazel](https://bazel.build) 是 Google 於 2015 年開源的構建系統。它是一款強大的工具，讓你能夠快速可靠地構建和測試任何規模的軟件。一些大型組織如 [Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/)、[Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae) 或 [Lyft](https://semaphoreci.com/blog/keith-smiley-bazel) 都在使用它，然而，引入和維護它需要前期（即學習該技術）和持續的投入（即跟進 Xcode 更新）。雖然這對一些將其視為跨領域關注點的組織有效，但對於那些希望專注於產品開發的組織來說，可能並非最佳選擇。例如，我們見過一些組織的 iOS 平台團隊引入了 Bazel，但在主導這項工作的工程師離職後不得不放棄它。Apple 對 Xcode 與構建系統之間緊密耦合的立場，是另一個使長期維護 Bazel 項目變得困難的因素。

> [!TIP]
> **Tuist 的獨特之處在於其精妙**
>
> Tuist 並非與 Xcode 及 Xcode 項目對抗，而是擁抱它。它採用相同的概念（例如 target、scheme、構建設置）、熟悉的語言（即 Swift），以及簡單愉快的體驗，讓維護和擴展項目成為每個人的工作，而不僅僅是 iOS 平台團隊的責任。


## 規則 {#rules}

Bazel 使用規則來定義如何構建和測試軟件。這些規則使用類似 Python 的語言 [Starlark](https://github.com/bazelbuild/starlark) 編寫。Tuist 使用 Swift 作為配置語言，為開發者提供使用 Xcode 自動補全、類型檢查和驗證功能的便利。例如，以下規則描述了如何在 Bazel 中構建 Swift 庫：

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

這是另一個例子，比較如何在 Bazel 和 Tuist 中定義單元測試：

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


## Swift Package Manager 依賴 {#swift-package-manager-dependencies}

在 Bazel 中，你可以使用 [`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager) [Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md) 插件將 Swift Packages 用作依賴項。該插件需要一個 `Package.swift` 作為依賴項的唯一真實來源。在這方面，Tuist 的接口與 Bazel 相似。你可以使用 `tuist install` 命令來解析並拉取包的依賴項。解析完成後，你可以使用 `tuist generate` 命令生成項目。

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## 項目生成 {#project-generation}

社區提供了一套規則 [rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj)，用於從 Bazel 聲明的項目生成 Xcode 項目。與 Bazel 不同，Bazel 需要在你的 `BUILD` 文件中添加一些配置，而 Tuist 完全不需要任何配置。你只需在項目的根目錄運行 `tuist generate`，Tuist 就會為你生成一個 Xcode 項目。
