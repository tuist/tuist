---
{
  "title": "生成プロジェクトを作成する",
  "titleTemplate": ":title · Xcode · チュートリアル · Tuist",
  "description": "最初のTuist生成Xcodeプロジェクトを作成し、依存関係を追加する方法を学びます"
}
---
# 生成プロジェクトを作成する {#create-a-generated-project}

空のディレクトリ、または既存のプロジェクトのディレクトリで `tuist init` を実行します。

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

このコマンドは、<.localized_link href="/guides/features/projects">生成プロジェクトを作成</.localized_link>するか、既存のXcodeプロジェクトまたはワークスペースを統合する手順を案内します。セットアップをリモートサーバーに接続し、<.localized_link href="/guides/features/selective-testing">選択的テスト</.localized_link>、<.localized_link href="/guides/features/previews">プレビュー</.localized_link>、<.localized_link href="/guides/features/package-registries/swift">レジストリ</.localized_link>などの機能を利用できるようにします。

> [!NOTE]
> **既存のプロジェクトを移行**
>
> 開発者体験を向上させ、<.localized_link href="/guides/features/cache">キャッシュ</.localized_link>を活用するために既存のプロジェクトを生成プロジェクトに移行したい場合は、<.localized_link href="/guides/features/projects/adoption/migrate/xcode-project">移行ガイド</.localized_link>をご覧ください。


## 依存関係を追加する {#add-dependencies}

プロジェクトが追加機能を提供するためにサードパーティ製ライブラリに依存することは一般的です。そのためには、以下のコマンドを実行して、プロジェクト編集の最適な環境を整えます。

```bash
tuist edit
```

プロジェクトファイルを含むXcodeプロジェクトが開きます。`Tuist/Package.swift` を編集し、Kingfisherを追加します。

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

次に、プロジェクト内のアプリケーションターゲットを編集し、`Kingfisher` を依存関係として宣言します。

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

その後、`tuist install` を実行して、[Swift Package Manager](https://www.swift.org/documentation/package-manager/)を使用して依存関係を解決および取得します。

> [!NOTE]
> **依存関係解決ツールとしてのSwiftPM**
>
> Tuistが推奨する依存関係の扱いは、Swift Package Manager (SPM) を依存関係の解決のみに使用します。その後、TuistはそれらをXcodeプロジェクトとターゲットに変換し、最大限の設定可能性と制御を実現します。


## プロジェクトを可視化する {#visualize-the-project}

以下のコマンドを実行すると、プロジェクト構造を可視化できます。

```bash
tuist graph
```

このコマンドは、プロジェクトのディレクトリに `graph.png` ファイルを出力して開きます。

![プロジェクトグラフ](/images/guides/quick-start/graph.png)

## 依存関係を使用する {#use-the-dependency}

`tuist generate` を実行してXcodeでプロジェクトを開き、`ContentView.swift` ファイルに以下の変更を加えます。

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

Xcodeからアプリを実行すると、URLから画像が読み込まれているのが確認できます。
