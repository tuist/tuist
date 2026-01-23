---
{
  "title": "Migrate an Xcode project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate an Xcode project to a Tuist project."
}
---
# 遷移 Xcode 專案{#migrate-an-xcode-project}

除非您<LocalizedLink href="/guides/features/projects/adoption/new-project">使用Tuist建立新專案</LocalizedLink>（此時所有設定將自動完成），否則必須透過Tuist的原始元件來定義Xcode專案。此過程的繁瑣程度取決於專案的複雜性。

您可能已知曉，Xcode
專案隨時間推移可能變得雜亂複雜：群組結構與目錄架構不符、檔案在不同目標間重複存在、或檔案參照指向不存在的檔案（僅舉數例）。這些累積的複雜性使我們難以提供可靠的專案遷移指令。

此外，手動遷移是清理與簡化專案的絕佳練習。不僅專案開發者會因此感激，Xcode 的處理與索引速度也將因此提升。當您全面採用 Tuist
後，它將確保專案定義保持一致且結構簡潔。

為減輕此項工作負擔，我們根據使用者回饋提供以下指引：

## 建立專案骨架{#create-project-scaffold}

首先，請使用以下 Tuist 檔案為專案建立骨架：

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
        // You can read more about dependencies here: https://docs.tuist.io/documentation/tuist/dependencies
    ]
)
```
<!-- -->
:::

`Project.swift` 是用於定義專案的清單檔案，而`Package.swift` 則是用於定義依賴項的清單檔案。`Tuist.swift`
檔案則可定義專案層級的 Tuist 設定。

::: tip PROJECT NAME WITH -TUIST SUFFIX
<!-- -->
為避免與現有 Xcode 專案衝突，建議在專案名稱後添加`-Tuist` 後綴。待專案完整遷移至 Tuist 後即可移除此後綴。
<!-- -->
:::

## 在持續整合環境中建置並測試 Tuist 專案{#build-and-test-the-tuist-project-in-ci}

為確保每次變更遷移的有效性，建議您擴充持續整合流程，以從您的清單檔案由 Tuist 生成的專案進行建置與測試：

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## 將專案建置設定提取至`.xcconfig` 檔案{#extract-the-project-build-settings-into-xcconfig-files}

`` 將專案的建置設定提取至獨立的 ``.xcconfig` 檔案，使專案更精簡且易於遷移。可使用以下指令將建置設定提取至 ``.xcconfig` 檔案：


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

接著更新您的`Project.swift 檔案，並將` 設定為指向您剛建立的`.xcconfig 檔案：`

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    settings: .settings(configurations: [
        .debug(name: "Debug", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"), // [!code ++]
        .release(name: "Release", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"), // [!code ++]
    ]),
    targets: [
        /** Targets will go here **/
    ]
)
```

接著擴充您的持續整合管線，執行下列指令以確保建置設定變更會直接套用至` 的 .xcconfig 檔案：`

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## 提取套件依賴關係{#extract-package-dependencies}

`將專案所有依賴項提取至 Tuist/Package.swift 檔案中的` 區塊：

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
        // You can read more about dependencies here: https://docs.tuist.io/documentation/tuist/dependencies
        .package(url: "https://github.com/onevcat/Kingfisher", .upToNextMajor(from: "7.12.0")) // [!code ++]
    ]
)
```

::: tip PRODUCT TYPES
<!-- -->
您可透過在`的 PackageSettings 結構體中，於` 字典的`欄位新增產品類型，來覆寫特定套件的預設類型。` 預設情況下，Tuist
會將所有套件視為靜態框架。
<!-- -->
:::


## 確定遷移順序{#determine-the-migration-order}

建議依賴程度由高至低遷移目標。可使用下列指令列出專案目標清單，並依依賴數量排序：

```bash
tuist migration list-targets -p Project.xcodeproj
```

請從清單頂端開始遷移目標，因這些項目具有最高依賴性。


## 遷移目標{#migrate-targets}

請逐一遷移目標語言。建議為每個目標語言提交拉取請求，以確保合併前完成變更審查與測試。

### 將目標建置設定提取至`.xcconfig` 檔案中{#extract-the-target-build-settings-into-xcconfig-files}

` 如同您處理專案建置設定的方式，請將目標建置設定提取至獨立的 ``.xcconfig`
檔案，以使目標更精簡且易於遷移。您可使用以下指令將目標建置設定提取至獨立檔案：`.xcconfig`

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### 在`專案的 Project.swift 檔案中定義目標：` {#define-the-target-in-the-projectswift-file}

於`中的 Project.targets 定義目標：` ：

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    settings: .settings(configurations: [
        .debug(name: "Debug", xcconfig: "./xcconfigs/Project.xcconfig"),
        .release(name: "Release", xcconfig: "./xcconfigs/Project.xcconfig"),
    ]),
    targets: [
        .target( // [!code ++]
            name: "TargetX", // [!code ++]
            destinations: .iOS, // [!code ++]
            product: .framework, // [!code ++] // or .staticFramework, .staticLibrary...
            bundleId: "dev.tuist.targetX", // [!code ++]
            sources: ["Sources/TargetX/**"], // [!code ++]
            dependencies: [ // [!code ++]
                /** Dependencies go here **/ // [!code ++]
                /** .external(name: "Kingfisher") **/ // [!code ++]
                /** .target(name: "OtherProjectTarget") **/ // [!code ++]
            ], // [!code ++]
            settings: .settings(configurations: [ // [!code ++]
                .debug(name: "Debug", xcconfig: "./xcconfigs/TargetX.xcconfig"), // [!code ++]
                .debug(name: "Release", xcconfig: "./xcconfigs/TargetX.xcconfig"), // [!code ++]
            ]) // [!code ++]
        ), // [!code ++]
    ]
)
```

::: info TEST TARGETS
<!-- -->
若目標存在關聯測試目標，應在`Project.swift 及` 檔案中重複相同步驟進行定義。
<!-- -->
:::

### 驗證目標遷移{#validate-the-target-migration}

執行`tuist generate` 接著執行`xcodebuild build` 以確保專案能成功編譯，並執行`tuist test`
確認測試通過。此外，可使用 [xcdiff](https://github.com/bloomberg/xcdiff) 比較生成的 Xcode
專案與現有版本，以驗證變更正確無誤。

### 重複{#repeat}

重複上述步驟直至所有目標完全遷移。完成後，建議更新您的持續整合與持續交付管道，使用以下指令建置並測試專案：`tuist generate`
接著執行：`xcodebuild build` 以及：`tuist test`

## 疑難排解{#troubleshooting}

### 因檔案遺失導致的編譯錯誤。{#compilation-errors-due-to-missing-files}

若 Xcode 專案目標的相關檔案未全數存放於代表該目標的檔案系統目錄中，可能導致專案無法編譯。請確認使用 Tuist 生成專案後的檔案清單與 Xcode
專案中的檔案清單相符，並藉此機會將檔案結構與目標結構對齊。
