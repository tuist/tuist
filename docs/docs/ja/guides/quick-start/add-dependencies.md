---
{
  "title": "依存関係の追加",
  "titleTemplate": ":title · クイックスタート · ガイド · Tuist",
  "description": "最初のSwiftプロジェクトに依存関係を追加する方法を学ぶ"
}
---
# 依存関係の追加 {#add-dependencies}

プロジェクトが追加機能を提供するためにサードパーティのライブラリに依存することは一般的です。 そのために、プロジェクトを編集するための最適な体験を得るために、次のコマンドを実行します。 そのために、プロジェクトを編集するための最適な体験を得るために、次のコマンドを実行します。

```bash
tuist edit
```

Xcodeプロジェクトが開き、プロジェクトファイルが表示されます。 Package.swiftを編集し、以下を追加します。

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

次に、プロジェクト内のアプリケーションターゲットを編集して、`Kingfisher` を依存関係として宣言します。

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    targets: [
        .target(
            name: "MyApp",
            destinations: .iOS,
            product: .app,
            bundleId: "io.tuist.MyApp",
            infoPlist: .extendingDefault(
                with: [
                    "UILaunchStoryboardName": "LaunchScreen.storyboard",
                ]
            ),
            sources: ["MyApp/Sources/**"],
            resources: ["MyApp/Resources/**"],
            dependencies: [
                .external(name: "Kingfisher") // [!code ++]
            ]
        ),
        .target(
            name: "MyAppTests",
            destinations: .iOS,
            product: .unitTests,
            bundleId: "io.tuist.MyAppTests",
            infoPlist: .default,
            sources: ["MyApp/Tests/**"],
            resources: [],
            dependencies: [.target(name: "MyApp")]
        ),
    ]
)
```

次に、`tuist install` を実行して、[Swift Package Manager](https://www.swift.org/documentation/package-manager/) を使用して依存関係を解決し、取得します。

> [!NOTE] 依存関係解決ツールとしてのSPM
> Tuistの推奨する依存関係のアプローチは、依存関係を解決するためにSwift Package Manager (SPM) を使用することです。 TuistはそれらをXcodeプロジェクトとターゲットに変換し、最大限の構成可能性と制御を提供します。 TuistはそれらをXcodeプロジェクトとターゲットに変換し、最大限の構成可能性と制御を提供します。 TuistはそれらをXcodeプロジェクトとターゲットに変換し、最大限の構成可能性と制御を提供します。 TuistはそれらをXcodeプロジェクトとターゲットに変換し、最大限の構成可能性と制御を提供します。 TuistはそれらをXcodeプロジェクトとターゲットに変換し、最大限の構成可能性と制御を提供します。

## プロジェクトの可視化 {#visualize-the-project}

次のコマンドを実行してプロジェクト構造を可視化できます。

```bash
tuist graph
```

このコマンドは、プロジェクトのディレクトリ内に `graph.png` ファイルを出力して開きます：

![Project graph](/images/guides/quick-start/graph.png)

## 依存関係の使用 {#use-the-dependency}

`tuist generate` を実行してプロジェクトをXcodeで開き、`ContentView.swift` ファイルに次の変更を加えます。

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
