---
{
  "title": "建立生成項目",
  "titleTemplate": ":title · Xcode · 教學 · Tuist",
  "description": "學習如何建立你第一個由 Tuist 生成的 Xcode 項目，並為其加入依賴"
}
---
# 建立生成項目 {#create-a-generated-project}

喺空白目錄或者現有項目嘅目錄入面執行 `tuist init`：

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

指令會引導你完成步驟，<.localized_link href="/guides/features/projects">建立生成項目</.localized_link> 或者整合現有嘅 Xcode 項目或工作區。佢幫你將設定連接到遠端伺服器，令你可以使用好似 <.localized_link href="/guides/features/selective-testing">選擇性測試</.localized_link>、<.localized_link href="/guides/features/previews">預覽</.localized_link> 同 <.localized_link href="/guides/features/package-registries/swift">註冊表</.localized_link> 等功能。

> [!NOTE]
> **遷移現有項目**
>
> 如果你想將現有項目遷移到生成項目，以改善開發者體驗並利用我哋嘅 <.localized_link href="/guides/features/cache">快取</.localized_link>，請參閱我哋嘅 <.localized_link href="/guides/features/projects/adoption/migrate/xcode-project">遷移指南</.localized_link>。


## 加入依賴 {#add-dependencies}

項目通常會依賴第三方程式庫嚟提供額外功能。要做到呢一點，請執行以下指令，獲得最佳嘅項目編輯體驗：

```bash
tuist edit
```

系統會開啟一個包含你項目檔案嘅 Xcode 項目。編輯 `Tuist/Package.swift` 並加入 Kingfisher：

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

然後編輯項目中嘅應用程式目標，將 `Kingfisher` 宣告為依賴：

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
                .external(name: "Kingfisher")
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

之後執行 `tuist install`，使用 [Swift Package Manager](https://www.swift.org/documentation/package-manager/) 解析並拉取依賴。

> [!NOTE]
> **使用 SwiftPM 作為依賴解析器**
>
> Tuist 建議嘅依賴處理方式只係使用 Swift Package Manager (SPM) 嚟解析依賴。然後 Tuist 會將佢哋轉換成 Xcode 項目同目標，以提供最大嘅可配置性同控制權。


## 視覺化項目結構 {#visualize-the-project}

你可以透過執行以下指令嚟視覺化項目結構：

```bash
tuist graph
```

指令會輸出並喺項目目錄中開啟 `graph.png` 檔案：

![項目圖](/images/guides/quick-start/graph.png)

## 使用依賴 {#use-the-dependency}

執行 `tuist generate` 以喺 Xcode 中開啟項目，並對 `ContentView.swift` 檔案作出以下更改：

```swift
import SwiftUI
import Kingfisher

public struct ContentView: View {
    public init() {}

    public var body: some View {
        KFImage(URL(string: "https://tuist.dev/images/tuist_logo_32x32@2x.png")!)
    }
}


struct ContentView_Previews: PreviewProvider {
    static var previews: some View {
        ContentView()
    }
}
```

從 Xcode 執行應用程式，你應該會見到從 URL 載入嘅圖片。
