---
{
  "title": "Migrate a Bazel project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from Bazel to Tuist."
}
---
# 遷移 Bazel 專案{#migrate-a-bazel-project}

[Bazel](https://bazel.build) 是 Google 於 2015
年開放源碼的建置系統。它是一個功能強大的工具，可讓您快速、可靠地建立和測試任何規模的軟體。一些大型組織如
[Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/)、[Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae)
或
[Lyft](https://semaphoreci.com/blog/keith-smiley-bazel)，都在使用它，然而，它需要前期（即學習技術）和持續的投資（即跟上
Xcode
更新）來引進和維護。雖然這對於某些將其視為跨領域問題的組織來說是可行的，但對於其他想要專注於產品開發的組織來說，這可能不是最適合的。舉例來說，我們曾見過一些組織的
iOS 平台團隊導入了 Bazel，但在領導這項工作的工程師離開公司後，他們不得不放棄這項工作。Apple 對於 Xcode
與建置系統之間強烈耦合的立場，也是導致 Bazel 專案難以長期維護的另一個因素。

::: tip TUIST UNIQUENESS LIES IN ITS FINESSE
<!-- -->
Tuist 並非與 Xcode 和 Xcode 專案對抗，而是擁抱它。相同的概念 (如目標、方案、建置設定)、熟悉的語言 (如 Swift)
以及簡單愉快的體驗，讓維護與擴充專案成為每個人的工作，而不只是 iOS 平台團隊的工作。
<!-- -->
:::

## 規則{#rules}

Bazel 使用規則來定義如何建立與測試軟體。這些規則是以類似 Python 的語言
[Starlark](https://github.com/bazelbuild/starlark) 寫成。Tuist 使用 Swift
作為配置語言，讓開發人員可以方便地使用 Xcode 的自動完成、類型檢查和驗證功能。例如，以下規則描述如何在 Bazel 中建立 Swift 函式庫：

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

這裡有另一個範例，但比較的是如何在 Bazel 和 Tuist 中定義單元測試：

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


## Swift 套件管理員相依性{#swift-package-manager-dependencies}

在 Bazel 中，您可以使用
[`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager)[Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md)
外掛來使用 Swift 套件作為依賴。該外掛需要`Package.swift` 作為依賴關係的真實來源。在這個意義上，Tuist 的介面與 Bazel
相似。您可以使用`tuist install` 指令來解析並拉取套件的相依性。解析完成後，您可以使用`tuist generate` 指令產生專案。

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## 專案產生{#project-generation}

社群提供了一組規則
[rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj)，用來在
Bazel 宣告的專案上產生 Xcode 專案。不像 Bazel，您需要在`BUILD` 檔案中加入一些設定，Tuist
完全不需要任何設定。您可以在專案的根目錄執行`tuist generate` ，Tuist 就會為您產生一個 Xcode 專案。
