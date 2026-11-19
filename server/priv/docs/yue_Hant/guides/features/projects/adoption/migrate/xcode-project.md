---
{
  "title": "遷移 Xcode 專案",
  "titleTemplate": ":title · 遷移 · 採用 · 專案 · 功能 · 指南 · Tuist",
  "description": "了解如何將 Xcode 專案遷移至 Tuist 專案。"
}
---
# 遷移 Xcode 專案 {#migrate-an-xcode-project}

除非你<.localized_link href="/guides/features/projects/adoption/new-project">使用 Tuist 建立新專案</.localized_link>（這種情況下所有設定都會自動完成），否則你需要使用 Tuist 的原語來定義你的 Xcode 專案。這個過程有多繁瑣，取決於你的專案有多複雜。

你可能知道，Xcode 專案隨著時間推移會變得混亂和複雜：群組與目錄結構不符、檔案在多個 target 之間共用，或檔案參考指向不存在的檔案（僅舉幾例）。這些累積的複雜性使我們難以提供一個能可靠遷移專案的命令。

此外，手動遷移是清理和簡化專案的絕佳練習。不僅專案中的開發人員會對此表示感謝，Xcode 也會因為處理和索引速度更快而受益。一旦你完全採用 Tuist，它將確保專案定義一致並保持簡單。

為了減輕這項工作，我們根據從用戶收到的反饋提供一些指引。

## 建立專案骨架 {#create-project-scaffold}

首先，使用以下 Tuist 檔案為你的專案建立骨架：

::: code-group

```js [Tuist.swift]
import ProjectDescription

let tuist = Tuist()
```

```js [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyApp-Tuist",
    targets: [
        /** Targets will go here **/
    ]
)
```

```js [Tuist/Package.swift]
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        // Customize the product types for specific package product
        // Default is .staticFramework
        // productTypes: ["Alamofire": .framework,]
        productTypes: [:]
    )
#endif

let package = Package(
    name: "MyApp",
    dependencies: [
        // Add your own dependencies here:
        // .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
        // You can read more about dependencies here: https://tuist.dev/en/docs/guides/features/projects/dependencies
    ]
)
```
<!-- -->
:::

`Project.swift` 是你定義專案的 manifest 檔案，而 `Package.swift` 是你定義依賴項的 manifest 檔案。`Tuist.swift` 檔案則是用來定義專案範圍內的 Tuist 設定。

> [!TIP]
> **專案名稱加上 -Tuist 後綴**
>
> 為了避免與現有的 Xcode 專案發生衝突，我們建議在專案名稱中加入 `-Tuist` 後綴。當你完全將專案遷移到 Tuist 後，可以刪除此後綴。


## 在 CI 中建構和測試 Tuist 專案 {#build-and-test-the-tuist-project-in-ci}

為了確保每次變更的遷移都有效，我們建議擴展你的持續整合流程，以建構和測試由 Tuist 從你的 manifest 檔案產生的專案：

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## 將專案建構設定提取到 `.xcconfig` 檔案中 {#extract-the-project-build-settings-into-xcconfig-files}

將專案中的建構設定提取到 `.xcconfig` 檔案中，使專案更精簡且更易於遷移。你可以使用以下命令將專案中的建構設定提取到 `.xcconfig` 檔案中：


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

然後更新你的 `Project.swift` 檔案，使其指向你剛建立的 `.xcconfig` 檔案：

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    settings: .settings(configurations: [
        .debug(name: "Debug", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"),
        .release(name: "Release", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"),
    ]),
    targets: [
        /** Targets will go here **/
    ]
)
```

然後擴展你的持續整合流程以運行以下命令，確保對建構設定的變更直接應用於 `.xcconfig` 檔案：

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## 提取套件依賴項 {#extract-package-dependencies}

將你專案的所有依賴項提取到 `Tuist/Package.swift` 檔案中：

```swift
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        // Customize the product types for specific package product
        // Default is .staticFramework
        // productTypes: ["Alamofire": .framework,]
        productTypes: [:]
    )
#endif

let package = Package(
    name: "MyApp",
    dependencies: [
        // Add your own dependencies here:
        // .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
        // You can read more about dependencies here: https://tuist.dev/en/docs/guides/features/projects/dependencies
        .package(url: "https://github.com/onevcat/Kingfisher", .upToNextMajor(from: "7.12.0"))
    ]
)
```

> [!TIP]
> **產品類型**
>
> 你可以透過將其添加到 `PackageSettings` 結構中的 `productTypes` 字典來覆蓋特定套件的產品類型。預設情況下，Tuist 假設所有套件都是靜態框架。


## 確定遷移順序 {#determine-the-migration-order}

我們建議從被依賴最多的 target 開始遷移，直到被依賴最少的 target。你可以使用以下命令列出專案的 target，並按依賴項數量排序：

```bash
tuist migration list-targets -p Project.xcodeproj
```

從列表頂部開始遷移 target，因為它們是被依賴最多的。


## 遷移 target {#migrate-targets}

逐一遷移 target。我們建議為每個 target 建立一個 pull request，以確保在合併之前對變更進行審查和測試。

### 將 target 建構設定提取到 `.xcconfig` 檔案中 {#extract-the-target-build-settings-into-xcconfig-files}

就像處理專案建構設定一樣，將 target 建構設定提取到 `.xcconfig` 檔案中，使 target 更精簡且更易於遷移。你可以使用以下命令將 target 中的建構設定提取到 `.xcconfig` 檔案中：

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### 在 `Project.swift` 檔案中定義 target {#define-the-target-in-the-projectswift-file}

在 `Project.targets` 中定義 target：

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    settings: .settings(configurations: [
        .debug(name: "Debug", xcconfig: "./xcconfigs/Project.xcconfig"),
        .release(name: "Release", xcconfig: "./xcconfigs/Project.xcconfig"),
    ]),
    targets: [
        .target(
            name: "TargetX",
            destinations: .iOS,
            product: .framework, // or .staticFramework, .staticLibrary...
            bundleId: "dev.tuist.targetX",
            sources: ["Sources/TargetX/**"],
            dependencies: [
                /** Dependencies go here **/
                /** .external(name: "Kingfisher") **/
                /** .target(name: "OtherProjectTarget") **/
            ],
            settings: .settings(configurations: [
                .debug(name: "Debug", xcconfig: "./xcconfigs/TargetX.xcconfig"),
                .release(name: "Release", xcconfig: "./xcconfigs/TargetX.xcconfig"),
            ])
        ),
    ]
)
```

> [!NOTE]
> **測試 target**
>
> 如果該 target 有關聯的測試 target，你應該在 `Project.swift` 檔案中重複相同的步驟來定義它。


### 驗證 target 遷移 {#validate-the-target-migration}

運行 `tuist generate`，接著運行 `xcodebuild build` 以確保專案可以建構，並運行 `tuist test` 以確保測試通過。此外，你可以使用 [xcdiff](https://github.com/bloomberg/xcdiff) 比較產生的 Xcode 專案與現有專案，以確保變更是正確的。

### 重複 {#repeat}

重複此過程直到所有 target 都完全遷移。完成後，我們建議更新你的 CI 和 CD 流程，使用 `tuist generate` 接著 `xcodebuild build` 和 `tuist test` 來建構和測試專案。

## 疑難排解 {#troubleshooting}

### 因缺少檔案而導致編譯錯誤。 {#compilation-errors-due-to-missing-files}

如果你的 Xcode 專案 target 關聯的檔案並非全部包含在代表該 target 的檔案系統目錄中，最終可能會得到一個無法編譯的專案。請確保使用 Tuist 產生專案後的檔案列表與 Xcode 專案中的檔案列表相符，並藉此機會將檔案結構與 target 結構對齊。
