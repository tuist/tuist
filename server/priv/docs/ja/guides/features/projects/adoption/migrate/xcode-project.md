---
{
  "title": "Xcode プロジェクトの移行",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Xcode プロジェクトを Tuist プロジェクトに移行する方法を学びます。"
}
---
# Xcode プロジェクトを移行する {#migrate-an-xcode-project}

<.localized_link href="/guides/features/projects/adoption/new-project">Tuist を使って新しいプロジェクトを作成する</.localized_link>場合を除き、その場合はすべて自動的に構成されますが、Tuist のプリミティブを使って Xcode プロジェクトを定義する必要があります。この作業の手間がかかるかどうかは、プロジェクトの複雑さによります。

ご存知のとおり、Xcode プロジェクトは時間とともに煩雑で複雑になりがちです。ディレクトリ構造と一致しないグループ、複数のターゲットで共有されるファイル、存在しないファイルを指すファイル参照などが挙げられます。こうした蓄積された複雑さにより、プロジェクトを確実に移行できるコマンドを提供することが難しくなっています。

さらに、手動での移行はプロジェクトの整理と簡素化を図る優れた機会です。プロジェクトの開発者だけでなく、処理やインデックス作成が高速化される Xcode にも役立ちます。Tuist を完全に導入すれば、プロジェクトが一貫して定義され、シンプルさを維持できるようになります。

この作業を容易にするため、ユーザーから寄せられたフィードバックに基づいたガイドラインを提供します。

## プロジェクトのスケルトンを作成する {#create-project-scaffold}

まず、以下の Tuist ファイルを使ってプロジェクトのスキャフォールドを作成します。

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

`Project.swift` はプロジェクトを定義するマニフェストファイルであり、`Package.swift` は依存関係を定義するマニフェストファイルです。`Tuist.swift` ファイルでは、プロジェクトスコープの Tuist 設定を定義できます。

> [!TIP]
> **プロジェクト名に -Tuist サフィックスを追加**
>
> 既存の Xcode プロジェクトとの競合を防ぐため、プロジェクト名に `-Tuist` サフィックスを追加することを推奨します。プロジェクトを Tuist に完全に移行し終えたら、このサフィックスは削除できます。


## CI で Tuist プロジェクトをビルド・テストする {#build-and-test-the-tuist-project-in-ci}

各変更の移行が有効であることを確認するため、継続的インテグレーションを拡張して、マニフェストファイルから Tuist が生成したプロジェクトをビルドおよびテストすることを推奨します。

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## プロジェクトのビルド設定を `.xcconfig` ファイルに抽出する {#extract-the-project-build-settings-into-xcconfig-files}

プロジェクトを軽量かつ移行しやすくするため、プロジェクトのビルド設定を `.xcconfig` ファイルに抽出します。プロジェクトのビルド設定を `.xcconfig` ファイルに抽出するには、次のコマンドを使用できます。


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
        .debug(name: "Debug", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"),
        .release(name: "Release", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"),
    ]),
    targets: [
        /** Targets will go here **/
    ]
)
```

その後、継続的インテグレーションパイプラインを拡張して次のコマンドを実行し、ビルド設定の変更が直接 `.xcconfig` ファイルに行われるようにします。

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## パッケージの依存関係を抽出する {#extract-package-dependencies}

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
        // You can read more about dependencies here: https://tuist.dev/en/docs/guides/features/projects/dependencies
        .package(url: "https://github.com/onevcat/Kingfisher", .upToNextMajor(from: "7.12.0"))
    ]
)
```

> [!TIP]
> **プロダクトタイプ**
>
> 特定のパッケージのプロダクトタイプを上書きするには、`PackageSettings` 構造体の `productTypes` ディクショナリに追加します。デフォルトでは、Tuist はすべてのパッケージをスタティックフレームワークとして扱います。


## 移行順序を決定する {#determine-the-migration-order}

最も依存されているターゲットから順に、依存度が低いものへと移行することを推奨します。次のコマンドを使用して、依存関係の数でソートされたプロジェクトのターゲットを一覧表示できます。

```bash
tuist migration list-targets -p Project.xcodeproj
```

リストの上位からターゲットの移行を開始してください。これらは最も他から依存されているターゲットです。


## ターゲットの移行 {#migrate-targets}

ターゲットを 1 つずつ移行します。変更をマージする前にレビューおよびテストが行われるよう、各ターゲットごとにプルリクエストを作成することを推奨します。

### ターゲットのビルド設定を `.xcconfig` ファイルに抽出する {#extract-the-target-build-settings-into-xcconfig-files}

プロジェクトのビルド設定と同様に、ターゲットを軽量かつ移行しやすくするため、ターゲットのビルド設定を `.xcconfig` ファイルに抽出します。ターゲットのビルド設定を `.xcconfig` ファイルに抽出するには、次のコマンドを使用できます。

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
> ターゲットに関連付けられたテストターゲットがある場合は、同じ手順を繰り返して `Project.swift` ファイルでも定義してください。


### ターゲットの移行を検証する {#validate-the-target-migration}

プロジェクトがビルドされることを確認するため `tuist generate` を実行し、続いて `xcodebuild build` を実行します。また、テストがパスすることを確認するため `tuist test` を実行します。さらに、[xcdiff](https://github.com/bloomberg/xcdiff) を使用して生成された Xcode プロジェクトと既存のプロジェクトを比較し、変更が正しいことを確認できます。

### 繰り返す {#repeat}

すべてのターゲットが完全に移行されるまで繰り返します。完了したら、CI および CD パイプラインを更新して、`tuist generate` を実行し、続いて `xcodebuild build` および `tuist test` を使用してプロジェクトをビルドおよびテストすることを推奨します。

## トラブルシューティング {#troubleshooting}

### ファイルが不足していることによるコンパイルエラー {#compilation-errors-due-to-missing-files}

Xcode プロジェクトのターゲットに関連付けられたファイルが、ターゲットを表すファイルシステムディレクトリにすべて含まれていない場合、コンパイルできないプロジェクトになってしまう可能性があります。Tuist でプロジェクトを生成した後のファイル一覧が Xcode プロジェクト内のファイル一覧と一致していることを確認し、この機会にファイル構造をターゲット構造に合わせて整えてください。
