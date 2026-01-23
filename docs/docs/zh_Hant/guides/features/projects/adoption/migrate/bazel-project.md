---
{
  "title": "Migrate a Bazel project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate your projects from Bazel to Tuist."
}
---
# 遷移 Bazel 專案{#migrate-a-bazel-project}

[Bazel](https://bazel.build) 是 Google 於 2015
年開源的建置系統。這項強大工具能讓您快速且可靠地建置與測試任何規模的軟體。
部分大型企業如[Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/)、[Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae)或[Lyft](https://semaphoreci.com/blog/keith-smiley-bazel)採用此系統，但導入與維護需前期投入（學習技術）及持續投入（跟進Xcode更新）。
對於將其視為橫切關注點的組織而言，此方案可行；但對專注產品開發的企業可能並非最佳選擇。例如我們觀察到，某些企業的iOS平台團隊導入Bazel後，因主導工程師離職而被迫放棄。蘋果對Xcode與建置系統強耦合的立場，更是導致Bazel專案長期維護困難的另一因素。

::: tip TUIST UNIQUENESS LIES IN ITS FINESSE
<!-- -->
Tuist 並非與 Xcode 及 Xcode
專案抗衡，而是擁抱其生態。相同的技術概念（如目標、方案、建置設定）、熟悉的語言（Swift），以及簡潔愉悅的操作體驗，讓專案維護與擴展成為全體成員的任務，而非僅由
iOS 平台團隊獨力承擔。
<!-- -->
:::

## 規則{#rules}

Bazel 透過規則定義軟體的建置與測試流程。這些規則採用類似 Python 的
[Starlark](https://github.com/bazelbuild/starlark) 語言編寫。Tuist 則以 Swift
作為配置語言，讓開發者能便捷使用 Xcode 的自動完成、類型檢查與驗證功能。以下規則即描述如何在 Bazel 中建置 Swift 函式庫：

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

以下是另一個範例，但比較如何在 Bazel 和 Tuist 中定義單元測試：

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

在 Bazel 中，可透過
[`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager)
[Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md)
外掛程式將 Swift Packages 用作依賴項。該外掛需以`Package.swift` 作為依賴項的權威來源。Tuist 的介面在此層面上與 Bazel
類似。 您可使用`tuist install` 指令解析並拉取套件的依賴項。解析完成後，即可透過`tuist generate` 指令生成專案。

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## 專案生成{#project-generation}

社群提供了一套規則集[rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj)，用於從Bazel宣告的專案生成Xcode專案。與Bazel需要在`的BUILD`
檔案中添加配置不同，Tuist完全不需要任何設定。您只需在專案根目錄執行`tuist generate` 指令，Tuist便會自動為您生成Xcode專案。
