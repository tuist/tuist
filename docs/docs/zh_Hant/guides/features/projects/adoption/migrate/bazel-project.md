---
{
  "title": "Migrate a Bazel project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from Bazel to Tuist."
}
---
# 遷移 Bazel 專案{#migrate-a-bazel-project}

[Bazel](https://bazel.build) 是 Google 於 2015
年開源的建置系統。這是一款強大的工具，能讓您快速且可靠地建置與測試任何規模的軟體。 一些大型組織如
[Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/)、[Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae)
或 [Lyft](https://semaphoreci.com/blog/keith-smiley-bazel)
都在使用它，然而，要導入並維護它需要前期投入（即學習這項技術）以及持續的投入（即跟上 Xcode 的更新）。
雖然這對將其視為橫向關切事項的組織而言可行，但對於希望專注於產品開發的其他組織來說，這可能並非最佳選擇。例如，我們曾見過某些組織的 iOS 平台團隊導入
Bazel 後，在主導該專案的工程師離職後，不得不放棄使用。蘋果對 Xcode 與建置系統之間強耦合的立場，是另一個導致 Bazel 專案難以長期維護的因素。

::: tip TUIST UNIQUENESS LIES IN ITS FINESSE
<!-- -->
Tuist 並非與 Xcode 及其專案對抗，而是擁抱它。它採用相同的概念（例如目標、方案、建置設定）、熟悉的語言（即
Swift），並提供簡單且愉悅的使用體驗，讓專案的維護與擴展成為每個人的責任，而不僅僅是 iOS 平台團隊的任務。
<!-- -->
:::

## 規則{#rules}

Bazel 使用規則來定義如何建置和測試軟體。這些規則以 [Starlark](https://github.com/bazelbuild/starlark)
編寫，這是一種類似 Python 的語言。Tuist 則採用 Swift 作為配置語言，讓開發者能便利地使用 Xcode
的自動完成、類型檢查和驗證功能。例如，以下規則描述了如何在 Bazel 中建置 Swift 函式庫：

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

以下是另一個範例，比較 Bazel 和 Tuist 中如何定義單元測試：

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


## Swift Package Manager 依賴項{#swift-package-manager-dependencies}

在 Bazel 中，您可以使用
[`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager)
[Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md)
外掛程式，將 Swift Packages 作為依賴項。該外掛程式需要一個`Package.swift` 作為依賴項的權威來源。從這一點來看，Tuist
的介面與 Bazel 相似。 您可以使用`tuist install` 指令來解析並拉取套件的依賴項。解析完成後，即可透過`tuist generate`
指令生成專案。

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## 專案生成{#project-generation}

社群提供了一套規則
[rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj)，用於從
Bazel 宣告的專案生成 Xcode 專案。與 Bazel 不同，Bazel 需要您在`BUILD` 檔案中添加一些設定，而 Tuist
則完全不需要任何設定。您可以在專案的根目錄中執行`tuist generate` ，Tuist 便會為您生成一個 Xcode 專案。
