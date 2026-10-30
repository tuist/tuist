---
{
  "title": "Xcode プロジェクトを移行する",
  "titleTemplate": ":title · 移行 · 導入 · プロジェクト · 機能 · ガイド · Tuist",
  "description": "Xcode プロジェクトを Tuist プロジェクトに移行する方法を学びます。"
}
---
# Xcode プロジェクトを移行する {#migrate-an-xcode-project}

<.localized_link href="/guides/features/projects/adoption/new-project">Tuistを使って新規プロジェクトを作成する</.localized_link>場合を除き、すべてが自動的に構成されます。それ以外の場合は、Tuistのプリミティブを使用してXcodeプロジェクトを定義する必要があります。この作業の手間は、プロジェクトの複雑さによって異なります。

ご存知のとおり、Xcodeプロジェクトは時間とともに煩雑で複雑になりがちです。ディレクトリ構造と一致しないグループ、複数のターゲットで共有されるファイル、存在しないファイルを指すファイル参照などがその例です。こうした蓄積された複雑さにより、プロジェクトを確実に移行できるコマンドを提供することが難しくなっています。

さらに、手動での移行はプロジェクトの整理と簡素化を行う優れた機会です。プロジェクトに関わる開発者だけでなく、処理やインデックス作成が高速化されるXcode側も恩恵を受けます。Tuistを完全に導入すれば、プロジェクトの一貫した定義と簡潔な状態が維持されます。

この作業を容易にするため、ユーザーからのフィードバックに基づいたガイドラインを紹介します。

## プロジェクトのスケルトンを作成する {#create-project-scaffold}

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
        // You can read more about dependencies here: https://docs.tuist.io/documentation/tuist/dependencies
    ]
)
```
<!-- -->
:::

`Project.swift`はプロジェクトを定義するマニフェストファイル、`Package.swift`は依存関係を定義するマニフェストファイルです。`Tuist.swift`ファイルでは、プロジェクトスコープのTuist設定を定義できます。

> [!TIP]
> **プロジェクト名に-tuistサフィックスを追加**
>
> 既存のXcodeプロジェクトとの競合を防ぐため、プロジェクト名に`-Tuist`サフィックスを追加することを推奨します。プロジェクトのTuistへの移行が完了したら、このサフィックスは削除できます。


## CI で Tuist プロジェクトをビルドおよびテストする {#build-and-test-the-tuist-project-in-ci}

各変更の移行が有効であることを確認するため、継続的インテグレーションを拡張して、マニフェストファイルからTuistが生成したプロジェクトのビルドとテストを実行することを推奨します。

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## プロジェクトのビルド設定を `.xcconfig` ファイルに抽出する {#extract-the-project-build-settings-into-xcconfig-files}

プロジェクトを軽量で移行しやすくするため、ビルド設定をプロジェクトから`.xcconfig`ファイルに抽出します。次のコマンドを使用すると、プロジェクトのビルド設定を`.xcconfig`ファイルに抽出できます。


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
        .debug(name: "Debug", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"), // [!code ++]
        .release(name: "Release", xcconfig: "./xcconfigs/MyApp-Project.xcconfig"), // [!code ++]
    ]),
    targets: [
        /** Targets will go here **/
    ]
)
```

さらに、継続的インテグレーションパイプラインを拡張して次のコマンドを実行し、ビルド設定の変更が直接`.xcconfig`ファイルに行われるようにします。

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## パッケージの依存関係を抽出する {#extract-package-dependencies}

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
        // You can read more about dependencies here: https://docs.tuist.io/documentation/tuist/dependencies
        .package(url: "https://github.com/onevcat/Kingfisher", .upToNextMajor(from: "7.12.0")) // [!code ++]
    ]
)
```

> [!TIP]
> **プロダクトタイプ**
>
> 特定のパッケージのプロダクトタイプを上書きするには、`PackageSettings`構造体の`productTypes`ディクショナリに追加します。デフォルトでは、Tuistはすべてのパッケージをスタティックフレームワークとして扱います。


## 移行順序を決定する {#determine-the-migration-order}

依存関係が最も多いターゲットから少ない順に移行することを推奨します。次のコマンドを使用すると、依存関係の数でソートされたプロジェクトのターゲット一覧を取得できます。

```bash
tuist migration list-targets -p Project.xcodeproj
```

リストの上位からターゲットの移行を開始してください。これらは他から最も依存されているターゲットです。


## ターゲットを移行する {#migrate-targets}

ターゲットを1つずつ移行します。変更をマージする前にレビューとテストが行われるよう、各ターゲットごとにプルリクエストを作成することを推奨します。

### ターゲットのビルド設定を `.xcconfig` ファイルに抽出する {#extract-the-target-build-settings-into-xcconfig-files}

プロジェクトのビルド設定と同様に、ターゲットのビルド設定を`.xcconfig`ファイルに抽出して、ターゲットを軽量で移行しやすくします。次のコマンドを使用すると、ターゲットのビルド設定を`.xcconfig`ファイルに抽出できます。

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### `Project.swift` ファイルでターゲットを定義する {#define-the-target-in-the-projectswift-file}

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
> ターゲットに関連付けられたテストターゲットがある場合は、同じ手順を繰り返して`Project.swift`ファイルで定義してください。


### ターゲットの移行を検証する {#validate-the-target-migration}

プロジェクトがビルドされることを確認するために`tuist generate`を実行し、続いて`xcodebuild build`を実行します。また、`tuist test`を実行してテストがパスすることを確認します。さらに、[xcdiff](https://github.com/bloomberg/xcdiff)を使用して生成されたXcodeプロジェクトと既存のプロジェクトを比較し、変更が正しいことを確認できます。

### 繰り返す {#repeat}

すべてのターゲットの移行が完了するまで繰り返します。完了したら、CIおよびCDパイプラインを更新して、`tuist generate`を実行し、続いて`xcodebuild build`および`tuist test`を使用してプロジェクトのビルドとテストを行うことを推奨します。

## トラブルシューティング {#troubleshooting}

### ファイルが不足していることによるコンパイルエラー {#compilation-errors-due-to-missing-files}

Xcodeプロジェクトのターゲットに関連付けられたファイルが、ターゲットを表すファイルシステムディレクトリにすべて含まれていない場合、コンパイルできないプロジェクトになってしまう可能性があります。Tuistでプロジェクトを生成した後のファイル一覧がXcodeプロジェクトのファイル一覧と一致していることを確認し、この機会にファイル構造をターゲット構造に合わせて整理してください。
