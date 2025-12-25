---
{
  "title": "Add dependencies",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to add dependencies to your first Swift project"
}
---
# 依存関係の追加{#add-dependencies}

追加機能を提供するために、プロジェクトがサードパーティのライブラリに依存することはよくあることです。そのためには、以下のコマンドを実行すると、プロジェクトの編集がより快適になります：

```bash
tuist edit
```

プロジェクト・ファイルを含むXcodeプロジェクトが開きます。`Package.swift` 。

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

次に、プロジェクトのアプリケーション・ターゲットを編集して、`Kingfisher` を依存関係として宣言します：

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

それから`tuist install` を実行し、[Swift Package
Manager](https://www.swift.org/documentation/package-manager/)を使って依存関係を解決し、取り出します。

::: info SPM AS A DEPENDENCY RESOLVER
<!-- -->
依存関係に対するTuistの推奨アプローチは、依存関係を解決するためにSwift Package Manager
(SPM)のみを使用する。そしてTuistはそれらをXcodeプロジェクトとターゲットに変換し、最大限の設定と制御を可能にする。
<!-- -->
:::

## プロジェクトを可視化する{#visualize-the-project}

を実行することで、プロジェクトの構造を可視化することができる：

```bash
tuist graph
```

このコマンドは、プロジェクトのディレクトリにある`graph.png` ファイルを出力し、開きます：

プロジェクトグラフ

## 依存関係を利用する{#use-the-dependency}

`tuist generate` を実行して Xcode でプロジェクトを開き、`ContentView.swift` ファイルに以下の変更を加えます：

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

Xcodeからアプリを実行すると、URLから読み込まれた画像が表示されるはずです。
