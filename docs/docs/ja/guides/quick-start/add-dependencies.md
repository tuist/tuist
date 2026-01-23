---
{
  "title": "Add dependencies",
  "titleTemplate": ":title · Quick-start · Guides · Tuist",
  "description": "Learn how to add dependencies to your first Swift project"
}
---
# 依存関係を追加{#add-dependencies}

プロジェクトが追加機能を提供するためにサードパーティライブラリに依存することは一般的です。プロジェクト編集の最適な環境を得るには、次のコマンドを実行してください：

```bash
tuist edit
```

`Xcodeプロジェクトが開き、プロジェクトファイルが含まれます。Package.swiftを編集し、` に以下の内容を追加してください：

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

次に、プロジェクト内のアプリケーションターゲットを編集し、`Kingfisher` を依存関係として宣言します:

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

その後、`tuist install` を実行し、[Swift Package
Manager](https://www.swift.org/documentation/package-manager/)
を使用して依存関係を解決・取得してください。

::: info SPM AS A DEPENDENCY RESOLVER
<!-- -->
Tuistが推奨する依存関係管理のアプローチでは、Swift Package Manager (SPM)
を依存関係の解決にのみ使用します。その後、TuistはそれらをXcodeプロジェクトとターゲットに変換し、最大限の設定性と制御性を実現します。
<!-- -->
:::

## プロジェクトを可視化する{#visualize-the-project}

プロジェクト構造を可視化するには、以下を実行してください：

```bash
tuist graph
```

このコマンドはプロジェクトディレクトリに`graph.png` ファイルを出力・開きます：

![プロジェクトグラフ](/images/guides/quick-start/graph.png)

## 依存関係を使用する{#use-the-dependency}

`tuist generate` を実行してプロジェクトをXcodeで開く。`/ContentView.swift` ファイルに以下の変更を加える：

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
