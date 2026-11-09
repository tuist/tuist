---
{
  "title": "遷移 Bazel 專案",
  "titleTemplate": ":title · 遷移 · 採用 · 專案 · 功能 · 指南 · Tuist",
  "description": "學習如何將你的專案從 Bazel 遷移至 Tuist。"
}
---
# 遷移 Bazel 專案 {#migrate-a-bazel-project}

[Bazel](https://bazel.build) 係 Google 喺 2015 年開源嘅建構系統。佢係一個強大嘅工具，令你能够快速可靠地建構同測試任何規模嘅軟件。一啲大型機構例如 [Spotify](https://engineering.atspotify.com/2023/10/switching-build-systems-seamlessly/)、[Tinder](https://medium.com/tinder/bazel-hermetic-toolchain-and-tooling-migration-c244dc0d3ae) 或 [Lyft](https://semaphoreci.com/blog/keith-smiley-bazel) 都有使用，不過，引入同維護佢需要前期（即係學習技術）同持續嘅投入（即係跟上 Xcode 更新）。雖然對於將佢視為跨領域關注事項嘅機構來講可行，但對於想專注於產品開發嘅其他機構來講，可能唔係最佳選擇。例如，我哋見過有機構嘅 iOS 平台團隊引入 Bazel，但當負責推動嘅工程師離職後，就不得不放棄。Apple 對 Xcode 同建構系統之間緊密耦合嘅立場，亦係令到長期維護 Bazel 專案變得困難嘅另一個因素。

> [!TIP]
> **Tuist 嘅獨特之處在於其巧妙設計**
>
> Tuist 並唔係對抗 Xcode 同 Xcode 專案，而係擁抱佢。佢採用相同嘅概念（例如 target、scheme、建構設定）、熟悉嘅語言（即係 Swift），以及簡單愉快嘅體驗，令到維護同擴展專案成為每個人嘅責任，而不僅限於 iOS 平台團隊。


## 規則 {#rules}

Bazel 使用規則來定義如何建構同測試軟件。呢啲規則係用 [Starlark](https://github.com/bazelbuild/starlark)（一種類似 Python 嘅語言）編寫。Tuist 使用 Swift 作為配置語言，為開發者提供使用 Xcode 自動完成、類型檢查同驗證功能嘅便利。例如，以下規則描述咗如何在 Bazel 中建構 Swift 庫：

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
        .target(
            name: "MyLibrary",
            destinations: .iOS,
            product: .staticLibrary,
            bundleId: "dev.tuist.MyLibrary",
            sources: ["**/*.swift"]
        )
    ]
)
```
<!-- -->
:::

以下係另一個例子，比較如何在 Bazel 同 Tuist 中定義單元測試：

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

在 Bazel 中，你可以使用 [`rules_swift_package_manager`](https://github.com/cgrindel/rules_swift_package_manager) [Gazelle](https://github.com/bazelbuild/bazel-gazelle/blob/master/extend.md) 插件來將 Swift Packages 用作依賴。該插件需要 `Package.swift` 作為依賴項嘅真實來源。從呢個角度來講，Tuist 嘅介面與 Bazel 相似。你可以使用 `tuist install` 命令來解析同拉取套件嘅依賴。解析完成後，你就可以使用 `tuist generate` 命令來生成專案。

```bash
tuist install # Fetch dependencies defined in Tuist/Package.swift
tuist generate # Generate an Xcode project
```

## 專案生成 {#project-generation}

社區提供咗一組規則 [rules_xcodeproj](https://github.com/MobileNativeFoundation/rules_xcodeproj)，用於從 Bazel 聲明嘅專案生成 Xcode 專案。與 Bazel 不同，你唔需要喺 `BUILD` 文件中添加任何配置，Tuist 完全唔需要任何配置。你只需要喺專案嘅根目錄運行 `tuist generate`，Tuist 就會為你生成一個 Xcode 專案。
