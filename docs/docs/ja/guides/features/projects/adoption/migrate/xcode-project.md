---
{
  "title": "Migrate an Xcode project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate an Xcode project to a Tuist project."
}
---
# Xcodeプロジェクトを移行する{#migrate-an-xcode-project}

Tuistを使用して新しいプロジェクトを作成しない限り、自動的にすべてが設定されるので、Tuistのプリミティブを使用してXcodeプロジェクトを定義する必要があります。この作業がどの程度面倒かは、あなたのプロジェクトがどの程度複雑かによる。

ディレクトリ構造と一致しないグループ、ターゲット間で共有されるファイル、存在しないファイルを指すファイル参照（いくつか挙げると）。このような複雑さが蓄積すると、プロジェクトを確実に移行するコマンドを提供することが難しくなります。

さらに、手作業での移行は、プロジェクトをクリーンアップし、シンプルにするための優れたエクササイズです。あなたのプロジェクトの開発者だけでなく、Xcodeもそのことに感謝するだろう。ひとたびTuistを完全に採用すれば、プロジェクトが一貫して定義され、シンプルなままであることを確認できるだろう。

その作業を軽減する目的で、ユーザーから寄せられたフィードバックに基づいたガイドラインをいくつか紹介する。

## プロジェクトの足場を作る{#create-project-scaffold}

まず、以下のTuistファイルでプロジェクトの足場を作る：

コードグループ

```js [Tuist.swift]
import ProjectDescription

let tuist = Tuist()
```

```js [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyApp-Tuist",
    targets: [
        /** Targets will go here **/
    ]
)
```

```js [Tuist/Package.swift]
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
    ]
)
```
<!-- -->
:::

`Project.swift` はプロジェクトを定義するマニフェスト・ファイルで、`Package.swift`
は依存関係を定義するマニフェスト・ファイルです。`Tuist.swift`
ファイルは、プロジェクトのためにプロジェクト・スコープのTuist設定を定義する場所です。

::: tip PROJECT NAME WITH -TUIST SUFFIX
<!-- -->
既存のXcodeプロジェクトとのコンフリクトを防ぐため、プロジェクト名に`-Tuist`
という接尾辞をつけることをお勧めします。プロジェクトをTuistに完全に移行したら、この接尾辞を削除することができます。
<!-- -->
:::

## CIでTuistプロジェクトをビルドしてテストする{#build-and-test-the-tuist-project-in-ci}

各変更の移行が有効であることを確認するために、継続的インテグレーションを拡張して、マニフェストファイルからTuistが生成したプロジェクトをビルドし、テストすることをお勧めします：

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## プロジェクトのビルド設定を`.xcconfig` ファイルに展開する。{#extract-the-project-build-settings-into-xcconfig-files}

プロジェクトからのビルド設定を`.xcconfig`
ファイルに抽出すると、プロジェクトがスリムになって移行しやすくなります。次のコマンドを使用して、プロジェクトからビルド設定を`.xcconfig`
ファイルに抽出できます：


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

次に、`Project.swift` ファイルを更新し、先ほど作成した`.xcconfig` ファイルを指すようにします：

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    settings: .settings(configurations: [
        .debug(name: "Debug", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"), // [!code ++]
        .release(name: "Release", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"), // [!code ++]
    ]),
    targets: [
        /** Targets will go here **/
    ]
)
```

次に、継続的インテグレーション・パイプラインを拡張して以下のコマンドを実行し、ビルド設定の変更が`.xcconfig` ファイルに直接行われるようにする：

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## パッケージの依存関係を抽出する{#extract-package-dependencies}

プロジェクトの依存関係をすべて、`Tuist/Package.swift` ファイルに展開します：

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

::: tip PRODUCT TYPES
<!-- -->
`PackageSettings` struct内の`productTypes`
dictionaryに追加することで、特定のパッケージの製品タイプをオーバーライドできます。デフォルトでは、Tuistはすべてのパッケージが静的フレームワークであると仮定しています。
<!-- -->
:::


## 移籍の順番を決める{#determine-the-migration-order}

依存関係の大きいものから小さいものへとターゲットを移行することをお勧めします。次のコマンドを使うと、プロジェクトのターゲットを依存関係の数でソートしてリストアップできます：

```bash
tuist migration list-targets -p Project.xcodeproj
```

リストの上位から移行を開始する。


## ターゲットの移行{#migrate-targets}

ターゲットを1つずつ移行する。変更をマージする前にレビューとテストを確実に行うために、ターゲットごとにプルリクエストを行うことを推奨します。

### ターゲットのビルド設定を`.xcconfig` ファイルに展開する。{#extract-the-target-build-settings-into-xcconfig-files}

プロジェクトのビルド設定で行ったように、ターゲットのビルド設定を`.xcconfig`
ファイルに抽出すると、ターゲットがスリムになり、移行しやすくなります。次のコマンドを使用して、ターゲットからビルド設定を`.xcconfig`
ファイルに抽出できます：

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### `Project.swift` ファイルでターゲットを定義する。{#define-the-target-in-the-projectswift-file}

`Project.targets` でターゲットを定義する：

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    settings: .settings(configurations: [
        .debug(name: "Debug", xcconfig: "./xcconfigs/Project.xcconfig"),
        .release(name: "Release", xcconfig: "./xcconfigs/Project.xcconfig"),
    ]),
    targets: [
        .target( // [!code ++]
            name: "TargetX", // [!code ++]
            destinations: .iOS, // [!code ++]
            product: .framework, // [!code ++] // or .staticFramework, .staticLibrary...
            bundleId: "dev.tuist.targetX", // [!code ++]
            sources: ["Sources/TargetX/**"], // [!code ++]
            dependencies: [ // [!code ++]
                /** Dependencies go here **/ // [!code ++]
                /** .external(name: "Kingfisher") **/ // [!code ++]
                /** .target(name: "OtherProjectTarget") **/ // [!code ++]
            ], // [!code ++]
            settings: .settings(configurations: [ // [!code ++]
                .debug(name: "Debug", xcconfig: "./xcconfigs/TargetX.xcconfig"), // [!code ++]
                .debug(name: "Release", xcconfig: "./xcconfigs/TargetX.xcconfig"), // [!code ++]
            ]) // [!code ++]
        ), // [!code ++]
    ]
)
```

::: info TEST TARGETS
<!-- -->
ターゲットに関連するテストターゲッ トがある場合は、`Project.swift` ファイルで定義し、同じ手順を繰り返します。
<!-- -->
:::

### ターゲット移行の検証{#validate-the-target-migration}

`tuist generate` に続いて、`xcodebuild build` を実行してプロジェクトがビルドされることを確認し、`tuist test`
を実行してテストがパスすることを確認する。さらに、[xcdiff](https://github.com/bloomberg/xcdiff)を使用して、生成されたXcodeプロジェクトを既存のものと比較し、変更が正しいことを確認できます。

### リピート{#repeat}

すべてのターゲットが完全に移行されるまで繰り返します。完了したら、`tuist generate` に続いて、`xcodebuild build`
と`tuist test` を使用してプロジェクトをビルドしてテストするように、CIとCDパイプラインを更新することをお勧めします。

## トラブルシューティング{#troubleshooting}

### ファイル不足によるコンパイルエラー。{#compilation-errors-due-to-missing-files}

Xcodeプロジェクトのターゲットに関連付けられたファイルが、ターゲットを表すファイルシステムディレクトリにすべて含まれていなかった場合、コンパイルできないプロジェクトになってしまうかもしれません。Tuistでプロジェクトを生成した後のファイルのリストがXcodeプロジェクトのファイルのリストと一致していることを確認し、この機会にファイル構造をターゲットの構造に合わせましょう。
