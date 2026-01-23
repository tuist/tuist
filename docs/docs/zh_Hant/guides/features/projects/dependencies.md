---
{
  "title": "Dependencies",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to declare dependencies in your Tuist project."
}
---
# 依賴項{#dependencies}

當專案規模擴大時，常見做法是將其拆分為多個目標，以實現程式碼共享、界定範圍並縮短建置時間。多個目標意味著需定義它們之間的依賴關係，形成**依賴關係圖**
，其中可能包含外部依賴項。

## XcodeProj-編碼圖表{#xcodeprojcodified-graphs}

由於 Xcode 與 XcodeProj 的設計，維護依賴關係圖可能是一項繁瑣且容易出錯的任務。以下是一些您可能遇到的問題範例：

- 由於 Xcode
  的建置系統會將所有專案產出物輸出至衍生資料的同一目錄，目標可能意外導入不應引用的產出物。這可能導致在更常執行完整建置的持續整合環境中編譯失敗，或後續使用不同配置時發生錯誤。
- 目標的傳遞動態依賴項需複製至任何屬於以下建置設定的目錄：`LD_RUNPATH_SEARCH_PATHS`
  若未複製，目標在執行階段將無法找到這些依賴項。當圖結構較小時，此設定易於理解與配置；但隨著圖結構擴展，此問題將日益顯著。
- 當目標連結靜態的
  [XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle)
  時，需為目標新增建置階段，以便 Xcode 處理套件並提取符合當前平台與架構的正確二進位檔。此建置階段不會自動新增，且容易遺漏添加。

以上僅為部分範例，多年來我們遇見的類似情況不勝枚舉。試想若需工程團隊維護依賴關係圖並確保其有效性，甚至更糟的是，這些複雜規則由封閉式建置系統在編譯階段強制執行，而您既無法控制也無法自訂。聽起來很熟悉嗎？這正是蘋果在
Xcode 與 XcodeProj 中採用的作法，而 Swift Package Manager 亦沿襲此模式。

**我們堅信依賴關係圖應具備明確性（**）、可驗證性（** ）、靜態性（**）與可優化性（** ），唯有如此方能實現驗證（**）、驗證（**
）及優化（**）。透過 Tuist，您只需專注描述依賴關係，其餘細節由我們處理。所有複雜的實作細節皆已為您抽象化。

在以下章節中，您將學習如何在專案中宣告依賴項。

::: tip GRAPH VALIDATION
<!-- -->
Tuist 在生成專案時會驗證圖形結構，確保不存在迴圈且所有依賴關係皆有效。此機制使任何團隊皆能參與依賴圖的演進，無須擔憂破壞結構完整性。
<!-- -->
:::

## 本地依賴項{#local-dependencies}

目標可依賴於同專案或不同專案中的其他目標，以及二進位檔。在實例化目標時（例如：`Target` ），可透過`dependencies` 參數傳遞下列任一選項：

- `目標`: 聲明與同一專案內目標的依賴關係。
- `專案`: 宣告與不同專案中目標的依賴關係。
- `框架`: 宣告與二進位框架的依賴關係。
- `函式庫 ```：宣告對二進位函式庫的依賴關係。
- `XCFramework`: 宣告與二進位檔 XCFramework 的依賴關係。
- `SDK`: 宣告與系統 SDK 的依賴關係。
- `XCTest`: 宣告與 XCTest 的依賴關係。

::: info DEPENDENCY CONDITIONS
<!-- -->
每種依賴類型皆接受 ``` 條件參數 `` `，用於依據平台條件連結依賴項。預設情況下，它會為目標支援的所有平台連結依賴項。
<!-- -->
:::

## 外部依賴項{#external-dependencies}

Tuist 亦允許您在專案中宣告外部依賴項。

### Swift 套件{#swift-packages}

Swift Packages 是我們推薦的專案依賴項宣告方式。您可透過 Xcode 的預設整合機制，或使用 Tuist 的 XcodeProj
整合方案進行整合。

#### Tuist 的 XcodeProj 基礎整合方案{#tuists-xcodeprojbased-integration}

Xcode 的預設整合方式雖最為便捷，卻缺乏中大型專案所需的靈活性與控制權。為此，Tuist 提供基於 XcodeProj 的整合方案，讓您能透過
XcodeProj 的目標將 Swift Packages 整合至專案中。 藉此不僅能強化整合控制權，更能與
<LocalizedLink href="/guides/features/cache">快取</LocalizedLink>及
<LocalizedLink href="/guides/features/test/selective-testing">選擇性測試執行</LocalizedLink>等工作流程相容。

XcodeProj 的整合功能在支援新 Swift Package 特性或處理更多套件設定時，可能需要較長時間。然而 Swift Packages 與
XcodeProj 目標之間的對應邏輯屬開源性質，可由社群共同貢獻。此特性有別於 Xcode 的預設整合機制——後者為閉源設計且由 Apple 維護。

若需新增外部依賴項，請於以下路徑建立 ``` 目錄下的 `Package.swift` 檔案：` 或直接放置於專案根目錄：`Tuist/`

::: code-group
```swift [Tuist/Package.swift]
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription
    import ProjectDescriptionHelpers

    let packageSettings = PackageSettings(
        productTypes: [
            "Alamofire": .framework, // default is .staticFramework
        ]
    )

#endif

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
    ],
    targets: [
        .binaryTarget(
            name: "Sentry",
            url: "https://github.com/getsentry/sentry-cocoa/releases/download/8.40.1/Sentry.xcframework.zip",
            checksum: "db928e6fdc30de1aa97200576d86d467880df710cf5eeb76af23997968d7b2c7"
        ),
    ]
)
```
<!-- -->
:::

::: tip PACKAGE SETTINGS
<!-- -->
`用編譯器指令包裹的 PackageSettings 實例（`
）可讓您設定套件整合方式。例如上文範例中，此設定用於覆寫套件預設的產品類型。預設情況下通常無需使用此設定。
<!-- -->
:::

> [!重要] 自訂建置設定 若您的專案使用自訂建置設定（非標準設定：`Debug` 與`Release` ），必須透過`baseSettings`
> 在`PackageSettings` 中指定。外部依賴項需知悉專案設定方能正確建置。例如：
> 
> ```swift
> #if TUIST
>     import ProjectDescription
> 
>     let packageSettings = PackageSettings(
>         productTypes: [:],
>         baseSettings: .settings(configurations: [
>             .debug(name: "Base"),
>             .release(name: "Production")
>         ])
>     )
> #endif
> ```
> 
> 詳情請參閱[#8345](https://github.com/tuist/tuist/issues/8345)。

``` Package.swift
檔案僅作為宣告外部依賴項的介面，別無他用。因此您無需在套件中定義任何目標或產出物。完成依賴項定義後，可執行以下指令將依賴項解析並拉取至
Tuist/Dependencies 目錄：`

```bash
tuist install
# Resolving and fetching dependencies. {#resolving-and-fetching-dependencies}
# Installing Swift Package Manager dependencies. {#installing-swift-package-manager-dependencies}
```

如您所見，我們採用類似[CocoaPods](https://cocoapods.org)的作法，將依賴項解析設為獨立指令。此設計讓使用者能自主決定何時解析與更新依賴項，並可直接開啟專案中的
Xcode 進行編譯。 我們認為，隨著專案規模擴大，Apple 與 Swift Package Manager 的整合所提供的開發者體驗，在此領域會逐漸惡化。

接著可從專案目標中，使用 TargetDependency.external 依賴類型參照這些依賴項：``

::: code-group
```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "App",
    organizationName: "tuist.io",
    targets: [
        .target(
            name: "App",
            destinations: [.iPhone],
            product: .app,
            bundleId: "dev.tuist.app",
            deploymentTargets: .iOS("13.0"),
            infoPlist: .default,
            sources: ["Targets/App/Sources/**"],
            dependencies: [
                .external(name: "Alamofire"), // [!code ++]
            ]
        ),
    ]
)
```
<!-- -->
:::

::: info NO SCHEMES GENERATED FOR EXTERNAL PACKAGES
<!-- -->
為保持方案清單簡潔，Swift Package 專案不會自動建立**方案（** ）。您可透過 Xcode 的使用者介面手動建立。
<!-- -->
:::

#### Xcode 的預設整合{#xcodes-default-integration}

若要使用 Xcode 的預設整合機制，可在建立專案時傳遞以下清單：`packages`

```swift
let project = Project(name: "MyProject", packages: [
    .remote(url: "https://github.com/krzyzanowskim/CryptoSwift", requirement: .exact("1.8.0"))
])
```

然後從目標檔案中引用它們：

```swift
let target = .target(name: "MyTarget", dependencies: [
    .package(product: "CryptoSwift", type: .runtime)
])
```

針對 Swift 宏指令與建置工具外掛程式，需分別使用類型`.macro` 及`.plugin` 。

::: warning SPM Build Tool Plugins
<!-- -->
SPM 構建工具外掛程式必須透過 [Xcode 的預設整合機制](#xcode-s-default-integration) 進行宣告，即使您的專案依賴項採用
Tuist 的 [基於 XcodeProj 的整合方案](#tuist-s-xcodeproj-based-integration) 亦然。
<!-- -->
:::

SPM建置工具外掛的實用應用場景，是在Xcode「執行建置工具外掛」階段執行程式碼檢查。於套件清單中定義如下：

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Framework",
    products: [
        .library(name: "Framework", targets: ["Framework"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", .upToNextMajor(from: "0.56.1")),
    ],
    targets: [
        .target(
            name: "Framework",
            plugins: [
                .plugin(name: "SwiftLint", package: "SwiftLintPlugin"),
            ]
        ),
    ]
)
```

若要生成完整保留建置工具外掛的 Xcode 專案，必須在專案清單的 ``` 區塊中宣告套件 `` `，並在目標的依賴項中加入類型 ``.plugin` 的套件
`` `。

```swift
import ProjectDescription

let project = Project(
    name: "Framework",
    packages: [
        .remote(url: "https://github.com/SimplyDanny/SwiftLintPlugins", requirement: .upToNextMajor(from: "0.56.1")),
    ],
    targets: [
        .target(
            name: "Framework",
            dependencies: [
                .package(product: "SwiftLintBuildToolPlugin", type: .plugin),
            ]
        ),
    ]
)
```

### 迦太基{#carthage}

由於 [Carthage](https://github.com/carthage/carthage) 會輸出`frameworks`
或`xcframeworks` ，您可執行`carthage update` 來輸出`Carthage/Build`
目錄中的依賴項，接著使用`.framework` 或`.xcframework`
目標依賴類型在您的目標中聲明依賴關係。您可將此操作封裝成腳本，在生成專案前執行。

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

::: warning BUILD AND TEST
<!-- -->
若您透過以下指令建置與測試專案：`xcodebuild build` 以及`tuist test` 則同樣需在建置或測試前執行以下指令，確保 Carthage
解析的依賴項存在：`carthage update`
<!-- -->
:::

### CocoaPods{#cocoapods}

[CocoaPods](https://cocoapods.org) 需透過 Xcode 專案整合依賴項。您可使用 Tuist 生成專案，再執行`pod
install` 指令，透過建立包含專案與 Pods 依賴項的工作區來整合依賴項。建議將此流程封裝成腳本，於生成專案前執行。

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

::: warning
<!-- -->
CocoaPods 依賴項與以下工作流程不相容：例如執行 ``` 建立專案後立即執行 `` ` 或 ``` 測試 `` `（這些指令會觸發 ``` 執行
`xcodebuild` 並建立 `` `）。此外，由於指紋識別邏輯未考量 Pod 依賴項，此類工作流程亦與二進位檔快取及選擇性測試機制不相容。
<!-- -->
:::

## 靜態或動態{#static-or-dynamic}

框架與函式庫可透過靜態或動態連結方式整合，**此選擇將對應用程式體積與啟動時間等面向產生重大影響** 。儘管此決策至關重要，實務上卻常未經深思即草率決定。

**的一般經驗法則** 是：在發布版本中應盡可能採用靜態連結以實現快速開機，而在除錯版本中則應盡可能採用動態連結以實現快速迭代。

在專案圖中切換靜態與動態連結的挑戰在於，此操作在 Xcode 中並非易事，因為變更會對整個圖產生連鎖效應（例如：函式庫無法包含資源，靜態框架無需嵌入）。
Apple曾嘗試透過編譯時解決方案處理此問題，例如Swift Package
Manager自動判斷靜態/動態連結，或[可合併函式庫](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)機制。然而此舉會為編譯圖增添動態變數，引入新的非確定性來源，並可能導致依賴編譯圖運作的功能（如Swift
Previews）變得不可靠。

所幸 Tuist 能概念化壓縮靜態與動態切換的複雜性，並整合出適用於所有連結類型的標準化
<LocalizedLink href="/guides/features/projects/synthesized-files#bundle-accessors">束綑存取器</LocalizedLink>。結合
<LocalizedLink href="/guides/features/projects/dynamic-configuration">透過環境變數設定動態配置</LocalizedLink>，您可在執行時傳遞連結類型，並運用清單中的值來設定目標的產品類型。

```swift
// Use the value returned by this function to set the product type of your targets.
func productType() -> Product {
    if case let .string(linking) = Environment.linking {
        return linking == "static" ? .staticFramework : .framework
    } else {
        return .framework
    }
}
```

請注意，Tuist
<LocalizedLink href="/guides/features/projects/cost-of-convenience">不會因成本考量</LocalizedLink>而預設透過隱含配置提供便利性。這意味著我們仰賴您自行設定連結類型及某些必要建置參數（例如連結器旗標[`-ObjC`
](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184)），以確保產出二進位檔正確無誤。因此，我們的立場是提供資源（通常以文件形式呈現），協助您做出正確決策。

::: tip EXAMPLE: THE COMPOSABLE ARCHITECTURE
<!-- -->
許多專案整合的 Swift 套件是
[可組合架構](https://github.com/pointfreeco/swift-composable-architecture)。詳情請參閱
[此節](#the-composable-architecture)。
<!-- -->
:::

### 情境說明{#scenarios}

在某些情境下，將連結完全設定為靜態或動態皆不可行或非最佳方案。以下列舉部分需混合使用靜態與動態連結的情境（此清單並非詳盡無遺）：

- **具備擴充功能的應用程式：**
  由於應用程式及其擴充功能需共享程式碼，您可能需要將這些目標設為動態。否則，應用程式與擴充功能將重複包含相同程式碼，導致二進位檔體積增大。
- **預編譯外部依賴項：** 有時您會獲得預編譯的二進位檔，其類型可能是靜態或動態。靜態二進位檔可封裝於動態框架或函式庫中，以實現動態連結。

當對圖進行修改時，Tuist
會分析並在偵測到「靜態副作用」時顯示警告。此警告旨在協助您識別因靜態連結目標所引發的問題——該目標透過動態目標間接依賴於靜態目標。此類副作用通常會導致二進位檔體積增大，最嚴重時甚至可能引發執行時崩潰。

## 疑難排解{#troubleshooting}

### Objective-C 依賴項{#objectivec-dependencies}

整合 Objective-C 依賴項時，為避免執行階段崩潰，需在使用目標中加入特定標記，詳見 [Apple 技術問答
QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html)。

` 由於建置系統與 Tuist 無法判斷標記是否必要，且該標記可能帶來不良副作用，Tuist 不會自動套用任何標記。此外，Swift Package
Manager 會將 ``-ObjC` 視為透過 ``` 包含的標記，而 `.unsafeFlag` 則被視為 `` `
的一部分，因此多數套件在需要時無法將其納入預設連結設定。

` 使用 Objective-C 依賴項（或內部 Objective-C 目標）的消費者，應在需要時於使用目標中設定 ```
並啟用 `OTHER_LDFLAGS` 旗標，使用以下指令：`-ObjC` 或`-force_load`

### Firebase 與其他 Google 函式庫{#firebase-other-google-libraries}

Google 的開源函式庫——儘管功能強大——在整合至 Tuist 時可能面臨困難，因其建構方式常採用非標準架構與技術。

以下是整合 Firebase 與 Google 其他 Apple 平台函式庫時，可能需要遵循的幾項要點：

#### 請確保在`的 OTHER_LDFLAGS 中加入`-ObjC`` {#ensure-objc-is-added-to-other_ldflags}

` 許多 Google 函式庫採用 Objective-C 編寫。因此，任何使用這些函式庫的目標需在`的 OTHER_LDFLAGS 設定中加入`-ObjC`
標記。此設定可透過`.xcconfig` 檔案設定，或於 Tuist 清單中的目標設定手動指定。範例如下：

```swift
Target.target(
    ...
    settings: .settings(
        base: ["OTHER_LDFLAGS": "$(inherited) -ObjC"]
    )
    ...
)
```

更多細節請參閱上文的[Objective-C 依賴項](#objective-c-dependencies) 部分。

#### 將產品類型設定為動態框架：`FBLPromises` {#set-the-product-type-for-fblpromises-to-dynamic-framework}

某些 Google 函式庫依賴於`FBLPromises` 這個 Google 函式庫。您可能會遇到提及`FBLPromises` 的當機訊息，內容類似如下：

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

在您的`Package.swift` 檔案中，明確將產品類型從`FBLPromises` 設定為`.framework` 應可解決此問題：

```swift [Tuist/Package.swift]
// swift-tools-version: 5.10

import PackageDescription

#if TUIST
import ProjectDescription
import ProjectDescriptionHelpers

let packageSettings = PackageSettings(
    productTypes: [
        "FBLPromises": .framework,
    ]
)
#endif

let package = Package(
...
```

### 可組合架構{#the-composable-architecture}

如[此處](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184)及[疑難排解章節](#troubleshooting)所述，靜態連結套件時需將`的OTHER_LDFLAGS設定為`
，具體值為`$(inherited) -ObjC` （此為Tuist預設連結類型）。另可將套件的產品類型覆寫為動態連結。
靜態連結時，測試與應用程式目標通常運作正常，但 SwiftUI 預覽功能會失效。此問題可透過動態連結所有元件解決。下例中同時將
[Sharing](https://github.com/pointfreeco/swift-sharing) 列為依賴項，因其常與 The
Composable Architecture 搭配使用，且存在專屬的
[配置陷阱](https://github.com/pointfreeco/swift-sharing/issues/150#issuecomment-2797107032)。

以下設定將動態連結所有項目——因此應用程式 + 測試目標與 SwiftUI 預覽功能皆可正常運作。

::: tip STATIC OR DYNAMIC
<!-- -->
動態連結並非總是最佳選擇。詳情請參閱[靜態或動態](#static-or-dynamic)章節。為簡化示例，此處所有依賴項均採用無條件動態連結。
<!-- -->
:::

```swift [Tuist/Package.swift]
// swift-tools-version: 6.0
import PackageDescription

#if TUIST
import enum ProjectDescription.Environment
import struct ProjectDescription.PackageSettings

let packageSettings = PackageSettings(
    productTypes: [
        "CasePaths": .framework,
        "CasePathsCore": .framework,
        "Clocks": .framework,
        "CombineSchedulers": .framework,
        "ComposableArchitecture": .framework,
        "ConcurrencyExtras": .framework,
        "CustomDump": .framework,
        "Dependencies": .framework,
        "DependenciesTestSupport": .framework,
        "IdentifiedCollections": .framework,
        "InternalCollectionsUtilities": .framework,
        "IssueReporting": .framework,
        "IssueReportingPackageSupport": .framework,
        "IssueReportingTestSupport": .framework,
        "OrderedCollections": .framework,
        "Perception": .framework,
        "PerceptionCore": .framework,
        "Sharing": .framework,
        "SnapshotTesting": .framework,
        "SwiftNavigation": .framework,
        "SwiftUINavigation": .framework,
        "UIKitNavigation": .framework,
        "XCTestDynamicOverlay": .framework
    ],
    targetSettings: [
        "ComposableArchitecture": .settings(base: [
            "OTHER_SWIFT_FLAGS": ["-module-alias", "Sharing=SwiftSharing"]
        ]),
        "Sharing": .settings(base: [
            "PRODUCT_NAME": "SwiftSharing",
            "OTHER_SWIFT_FLAGS": ["-module-alias", "Sharing=SwiftSharing"]
        ])
    ]
)
#endif
```

::: warning
<!-- -->
請將原始語法：`import Sharing` 替換為：`import SwiftSharing`
<!-- -->
:::

### 透過 ``` 洩漏的傳遞性靜態依賴關係` {#transitive-static-dependencies-leaking-through-swiftmodule}

` 當動態框架或函式庫透過以下方式依賴靜態框架時：`import StaticSwiftModule` ，其符號會被納入動態框架或函式庫的
``.swiftmodule` 檔案中，可能導致編譯失敗。為避免此情況，需使用以下方式導入靜態依賴項：``` `internal import` ```
`</LocalizedLink>`：

```swift
internal import StaticModule
```

::: info
<!-- -->
Swift 6 引入了導入層級的存取限制。若使用舊版
Swift，請改用以下格式：<LocalizedLink href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_implementationOnly`</LocalizedLink>
<!-- -->
:::

```swift
@_implementationOnly import StaticModule
```
