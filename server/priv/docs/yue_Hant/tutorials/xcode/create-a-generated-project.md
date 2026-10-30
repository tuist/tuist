---
{
  "title": "建立生成式專案",
  "titleTemplate": ":title · Xcode · 教學 · Tuist",
  "description": "學習如何建立你第一個由 Tuist 生成的 Xcode 專案，並為其加入依賴項"
}
---
# 建立生成項目 {#create-a-generated-project}

在任何目錄或現有項目目錄中開始使用 Tuist 的最簡單方法：

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

此指令會引導你完成<.localized_link href="/guides/features/projects">建立生成項目</.localized_link>或整合現有 Xcode 項目或工作區的步驟。它幫助你將設定連接到遠端伺服器，讓你可以使用<.localized_link href="/guides/features/selective-testing">選擇性測試</.localized_link>、<.localized_link href="/guides/features/previews">預覽</.localized_link>和<.localized_link href="/guides/features/package-registries/swift">註冊表</.localized_link>等功能。

> [!NOTE]
> **遷移現有項目**
>
> 如果你想將現有項目遷移到生成項目以改善開發者體驗並利用我們的<.localized_link href="/guides/features/cache">快取</.localized_link>，請查看我們的<.localized_link href="/guides/features/projects/adoption/migrate/xcode-project">遷移指南</.localized_link>。


## 新增依賴項 {#add-dependencies}

項目通常依賴第三方庫來提供額外功能。為此，請執行以下指令以獲得最佳的項目編輯體驗：

```bash
tuist edit
```

將會開啟一個包含你項目檔案的 Xcode 項目。編輯 `Package.swift` 並新增

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

然後編輯項目中的應用程式目標，將 `Kingfisher` 宣告為依賴項：

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

然後執行 `tuist install` 以使用 [Swift Package Manager](https://www.swift.org/documentation/package-manager/) 解析並拉取依賴項。

> [!NOTE]
> **使用 SPM 作為依賴項解析器**
>
> Tuist 建議的依賴項處理方法僅使用 Swift Package Manager (SPM) 來解析依賴項。然後 Tuist 會將它們轉換為 Xcode 項目和目標，以實現最大的可配置性和控制力。


## 視覺化項目 {#visualize-the-project}

你可以通過執行以下指令來視覺化項目結構：

```bash
tuist graph
```

該指令將在項目目錄中輸出並開啟一個 `graph.png` 檔案：

![項目圖](/images/guides/quick-start/graph.png)

## 使用依賴項 {#use-the-dependency}

執行 `tuist generate` 以在 Xcode 中開啟項目，並對 `ContentView.swift` 檔案進行以下更改：

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

從 Xcode 運行應用程式，你應該會看到從 URL 載入的圖像。
