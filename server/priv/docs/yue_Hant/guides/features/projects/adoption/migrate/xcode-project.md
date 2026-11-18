---
{
  "title": "遷移 Xcode 專案",
  "titleTemplate": ":title · 遷移 · 採用 · 專案 · 功能 · 指南 · Tuist",
  "description": "了解如何將 Xcode 專案遷移至 Tuist 專案。"
}
---
# 遷移 Xcode 專案 {#migrate-an-xcode-project}

除非你<.localized_link href="/guides/features/projects/adoption/new-project">使用 Tuist 建立新專案</.localized_link>（咁樣會自動設定好一切），否則你需要用 Tuist 嘅基本元件嚟定義你嘅 Xcode 專案。呢個過程有幾繁瑣，取決於你嘅專案有幾複雜。

正如你所知，Xcode 專案隨住時間推移會變得雜亂同複雜：群組與目錄結構唔匹配、檔案喺多個 target 之間共享，或者檔案參照指向唔存在嘅檔案（僅舉幾例）。呢啲累積嘅複雜性令我哋難以提供一個可靠遷移專案嘅指令。

此外，手動遷移係清理同簡化專案嘅絕佳練習。唔單止專案開發人員會感謝你，Xcode 處理同索引專案時亦會更快。當你完全採用 Tuist 之後，佢會確保專案定義一致並保持簡單。

為咗減輕呢項工作，我哋根據從用戶收到嘅反饋提供咗一啲指引。

## 建立專案骨架 {#create-project-scaffold}

首先，使用以下 Tuist 檔案為你嘅專案建立骨架：

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

`Project.swift` 係你用嚟定義專案嘅清單檔案，而 `Package.swift` 係你用嚟定義依賴項嘅清單檔案。`Tuist.swift` 檔案則係你用嚟定義專案範圍內 Tuist 設定嘅地方。

> [!TIP]
> **專案名稱加上 -Tuist 後綴**
>
> 為避免與現有 Xcode 專案衝突，我哋建議喺專案名稱加上 `-Tuist` 後綴。當你完全將專案遷移至 Tuist 後，就可以移除佢。


## 喺 CI 中建構同測試 Tuist 專案 {#build-and-test-the-tuist-project-in-ci}

為確保每次變更嘅遷移都有效，我哋建議擴展你嘅持續整合流程，以建構同測試由你嘅清單檔案生成嘅 Tuist 專案：

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## 將專案建構設定提取到 `.xcconfig` 檔案 {#extract-the-project-build-settings-into-xcconfig-files}

將專案嘅建構設定提取到 `.xcconfig` 檔案中，令專案更輕量並更易於遷移。你可以使用以下指令將專案嘅建構設定提取到 `.xcconfig` 檔案：


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

然後更新你嘅 `Project.swift` 檔案，使其指向你剛剛建立嘅 `.xcconfig` 檔案：

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

接著擴展你嘅持續整合流程以執行以下指令，確保對建構設定嘅變更直接應用於 `.xcconfig` 檔案：

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## 提取套件依賴項 {#extract-package-dependencies}

將你專案嘅所有依賴項提取到 `Tuist/Package.swift` 檔案中：

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
> 你可以透過將特定套件添加到 `PackageSettings` 結構體中嘅 `productTypes` 字典嚟覆蓋其產品類型。預設情況下，Tuist 假設所有套件都係靜態框架。


## 確定遷移順序 {#determine-the-migration-order}

我哋建議按照依賴程度由高到低嘅順序遷移 target。你可以使用以下指令列出專案嘅 target，並按依賴項數量排序：

```bash
tuist migration list-targets -p Project.xcodeproj
```

從列表頂部開始遷移 target，因為佢哋係被依賴最多嘅。


## 遷移 target {#migrate-targets}

逐個遷移 target。我哋建議為每個 target 建立一個 pull request，以確保變更喺合併之前經過審查同測試。

### 將 target 建構設定提取到 `.xcconfig` 檔案 {#extract-the-target-build-settings-into-xcconfig-files}

好似你處理專案建構設定一樣，將 target 建構設定提取到 `.xcconfig` 檔案中，令 target 更輕量並更易於遷移。你可以使用以下指令將 target 嘅建構設定提取到 `.xcconfig` 檔案：

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### 喺 `Project.swift` 檔案中定義 target {#define-the-target-in-the-projectswift-file}

喺 `Project.targets` 中定義 target：

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
> 如果 target 有關聯嘅測試 target，你應該重複相同步驟，亦喺 `Project.swift` 檔案中定義佢。


### 驗證 target 遷移 {#validate-the-target-migration}

執行 `tuist generate`，然後執行 `xcodebuild build` 以確保專案可以成功建構，並執行 `tuist test` 以確保測試通過。此外，你可以使用 [xcdiff](https://github.com/bloomberg/xcdiff) 比較生成嘅 Xcode 專案與現有專案，以確保變更正確無誤。

### 重複 {#repeat}

重複直到所有 target 都完全遷移。完成後，我哋建議更新你嘅 CI 同 CD 流程，使用 `tuist generate`，然後執行 `xcodebuild build` 同 `tuist test` 嚟建構同測試專案。

## 疑難排解 {#troubleshooting}

### 由於缺少檔案導致嘅編譯錯誤。 {#compilation-errors-due-to-missing-files}

如果與你 Xcode 專案 target 關聯嘅檔案並非全部包含喺代表該 target 嘅檔案系統目錄中，你可能會遇到無法編譯嘅專案。請確保使用 Tuist 生成專案後嘅檔案列表與 Xcode 專案中嘅檔案列表匹配，並藉此機會將檔案結構與 target 結構對齊。
