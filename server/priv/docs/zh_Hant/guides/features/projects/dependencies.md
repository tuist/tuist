---
{
  "title": "相依性",
  "titleTemplate": ":title · 專案 · 功能 · 指南 · Tuist",
  "description": "了解如何在 Tuist 專案中宣告相依性。"
}
---
# 相依性 {#dependencies}

隨著專案規模擴大，通常會將其拆分為多個目標以共用程式碼、界定邊界並改善建置時間。多個目標意味著定義它們之間的相依關係，形成**相依圖**，其中也可能包含外部相依性。

## XcodeProj 編碼的圖表 {#xcodeprojcodified-graphs}

由於 Xcode 與 XcodeProj 的設計，維護相依圖可能是一項繁瑣且容易出錯的工作。以下是一些你可能遇到的問題範例：

- 因為 Xcode 的建置系統會將專案的所有產出物輸出到衍生資料中的同一個目錄，目標可能會匯入不該匯入的產出物。在 CI 環境中（乾淨建置較為常見），或稍後使用不同組態時，編譯可能會失敗。
- 目標的傳遞動態相依性需要複製到屬於 `LD_RUNPATH_SEARCH_PATHS` 建置設定的任何目錄中。如果沒有這麼做，目標在執行階段將無法找到它們。當圖表規模較小時，這很容易思考與設定，但隨著圖表增長，就會成為問題。
- 當目標連結靜態 [XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle) 時，目標需要額外的建置階段，讓 Xcode 處理套件並擷取適合目前平台與架構的二進位檔。此建置階段不會自動加入，很容易忘記新增。

以上只是幾個範例，我們多年來還遇到過更多問題。想像一下，如果你需要一支工程師團隊來維護相依圖並確保其有效性。或者更糟的是，這些複雜細節由一個你無法控制或自訂的閉源建置系統在建置時期解決。聽起來很熟悉嗎？這就是 Apple 在 Xcode 與 XcodeProj 中採取的方法，而 Swift Package Manager 也繼承了這種做法。

我們堅信相依圖應該是**明確**且**靜態**的，因為只有這樣才能對其進行**驗證**與**最佳化**。使用 Tuist 時，你只需專注於描述誰相依於誰，其餘部分由我們處理。複雜性與實作細節都對你抽象化。

在以下章節中，你將學習如何在專案中宣告相依性。

> [!TIP]
> **圖表驗證**
>
> Tuist 會在產生專案時驗證圖表，以確保沒有循環且所有相依性皆有效。得益於此，任何團隊都能參與演進相依圖，而不必擔心破壞它。


## 本機相依性 {#local-dependencies}

目標可以相依於相同或不同專案中的其他目標，以及二進位檔。在實體化 `Target` 時，你可以透過 `dependencies` 參數傳入下列任一選項：

- `Target`：宣告與同一專案內目標的相依性。
- `Project`：宣告與不同專案中目標的相依性。
- `Framework`：宣告與二進位框架的相依性。
- `Library`：宣告與二進位函式庫的相依性。
- `XCFramework`：宣告與二進位 XCFramework 的相依性。
- `SDK`：宣告與系統 SDK 的相依性。
- `XCTest`：宣告與 XCTest 的相依性。
- `Macro`：宣告與同一專案中定義的 Swift macro 目標的相依性（請參閱 [Swift Macros](#swift-macros)）。

> [!NOTE]
> **相依條件**
>
> 每種相依類型都接受 `condition` 選項，以便根據平台條件式連結相依性。預設情況下，它會為目標支援的所有平台連結相依性。


## 外部相依性 {#external-dependencies}

Tuist 也允許你在專案中宣告外部相依性。

### Swift Packages {#swift-packages}

Swift Packages 是我們建議在專案中宣告相依性的方式。Tuist 使用 Swift Package Manager 來解析它們；若要了解使用本機套件進行模組化與 Tuist 專案的比較，請參閱 [Swift Package Manager vs Tuist](https://tuist.dev/compare/swift-package-manager)。你可以使用 Xcode 的預設整合機制，或使用 Tuist 基於 XcodeProj 的整合來整合它們。

#### Tuist 基於 XcodeProj 的整合 {#tuists-xcodeprojbased-integration}

Xcode 的預設整合雖然最為方便，但缺乏中型與大型專案所需的彈性與控制力。為了克服這個問題，Tuist 提供基於 XcodeProj 的整合，讓你能够使用 XcodeProj 的目標在專案中整合 Swift Packages。得益於此，我們不僅能讓你對整合擁有更多控制權，還能使其與<.localized_link href="/guides/features/cache">快取</.localized_link>和<.localized_link href="/guides/features/selective-testing">選擇性測試執行</.localized_link>等工作流程相容。

XcodeProj 的整合較可能需要更多時間來支援新的 Swift Package 功能或處理更多套件組態。然而，Swift Packages 與 XcodeProj 目標之間的對應邏輯是開源的，社群可以貢獻改進。這與 Xcode 的預設整合相反，後者是閉源且由 Apple 維護。

若要新增外部相依性，你必須在 `Tuist/` 底下或專案根目錄建立 `Package.swift`。

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

> [!TIP]
> **套件設定**
>
> 包裹在編譯器指令中的 `PackageSettings` 實體可讓你設定套件的整合方式。例如，在上述範例中，它用於覆寫套件預設使用的產品類型。預設情況下，你應該不需要它。你也可以透過 `expectedSignatures` 使用它來設定 SwiftPM 二進位目標的预期簽章。


### 二進位目標簽章

如果本機或遠端 Swift 套件公開二進位 XCFramework 目標，你可以使用 `PackageSettings.expectedSignatures` 設定其預期簽章：

```swift
#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        expectedSignatures: [
            "SelfSignedXCFramework": .selfSigned(
                fingerprint: "EF61C3C0339FC84805357AFEC2E0BB0E6A0D5EE64165B333F934BF9E282785BC"
            ),
        ]
    )
#endif
```

> [!IMPORTANT] CUSTOM BUILD CONFIGURATIONS
> 如果你的專案使用自訂建置組態（標準 `Debug` 與 `Release` 以外的組態），你必須在 `PackageSettings` 中使用 `baseSettings` 指定它們。外部相依性需要知道你的專案組態才能正確建置。例如：
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
> 如需更多詳細資訊，請參閱 [#8345](https://github.com/tuist/tuist/issues/8345)。

`Package.swift` 檔案僅是用來宣告外部相依性的介面，別無其他。這就是為什麼你不在套件中定義任何目標或產品。一旦定義好相依性，你就可以執行下列命令來解析並將相依性拉取到 `Tuist/Dependencies` 目錄中：

```bash
tuist install
# Resolving and fetching dependencies.
# Installing Swift Package Manager dependencies.
```

如你所見，我們採用與 [CocoaPods](https://cocoapods.org) 類似的方式，將相依性解析作為獨立命令執行。這讓使用者能自行決定何時解析與更新相依性，並允許在 Xcode 中開啟專案且準備好進行編譯。我們認為，隨著專案規模擴大，Apple 與 Swift Package Manager 整合所提供的開發者體驗會逐漸下降，這正是其中一個領域。

接著，你可以從專案目標中使用 `TargetDependency.external` 相依性類型來參考這些相依性：

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
                .external(name: "Alamofire"),
            ]
        ),
    ]
)
```
<!-- -->
:::

> [!NOTE]
> **不會為外部套件產生 Scheme**
>
> 為了保持 Scheme 清單整潔，Swift Package 專案不會自動建立 **schemes**。你可以透過 Xcode 的介面來建立它們。


#### Xcode 的預設整合 {#xcodes-default-integration}

如果你想使用 Xcode 的預設整合機制，可以在實例化專案時傳入 `packages` 清單：

```swift
let project = Project(name: "MyProject", packages: [
    .package(url: "https://github.com/krzyzanowskim/CryptoSwift", .exact("1.8.0"))
])
```

然後從你的目標中參考它們：

```swift
let target: Target = .target(name: "MyTarget", destinations: .iOS, product: .framework, bundleId: "dev.tuist.MyTarget", dependencies: [
    .package(product: "CryptoSwift", type: .runtime)
])
```

當透過 Xcode 的預設整合從外部 Swift Package 整合 Swift Macro 或 Build Tool Plugin 時，請分別使用類型 `.macro` 和 `.plugin` 進行宣告。Macro 也可以透過 [Tuist 基於 XcodeProj 的整合](#tuists-xcodeprojbased-integration) 來使用；如果你想定義自己的 Swift Macro 而不是使用套件中的 Macro，請參閱 [Swift Macros](#swift-macros)。

> [!WARNING]
> **SPM 建置工具外掛程式**
>
> 即使你的專案相依性使用 Tuist 的 [XcodeProj 基礎整合](#tuists-xcodeprojbased-integration)，SPM 建置工具外掛程式仍必須使用 [Xcode 的預設整合](#xcodes-default-integration) 機制來宣告。

SPM 建置工具外掛程式是 Swift 程式，由 Xcode 和 SwiftPM 執行，用以發現目標應執行的具體建置命令。這些命令可能取決於套件圖、目標檔案、外掛程式工作目錄、已解析的外掛程式工具，以及外掛程式宣告的輸出。有些外掛程式也會產生必須成為同一目標建置一部分的檔案。

Tuist 基於 XcodeProj 的整合會在對應為靜態時（例如函式庫、二進位檔、可執行檔和 macro），將套件產品對應到原生 Xcode 目標。建置工具外掛程式在 Xcode 的 SwiftPM 整合之外，沒有等效的原生 Xcode 專案基元。雖然外掛程式最終可以執行可執行檔，但從常規指令碼建置階段呼叫該可執行檔並不等於執行外掛程式：Tuist 需要先評估外掛程式的 Swift 程式碼、重現 SwiftPM 的外掛程式內容、發現命令、模擬宣告的輸入和輸出，並在 Xcode 規劃建置前將任何產生的檔案加入目標圖。

因此，不支援僅在 `Tuist/Package.swift` 中宣告外掛程式套件並透過 `.external(name:)` 使用它。支援的替代方案是在 `Project.packages` 中宣告套件，並使用 `.package(product:type: .plugin)` 將外掛程式產品加入到消費目標中。這會讓外掛程式以 Swift Package 產品相依性的形式依附於產生的 Xcode 專案，以便 Xcode 和 SwiftPM 能以原生外掛程式內容執行它。

權衡取捨在於 Xcode 擁有該外掛程式整合：

- Xcode 透過其 SwiftPM 整合來解析並建置外掛程式套件。
- 該套件在產生的專案中以 Swift Package 參考的形式出現，而非 Tuist 產生的外部目標。
- Tuist 無法提供與靜態對應套件產品相同等級的控制、驗證、快取和選擇性測試行為。
- CI 和本機建置必須允許針對那些外掛程式套件進行 Xcode 的套件解析。

由於這些影響，我們通常不建議在 Tuist 專案中使用 SPM 建置工具外掛程式。盡可能優先使用在目標中宣告的建置階段指令碼，或在呼叫 Tuist 或 Xcode 之前，從產生的 Xcode 專案之外的指令碼執行該工具。

SPM 建置工具外掛程式的一個實際應用是在 Xcode 的「Run Build Tool Plug-ins」建置階段執行程式碼 linting。若要產生保留建置工具外掛程式的 Xcode 專案，請在專案資訊清單的 `packages` 陣列中宣告套件，然後在目標的相依性中包含類型為 `.plugin` 的套件。

```swift
import ProjectDescription

let project = Project(
    name: "Framework",
    packages: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.56.1"),
    ],
    targets: [
        .target(
            name: "Framework",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.Framework",
            dependencies: [
                .package(product: "SwiftLintBuildToolPlugin", type: .plugin),
            ]
        ),
    ]
)
```

### Carthage {#carthage}

由於 [Carthage](https://github.com/carthage/carthage) 會輸出 `frameworks` 或 `xcframeworks`，你可以執行 `carthage update` 將相依性輸出到 `Carthage/Build` 目錄，然後使用 `.framework` 或 `.xcframework` 目標相依性類型在目標中宣告該相依性。你可以將此包裝在指令碼中，在產生專案之前執行。

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

> [!WARNING]
> **建置與測試**
>
> 如果你透過 `xcodebuild build` 和 `tuist test` 來建置和測試專案，同樣需要確保 Carthage 解析的相依性存在，方法是在建置或測試之前執行 `carthage update` 命令。


### CocoaPods {#cocoapods}

[CocoaPods](https://cocoapods.org) 預期 Xcode 專案會整合相依性。你可以使用 Tuist 產生專案，然後執行 `pod install` 來整合相依性，這會建立一個包含你的專案和 Pods 相依性的工作區。你可以將此包裝在指令碼中，在產生專案之前執行。

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

> [!WARNING]
> CocoaPods 相依性不相容於在產生專案後立即執行 `xcodebuild` 的工作流程，例如 `build` 或 `test`。它們也不相容於二進位快取和選擇性測試，因為指紋邏輯未考量 Pods 相依性。


## Swift Macros {#swift-macros}

在 Tuist 專案中使用 [Swift Macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/) 時有兩種截然不同的情境，明確指出你處於哪一種情境是值得的：

- **使用外部 Swift Package 中定義的 macro。** 兩種整合機制都支援 macro。使用 [Tuist 基於 XcodeProj 的整合](#tuists-xcodeprojbased-integration) 時，你在 `Tuist/Package.swift` 中宣告套件並使用 `.external(name:)` 依賴它——Tuist 會將 macro 產品對應到原生目標。使用 [Xcode 的預設整合](#xcodes-default-integration) 時，你使用 `.package(product:type: .macro)` 宣告相依性。與建置工具外掛程式不同，macro 不限於 Xcode 的預設整合。
- **定義你自己的 macro** 作為專案的一部分——例如在 monorepo 中的共用程式庫。你不需要為此使用 `Package.swift`：Tuist 提供一流的 `.macro` 產品類型，因此你可以直接在資訊清單中宣告 macro 目標。

### 定義你自己的 macro {#defining-your-own-macro}

Swift macro 是一種編譯器外掛程式：一個由 Swift 編譯器在編譯時期載入並執行的可執行檔。Tuist 透過 `.macro` 產品類型原生地建模此行為。雖然 Apple 未在 Xcode 專案中公開 Swift Macro 目標類型，但 Tuist 透過產生命令列工具目標、將其連接為使用 macro 之目標的相依性，以及將 `-load-plugin-executable` 旗標注入其 Swift 編譯器設定來啟用此功能。所有這些底層細節都由 Tuist 為你處理。

典型的 macro 分為兩個目標：實作 macro 的 **外掛程式** 目標（`product: .macro`），以及宣告 macro 公開介面（`@attached`/`@freestanding` 宣告）並透過 `.macro(name:)` 依賴外掛程式的 **程式庫** 目標。由於外掛程式在建置機器上執行，其目標僅限主機（macOS）。

Macro 實作依賴於 [swift-syntax](https://github.com/swiftlang/swift-syntax)，你可以在 `Tuist/Package.swift` 中將其宣告為一般的外部相依性：

```swift [Tuist/Package.swift]
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "600.0.0"),
    ]
)
```

接著你可以直接在專案中定義 macro 外掛程式和程式庫目標：

```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyLibrary",
    targets: [
        // The compiler plugin that implements the macro. macOS-only, since it
        // runs on the build machine at compile time.
        .target(
            name: "MyMacrosImplementation",
            destinations: [.mac],
            product: .macro,
            bundleId: "dev.tuist.MyMacrosImplementation",
            sources: ["Sources/MyMacrosImplementation/**"],
            dependencies: [
                .external(name: "SwiftSyntax"),
                .external(name: "SwiftSyntaxMacros"),
                .external(name: "SwiftCompilerPlugin"),
            ]
        ),
        // The library that exposes the macro declarations to consumers and
        // depends on the plugin via `.macro(name:)`.
        .target(
            name: "MyLibrary",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.MyLibrary",
            sources: ["Sources/MyLibrary/**"],
            dependencies: [
                .macro(name: "MyMacrosImplementation"),
            ]
        ),
    ]
)
```

任何連結 `MyLibrary` 的目標現在都可以使用該 macro——Tuist 會傳播外掛程式，讓編譯器能夠載入它。


## 靜態或動態 {#static-or-dynamic}

框架和程式庫可以靜態或動態連結，**這個選擇對應用程式大小和啟動時間等方面有重大影響**。儘管其重要性，這個決定往往未經深思熟慮就做出。

**一般的經驗法則**是，在 release 建置中盡可能多地進行靜態連結以實現快速啟動時間，而在 debug 建置中盡可能多地進行動態連結以實現快速迭代時間。

在專案圖中切換靜態和動態連結的挑戰在於，這在 Xcode 中並非易事，因為變更會對整個圖產生連鎖效應（例如，程式庫不能包含資源，靜態框架不需要嵌入）。Apple 嘗試透過編譯時期解決方案來解決這個問題，例如 Swift Package Manager 在靜態和動態連結之間的自動決策，或 [Mergeable Libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)。然而，這會為編譯圖添加新的動態變數，增加非確定性的來源，並可能導致某些依賴編譯圖的功能（如 Swift Previews）變得不穩定。

幸運的是，Tuist 在概念上壓縮了與靜態和動態之間切換相關的複雜性，並合成跨連結類型標準化的 <.localized_link href="/guides/features/projects/synthesized-files#bundle-accessors">bundle 存取器</.localized_link>。結合 <.localized_link href="/guides/features/projects/dynamic-configuration">透過環境變數的動態設定</.localized_link>，你可以在叫用時傳遞連結類型，並在資訊清單中使用該值來設定目標的產品類型。

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

請注意，Tuist <.localized_link href="/guides/features/projects/cost-of-convenience">不會因為隱式設定的成本而預設採用便利性</.localized_link>。這意味著我們依賴你設定連結類型以及有時需要的任何其他建置設定，例如 [`-ObjC` 連結器旗標](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184)，以確保產生的二進位檔正確無誤。因此，我們的立場是提供資源（通常以文件形式）讓你做出正確的決定。

> [!TIP]
> **範例：The Composable Architecture**
>
> 許多專案整合的一個 Swift Package 是 [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture)。請參閱 [本節](#the-composable-architecture) 以了解更多詳細資訊。


### 情境 {#scenarios}

在某些情境下，將連結完全設定為靜態或動態並不可行或不是好主意。以下是不完全的情境列表，你可能需要在其中混合靜態和動態連結：

- **帶有擴充功能的應用程式：** 由於應用程式及其擴充功能需要共用程式碼，你可能需要將這些目標設為動態。否則，你最終會在應用程式和擴充功能中重複相同的程式碼，導致二進位檔大小增加。
- **預編譯的外部相依性：** 有時你會獲得預編譯的二進位檔，它們可能是靜態或動態的。靜態二進位檔可以包裝在動態框架或程式庫中以進行動態連結。

當對圖進行變更時，Tuist 會分析它，如果偵測到「靜態副作用」，則會顯示警告。此警告旨在幫助你識別因靜態連結一個透過動態目標間接依賴靜態目標的目標而可能產生的問題。這些副作用通常表現為二進位檔大小增加，或在最壞的情況下導致執行時期崩潰。

## 疑難排解 {#troubleshooting}

### Objective-C 相依性 {#objectivec-dependencies}

在整合 Objective-C 相依性時，可能需要在消費目標中包含某些旗標以避免執行時期崩潰，詳情請參閱 [Apple Technical Q&A QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html)。

由於建置系統和 Tuist 無法推斷是否需要該旗標，且該旗標可能帶來不良副作用，Tuist 不會自動套用任何這些旗標。此外，由於 Swift Package Manager 認為 `-ObjC` 是透過 `.unsafeFlag` 包含的，因此大多數套件在需要時無法將其包含在預設連結設定中。

Objective-C 相依性的消費者（或內部 Objective-C 目標）應在需要時透過在消費目標上設定 `OTHER_LDFLAGS` 來套用 `-ObjC` 或 `-force_load` 旗標。

### Firebase 和其他 Google 程式庫 {#firebase-other-google-libraries}

Google 的開源程式庫雖然功能強大，但在 Tuist 中整合可能很困難，因為它們在建置方式上經常使用非標準的架構和技術。

以下是一些整合 Firebase 和 Google 其他 Apple 平台程式庫時可能需要遵循的提示：

#### 確保將 `-ObjC` 添加到 `OTHER_LDFLAGS` {#ensure-objc-is-added-to-other_ldflags}

Google 的許多程式庫都是使用 Objective-C 撰寫的。因此，任何消費目標都需要在其 `OTHER_LDFLAGS` 建置設定中包含 `-ObjC` 旗標。這可以在 `.xcconfig` 檔案中設定，或在 Tuist 清單的目標設定中手動指定。範例如下：

```swift
Target.target(
    ...
    settings: .settings(
        base: ["OTHER_LDFLAGS": "$(inherited) -ObjC"]
    )
    ...
)
```

如需更多詳細資訊，請參閱上方的 [Objective-C 相依性](#objectivec-dependencies) 章節。

#### 將 `FBLPromises` 的產品類型設為動態框架 {#set-the-product-type-for-fblpromises-to-dynamic-framework}

某些 Google 程式庫依賴於 `FBLPromises`，這是 Google 的另一個程式庫。你可能會遇到提及 `FBLPromises` 的崩潰，看起來像這樣：

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

在 `Package.swift` 檔案中明確將 `FBLPromises` 的產品類型設為 `.framework` 應該可以解決此問題：

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

### The Composable Architecture {#the-composable-architecture}

如 [這裡](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184) 和 [疑難排解章節](#troubleshooting) 所述，當靜態連結套件時（這是 Tuist 的預設連結類型），你需要將 `OTHER_LDFLAGS` 建置設定設為 `$(inherited) -ObjC`。或者，你可以覆寫套件的產品類型為動態。靜態連結時，測試和應用程式目標通常運作正常，但 SwiftUI 預覽會損壞。這可以透過將所有内容動態連結來解決。在下面的範例中，[Sharing](https://github.com/pointfreeco/swift-sharing) 也被添加為相依性，因為它經常與 The Composable Architecture 一起使用，並且有其自身的 [設定陷阱](https://github.com/pointfreeco/swift-sharing/issues/150#issuecomment-2797107032)。

following 設定將所有內容動態連結 - 因此應用程式 + 測試目標和 SwiftUI 預覽都能正常運作。

> [!TIP]
> **靜態或動態**
>
> 動態連結並不總是推薦的。請參閱 [靜態或動態](#static-or-dynamic) 章節以了解更多詳細資訊。在此範例中，為了簡單起見，所有相依性都無條件地進行動態連結。


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

> [!WARNING]
> 你必須改為使用 `import SwiftSharing`，而不是 `import Sharing`。


### 傳遞靜態相依性透過 `.swiftmodule` 洩漏 {#transitive-static-dependencies-leaking-through-swiftmodule}

當動態框架或程式庫透過 `import StaticSwiftModule` 依賴靜態框架或程式庫時，符號會被包含在動態框架或程式庫的 `.swiftmodule` 中，可能 <.localized_link href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1">導致編譯失敗</.localized_link>。為了防止這種情況，你必須使用 <.localized_link href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`internal import`</.localized_link> 匯入靜態相依性：

```swift
internal import StaticModule
```

> [!NOTE]
> Swift 6 包含了匯入的存取層級。如果你使用的是較舊版本的 Swift，則需要改用 <.localized_link href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_implementationOnly`</.localized_link>：


```swift
@_implementationOnly import StaticModule
```

## 相關 {#related}

閱讀 [monday.com 如何採用 Tuist 的模組化專案圖](https://tuist.dev/customers/monday)，從相依性最少的目標開始。
