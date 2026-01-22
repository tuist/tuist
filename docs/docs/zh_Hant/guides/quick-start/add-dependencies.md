---
{
  "title": "Add dependencies",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to add dependencies to your first Swift project"
}
---
# 新增依賴項{#add-dependencies}

專案常需依賴第三方函式庫提供額外功能。為獲得最佳編輯體驗，請執行以下指令：

```bash
tuist edit
```

Xcode 專案將開啟並載入您的專案檔案。編輯`中的 Package.swift 檔案，前往` 位置，並新增以下內容：

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

接著編輯專案中的應用程式目標，宣告`Kingfisher` 為依賴項：

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

接著執行 ``` 並安裝 `` ` 以透過 [Swift Package
Manager](https://www.swift.org/documentation/package-manager/) 解決並拉取依賴項。

::: info SPM AS A DEPENDENCY RESOLVER
<!-- -->
Tuist 建議的依賴管理方法僅使用 Swift Package Manager (SPM) 解析依賴項，隨後將其轉換為 Xcode
專案與目標，以實現最高程度的可配置性與控制力。
<!-- -->
:::

## 視覺化專案{#visualize-the-project}

執行以下指令可檢視專案結構：

```bash
tuist graph
```

此指令將在專案目錄中輸出並開啟檔案：`graph.png`

![專案圖表](/images/guides/quick-start/graph.png)

## 使用依賴關係{#use-the-dependency}

執行`tuist generate` 以在 Xcode 中開啟專案，並對`ContentView.swift 檔案進行以下修改：`

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

從 Xcode 執行應用程式，您應能看見從 URL 載入的圖片。
