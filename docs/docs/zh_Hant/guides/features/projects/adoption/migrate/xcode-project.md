---
{
  "title": "Migrate an Xcode project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate an Xcode project to a Tuist project."
}
---
# 遷移 Xcode 專案{#migrate-an-xcode-project}

除非您 <LocalizedLink href="/guides/features/projects/adoption/new-project">使用
Tuist 建立新專案</LocalizedLink>（此情況下所有設定將自動完成），否則您必須使用 Tuist 的基礎元件來定義您的 Xcode
專案。此過程的繁瑣程度，取決於您的專案複雜度。

您可能已經知道，Xcode
專案隨著時間推移可能會變得雜亂且複雜：例如與目錄結構不符的群組、在不同目標間共享的檔案，或是指向不存在的檔案的檔案參照（僅舉幾例）。所有這些累積的複雜性，使得我們難以提供一個能可靠地遷移專案的命令。

此外，手動遷移是整理並簡化專案的絕佳練習。這不僅會讓專案中的開發人員感激不盡，Xcode 也能因此更快地處理和索引這些檔案。一旦您完全採用
Tuist，它將確保專案定義的一致性，並使其保持簡潔。

為了減輕您的工作負擔，我們根據使用者提供的回饋，為您提供以下指引。

## 建立專案骨架{#create-project-scaffold}

首先，請使用以下 Tuist 檔案為您的專案建立基礎架構：

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

`Project.swift` 是您用來定義專案的清單檔案，而`Package.swift` 則是您用來定義依賴項的清單檔案。`Tuist.swift`
檔案則可讓您為專案定義專案範圍內的 Tuist 設定。

::: tip PROJECT NAME WITH -TUIST SUFFIX
<!-- -->
為避免與現有 Xcode 專案產生衝突，建議在專案名稱後方加上「`-Tuist` 」的後綴。待專案完全遷移至 Tuist 後，即可移除此後綴。
<!-- -->
:::

## 在 CI 中建置並測試 Tuist 專案{#build-and-test-the-tuist-project-in-ci}

為確保每次變更的遷移有效，我們建議擴展您的持續整合流程，以建置並測試由 Tuist 根據您的設定檔所生成的專案：

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## 將專案建置設定匯出至`.xcconfig` 檔案{#extract-the-project-build-settings-into-xcconfig-files}

將專案中的建置設定擷取至`.xcconfig` 檔案，以使專案更精簡且更易於遷移。您可以使用以下指令，將專案中的建置設定擷取至`.xcconfig` 檔案：


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

接著，請更新您的`Project.swift` 檔案，使其指向您剛建立的`.xcconfig` 檔案：

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

接著，請擴展您的持續整合管道，以執行以下指令，確保對建置設定的變更會直接套用至` 中的 .xcconfig 及` 檔案：

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## 提取套件依賴項{#extract-package-dependencies}

將專案的所有依賴項提取至`Tuist/Package.swift` 檔案中：

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
您可以透過將特定套件新增至`PackageSettings` 結構中的`productTypes` 字典，來覆寫該套件的產品類型。預設情況下，Tuist
會假設所有套件皆為靜態框架。
<!-- -->
:::


## 確定遷移順序{#determine-the-migration-order}

我們建議將目標依賴關係從最高到最低的順序進行遷移。您可以使用以下指令列出專案的目標，並按依賴關係數量排序：

```bash
tuist migration list-targets -p Project.xcodeproj
```

請從清單頂端開始遷移目標，因為這些是依賴性最高的項目。


## 遷移目標{#migrate-targets}

請逐一遷移各目標。我們建議針對每個目標提交拉取請求，以確保在合併前，相關變更已通過審查與測試。

### 將目標建置設定提取至`.xcconfig 及` 檔案中{#extract-the-target-build-settings-into-xcconfig-files}

如同處理專案建置設定時一樣，將目標的建置設定提取至`.xcconfig`
檔案中，以使目標更精簡且更易於遷移。您可以使用以下指令，將建置設定從目標提取至`.xcconfig` 檔案中：

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### 在`Project.swift` 檔案中定義目標{#define-the-target-in-the-projectswift-file}

在`Project.targets 中定義目標：`:

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
若目標具有關聯的測試目標，您應在`Project.swift` 檔案中定義該測試目標，並重複相同的步驟。
<!-- -->
:::

### 驗證目標遷移{#validate-the-target-migration}

執行`tuist generate` ，接著執行`xcodebuild build` 以確保專案能成功建置，並執行`tuist test`
以確保測試通過。此外，您可以使用 [xcdiff](https://github.com/bloomberg/xcdiff) 比較生成的 Xcode
專案與現有專案，以確保變更內容正確無誤。

### 重複{#repeat}

重複此步驟，直到所有目標完全遷移完成。完成後，建議更新您的 CI 和 CD 管道，使用`tuist generate`
來建置和測試專案，接著執行`xcodebuild build` 以及`tuist test` 。

## 疑難排解{#troubleshooting}

### 因檔案遺失而導致的編譯錯誤。{#compilation-errors-due-to-missing-files}

若您 Xcode 專案目標相關的檔案並未全數存放於代表該目標的檔案系統目錄中，最終可能導致專案無法編譯。請確保使用 Tuist 生成專案後的檔案清單與
Xcode 專案中的檔案清單相符，並藉此機會將檔案結構與目標結構對齊。
