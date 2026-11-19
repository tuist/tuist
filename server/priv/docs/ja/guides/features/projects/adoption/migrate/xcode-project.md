---
{
  "title": "Xcode プロジェクトを移行する",
  "titleTemplate": ":title · 移行 · 導入 · プロジェクト · 機能 · ガイド · Tuist",
  "description": "Xcode プロジェクトを Tuist プロジェクトに移行する方法を学びます。"
}
---
# Xcodeプロジェクトの移行 {#migrate-an-xcode-project}

<.localized_link href="/guides/features/projects/adoption/new-project">Tuistを使用して新しいプロジェクトを作成する</.localized_link>場合を除き、すべてが自動的に構成されます。それ以外の場合は、Tuistのプリミティブを使用してXcodeプロジェクトを定義する必要があります。このプロセスの手間がかかるかどうかは、プロジェクトの複雑さによって異なります。

ご存知のとおり、Xcodeプロジェクトは時間とともに混乱し、複雑になる可能性があります。ディレクトリ構造と一致しないグループ、ターゲット間で共有されるファイル、存在しないファイルを指すファイル参照などです（一部を挙げると）。蓄積された複雑さにより、プロジェクトを確実に移行するコマンドを提供することが難しくなっています。

さらに、手動での移行はプロジェクトを整理し、簡素化するための優れた練習になります。プロジェクトの開発者だけでなく、処理とインデックス作成が高速化されるXcodeも恩恵を受けます。Tuistを完全に採用すると、プロジェクトが一貫して定義され、シンプルに保たれるようになります。

その作業を容易にするために、ユーザーから寄せられたフィードバックに基づいたガイドラインを提供します。

## プロジェクトのスキャフォールドを作成する {#create-project-scaffold}

まず、以下のTuistファイルを使用してプロジェクトのスキャフォールドを作成します。

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
        // You can read more about dependencies here: https://tuist.dev/en/docs/guides/features/projects/dependencies
    ]
)
```
<!-- -->
:::

`Project.swift`はプロジェクトを定義するマニフェストファイルであり、`Package.swift`は依存関係を定義するマニフェストファイルです。`Tuist.swift`ファイルでは、プロジェクトスコープのTuist設定を定義できます。

> [!TIP]
> **-Tuistサフィックス付きのプロジェクト名**
>
> 既存のXcodeプロジェクトとの競合を防ぐため、プロジェクト名に`-Tuist`サフィックスを追加することをお勧めします。プロジェクトをTuistに完全に移行したら、このサフィックスを削除できます。


## CIでTuistプロジェクトをビルドおよびテストする {#build-and-test-the-tuist-project-in-ci}

各変更の移行が有効であることを確認するために、継続的インテグレーションを拡張して、マニフェストファイルからTuistによって生成されたプロジェクトをビルドおよびテストすることをお勧めします。

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## プロジェクトのビルド設定を`.xcconfig`ファイルに抽出する {#extract-the-project-build-settings-into-xcconfig-files}

プロジェクトをより軽量にし、移行を容易にするために、プロジェクトのビルド設定を`.xcconfig`ファイルに抽出します。次のコマンドを使用して、プロジェクトのビルド設定を`.xcconfig`ファイルに抽出できます。


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

次に、`Project.swift`ファイルを更新して、作成したばかりの`.xcconfig`ファイルを指すようにします。

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    settings: .settings(configurations: [
        .debug(name: "Debug", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"),
        .release(name: "Release", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"),
    ]),
    targets: [
        /** Targets will go here **/
    ]
)
```

次に、継続的インテグレーションパイプラインを拡張して、次のコマンドを実行し、ビルド設定の変更が直接`.xcconfig`ファイルに行われることを確認します。

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## パッケージ依存関係を抽出する {#extract-package-dependencies}

プロジェクトのすべての依存関係を`Tuist/Package.swift`ファイルに抽出します。

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

> [!TIP]
> **プロダクトタイプ**
>
> `PackageSettings`構造体の`productTypes`ディクショナリに追加することで、特定のパッケージのプロダクトタイプを上書きできます。デフォルトでは、Tuistはすべてのパッケージが静的フレームワークであると想定しています。


## 移行順序を決定する {#determine-the-migration-order}

最も依存されているターゲットから最も依存されていないターゲットへと移行することをお勧めします。次のコマンドを使用して、依存関係の数でソートされたプロジェクトのターゲットを一覧表示できます。

```bash
tuist migration list-targets -p Project.xcodeproj
```

リストの先頭からターゲットの移行を開始してください。これらは最も依存されているターゲットです。


## ターゲットを移行する {#migrate-targets}

ターゲットを1つずつ移行します。変更をマージする前にレビューおよびテストされることを確認するため、各ターゲットに対してプルリクエストを作成することをお勧めします。

### ターゲットのビルド設定を`.xcconfig`ファイルに抽出する {#extract-the-target-build-settings-into-xcconfig-files}

プロジェクトのビルド設定で行ったのと同様に、ターゲットのビルド設定を`.xcconfig`ファイルに抽出して、ターゲットをより軽量にし、移行を容易にします。次のコマンドを使用して、ターゲットのビルド設定を`.xcconfig`ファイルに抽出できます。

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### `Project.swift`ファイルでターゲットを定義する {#define-the-target-in-the-projectswift-file}

`Project.targets`でターゲットを定義します。

```swift
import ProjectDescription

let project = Project(
    name: "MyApp",
    settings: .settings(configurations: [
        .debug(name: "Debug", xcconfig: "./xcconfigs/Project.xcconfig"),
        .release(name: "Release", xcconfig: "./xcconfigs/Project.xcconfig"),
    ]),
    targets: [
        .target(
            name: "TargetX",
            destinations: .iOS,
            product: .framework, // or .staticFramework, .staticLibrary...
            bundleId: "dev.tuist.targetX",
            sources: ["Sources/TargetX/**"],
            dependencies: [
                /** Dependencies go here **/
                /** .external(name: "Kingfisher") **/
                /** .target(name: "OtherProjectTarget") **/
            ],
            settings: .settings(configurations: [
                .debug(name: "Debug", xcconfig: "./xcconfigs/TargetX.xcconfig"),
                .release(name: "Release", xcconfig: "./xcconfigs/TargetX.xcconfig"),
            ])
        ),
    ]
)
```

> [!NOTE]
> **テストターゲット**
>
> ターゲットに関連付けられたテストターゲットがある場合は、同じ手順を繰り返して`Project.swift`ファイルでもそれを定義する必要があります。


### ターゲットの移行を検証する {#validate-the-target-migration}

`tuist generate`を実行し、続いて`xcodebuild build`を実行してプロジェクトがビルドされることを確認し、`tuist test`を実行してテストがパスすることを確認します。さらに、[xcdiff](https://github.com/bloomberg/xcdiff)を使用して、生成されたXcodeプロジェクトと既存のプロジェクトを比較し、変更が正しいことを確認できます。

### 繰り返す {#repeat}

すべてのターゲットが完全に移行されるまで繰り返します。完了したら、CIおよびCDパイプラインを更新して、`tuist generate`を実行し、続いて`xcodebuild build`および`tuist test`を使用してプロジェクトをビルドおよびテストすることをお勧めします。

## トラブルシューティング {#troubleshooting}

### ファイルが見つからないことによるコンパイルエラー {#compilation-errors-due-to-missing-files}

Xcodeプロジェクトのターゲットに関連付けられたファイルが、ターゲットを表すファイルシステムディレクトリにすべて含まれていない場合、コンパイルできないプロジェクトになってしまう可能性があります。Tuistでプロジェクトを生成した後のファイル一覧がXcodeプロジェクトのファイル一覧と一致していることを確認し、この機会にファイル構造をターゲット構造に合わせて整えてください。
