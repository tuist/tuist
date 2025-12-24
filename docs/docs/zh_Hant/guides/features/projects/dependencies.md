---
{
  "title": "Dependencies",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to declare dependencies in your Tuist project."
}
---
# 依賴{#dependencies}

當專案成長時，通常會將專案分割成多個目標，以分享程式碼、定義邊界並改善建置時間。多個目標意味著定義它們之間的依賴關係，形成**依賴關係圖**
，其中也可能包括外部依賴關係。

## XcodeProj 編碼的圖形{#xcodeprojcodified-graphs}

由於 Xcode 和 XcodeProj 的設計，維護相依性圖形可能是一項乏味且容易出錯的工作。以下是您可能會遇到的問題的一些範例：

- 由於 Xcode 的建立系統會將專案的所有產品輸出到派生資料中的同一個目錄，因此目標可能會匯入不該匯入的產品。編譯可能會在 CI 上失敗，在 CI
  上，乾淨的建置比較常見，或者之後使用不同的組態時也可能會失敗。
- 目標的 Transitive 動態相依性需要複製到任何屬於`LD_RUNPATH_SEARCH_PATHS`
  建立設定的目錄中。如果沒有，目標就無法在執行時找到它們。這在圖表較小的時候很容易考慮和設定，但當圖表越來越大時就會成為問題。
- 當目標連結靜態
  [XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle)
  時，目標需要一個額外的建立階段，以便 Xcode 處理 bundle
  並針對目前的平台和架構擷取正確的二進位檔。這個建立階段不會自動加入，而且很容易忘記加入。

以上只是幾個例子，多年來我們遇到的例子還有很多。試想一下，如果您需要一組工程師來維護相依性圖表，並確保其有效性。或者更糟糕的是，複雜的問題在建立時由一個您無法控制或自訂的封閉式建立系統來解決。聽起來耳熟嗎？Apple
在 Xcode 和 XcodeProj 中採用了這種方式，而 Swift Package Manager 也承襲了這種方式。

我們堅信，依賴圖應該是**明確的** 和**靜態的** ，因為只有這樣才能**驗證** 和**優化** 。有了
Tuist，您只需專注於描述何者依賴於何者，其餘的就交給我們處理。複雜的問題和實作細節都會被抽象出來。

在以下幾節中，您將學習如何在專案中宣告依賴關係。

::: tip GRAPH VALIDATION
<!-- -->
Tuist 會在產生專案時驗證圖形，以確保沒有循環，且所有的相依性都是有效的。有了這個功能，任何團隊都可以參與相依圖的演進，而不必擔心會破壞相依圖。
<!-- -->
:::

## 本地依賴{#local-dependencies}

目標可以依賴相同或不同專案中的其他目標，以及二進位檔案。在實體化`Target` 時，您可以傳送`dependencies` 參數與下列任何選項：

- `目標` ：在同一專案中宣告與目標的相依性。
- `專案` ：宣告與不同專案中的目標相依的依賴關係。
- `框架` ：宣告與二進位框架的依賴關係。
- `函式庫` ：宣告與二進位函式庫的相依性。
- `XCFramework` ：宣告與二進位 XCFramework 的相依性。
- `SDK` ：宣告與系統 SDK 的依賴關係。
- `XCTest` ：宣告與 XCTest 的相依性。

::: info DEPENDENCY CONDITIONS
<!-- -->
每個依賴類型都接受`condition` 選項，以根據平台有條件地連結依賴。預設情況下，它會連結目標支援的所有平台的相依性。
<!-- -->
:::

## 外部依賴{#external-dependencies}

Tuist 也允許您在專案中宣告外部相依性。

### 迅捷套裝{#swift-packages}

Swift Packages 是我們推薦的在專案中宣告相依性的方式。您可以使用 Xcode 的預設整合機制或 Tuist 的基於 XcodeProj
的整合來整合它們。

#### Tuist 基於 XcodeProj 的整合{#tuists-xcodeprojbased-integration}

Xcode 的預設整合雖然是最方便的，但缺乏中大型專案所需的彈性與控制。為了克服這個問題，Tuist 提供了一個基於 XcodeProj 的整合，允許您使用
XcodeProj 的目標在專案中整合 Swift
套件。有賴於此，我們不僅能讓您對整合有更多控制，還能使其相容於<LocalizedLink href="/guides/features/cache">快取</LocalizedLink>和<LocalizedLink href="/guides/features/test/selective-testing">選擇性測試執行</LocalizedLink>等工作流程。

XcodeProj 的整合更可能需要更多的時間來支援新的 Swift 套件功能或處理更多的套件配置。不過，Swift 套件與 XcodeProj
目標之間的對應邏輯是開放原始碼的，可以由社群貢獻。這與 Xcode 的預設整合相反，Xcode 的預設整合是封閉源碼，並由 Apple 維護。

若要新增外部相依性，您必須在`Tuist/` 或專案根目錄下建立`Package.swift` 。

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
`PackageSettings`
包裝在編譯器指令中的實例，可讓您設定套件的整合方式。例如，在上面的範例中，它是用來覆寫套件所使用的預設產品類型。預設情況下，您應該不需要它。
<!-- -->
:::

> [！重要] 自訂建置配置 如果您的專案使用自訂建置配置 (除了標準的`Debug` 和`Release`
> 之外的配置)，您必須在`PackageSettings` 使用`baseSettings` 指定它們。外部相依性需要知道您專案的組態，才能正確地建立。例如
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
> 詳情請參閱 [#8345](https://github.com/tuist/tuist/issues/8345)。

`Package.swift`
檔案只是用來宣告外部依賴的介面，沒有其他功能。這就是為什麼您不會在套件中定義任何目標或產品。定義了相依性之後，您就可以執行下列指令來解析並將相依性拉到`Tuist/Dependencies`
目錄中：

```bash
tuist install
# Resolving and fetching dependencies. {#resolving-and-fetching-dependencies}
# Installing Swift Package Manager dependencies. {#installing-swift-package-manager-dependencies}
```

您可能已經注意到了，我們採用了類似 [CocoaPods](https://cocoapods.org)'
的方式，將解決相依性作為自己的指令。這讓使用者可以控制何時需要解析與更新依賴項目，並允許開啟專案中的 Xcode，讓它準備好進行編譯。這是我們認為 Apple
與 Swift Package Manager 整合所提供的開發者體驗會隨著專案成長而降低的地方。

然後，您可以從專案目標使用`TargetDependency.external` 依賴類型來引用這些依賴：

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
**schemes** 不會自動為 Swift Package 專案建立，以保持 scheme 清單乾淨。您可以透過 Xcode 的 UI 建立它們。
<!-- -->
:::

#### Xcode 的預設整合{#xcodes-default-integration}

如果您想使用 Xcode 的預設整合機制，您可以在實體化專案時傳送`套件清單` ：

```swift
let project = Project(name: "MyProject", packages: [
    .remote(url: "https://github.com/krzyzanowskim/CryptoSwift", requirement: .exact("1.8.0"))
])
```

然後從您的目標中參考它們：

```swift
let target = .target(name: "MyTarget", dependencies: [
    .package(product: "CryptoSwift", type: .runtime)
])
```

對於 Swift 巨集和建置工具外掛，您需要分別使用類型`.macro` 和`.plugin` 。

::: warning SPM Build Tool Plugins
<!-- -->
SPM 建立工具外掛必須使用 [Xcode 的預設整合](#xcode-s-default-integration)機制來宣告，即使使用 Tuist 的
[XcodeProj-based integration](#tuist-s-xcodeproj-based-integration) 來宣告您的專案相依性。
<!-- -->
:::

SPM 建立工具外掛的實際應用是在 Xcode 的「執行建立工具外掛」建立階段中執行程式碼校正。在套件清單中的定義如下：

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

若要生成一個不含建立工具外掛的 Xcode 專案，您必須在專案清單的`packages` 陣列中宣告套件，然後在目標的相依性中包含類型為`.plugin`
的套件。

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
或`xcframeworks` ，您可以執行`carthage update` 來輸出`Carthage/Build`
目錄中的相依性，然後在您的目標中使用`.framework` 或`.xcframework`
目錄相依性類型來宣告相依性。您可以將此包裝在一個腳本中，在產生專案前執行。

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

::: warning BUILD AND TEST
<!-- -->
如果您透過`xcodebuild build` 和`tuist test` 來建立和測試專案，您同樣需要在建立或測試前執行`carthage update`
指令，以確保 Carthage 解析的相依性存在。
<!-- -->
:::

### CocoaPods{#cocoapods}

[CocoaPods](https://cocoapods.org) 期望一個 Xcode 專案來整合相依性。您可以使用 Tuist
來產生專案，然後執行`pod install` ，藉由建立包含您的專案與 Pods 相依性的工作區來整合相依性。您可以在產生專案前執行腳本，將此功能包裝起來。

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

::: warning
<!-- -->
CocoaPods 相依性與`build` 或`test` 等工作流程不相容，這些工作流程會在產生專案後立即執行`xcodebuild`
。它們也與二進位快取和選擇性測試不相容，因為指紋邏輯並不考慮 Pods 的相依性。
<!-- -->
:::

## 靜態或動態{#static-or-dynamic}

框架和函式庫可以靜態或動態連結，**，這個選擇對應用程式大小和開機時間等方面有重大影響** 。儘管這個選擇很重要，但在做這個決定時往往沒有多加考慮。

**一般的經驗法則**
是，您希望在釋出版本的建立過程中，儘可能多地使用靜態連結，以達到快速開機的目的；而在除錯版本的建立過程中，儘可能多地使用動態連結，以達到快速迭代的目的。

在專案圖形中改變靜態連結與動態連結的挑戰，在 Xcode
中並非小事，因為改變會對整個圖形產生連鎖效應（例如：程式庫無法包含資源、靜態框架不需要嵌入）。Apple 嘗試以編譯時的解決方案來解決這個問題，例如 Swift
Package Manager 自動決定靜態連結與動態連結，或是 [Mergeable
Libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)。然而，這會在編譯圖形中加入新的動態變數，增加新的非決定性來源，並可能導致一些依賴編譯圖形的
Swift 預覽等功能變得不可靠。

幸運的是，Tuist 從概念上壓縮了在靜態與動態之間轉換的複雜性，並合成了跨連結類型的標準
<LocalizedLink href="/guides/features/projects/synthesized-files#bundle-accessors"> 綑綁存取器</LocalizedLink>。結合
<LocalizedLink href="/guides/features/projects/dynamic-configuration"> 透過環境變數進行的動態配置</LocalizedLink>，您可以在調用時傳遞連結類型，並在您的manifests中使用該值來設定目標的產品類型。

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

請注意，由於成本的關係，Tuist
<LocalizedLink href="/guides/features/projects/cost-of-convenience"> 並不會透過隱含設定來預設方便性</LocalizedLink>。這表示我們需要您設定連結類型，以及有時需要的額外建置設定，例如 [`-ObjC` linker
flag](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184)
，以確保產生的二進位檔正確無誤。因此，我們的立場是提供您資源，通常是以文件的形式，讓您做出正確的決定。

::: tip EXAMPLE: THE COMPOSABLE ARCHITECTURE
<!-- -->
許多專案整合的 Swift 套件是 [The Composable
Architecture](https://github.com/pointfreeco/swift-composable-architecture)。詳情請參閱
[本節](#the-composable-architecture)。
<!-- -->
:::

### 情境{#scenarios}

在某些情況下，將連結完全設定為靜態或動態並不可行，也不是一個好主意。以下是您可能需要混合使用靜態與動態連結的情況的非詳盡清單：

- **具有擴充功能的應用程式：**
  由於應用程式及其擴充套件需要共用程式碼，您可能需要讓這些目標成為動態。否則，您會在應用程式和擴充套件中重複相同的程式碼，導致二進位大小增加。
- **預先編譯的外部相依性：**
  有時您會收到預先編譯好的二進位檔，這些二進位檔可以是靜態的，也可以是動態的。靜態二進位檔可以包裝在動態框架或函式庫中，以動態連結。

在對圖表進行變更時，Tuist 會對其進行分析，並在偵測到 「靜態副作用
」時顯示警告。此警告的目的是幫助您識別靜態連結目標可能產生的問題，這些目標會透過動態目標過渡依賴於靜態目標。這些副作用通常會表現為二進位大小增加，或在最糟糕的情況下，執行時當機。

## 疑難排解{#troubleshooting}

### Objective-C 相依性{#objectivec-dependencies}

如 [Apple Technical Q&A
QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html)
所述，在整合 Objective-C 的相依性時，可能必須在消耗目標上包含某些旗標，以避免執行時當機。

由於建立系統和 Tuist 無法推斷該標誌是否必要，而且該標誌可能會帶來不良的副作用，因此 Tuist 不會自動套用任何這些標誌，而且由於 Swift
套件管理員認為`-ObjC` 是透過`.unsafeFlag` 包含的，因此大多數套件在需要時無法將其納入預設連結設定中。

Objective-C 依賴 (或內部 Objective-C 目標) 的消耗者應該在需要時套用`-ObjC` 或`-force_load`
旗標，方法是在消耗目標上設定`OTHER_LDFLAGS` 。

### Firebase 與其他 Google 程式庫{#firebase-other-google-libraries}

Google 的開放原始碼程式庫雖然功能強大，但卻很難整合到 Tuist 中，因為這些程式庫在建立時通常會使用非標準架構和技術。

以下是整合 Firebase 和 Google 其他 Apple 平台程式庫時可能需要遵循的一些提示：

#### 確保`-ObjC` 已加入`OTHER_LDFLAGS` {#ensure-objc-is-added-to-other_ldflags}

Google 的許多函式庫都是用 Objective-C 寫成的。因此，任何消耗目標都需要在其`OTHER_LDFLAGS` 建立設定中包含`-ObjC`
標籤。這可以在`.xcconfig` 檔案中設定，或是在 Tuist 艙單內的目標設定中手動指定。舉例說明：

```swift
Target.target(
    ...
    settings: .settings(
        base: ["OTHER_LDFLAGS": "$(inherited) -ObjC"]
    )
    ...
)
```

詳情請參閱上述 [Objective-C Dependencies](#objective-c-dependencies) 章節。

#### 將`FBLPromises` 的產品類型設定為動態框架{#set-the-product-type-for-fblpromises-to-dynamic-framework}

某些 Google 函式庫依賴`FBLPromises` ，這是 Google 的另一個函式庫。您可能會遇到提到`FBLPromises`
的當機情況，看起來像這樣：

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

在`Package.swift` 檔案中，明確地將`FBLPromises` 的產品類型設定為`.framework` ，應該可以解決問題：

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

如
[here](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184)
和 [troubleshooting section](#troubleshooting) 所述，在靜態連結套件時，您需要將`OTHER_LDFLAGS`
build 設定為`$(inherited) -ObjC` ，這是 Tuist
的預設連結類型。另外，您也可以覆寫套件的產品類型為動態。以靜態方式連結時，測試和應用程式目標通常可以順利運作，但 SwiftUI
預覽則會損壞。這可以透過動態連結來解決。在下面的範例中，[Sharing](https://github.com/pointfreeco/swift-sharing)
也被加入為相依性，因為它經常與 The Composable Architecture 一起使用，而且有自己的 [configuration
pitfalls](https://github.com/pointfreeco/swift-sharing/issues/150#issuecomment-2797107032)。

以下設定會動態連結所有內容 - 因此應用程式 + 測試目標和 SwiftUI 預覽都能正常運作。

::: tip STATIC OR DYNAMIC
<!-- -->
不一定建議使用動態連結。詳情請參閱 [Static or dynamic](#static-or-dynamic)
一節。在這個範例中，為了簡單起見，所有的相依性都是無條件動態連結。
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
您必須以`import SwiftSharing` 來取代`import Sharing` 。
<!-- -->
:::

### Transitive static dependencies leaking through`.swiftmodule` {#transitive-static-dependencies-leaking-through-swiftmodule}

當動態框架或函式庫透過`import StaticSwiftModule`
依賴於靜態框架或函式庫時，這些符號會被包含在動態框架或函式庫的`.swiftmodule` 中，可能會
<LocalizedLink href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1">導致編譯失敗</LocalizedLink>。為了避免這種情況，您必須使用
<LocalizedLink href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`internal import`</LocalizedLink> 來匯入靜態相依性：

```swift
internal import StaticModule
```

::: info
<!-- -->
Swift 6 中加入了導入的存取層級。如果您使用的是較舊版本的 Swift，您需要使用
<LocalizedLink href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_implementationOnly`</LocalizedLink>
來取代：
<!-- -->
:::

```swift
@_implementationOnly import StaticModule
```
