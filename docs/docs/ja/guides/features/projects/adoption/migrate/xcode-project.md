---
{
  "title": "Migrate an Xcode project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate an Xcode project to a Tuist project."
}
---
# Xcodeプロジェクトを移行する{#migrate-an-xcode-project}

Tuistを使用して新しいプロジェクトを作成しない限り<LocalizedLink href="/guides/features/projects/adoption/new-project">、すべての設定が自動的に行われます。Tuistのプリミティブを使用してXcodeプロジェクトを定義する必要があります。このプロセスの煩雑さは、プロジェクトの複雑さに依存します。

ご存知かもしれませんが、Xcodeプロジェクトは時間の経過とともに複雑で混乱しがちです：ディレクトリ構造と一致しないグループ、複数のターゲット間で共有されるファイル、存在しないファイルを参照するファイル参照（一部を挙げると）などです。こうした複雑さの蓄積により、プロジェクトを確実に移行するコマンドを提供することが困難になっています。

さらに、手動での移行はプロジェクトを整理し簡素化する優れた練習となります。プロジェクトの開発者だけでなく、処理やインデックス作成が高速化するXcodeも感謝するでしょう。Tuistを完全に導入すれば、プロジェクトが一貫して定義され、シンプルに保たれることが保証されます。

この作業を容易にするため、ユーザーから寄せられたフィードバックに基づき、いくつかのガイドラインを提供します。

## プロジェクトの骨組みを作成する{#create-project-scaffold}

まず、以下のTuistファイルでプロジェクトの骨組みを作成してください：

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

`Project.swift` はプロジェクトを定義するマニフェストファイルです。`Package.swift`
は依存関係を定義するマニフェストファイルです。`Tuist.swift` ファイルでは、プロジェクト全体のTuist設定を定義できます。

::: tip PROJECT NAME WITH -TUIST SUFFIX
<!-- -->
既存のXcodeプロジェクトとの競合を防ぐため、プロジェクト名に「`-Tuist`
」のサフィックスを追加することを推奨します。プロジェクトをTuistへ完全に移行した後は、このサフィックスを削除できます。
<!-- -->
:::

## CIでTuistプロジェクトをビルドおよびテストする{#build-and-test-the-tuist-project-in-ci}

各変更の移行が有効であることを確認するため、マニフェストファイルからTuistが生成したプロジェクトをビルドおよびテストする継続的インテグレーションの拡張を推奨します：

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## プロジェクトのビルド設定を`.xcconfig、` ファイルに抽出する{#extract-the-project-build-settings-into-xcconfig-files}

プロジェクトからビルド設定を抽出して、`.xcconfig`
ファイルに保存すると、プロジェクトがスリム化され移行が容易になります。プロジェクトからビルド設定を抽出して`.xcconfig`
ファイルに保存するには、次のコマンドを使用できます：


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

次に、`プロジェクトのProject.swiftファイルと` ファイルを更新し、先ほど作成した`.xcconfigファイルと` ファイルを指すように設定します：

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

次に、継続的インテグレーションパイプラインを拡張し、以下のコマンドを実行してビルド設定の変更が直接 ``.xcconfig` および `` `
ファイルに反映されるようにします：

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## パッケージ依存関係を抽出する{#extract-package-dependencies}

`プロジェクトの依存関係をすべて、`Tuist/Package.swift` ファイル（`` `）に抽出してください：

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
` 特定のパッケージの製品タイプを上書きするには、`の PackageSettings 構造体内の` 辞書に、`の productTypes
を追加します。デフォルトでは、Tuist はすべてのパッケージが静的フレームワークであると想定します。
<!-- -->
:::


## 移行順序を決定する{#determine-the-migration-order}

依存関係が最も強いターゲットから弱い順に移行することを推奨します。プロジェクトのターゲットを依存関係の数で並べ替えて一覧表示するには、次のコマンドを使用できます：

```bash
tuist migration list-targets -p Project.xcodeproj
```

リストの上部からターゲットの移行を開始してください。これらは最も依存度の高いものだからです。


## 移行対象{#migrate-targets}

各ターゲットを順次移行してください。変更内容をマージする前にレビューとテストが行われるよう、各ターゲットごとにプルリクエストを提出することを推奨します。

### ターゲットビルド設定を抽出する`.xcconfig` ファイル{#extract-the-target-build-settings-into-xcconfig-files}

プロジェクトのビルド設定と同様に、ターゲットのビルド設定を`.xcconfig`
ファイルに抽出することで、ターゲットをスリム化し移行を容易にします。以下のコマンドでターゲットからビルド設定を`.xcconfig` ファイルに抽出できます：

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### `プロジェクトのProject.swiftファイルでターゲットを定義してください。` {#define-the-target-in-the-projectswift-file}

`のProject.targetsでターゲットを定義します。`:

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
ターゲットに関連付けられたテストターゲットがある場合、同じ手順を繰り返して、`/Project.swift/` ファイルにも定義する必要があります。
<!-- -->
:::

### 移行先の検証{#validate-the-target-migration}

`tuist generate` を実行し、続いて`xcodebuild build` を実行してプロジェクトがビルドされることを確認し、`tuist
test` を実行してテストがパスすることを確認してください。さらに、[xcdiff](https://github.com/bloomberg/xcdiff)
を使用して生成された Xcode プロジェクトと既存のプロジェクトを比較し、変更が正しいことを確認できます。

### Repeat{#repeat}

すべてのターゲットが完全に移行されるまで繰り返してください。完了後、CI/CDパイプラインを更新し、`tuist generate`
を実行してプロジェクトをビルド・テストし、続いて`xcodebuild build` および`tuist test` を実行することを推奨します。

## トラブルシューティング{#troubleshooting}

### ファイル不足によるコンパイルエラー。{#compilation-errors-due-to-missing-files}

Xcodeプロジェクトのターゲットに関連付けられたファイルが、ターゲットを表すファイルシステムディレクトリ内にすべて含まれていない場合、コンパイルできないプロジェクトになる可能性があります。Tuistでプロジェクトを生成した後のファイルリストがXcodeプロジェクト内のファイルリストと一致していることを確認し、この機会にファイル構造をターゲット構造に合わせてください。
