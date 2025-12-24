---
{
  "title": "Add dependencies",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to add dependencies to your first Swift project"
}
---
# 新增依賴{#add-dependencies}

專案通常會依賴第三方函式庫來提供額外的功能。為此，請執行下列指令，以獲得編輯專案的最佳體驗：

```bash
tuist edit
```

一個包含您專案檔案的 Xcode 專案將會開啟。編輯`Package.swift` 並加入

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

然後編輯專案中的應用程式目標，將`Kingfisher` 宣告為相依性：

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

然後使用 [Swift
套件管理員](https://www.swift.org/documentation/package-manager/)，執行`tuist install`
來解析並拉取相依性。

::: info SPM AS A DEPENDENCY RESOLVER
<!-- -->
Tuist 推薦的相依性方法僅使用 Swift Package Manager (SPM) 來解決相依性問題。然後 Tuist 將其轉換為 Xcode
專案和目標，以達到最大的可配置性和控制性。
<!-- -->
:::

## 視覺化專案{#visualize-the-project}

您可以執行下列步驟，以視覺化專案結構：

```bash
tuist graph
```

指令會輸出並開啟專案目錄中的`graph.png` 檔案：

！[專案圖形](/images/guides/quick-start/graph.png)

## 使用相依性{#use-the-dependency}

執行`tuist generate` 在 Xcode 中開啟專案，並對`ContentView.swift` 檔案進行下列變更：

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

從 Xcode 執行應用程式，您應該會看到從 URL 載入的圖片。
