---
{
  "title": "生成されたプロジェクトを作成する",
  "titleTemplate": ":title · Xcode · チュートリアル · Tuist",
  "description": "最初のTuist生成Xcodeプロジェクトを作成し、依存関係を追加する方法を学びます"
}
---
# 生成されたプロジェクトを作成する {#create-a-generated-project}

任意のディレクトリ、または既存のプロジェクトのディレクトリで Tuist を使い始める最も簡単な方法:

::: code-group

```bash [Mise]
mise x tuist@latest -- tuist init
```

```bash [Global Tuist (Homebrew)]
tuist init
```
<!-- -->
:::

このコマンドは、<.localized_link href="/guides/features/projects">生成されたプロジェクトを作成</.localized_link>するか、既存の Xcode プロジェクトやワークスペースを統合するための手順を案内します。セットアップをリモートサーバーに接続し、<.localized_link href="/guides/features/selective-testing">選択的テスト</.localized_link>、<.localized_link href="/guides/features/previews">プレビュー</.localized_link>、<.localized_link href="/guides/features/package-registries/swift">レジストリ</.localized_link>などの機能を利用できるようにします。

> [!NOTE]
> **既存のプロジェクトを移行する**
>
> 開発者体験を向上させ、<.localized_link href="/guides/features/cache">キャッシュ</.localized_link>を活用するために既存のプロジェクトを生成されたプロジェクトに移行したい場合は、<.localized_link href="/guides/features/projects/adoption/migrate/xcode-project">移行ガイド</.localized_link>をご覧ください。


## 依存関係を追加する {#add-dependencies}

プロジェクトが追加機能を提供するためにサードパーティ製ライブラリに依存することは一般的です。そのためには、以下のコマンドを実行して、プロジェクト編集時の最適な体験を得てください:

```bash
tuist edit
```

プロジェクトファイルを含む Xcode プロジェクトが開きます。`Package.swift` を編集して、以下を追加してください

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

次に、プロジェクト内のアプリケーションターゲットを編集して、`Kingfisher` を依存関係として宣言します:

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

その後、`tuist install` を実行して、[Swift Package Manager](https://www.swift.org/documentation/package-manager/) を使用して依存関係を解決および取得します。

> [!NOTE]
> **依存関係リゾルバーとしての SPM**
>
> Tuist が推奨する依存関係の扱い方では、Swift Package Manager (SPM) は依存関係の解決のみで使用されます。Tuist はその後、それらを最大限の設定可能性と制御を実現するために Xcode プロジェクトとターゲットに変換します。


## プロジェクトを可視化する {#visualize-the-project}

以下のコマンドを実行することで、プロジェクト構造を可視化できます:

```bash
tuist graph
```

このコマンドは、プロジェクトのディレクトリに `graph.png` ファイルを出力して開きます:

![プロジェクトグラフ](/images/guides/quick-start/graph.png)

## 依存関係を使用する {#use-the-dependency}

`tuist generate` を実行して Xcode でプロジェクトを開き、`ContentView.swift` ファイルに以下の変更を加えます:

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

Xcode からアプリを実行すると、URL から画像が読み込まれているのが確認できます。
