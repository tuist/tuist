---
{
  "title": "相依性",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "了解如何在 Tuist 專案中宣告相依性。"
}
---
# 依賴關係 {#dependencies}

當專案規模增長時，通常會將其拆分為多個 target，以共用程式碼、界定邊界並改善建置時間。多個 target 意味著需要定義它們之間的依賴關係，從而形成一個 **依賴圖**，其中也可能包含外部依賴。

## XcodeProj 編碼的圖 {#xcodeprojcodified-graphs}

由於 Xcode 和 XcodeProj 的設計，維護依賴圖可能是一項繁瑣且容易出錯的工作。以下是一些你可能遇到的問題範例：

- 因為 Xcode 的建置系統會將專案的所有產出物輸出到 derived data 中的同一個目錄，target 可能會匯入不應該匯入的產出物。在 CI 上（乾淨建置更為常見）或稍後使用不同設定時，編譯可能會失敗。
- Target 的傳遞性動態依賴需要複製到屬於 `LD_RUNPATH_SEARCH_PATHS` 建置設定的任何目錄中。如果沒有這樣做，target 在執行時就無法找到它們。當圖較小時，這很容易考慮和設定，但隨著圖變大，這就會成為問題。
- 當 target 連結靜態 [XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle) 時，target 需要額外的建置階段，讓 Xcode 處理 bundle 並提取適合目前平台和架構的正確二進位檔。這個建置階段不會自動新增，因此很容易忘記新增。

以上只是一些範例，多年來我們還遇到過更多問題。想像一下，如果你需要一支工程師團隊來維護依賴圖並確保其有效性。或者更糟的是，這些複雜性由一個你無法控制或自訂的閉源建置系統在建置時解決。聽起來很熟悉？這就是 Apple 對 Xcode 和 XcodeProj 採取的方法，而 Swift Package Manager 也繼承了這種方式。

我們堅信依賴圖應該是 **明確** 且 **靜態** 的，因為只有這樣才能對其進行 **驗證** 和 **最佳化**。使用 Tuist，你只需專注於描述什麼依賴什麼，其餘的交給我們處理。複雜性和實作細節都對你抽象化了。

在以下章節中，你將學習如何在專案中宣告依賴關係。

> [!TIP]
> **圖驗證**
>
> Tuist 會在產生專案時驗證圖，以確保沒有循環且所有依賴關係都有效。得益於此，任何團隊都可以參與演化依賴圖，而不必擔心破壞它。


## 本機依賴 {#local-dependencies}

Target 可以依賴同一專案或不同專案中的其他 target，以及二進位檔。當實體化 `Target` 時，你可以傳入 `dependencies` 參數，並選擇以下任一選項：

- `Target`：宣告與同一專案內 target 的依賴關係。
- `Project`：宣告與不同專案中 target 的依賴關係。
- `Framework`：宣告與二進位 framework 的依賴關係。
- `Library`：宣告與二進位 library 的依賴關係。
- `XCFramework`：宣告與二進位 XCFramework 的依賴關係。
- `SDK`：宣告與系統 SDK 的依賴關係。
- `XCTest`：宣告與 XCTest 的依賴關係。
- `Macro`：宣告與在同一專案中定義的 Swift macro target 的依賴關係（請參閱 [Swift Macros](#swift-macros)）。

> [!NOTE]
> **依賴條件**
>
> 每種依賴類型都接受 `condition` 選項，以便根據平台條件式地連結依賴。預設情況下，它會為 target 支援的所有平台連結依賴。


## 外部依賴 {#external-dependencies}

Tuist 也允許你在專案中宣告外部依賴。

### Swift Packages {#swift-packages}

Swift Packages 是我們推薦在專案中宣告依賴的方式。你可以使用 Xcode 的預設整合機制，或使用 Tuist 基於 XcodeProj 的整合來整合它們。

#### Tuist 基於 XcodeProj 的整合 {#tuists-xcodeprojbased-integration}

Xcode 的預設整合雖然最方便，但缺乏中型和大型專案所需的靈活性和控制權。為了克服這一點，Tuist 提供了基於 XcodeProj 的整合，讓你能够使用 XcodeProj 的 target 在專案中整合 Swift Packages。得益於此，我們不僅能讓你對整合有更多控制權，還能使其與 <.localized_link href="/guides/features/cache">快取</.localized_link> 和 <.localized_link href="/guides/features/selective-testing">選擇性測試執行</.localized_link> 等工作流程相容。

XcodeProj 的整合可能需要更多時間來支援新的 Swift Package 功能或處理更多 package 設定。然而，Swift Packages 和 XcodeProj target 之間的對應邏輯是開源的，可以由社群貢獻。這與 Xcode 的預設整合相反，後者是閉源的并由 Apple 維護。

要新增外部依賴，你必須在 `Tuist/` 下方或專案根目錄建立 `Package.swift`。

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
> **Package 設定**
>
> 包裝在編譯器指令中的 `PackageSettings` 實體允許你設定如何整合 packages。例如，在上述範例中，它用於覆寫 packages 使用的預設產品類型。預設情況下，你不需要使用它。你也可以透過 `expectedSignatures` 使用它來設定 SwiftPM 二進位 target 的預期簽章。


### 二進位 Target 簽章

如果本機或遠端 Swift package 公開二進位 XCFramework target，你可以使用 `PackageSettings.expectedSignatures` 設定其預期簽章：

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
> 如果你的專案使用自訂建置設定（標準 `Debug` 和 `Release` 以外的設定），你必須在 `PackageSettings` 中使用 `baseSettings` 指定它們。外部依賴需要了解你專案的設定才能正確建置。例如：
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
> 請參閱 [#8345](https://github.com/tuist/tuist/issues/8345) 以取得更多詳細資訊。

`Package.swift` 檔案只是宣告外部依賴的介面，僅此而已。這就是為什麼你不在 package 中定義任何 target 或產品。一旦定義了依賴，你可以執行以下命令來解析並將依賴拉取到 `Tuist/Dependencies` 目錄：

```bash
tuist install
# Resolving and fetching dependencies. {#resolving-and-fetching-dependencies}
# Installing Swift Package Manager dependencies. {#installing-swift-package-manager-dependencies}
```

你可能已經注意到，我們採取了與 [CocoaPods](https://cocoapods.org) 類似的方法，其中依賴解析是一個獨立的命令。這讓用戶可以控制何時解析和更新依賴，並允許在專案中打開 Xcode 並準備好編譯。我們認為，隨著專案規模增長，Apple 與 Swift Package Manager 整合所提供的開發者體驗會逐漸下降。

你可以從專案 target 中使用 `TargetDependency.external` 依賴類型來引用這些依賴：

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

> [!NOTE]
> **不會為外部 Packages 產生 Scheme**
>
> 為了保持 scheme 列表整潔，Swift Package 專案不會自動建立 **schemes**。你可以透過 Xcode 的 UI 建立它們。


#### Xcode 的預設整合 {#xcodes-default-integration}

如果你想使用 Xcode 的預設整合機制，你可以在實例化專案時傳遞 `packages` 列表：

```swift
let project = Project(name: "MyProject", packages: [
    .remote(url: "https://github.com/krzyzanowskim/CryptoSwift", requirement: .exact("1.8.0"))
])
```

然後從你的 target 中引用它們：

```swift
let target = .target(name: "MyTarget", dependencies: [
    .package(product: "CryptoSwift", type: .runtime)
])
```

當透過 Xcode 的預設整合從外部 Swift Package 整合 Swift Macro 或 Build Tool Plugin 時，請分別使用 `.macro` 和 `.plugin` 類型宣告。Macro 也可以透過 [Tuist 基於 XcodeProj 的整合](#tuists-xcodeprojbased-integration) 使用，如果你想定義自己的 Swift macro 而不是從 package 中使用一個，請參閱 [Swift Macros](#swift-macros)。

> [!WARNING]
> **SPM Build Tool Plugins**
>
> 即使對你的專案依賴使用 Tuist 的 [XcodeProj-based integration](#tuists-xcodeprojbased-integration)，也必須使用 [Xcode 的預設整合](#xcodes-default-integration) 機制來宣告 SPM build tool plugins。

SPM build tool plugins 是 Xcode 和 SwiftPM 執行的 Swift 程式，用於發現應該為 target 運行的具體建置命令。這些命令可能取決於 package 圖、target 檔案、plugin 工作目錄、已解析的 plugin 工具以及 plugin 宣告的輸出。有些 plugin 還會產生必須成為同一 target 建置一部分的檔案。

Tuist 基於 XcodeProj 的整合在映射是靜態時（例如 libraries、binaries、executables 和 macros），會將 package 產品映射到原生 Xcode targets。Build tool plugins 在 Xcode 的 SwiftPM 整合之外沒有等效的原生 Xcode 專案基元。雖然 plugin 最終可以運行可執行檔，但從常規腳本建置階段調用該可執行檔不等於運行 plugin：Tuist 首先需要評估 plugin 的 Swift 代碼，重現 SwiftPM 的 plugin 上下文，發現命令，建模宣告的輸入和輸出，並在 Xcode 規劃建置之前將任何產生的檔案添加到 target 圖中。

因此，不支援僅在 `Tuist/Package.swift` 中宣告 plugin package 並透過 `.external(name:)` 使用它。支援的替代方案是在 `Project.packages` 中宣告 package，並使用 `.package(product:type: .plugin)` 將 plugin 產品添加到消費 target。這使得 plugin 作為 Swift Package 產品依賴附加到產生的 Xcode 專案，以便 Xcode 和 SwiftPM 可以使用原生 plugin 上下文運行它。

權衡取捨是 Xcode 擁有該 plugin 整合：

- Xcode 透過其 SwiftPM 整合解析並建置 plugin package。
- 該 package 在產生的專案中顯示為 Swift Package 引用，而不是 Tuist 產生的外部 target。
- Tuist 無法為 plugin 提供與靜態映射的 package 產品相同級別的控制、驗證、快取和選擇性測試行為。
- CI 和本地建置必須允許那些 plugin packages 的 Xcode package 解析。

由於這些影響，我們通常不建議在 Tuist 專案中使用 SPM build tool plugins。如果可能，優先使用在 target 中宣告的建置階段腳本，或在調用 Tuist 或 Xcode 之前從產生的 Xcode 專案之外的腳本運行工具。

SPM build tool plugin 的一個實際應用是在 Xcode 的「Run Build Tool Plug-ins」建置階段執行代碼 linting。要產生包含 build tool plugin 的 Xcode 專案，請在專案 manifest 的 `packages` 陣列中宣告 package，然後在 target 的依賴中包含類型為 `.plugin` 的 package。

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

### Carthage {#carthage}

由於 [Carthage](https://github.com/carthage/carthage) 輸出 `frameworks` 或 `xcframeworks`，你可以運行 `carthage update` 將依賴輸出到 `Carthage/Build` 目錄，然後使用 `.framework` 或 `.xcframework` target 依賴類型在你的 target 中宣告依賴。你可以將其包裝在一個腳本中，在產生專案之前運行。

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

> [!WARNING]
> **建置和測試**
>
> 如果你透過 `xcodebuild build` 和 `tuist test` 建置和測試你的專案，你同樣需要確保 Carthage 解析的依賴存在，方法是在建置或測試之前運行 `carthage update` 命令。


### CocoaPods {#cocoapods}

[CocoaPods](https://cocoapods.org) 期望 Xcode 專案整合依賴。你可以使用 Tuist 產生專案，然後運行 `pod install` 透過建立包含你的專案和 Pods 依賴的工作區來整合依賴。你可以將其包裝在一個腳本中，在產生專案之前運行。

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

> [!WARNING]
> CocoaPods 依賴與像 `build` 或 `test` 這樣在產生專案後立即運行 `xcodebuild` 的工作流程不相容。它們也與二進位快取和選擇性測試不相容，因為指紋邏輯沒有考慮 Pods 依賴。


## Swift Macros {#swift-macros}

在 Tuist 專案中使用 [Swift Macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/) 時有兩種不同的情境，明確說明你處於哪一種情境是值得的：

- **使用在外部 Swift Package 中定義的 macro。** 兩種整合機制都支援 macros。使用 [Tuist 基於 XcodeProj 的整合](#tuists-xcodeprojbased-integration) 時，你在 `Tuist/Package.swift` 中宣告 package 並使用 `.external(name:)` 依賴它 — Tuist 將 macro 產品映射到原生 target。使用 [Xcode 的預設整合](#xcodes-default-integration) 時，你使用 `.package(product:type: .macro)` 宣告依賴。與 build tool plugins 不同，macros 不限於 Xcode 的預設整合。
- **定義你自己的 macro** 作為專案的一部分 — 例如在 monorepo 中的共享函式庫。你不需要為此使用 `Package.swift`：Tuist 擁有一流的 `.macro` 產品類型，因此你可以直接在 manifests 中宣告 macro target。

### 定義你自己的 macro {#defining-your-own-macro}

Swift macro 是一個編譯器插件：一個 Swift 編譯器在編譯時載入並執行的可執行檔。Tuist 原生地使用 `.macro` 產品類型來建模這一點。雖然 Apple 沒有在 Xcode 專案中公開 Swift Macro target 類型，但 Tuist 透過產生命令列工具 target、將其連接為使用 macro 的 target 的依賴，並將 `-load-plugin-executable` 標誌注入其 Swift 編譯器設定來啟用此功能。所有這些底層工作都由 Tuist 為你處理。

典型的 macro 分為兩個 target：實現 macro 的 **plugin** target（`product: .macro`），以及宣告 macro 公共介面（`@attached`/`@freestanding` 宣告）並透過 `.macro(name:)` 依賴 plugin 的 **library** target。由於 plugin 在建置機器上運行，其 target 僅限主機（macOS）。

macro 實現依賴於 [swift-syntax](https://github.com/swiftlang/swift-syntax)，你在 `Tuist/Package.swift` 中將其宣告為常規外部依賴：

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

然後你可以在專案中直接定義 macro plugin 和 library targets：

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

任何連結 `MyLibrary` 的 target 現在都可以使用該 macro — Tuist 會傳播 plugin，以便編譯器可以載入它。


## 靜態或動態 {#static-or-dynamic}

Frameworks 和 libraries 可以靜態或動態連結，**這個選擇對應用程式大小和啟動時間等方面有重大影響**。儘管其重要性，這個決定往往是在沒有太多考慮的情況下做出的。

**一般經驗法則**是，你希望在 release 建置中盡可能多地靜態連結以實現快速啟動時間，並在 debug 建置中盡可能多地動態連結以實現快速迭代時間。

在專案圖中更改靜態和動態連結之間的挑戰在於，這在 Xcode 中並非易事，因為更改會對整個圖產生連鎖反應（例如，libraries 不能包含資源，靜態 frameworks 不需要嵌入）。Apple 嘗試透過編譯時解決方案來解決這個問題，例如 Swift Package Manager 在靜態和動態連結之間的自動決策，或 [Mergeable Libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)。然而，這為編譯圖添加了新的動態變數，增加了非確定性的新來源，並可能導致一些依賴編譯圖的功能（如 Swift Previews）變得不穩定。

幸運的是，Tuist 在概念上壓縮了與靜態和動態之間切換相關的複雜性，並合成了跨連結類型標準化的 <.localized_link href="/guides/features/projects/synthesized-files#bundle-accessors">bundle accessors</.localized_link>。結合 <.localized_link href="/guides/features/projects/dynamic-configuration">透過環境變數的動態配置</.localized_link>，你可以在調用時傳遞連結類型，並在 manifests 中使用該值來設定 targets 的產品類型。

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

請注意，Tuist <.localized_link href="/guides/features/projects/cost-of-convenience">由於其成本，不會預設透過隱式配置提供便利性</.localized_link>。這意味著我們依賴你設定連結類型以及有時需要的任何其他建置設定，例如 [`-ObjC` linker flag](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184)，以確保產生的二進位檔正確無誤。因此，我們的立場是為你提供資源（通常以文件的形式），幫助你做出正確的決定。

> [!TIP]
> **範例：The Composable Architecture**
>
> 許多專案整合的 Swift Package 是 [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture)。有關更多詳情，請參閱 [本節](#the-composable-architecture)。


### 情境 {#scenarios}

在某些情境下，將連結完全設定為靜態或動態並不可行或不是好主意。以下是不完整的情境列表，你可能需要在其中混合靜態和動態連結：

- **帶有 extensions 的應用程式：** 由於應用程式及其 extensions 需要共享代碼，你可能需要將這些 targets 設為動態。否則，你最終會在應用程式和 extension 中複製相同的代碼，導致二進位檔大小增加。
- **預編譯的外部依賴：** 有時你會獲得預編譯的二進位檔，它們要么是靜態的，要么是動態的。靜態二進位檔可以包裝在動態 frameworks 或 libraries 中以進行動態連結。

當對圖進行更改時，Tuist 會分析它，如果檢測到「靜態副作用」，則顯示警告。此警告旨在幫助你識別因靜態連結一個透過動態 targets 傳遞依賴於靜態 target 的 target 而可能出現的問題。這些副作用通常表現為二進位檔大小增加，或在最壞的情況下，運行時崩潰。

## 疑難排解 {#troubleshooting}

### Objective-C 依賴 {#objectivec-dependencies}

整合 Objective-C 依賴時，可能需要在消費 target 中包含某些標誌以避免運行時崩潰，詳情請參閱 [Apple Technical Q&A QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html)。

由於建置系統和 Tuist 無法推斷該標誌是否必要，且該標誌可能帶來不良副作用，Tuist 不會自動應用任何這些標誌，並且因為 Swift Package Manager 認為 `-ObjC` 是透過 `.unsafeFlag` 包含的，所以大多數 packages 在需要時無法將其作為預設連結設定的一部分。

Objective-C 依賴的使用者（或內部 Objective-C targets）應在需要時透過在消費 targets 上設定 `OTHER_LDFLAGS` 來應用 `-ObjC` 或 `-force_load` 標誌。

### Firebase 和其他 Google Libraries {#firebase-other-google-libraries}

Google 的開源 libraries — 雖然功能強大 — 但在 Tuist 中整合可能很困難，因為它們在構建方式上經常使用非標準架構和技術。

以下是一些整合 Firebase 和 Google 其他 Apple 平台 libraries 時可能需要遵循的提示：

#### 確保將 `-ObjC` 添加到 `OTHER_LDFLAGS` {#ensure-objc-is-added-to-other_ldflags}

Google 的許多 libraries 都是用 Objective-C 編寫的。因此，任何消費 target 都需要在其 `OTHER_LDFLAGS` 建置設定中包含 `-ObjC` 標籤。這可以在 `.xcconfig` 檔案中設定，或在 Tuist manifests 內的 target 設定中手動指定。例如：

```swift
Target.target(
    ...
    settings: .settings(
        base: ["OTHER_LDFLAGS": "$(inherited) -ObjC"]
    )
    ...
)
```

請參閱上方的 [Objective-C Dependencies](#objective-c-dependencies) 章節以了解更多詳情。

#### 將 `FBLPromises` 的產品類型設為動態 framework {#set-the-product-type-for-fblpromises-to-dynamic-framework}

某些 Google libraries 依賴於 `FBLPromises`，這是 Google 的另一個 library。你可能會遇到提及 `FBLPromises` 的崩潰，看起來像這樣：

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

如 [這裡](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184) 和 [疑難排解章節](#troubleshooting) 所述，當靜態連結 packages（這是 Tuist 的預設連結類型）時，你需要將 `OTHER_LDFLAGS` 建置設定設為 `$(inherited) -ObjC`。或者，你可以覆寫 package 的產品類型為動態。靜態連結時，test 和 app targets 通常能正常運作，但 SwiftUI previews 會失效。這可以透過將所有內容動態連結來解決。在下面的範例中，[Sharing](https://github.com/pointfreeco/swift-sharing) 也被添加為依賴，因為它經常與 The Composable Architecture 一起使用，並且有其自身的 [設定陷阱](https://github.com/pointfreeco/swift-sharing/issues/150#issuecomment-2797107032)。

以下設定將所有內容動態連結 - 因此 app + test targets 和 SwiftUI previews 都能正常運作。

> [!TIP]
> **靜態或動態**
>
> 動態連結並非總是建議使用。請參閱 [靜態或動態](#static-or-dynamic) 章節以了解更多詳情。在此範例中，為簡單起見，所有依賴都無條件地動態連結。


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
> 你必須使用 `import SwiftSharing` 而不是 `import Sharing`。


### 傳遞靜態依賴透過 `.swiftmodule` 洩漏 {#transitive-static-dependencies-leaking-through-swiftmodule}

當動態 framework 或 library 透過 `import StaticSwiftModule` 依賴於靜態 ones 時，符號會被包含在動態 framework 或 library 的 `.swiftmodule` 中，可能 <.localized_link href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1">導致編譯失敗</.localized_link>。為防止這種情況，你必須使用 <.localized_link href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`internal import`</.localized_link> 匯入靜態依賴：

```swift
internal import StaticModule
```

> [!NOTE]
> Swift 6 已包含匯入的存取層級。如果你使用的是較舊版本的 Swift，則需要改用 <.localized_link href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_implementationOnly`</.localized_link>：


```swift
@_implementationOnly import StaticModule
```
