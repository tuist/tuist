---
{
  "title": "建立產生的專案",
  "titleTemplate": ":title · Xcode · 教學課程 · Tuist",
  "description": "了解如何建立第一個由 Tuist 產生的 Xcode 專案，並為其新增相依性"
}
---
# 建立產生的專案 {#create-a-generated-project}

在任何目錄或現有專案目錄中開始使用 Tuist 的最簡單方式：

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

此指令將引導你完成<.localized_link href="/guides/features/projects">建立產生的專案</.localized_link>，或整合現有 Xcode 專案或工作區的步驟。它能協助你將設定連線至遠端伺服器，讓你使用如<.localized_link href="/guides/features/selective-testing">選擇性測試</.localized_link>、<.localized_link href="/guides/features/previews">預覽</.localized_link>與<.localized_link href="/guides/features/package-registries/swift">套件註冊中心</.localized_link>等功能。

> [!NOTE]
> **遷移現有專案**
>
> 若你想將現有專案遷移至產生的專案，以改善開發者體驗並善用我們的<.localized_link href="/guides/features/cache">快取</.localized_link>，請參閱我們的<.localized_link href="/guides/features/projects/adoption/migrate/xcode-project">遷移指南</.localized_link>。


## 新增相依性 {#add-dependencies}

專案常依賴第三方程式庫來提供額外功能。為此，請執行以下指令，獲得最佳的專案編輯體驗：

```bash
tuist edit
```

系統會開啟包含你專案檔案的 Xcode 專案。編輯 `Package.swift` 並加入

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

接著編輯專案中的應用程式目標，將 `Kingfisher` 宣告為相依性：

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        .target(
            name: "MyApp",
            destinations: .iOS,
            product: .app,
            bundleId: "dev.tuist.MyApp",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchStoryboardName": "LaunchScreen.storyboard",
                ]
            ),
            buildableFolders: [
                "MyApp/Sources",
                "MyApp/Resources",
            ],
            dependencies: [
                .external(name: "Kingfisher") // [!code ++]
            ]
        ),
        .target(
            name: "MyAppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "dev.tuist.MyAppTests",
            infoPlist: .default,
            sources: ["MyApp/Tests/**"],
            resources: [],
            dependencies: [.target(name: "MyApp")]
        ),
    ]
)
```

然後執行 `tuist install`，透過 [Swift Package Manager](https://www.swift.org/documentation/package-manager/) 解析並拉取相依性。

> [!NOTE]
> **以 SPM 作為相依性解析器**
>
> Tuist 建議的相依性處理方式僅使用 Swift Package Manager (SPM) 來解析相依性。隨後 Tuist 會將其轉換為 Xcode 專案與目標，以提供最大的可設定性與控制力。


## 視覺化專案結構 {#visualize-the-project}

你可以執行以下指令來視覺化專案結構：

```bash
tuist graph
```

該指令會在專案目錄中輸出並開啟 `graph.png` 檔案：

![專案圖表](/images/guides/quick-start/graph.png)

## 使用相依性 {#use-the-dependency}

執行 `tuist generate` 以在 Xcode 中開啟專案，並對 `ContentView.swift` 檔案進行以下變更：

```swift
import SwiftUI
import Kingfisher // [!code ++]

public struct ContentView: View {
    public init() {}

    public var body: some View {
        Text("Hello, World!") // [!code --]
            .padding() // [!code --]
        KFImage(URL(string: "https://cloud.tuist.io/images/tuist_logo_32x32@2x.png")!) // [!code ++]
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
```

從 Xcode 執行應用程式，你應該會看到從 URL 載入的圖片。
