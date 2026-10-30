---
{
  "title": "遷移 Bazel 專案",
  "titleTemplate": ":title · 遷移 · 採用 · 專案 · 功能 · 指南 · Tuist",
  "description": "了解如何將你的專案從 Bazel 遷移至 Tuist。"
}
---
# 遷移 Bazel 專案 {#migrate-a-bazel-project}

[Bazel](https://bazel.build) 是 Google 於 2015 年開源的建置系統。這是一款強大的工具，讓你能够快速且可靠地建置與測試任何規模的軟體。一些大型組織如 [Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/)、[Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae) 或 [Lyft](https://semaphoreci.com/blog/keith-smiley-bazel) 都在使用它；然而，導入與維護需要前期（例如學習該技術）與持續（例如配合 Xcode 更新）的投入。雖然這對將其視為跨領域關注事項的某些組織可行，但對希望專注於產品開發的其他組織而言，未必是最合適的選擇。例如，我們曾見過某些組織由 iOS 平台團隊導入 Bazel，但在主導這項工作的工程師離職後不得不放棄。Apple 對於 Xcode 與建置系統之間緊密耦合的立場，也是讓 Bazel 專案隨時間難以維護的另一個因素。

> [!TIP]
> **Tuist 的獨特之處在於其細膩設計**
>
> Tuist 不與 Xcode 及 Xcode 專案對抗，而是擁抱它們。採用相同的概念（例如 target、scheme、建置設定）、熟悉的語言（即 Swift），以及簡單愉快的體驗，讓維護與擴展專案成為每個人的工作，而不僅是 iOS 平台團隊的責任。


## 規則 {#rules}

Bazel 使用規則來定義如何建置與測試軟體。這些規則以類似 Python 的語言 [Starlark](https://github.com/bazelbuild/starlark) 撰寫。Tuist 則使用 Swift 作為設定語言，讓開發者能夠享有 Xcode 的自動完成、型別檢查與驗證功能帶來的便利。例如，以下規則描述了如何在 Bazel 中建置 Swift 函式庫：

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

以下是另一個範例，比較在 Bazel 與 Tuist 中如何定義單元測試：

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


## Swift Package Manager 相依性 {#swift-package-manager-dependencies}

在 Bazel 中，你可以使用 [`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager) [Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md) 外掛程式，將 Swift Packages 作為相依性。此外掛程式需要一個 `Package.swift` 作為相依性的單一真實來源。在這方面，Tuist 的介面與 Bazel 類似。你可以使用 `tuist install` 指令來解析並拉取套件的相依性。解析完成後，即可使用 `tuist generate` 指令產生專案。

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## 專案產生 {#project-generation}

社群提供了一組規則 [rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj)，用於從 Bazel 宣告的專案產生 Xcode 專案。與需要在 `BUILD` 檔案中加入設定的 Bazel 不同，Tuist 完全不需要任何設定。你只需在專案根目錄執行 `tuist generate`，Tuist 就會為你產生一個 Xcode 專案。
