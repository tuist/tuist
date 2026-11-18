---
{
  "title": "相依性",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "了解如何在 Tuist 專案中宣告相依性。"
}
---
# 依賴關係 {#dependencies}

當項目增長時，通常會將其拆分為多個目標以共享代碼、定義邊界並改善構建時間。多個目標意味著在它們之間定義依賴關係，形成一個**依賴圖**，其中也可能包括外部依賴關係。

## XcodeProj 編碼的圖 {#xcodeprojcodified-graphs}

由於 Xcode 和 XcodeProj 的設計，維護依賴圖可能是一項繁瑣且容易出錯的工作。以下是一些您可能會遇到的問題示例：

- 因為 Xcode 的構建系統將項目的所有產品輸出到派生數據中的同一個目錄，目標可能會導入它們不應該導入的產品。編譯可能在 CI 上失敗（在那裡乾淨構建更常見），或者在以後使用不同配置時失敗。
- 目標的傳遞動態依賴需要複製到屬於 `LD_RUNPATH_SEARCH_PATHS` 構建設置的任何目錄中。如果沒有這樣做，目標將無法在運行時找到它們。當圖很小時，這很容易考慮和設置，但隨著圖的增長，這就成為了一個問題。
- 當目標鏈接靜態 [XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle) 時，目標需要額外的構建階段，以便 Xcode 處理包並為當前平台和架構提取正確的二進制文件。此構建階段不會自動添加，很容易忘記添加它。

以上只是一些例子，但我們在過去幾年中遇到了更多。想像一下，如果您需要一個工程師團隊來維護依賴圖並確保其有效性。或者更糟糕的是，這些複雜性由一個您無法控制或定制的閉源構建系統在構建時解決。聽起來很熟悉？這是 Apple 對 Xcode 和 XcodeProj 採取的方法，也是 Swift Package Manager 繼承的方法。

我們堅信依賴圖應該是**明確**和**靜態**的，因為只有這樣才能對其進行**驗證**和**優化**。使用 Tuist，您只需專注於描述什麼依賴於什麼，其餘的交給我們。複雜性和實現細節都對您抽象化了。

在以下部分中，您將學習如何在項目中聲明依賴關係。

> [!TIP]
> **圖驗證**
>
> Tuist 在生成項目時驗證圖，以確保沒有循環並且所有依賴關係都有效。得益於此，任何團隊都可以參與演進依賴圖，而無需擔心破壞它。


## 本地依賴關係 {#local-dependencies}

目標可以依賴於相同和不同項目中的其他目標，以及二進制文件。實例化 `Target` 時，您可以傳遞 `dependencies` 參數，選項如下：

- `Target`：聲明與同一項目中目標的依賴關係。
- `Project`：聲明與不同項目中目標的依賴關係。
- `Framework`：聲明與二進制框架的依賴關係。
- `Library`：聲明與二進制庫的依賴關係。
- `XCFramework`：聲明與二進制 XCFramework 的依賴關係。
- `SDK`：聲明與系統 SDK 的依賴關係。
- `XCTest`：聲明與 XCTest 的依賴關係。
- `Macro`：聲明與在同一項目中定義的 Swift 宏目標的依賴關係（參見 [Swift Macros](#swift-macros)）。

> [!NOTE]
> **依賴條件**
>
> 每種依賴類型都接受 `condition` 選項，以根據平台有條件地鏈接依賴關係。默認情況下，它會為目標支持的所有平台鏈接依賴關係。


## 外部依賴關係 {#external-dependencies}

Tuist 還允許您在項目中聲明外部依賴關係。

### Swift Packages {#swift-packages}

Swift Packages 是我們推薦的在項目中聲明依賴關係的方式。Tuist 使用 Swift Package Manager 來解析它們；有關使用本地包模塊化與 Tuist 項目的比較，請參閱 [Swift Package Manager vs Tuist](https://tuist.dev/compare/swift-package-manager)。您可以使用 Xcode 的默認集成機制或使用 Tuist 基於 XcodeProj 的集成來集成它們。

#### Tuist 基於 XcodeProj 的集成 {#tuists-xcodeprojbased-integration}

Xcode 的默認集成雖然最方便，但缺乏中型和大型項目所需的靈活性和控制力。為了克服這一點，Tuist 提供了基於 XcodeProj 的集成，允許您使用 XcodeProj 的目標在項目中集成 Swift Packages。得益於此，我們不僅可以讓您更好地控制集成，還可以使其與 <.localized_link href="/guides/features/cache">緩存</.localized_link> 和 <.localized_link href="/guides/features/selective-testing">選擇性測試運行</.localized_link> 等工作流程兼容。

XcodeProj 的集成可能需要更多時間來支持新的 Swift Package 功能或處理更多的包配置。然而，Swift Packages 和 XcodeProj 目標之間的映射邏輯是開源的，社區可以貢獻代碼。這與 Xcode 的默認集成相反，後者是閉源的，由 Apple 維護。

要添加外部依賴關係，您必須在 `Tuist/` 下或項目根目錄中創建 `Package.swift`。

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
> **包設置**
>
> 包裹在編譯器指令中的 `PackageSettings` 實例允許您配置包的集成方式。例如，在上面的示例中，它用於覆蓋包的默認產品類型。默認情況下，您不需要它。您還可以使用它通過 `expectedSignatures` 配置 SwiftPM 二進制目標的预期簽名。


### 二進制目標簽名

如果本地或遠程 Swift 包公開二進制 XCFramework 目標，您可以使用 `PackageSettings.expectedSignatures` 配置其預期簽名：

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
> 如果您的項目使用自定義構建配置（標準 `Debug` 和 `Release` 以外的配置），您必須在 `PackageSettings` 中使用 `baseSettings` 指定它們。外部依賴關係需要了解項目的配置才能正確構建。例如：
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

`Package.swift` 文件僅是用於聲明外部依賴關係的接口，別無其他。這就是為什麼您不在包中定義任何目標或產品。一旦定義了依賴關係，您可以運行以下命令來解析並將依賴關係拉取到 `Tuist/Dependencies` 目錄中：

```bash
tuist install
# Resolving and fetching dependencies.
# Installing Swift Package Manager dependencies.
```

你可能已經注意到，我們採取了與 [CocoaPods](https://cocoapods.org) 類似的方法，將依賴關係解析作為一個獨立的命令。這讓用戶可以控制何時解析和更新依賴關係，並允許在 Xcode 中打開項目並準備好進行編譯。我們認為，隨著項目規模增長，Apple 與 Swift Package Manager 集成所提供的開發者體驗會逐漸下降。

然後，您可以從項目目標中使用 `TargetDependency.external` 依賴類型來引用這些依賴關係：

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
> **不為外部包生成 Scheme**
>
> 為了保持 Scheme 列表整潔，**Scheme** 不會自動為 Swift Package 項目創建。您可以通過 Xcode 的界面創建它們。


#### Xcode 的默認集成 {#xcodes-default-integration}

如果您想使用 Xcode 的默認集成機制，可以在實例化項目時傳遞 `packages` 列表：

```swift
let project = Project(name: "MyProject", packages: [
    .package(url: "https://github.com/krzyzanowskim/CryptoSwift", .exact("1.8.0"))
])
```

然後從您的目標中引用它們：

```swift
let target: Target = .target(name: "MyTarget", destinations: .iOS, product: .framework, bundleId: "dev.tuist.MyTarget", dependencies: [
    .package(product: "CryptoSwift", type: .runtime)
])
```

當通過 Xcode 的默認集成從外部 Swift Package 集成 Swift Macro 或 Build Tool Plugin 時，請分別使用類型 `.macro` 和 `.plugin` 聲明它。Macro 也可以通過 [Tuist 基於 XcodeProj 的集成](#tuists-xcodeprojbased-integration) 使用，如果您想定義自己的 Swift Macro 而不是使用包中的 Macro，請參閱 [Swift Macros](#swift-macros)。

> [!WARNING]
> **SPM 構建工具插件**
>
> 即使您的項目依賴項使用 Tuist 的 [XcodeProj 基礎集成](#tuists-xcodeprojbased-integration)，也必須使用 [Xcode 的默認集成](#xcodes-default-integration) 機制來聲明 SPM 構建工具插件。

SPM 構建工具插件是 Swift 程序，由 Xcode 和 SwiftPM 執行以發現應為目標運行的具體構建命令。這些命令可能取決於包圖、目標文件、插件工作目錄、已解析的插件工具以及插件聲明的輸出。某些插件還會生成必須成為同一目標構建一部分的文件。

Tuist 基於 XcodeProj 的集成在映射是靜態時（例如庫、二進制文件、可執行文件和宏），將包產品映射到原生 Xcode 目標。構建工具插件在 Xcode 的 SwiftPM 集成之外沒有等效的原生 Xcode 項目基元。雖然插件最終可以運行可執行文件，但從常規腳本構建階段調用該可執行文件不等於運行插件：Tuist 需要先評估插件的 Swift 代碼，重現 SwiftPM 的插件上下文，發現命令，建模聲明的輸入和輸出，並在 Xcode 規劃構建之前將任何生成的文件添加到目標圖中。

因此，不支持僅在 `Tuist/Package.swift` 中聲明插件包並通過 `.external(name:)` 使用它。支持的替代方案是在 `Project.packages` 中聲明包，並使用 `.package(product:type: .plugin)` 將插件產品添加到消費目標中。這使插件作為 Swift Package 產品依賴項附加到生成的 Xcode 項目，以便 Xcode 和 SwiftPM 可以使用原生插件上下文運行它。

權衡在於 Xcode 擁有該插件集成：

- Xcode 通過其 SwiftPM 集成解析和構建插件包。
- 該包在生成的項目中顯示為 Swift Package 引用，而不是 Tuist 生成的外部目標。
- Tuist 無法為插件提供與靜態映射包產品相同級別的控制、驗證、緩存和選擇性測試行為。
- CI 和本地構建必須允許 Xcode 對這些插件包進行包解析。

由於這些影響，我們通常不建議在 Tuist 項目中使用 SPM 構建工具插件。如果可能，首選在目標中聲明的構建階段腳本，或在調用 Tuist 或 Xcode 之前從生成的 Xcode 項目之外的腳本運行該工具。

SPM 構建工具插件的一個實際應用是在 Xcode 的「Run Build Tool Plug-ins」構建階段執行代碼檢查。要生成包含構建工具插件的 Xcode 項目，請在項目清單的 `packages` 數組中聲明包，然後在目標的依賴項中包含類型為 `.plugin` 的包。

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

由於 [Carthage](https://github.com/carthage/carthage) 輸出 `frameworks` 或 `xcframeworks`，您可以運行 `carthage update` 將依賴關係輸出到 `Carthage/Build` 目錄，然後使用 `.framework` 或 `.xcframework` 目標依賴類型在您的目標中聲明依賴關係。您可以將其包裝在一個腳本中，在生成項目之前運行。

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

> [!WARNING]
> **構建和測試**
>
> 如果您通過 `xcodebuild build` 和 `tuist test` 構建和測試項目，同樣需要確保在構建或測試之前運行 `carthage update` 命令，以使 Carthage 解析的依賴關係存在。


### CocoaPods {#cocoapods}

[CocoaPods](https://cocoapods.org) 期望 Xcode 項目集成依賴關係。您可以使用 Tuist 生成項目，然後運行 `pod install` 通過創建包含您的項目和 Pods 依賴關係的工作區來集成依賴關係。您可以將其包裝在一個腳本中，在生成項目之前運行。

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

> [!WARNING]
> CocoaPods 依賴關係與在生成項目後立即運行 `xcodebuild` 的工作流程（如 `build` 或 `test`）不兼容。它們也與二進制緩存和選擇性測試不兼容，因為指紋邏輯未考慮 Pods 依賴關係。


## Swift Macros {#swift-macros}

在 Tuist 項目中使用 [Swift Macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/) 時有兩種不同的場景，明確您處於哪種場景很重要：

- **使用外部 Swift Package 中定義的 Macro。** 兩種集成機制都支持 Macro。使用 [Tuist 基於 XcodeProj 的集成](#tuists-xcodeprojbased-integration) 時，您在 `Tuist/Package.swift` 中聲明包並使用 `.external(name:)` 依賴它 — Tuist 將 Macro 產品映射到原生目標。使用 [Xcode 的默認集成](#xcodes-default-integration) 時，您使用 `.package(product:type: .macro)` 聲明依賴關係。與構建工具插件不同，Macro 不限於 Xcode 的默認集成。
- **定義自己的 Macro**作為項目的一部分——例如在 monorepo 中的共享庫中。您不需要為此使用 `Package.swift`：Tuist 提供一流的 `.macro` 產品類型，因此您可以直接在清單中聲明 Macro 目標。

### 定義自己的 Macro {#defining-your-own-macro}

Swift Macro 是一種編譯器插件：一個可執行文件，Swift 編譯器在編譯時加載並運行它。Tuist 通過 `.macro` 產品類型原生地建模這一點。雖然 Apple 沒有在 Xcode 項目中公開 Swift Macro 目標類型，但 Tuist 通過生成命令行工具目標、將其連接為使用 Macro 的目標的依賴項，並將 `-load-plugin-executable` 標誌注入其 Swift 編譯器設置來實現這一功能。所有這些底層工作都由 Tuist 為您處理。

典型的 Macro 分為兩個目標：實現 Macro 的 **插件**目標（`product: .macro`），以及聲明 Macro 公共接口（`@attached`/`@freestanding` 聲明）並通過 `.macro(name:)` 依賴插件的 **庫**目標。由於插件在構建機器上運行，其目標僅限於主機（macOS）。

Macro 實現依賴於 [swift-syntax](https://github.com/swiftlang/swift-syntax)，您可以在 `Tuist/Package.swift` 中將其聲明為常規外部依賴項：

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

然後，您可以直接在項目中定義 Macro 插件和庫目標：

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

任何鏈接 `MyLibrary` 的目標現在都可以使用 Macro — Tuist 會傳播插件，以便編譯器可以加載它。


## 靜態或動態 {#static-or-dynamic}

框架和庫可以靜態或動態鏈接，**這一選擇對應用大小和啟動時間等方面有重大影響**。儘管其重要性不言而喻，但這一決定往往未經深思熟慮。

**一般經驗法則**是，在發布構建中盡可能多地靜態鏈接以實現快速啟動，而在調試構建中盡可能多地動態鏈接以實現快速迭代。

在項目圖中更改靜態和動態鏈接的挑戰在於，這在 Xcode 中並非易事，因為更改會對整個圖產生連鎖反應（例如，庫不能包含資源，靜態框架不需要嵌入）。Apple 試圖通過編譯時解決方案來解決這個問題，例如 Swift Package Manager 自動決定靜態或動態鏈接，或 [Mergeable Libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)。然而，這為編譯圖添加了新的動態變量，增加了非確定性的來源，並可能導致依賴編譯圖的功能（如 Swift Previews）變得不穩定。

幸運的是，Tuist 在概念上簡化了靜態和動態之間切換的複雜性，並合成了跨鏈接類型標準化的 <.localized_link href="/guides/features/projects/synthesized-files#bundle-accessors">bundle accessors</.localized_link>。結合 <.localized_link href="/guides/features/projects/dynamic-configuration">通過環境變量的動態配置</.localized_link>，您可以在調用時傳遞鏈接類型，並在清單中使用該值來設置目標的產品類型。

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

請注意，Tuist <.localized_link href="/guides/features/projects/cost-of-convenience">由於成本原因，不會默認通過隱式配置提供便利</.localized_link>。這意味著我們依賴您設置鏈接類型以及有時需要的其他構建設置，例如 [`-ObjC` 鏈接器標誌](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184)，以確保生成的二進制文件正確無誤。因此，我們的立場是為您提供資源（通常以文檔形式），幫助您做出正確的決定。

> [!TIP]
> **示例：The Composable Architecture**
>
> 許多項目集成的 Swift Package 是 [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture)。有關更多詳情，請參閱 [本節](#the-composable-architecture)。


### 場景 {#scenarios}

在某些情況下，將鏈接完全設置為靜態或動態並不可行或不是好主意。以下是一個非詳盡列表，列出了您可能需要混合使用靜態和動態鏈接的場景：

- **帶有擴展的應用：** 由於應用及其擴展需要共享代碼，您可能需要將這些目標設置為動態。否則，您最終會在應用和擴展中重複相同的代碼，導致二進制文件大小增加。
- **預編譯的外部依賴項：** 有時您會獲得預編譯的二進制文件，它們可能是靜態或動態的。靜態二進制文件可以包裝在動態框架或庫中以進行動態鏈接。

當更改圖時，Tuist 會分析它，如果檢測到「靜態副作用」，則顯示警告。此警告旨在幫助您識別因靜態鏈接依賴於通過動態目標傳遞依賴於靜態目標的目標而可能出現的問題。這些副作用通常表現為二進制大小增加，在最壞的情況下會導致運行時崩潰。

## 故障排除 {#troubleshooting}

### Objective-C 依賴項 {#objectivec-dependencies}

集成 Objective-C 依賴項時，可能需要在消費目標中包含某些標誌以避免運行時崩潰，詳細信息見 [Apple Technical Q&A QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html)。

由於構建系統和 Tuist 無法推斷是否需要該標誌，且該標誌可能帶來不必要的副作用，Tuist 不會自動應用任何這些標誌。此外，由於 Swift Package Manager 認為 `-ObjC` 是通過 `.unsafeFlag` 包含的，大多數包在需要時無法將其作為默認鏈接設置的一部分。

Objective-C 依賴項的使用者（或內部 Objective-C 目標）應在需要時通過在消費目標上設置 `OTHER_LDFLAGS` 來應用 `-ObjC` 或 `-force_load` 標誌。

### Firebase 和其他 Google 庫 {#firebase-other-google-libraries}

Google 的開源庫雖然功能強大，但在 Tuist 中集成可能比較困難，因為它們在構建方式上經常使用非標準的架構和技術。

以下是一些集成 Firebase 和 Google 其他 Apple 平台庫時可能需要遵循的技巧：

#### 確保將 `-ObjC` 添加到 `OTHER_LDFLAGS` {#ensure-objc-is-added-to-other_ldflags}

Google 嘅好多庫都用 Objective-C 寫成。因此，任何使用目標都需要喺佢嘅 `OTHER_LDFLAGS` 構建設置中包含 `-ObjC` 標籤。你可以喺 `.xcconfig` 文件中設置，或者喺 Tuist 清單嘅目標設置中手動指定。例如：

```swift
Target.target(
    ...
    settings: .settings(
        base: ["OTHER_LDFLAGS": "$(inherited) -ObjC"]
    )
    ...
)
```

詳情請參閱上面嘅 [Objective-C 依賴項](#objectivec-dependencies) 章節。

#### 將 `FBLPromises` 嘅產品類型設置為動態框架 {#set-the-product-type-for-fblpromises-to-dynamic-framework}

某些 Google 庫依賴於 `FBLPromises`，呢個係 Google 嘅另一個庫。你可能會遇到提到 `FBLPromises` 嘅崩潰，類似咁樣：

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

喺你嘅 `Package.swift` 文件中將 `FBLPromises` 嘅產品類型明確設置為 `.framework` 應該可以解決問題：

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

正如 [此處](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184) 同 [故障排除章節](#troubleshooting) 所述，當靜態鏈接包時（Tuist 嘅默認鏈接類型），你需要將 `OTHER_LDFLAGS` 構建設置設置為 `$(inherited) -ObjC`。或者，你可以覆蓋包嘅產品類型為動態。靜態鏈接時，測試同應用目標通常運作無誤，但 SwiftUI 預覽會失效。透過將所有內容動態鏈接可以解決呢個問題。下面嘅例子中亦都加入咗 [Sharing](https://github.com/pointfreeco/swift-sharing) 作為依賴，因為佢經常同 The Composable Architecture 一齊使用，並且有自己嘅 [配置陷阱](https://github.com/pointfreeco/swift-sharing/issues/150#issuecomment-2797107032)。

以下配置會將所有內容動態鏈接——因此應用 + 測試目標同 SwiftUI 預覽都可以正常運作。

> [!TIP]
> **靜態或動態**
>
> 動態鏈接並唔總係推薦嘅。詳情請參閱 [靜態或動態](#static-or-dynamic) 章節。為咗簡單起見，本例中所有依賴項都無條件地動態鏈接。


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
> 你必須改用 `import SwiftSharing` 而唔係 `import Sharing`。


### 傳遞性靜態依賴透過 `.swiftmodule` 洩漏 {#transitive-static-dependencies-leaking-through-swiftmodule}

當動態框架或庫透過 `import StaticSwiftModule` 依賴於靜態庫時，符號會被包含喺動態框架或庫嘅 `.swiftmodule` 中，可能<.localized_link href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1">導致編譯失敗</.localized_link>。為咗防止呢種情況，你需要使用 <.localized_link href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`internal import`</.localized_link> 來導入靜態依賴：

```swift
internal import StaticModule
```

> [!NOTE]
> Swift 6 已包含導入訪問級別。如果你使用較舊版本嘅 Swift，則需要改用 <.localized_link href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_implementationOnly`</.localized_link>：


```swift
@_implementationOnly import StaticModule
```

## 相關 {#related}

閱讀 [monday.com 如何採用 Tuist 實現模塊化項目圖](https://tuist.dev/customers/monday)，從依賴最少嘅目標開始。
