---
{
  "title": "Migrate an Xcode project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate an Xcode project to a Tuist project."
}
---
# 遷移 Xcode 專案{#migrate-an-xcode-project}

除非您 <LocalizedLink href="/guides/features/projects/adoption/new-project"> 使用 Tuist</LocalizedLink> 創建一個新專案，在這種情況下，您會自動獲得所有配置，否則您必須使用 Tuist 的基元來定義您的 Xcode
專案。這個過程有多繁瑣，取決於您的專案有多複雜。

您可能知道，Xcode 專案可能會隨著時間的推移而變得混亂且複雜：與目錄結構不符的群組、跨目標共用的檔案，或是指向不存在檔案的檔案引用
(僅舉幾例)。所有這些累積的複雜性讓我們很難提供一個可以可靠地遷移專案的指令。

此外，手動轉移是清理和簡化專案的絕佳練習。不僅您專案中的開發人員會因此而感謝，Xcode 也會因此而加快處理和編制索引的速度。一旦您完全採用
Tuist，它將確保專案的定義一致，並且保持簡單。

為了減輕這項工作的負擔，我們根據從使用者收到的回饋，提供一些指引給您。

## 建立專案鷹架{#create-project-scaffold}

首先，使用下列 Tuist 檔案為專案建立鷹架：

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

`Project.swift` 是您定義專案的清單檔，而`Package.swift` 則是您定義依賴物件的清單檔。`Tuist.swift`
檔案可讓您為專案定義專案範圍內的 Tuist 設定。

::: tip PROJECT NAME WITH -TUIST SUFFIX
<!-- -->
為了防止與現有的 Xcode 專案衝突，我們建議在專案名稱中加入`-Tuist` 後綴。當您完全將專案遷移至 Tuist 之後，您就可以將它刪除。
<!-- -->
:::

## 在 CI 中建立並測試 Tuist 專案{#build-and-test-the-tuist-project-in-ci}

為了確保每次變更的遷移都是有效的，我們建議擴展您的持續整合，以建立並測試 Tuist 從您的清單檔所產生的專案：

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## 將專案建立設定萃取到`.xcconfig` 檔案中{#extract-the-project-build-settings-into-xcconfig-files}

將專案中的建立設定萃取到`.xcconfig` 檔案中，讓專案更精簡，也更容易移植。您可以使用下列指令，將專案中的建立設定萃取到`.xcconfig` 檔案中：


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

然後更新您的`Project.swift` 檔案，指向您剛建立的`.xcconfig` 檔案：

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

然後延伸您的持續整合管道，執行下列指令以確保對建立設定的變更會直接到`.xcconfig` 檔案：

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## 擷取套件相依性{#extract-package-dependencies}

將專案的所有相依性檔案萃取到`Tuist/Package.swift` 檔案中：

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
您可以在`PackageSettings` 結構中，將特定套件的產品類型加入`productTypes` 字典，以覆寫該套件的產品類型。預設情況下，Tuist
假定所有套件都是靜態框架。
<!-- -->
:::


## 確定移轉順序{#determine-the-migration-order}

我們建議從依賴度最高的目標轉移到依賴度最低的目標。您可以使用下列指令列出專案的目標，依據依賴的數量排序：

```bash
tuist migration list-targets -p Project.xcodeproj
```

從清單頂端的目標開始遷移，因為它們是最需要依賴的目標。


## 遷移目標{#migrate-targets}

逐一遷移目標。我們建議為每個目標進行拉取請求，以確保變更在合併前經過審核和測試。

### 將目標建立設定萃取到`.xcconfig` 檔案中{#extract-the-target-build-settings-into-xcconfig-files}

像處理專案建立設定一樣，將目標建立設定萃取到`.xcconfig`
檔案中，讓目標更精簡，也更容易移植。您可以使用下列指令將目標建立設定擷取至`.xcconfig` 檔案：

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### 在`Project.swift` 檔案中定義目標{#define-the-target-in-the-projectswift-file}

在`Project.targets` 中定義目標：

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
如果目標有關聯的測試目標，您應該在`Project.swift` 檔案中定義，並重複相同的步驟。
<!-- -->
:::

### 驗證目標移轉{#validate-the-target-migration}

執行`tuist generate` ，接著執行`xcodebuild build` 以確保專案建立，並執行`tuist test`
以確保測試通過。此外，您可以使用 [xcdiff](https://github.com/bloomberg/xcdiff) 將產生的 Xcode
專案與現有專案進行比較，以確保變更正確無誤。

### 重複{#repeat}

重複上述動作，直到所有目標都完全轉移為止。完成後，我們建議更新您的 CI 和 CD 管道，使用`tuist generate`
來建立和測試專案，接著使用`xcodebuild build` 和`tuist test` 。

## 疑難排解{#troubleshooting}

### 由於遺失檔案造成編譯錯誤。{#compilation-errors-due-to-missing-files}

如果與您的 Xcode 專案目標相關的檔案並非全部包含在代表目標的檔案系統目錄中，您可能會得到一個無法編譯的專案。確保使用 Tuist 產生專案後的檔案清單與
Xcode 專案中的檔案清單相符，並把握機會使檔案結構與目標結構一致。
