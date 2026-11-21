---
{
  "title": "遷移 Xcode 專案",
  "titleTemplate": ":title · 遷移 · 採用 · 專案 · 功能 · 指南 · Tuist",
  "description": "了解如何將 Xcode 專案遷移至 Tuist 專案。"
}
---
# 遷移 Xcode 專案 {#migrate-an-xcode-project}

除非你<.localized_link href="/guides/features/projects/adoption/new-project">使用 Tuist 建立新專案</.localized_link>（此時所有設定會自動完成），否則你需要使用 Tuist 的原語來定義你的 Xcode 專案。此過程的繁瑣程度取決於專案的複雜度。

如你所知，Xcode 專案隨著時間推移可能變得雜亂且複雜：群組與目錄結構不符、檔案在不同 target 之間共用，或檔案參照指向不存在的檔案（僅舉幾例）。這些累積的複雜性使我們難以提供一個能可靠遷移專案的命令。

此外，手動遷移是清理並簡化專案的絕佳練習。不僅專案中的開發者會因此受益，Xcode 在處理與索引時也會更快。當你全面採用 Tuist 後，它能確保專案定義一致且保持簡潔。

為了減輕這項工作，我們根據用戶回饋提供一些指導方針。

## 建立專案骨架 {#create-project-scaffold}

首先，使用下列 Tuist 檔案為你的專案建立骨架：

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

`Project.swift` 是用來定義專案的資訊清單檔案，而 `Package.swift` 是用來定義相依性的資訊清單檔案。`Tuist.swift` 檔案則可用來定義專案範圍內的 Tuist 設定。

> [!TIP]
> **專案名稱加上 -Tuist 後綴**
>
> 為避免與現有的 Xcode 專案衝突，我們建議在專案名稱中加入 `-Tuist` 後綴。當專案完全遷移至 Tuist 後，你可以移除此後綴。


## 在 CI 中建置並測試 Tuist 專案 {#build-and-test-the-tuist-project-in-ci}

為確保每次變更的遷移皆有效，我們建議擴充你的持續整合流程，以建置並測試由 Tuist 從資訊清單檔案產生的專案：

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## 將專案建置設定提取至 `.xcconfig` 檔案 {#extract-the-project-build-settings-into-xcconfig-files}

將專案的建置設定提取到 `.xcconfig` 檔案中，讓專案更精簡且易於遷移。你可以使用以下命令將專案的建置設定提取到 `.xcconfig` 檔案：


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

接著更新你的 `Project.swift` 檔案，使其指向你剛建立的 `.xcconfig` 檔案：

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

然後擴充你的持續整合管線，執行以下命令以確保對建置設定的變更直接寫入 `.xcconfig` 檔案：

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## 提取套件相依性 {#extract-package-dependencies}

將專案的所有相依性提取到 `Tuist/Package.swift` 檔案中：

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
> 你可以透過將特定套件加入 `PackageSettings` 結構中的 `productTypes` 字典，來覆寫該套件的產品類型。預設情況下，Tuist 假設所有套件皆為靜態框架。


## 決定遷移順序 {#determine-the-migration-order}

我們建議依照 target 被依賴的程度，從最常被依賴到最少被依賴的順序進行遷移。你可以使用以下命令列出專案的 target，並依相依數量排序：

```bash
tuist migration list-targets -p Project.xcodeproj
```

從清單頂端開始遷移 target，因為它們是最常被依賴的項目。


## 遷移 target {#migrate-targets}

逐一遷移 target。我們建議為每個 target 建立拉取請求，以確保在合併前經過審查與測試。

### 將 target 建置設定提取至 `.xcconfig` 檔案 {#extract-the-target-build-settings-into-xcconfig-files}

如同處理專案建置設定，將 target 的建置設定提取到 `.xcconfig` 檔案中，讓 target 更精簡且易於遷移。你可以使用以下命令將 target 的建置設定提取到 `.xcconfig` 檔案：

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
> 如果該 target 有關聯的測試 target，你也應該在 `Project.swift` 檔案中重複相同步驟來定義它。


### 驗證 target 遷移 {#validate-the-target-migration}

執行 `tuist generate`，接著執行 `xcodebuild build` 以確保專案可以建置，並執行 `tuist test` 以確保測試通過。此外，你可以使用 [xcdiff](https://github.com/bloomberg/xcdiff) 比較產生的 Xcode 專案與現有專案，以確保變更正確無誤。

### 重複 {#repeat}

重複上述步驟直到所有 target 都完成遷移。完成後，我們建議更新你的 CI 與 CD 管線，使用 `tuist generate` 接著 `xcodebuild build` 與 `tuist test` 來建置並測試專案。

## 疑難排解 {#troubleshooting}

### 因缺少檔案导致的編譯錯誤。 {#compilation-errors-due-to-missing-files}

如果與 Xcode 專案 target 關聯的檔案並未全部位於代表該 target 的檔案系統目錄中，可能會導致專案無法編譯。請確認使用 Tuist 產生專案後的檔案清單與 Xcode 專案中的檔案清單相符，並藉此機會將檔案結構與 target 結構對齊。
