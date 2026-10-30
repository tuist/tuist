---
{
  "title": "Xcodeプロジェクトの移行",
  "titleTemplate": ":title · 移行 · 導入 · プロジェクト · 機能 · ガイド · Tuist",
  "description": "XcodeプロジェクトをTuistプロジェクトに移行する方法を学びます。"
}
---
# Xcode プロジェクトの移行 {#migrate-an-xcode-project}

<.localized_link href="/guides/features/projects/adoption/new-project">Tuist を使用して新しいプロジェクトを作成</.localized_link>する場合を除き、すべてが自動的に構成されます。それ以外の場合は、Tuist のプリミティブを使用して Xcode プロジェクトを定義する必要があります。このプロセスの手間のかかり方は、プロジェクトの複雑さに依存します。

ご存知のとおり、Xcode プロジェクトは時間とともに煩雑で複雑になることがあります。ディレクトリ構造と一致しないグループ、ターゲット間で共有されるファイル、存在しないファイルを指すファイル参照などがその例です。蓄積されたこうした複雑さにより、プロジェクトを確実に移行できるコマンドを提供することが難しくなっています。

さらに、手動での移行はプロジェクトを整理・簡素化するための優れた練習になります。プロジェクトの開発者だけでなく、処理やインデックス作成が高速化される Xcode も恩恵を受けます。Tuist を完全に導入すると、プロジェクトが一貫して定義され、シンプルに保たれるようになります。

この作業を容易にするために、ユーザーから寄せられたフィードバックに基づいたガイドラインを紹介します。

## プロジェクトのスキャフォールドを作成する {#create-project-scaffold}

まず、以下の Tuist ファイルを使用してプロジェクトのスキャフォールドを作成します。

::: code-group

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

`Project.swift` はプロジェクトを定義するマニフェストファイルであり、`Package.swift` は依存関係を定義するマニフェストファイルです。`Tuist.swift` ファイルでは、プロジェクトスコープの Tuist 設定を定義できます。

> [!TIP]
> **プロジェクト名に -tuist サフィックスを追加**
>
> 既存の Xcode プロジェクトとの競合を防ぐため、プロジェクト名に `-Tuist` サフィックスを追加することをお勧めします。プロジェクトの Tuist への移行が完了したら、このサフィックスは削除できます。


## CI で Tuist プロジェクトをビルドおよびテストする {#build-and-test-the-tuist-project-in-ci}

各変更の移行が有効であることを確認するため、継続的インテグレーションを拡張して、マニフェストファイルから Tuist によって生成されたプロジェクトをビルドおよびテストすることをお勧めします。

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## プロジェクトのビルド設定を `.xcconfig` ファイルに抽出する {#extract-the-project-build-settings-into-xcconfig-files}

プロジェクトを軽量で移行しやすい状態にするため、ビルド設定をプロジェクトから `.xcconfig` ファイルに抽出します。次のコマンドを使用して、プロジェクトのビルド設定を `.xcconfig` ファイルに抽出できます。


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

次に、`Project.swift` ファイルを更新して、作成したばかりの `.xcconfig` ファイルを指すようにします。

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

次に、継続的インテグレーションパイプラインを拡張して次のコマンドを実行し、ビルド設定の変更が直接 `.xcconfig` ファイルに行われることを確認します。

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## パッケージ依存関係を抽出する {#extract-package-dependencies}

プロジェクトのすべての依存関係を `Tuist/Package.swift` ファイルに抽出します。

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

> [!TIP]
> **プロダクトタイプ**
>
> `PackageSettings` 構造体の `productTypes` ディクショナリに追加することで、特定のパッケージのプロダクトタイプを上書きできます。デフォルトでは、Tuist はすべてのパッケージがスタティックフレームワークであると想定します。


## 移行順序を決定する {#determine-the-migration-order}

最も依存されているターゲットから順に、依存度が低いターゲットへと移行することをお勧めします。次のコマンドを使用すると、依存関係の数でソートされたプロジェクトのターゲットを一覧表示できます。

```bash
tuist migration list-targets -p Project.xcodeproj
```

リストの上位からターゲットの移行を開始してください。これらは最も他から依存されているターゲットです。


## ターゲットを移行する {#migrate-targets}

ターゲットを一つずつ移行します。変更をマージする前にレビューおよびテストが行われるよう、各ターゲットごとにプルリクエストを作成することをお勧めします。

### ターゲットのビルド設定を `.xcconfig` ファイルに抽出する {#extract-the-target-build-settings-into-xcconfig-files}

プロジェクトのビルド設定と同様に、ターゲットのビルド設定を `.xcconfig` ファイルに抽出して、ターゲットを軽量で移行しやすい状態にします。次のコマンドを使用して、ターゲットのビルド設定を `.xcconfig` ファイルに抽出できます。

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### `Project.swift` ファイルでターゲットを定義する {#define-the-target-in-the-projectswift-file}

`Project.targets` でターゲットを定義します。

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

> [!NOTE]
> **テストターゲット**
>
> ターゲットに関連付けられたテストターゲットがある場合は、同じ手順を繰り返して `Project.swift` ファイルでも定義する必要があります。


### ターゲットの移行を検証する {#validate-the-target-migration}

プロジェクトがビルドされることを確認するために `tuist generate` を実行し、続いて `xcodebuild build` を実行します。また、`tuist test` を実行してテストがパスすることを確認します。さらに、[xcdiff](https://github.com/bloomberg/xcdiff) を使用して生成された Xcode プロジェクトと既存のプロジェクトを比較し、変更が正しいことを確認できます。

### 繰り返す {#repeat}

すべてのターゲットが完全に移行されるまで繰り返します。完了したら、CI および CD パイプラインを更新して、`tuist generate` に続いて `xcodebuild build` および `tuist test` を使用してプロジェクトをビルドおよびテストすることをお勧めします。

## トラブルシューティング {#troubleshooting}

### ファイル不足によるコンパイルエラー {#compilation-errors-due-to-missing-files}

Xcode プロジェクトのターゲットに関連付けられたファイルが、ターゲットを表すファイルシステムディレクトリ内にすべて含まれていない場合、コンパイルできないプロジェクトになってしまう可能性があります。Tuist でプロジェクトを生成した後のファイル一覧が Xcode プロジェクト内のファイル一覧と一致していることを確認し、この機会にファイル構造をターゲット構造に合わせて整えてください。
