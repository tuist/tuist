---
{
  "title": "Migrate an Xcode project",
  "titleTemplate": ":title · Migrate · Adoption · Projects · Features · Guides · Tuist",
  "description": "Learn how to migrate an Xcode project to a Tuist project."
}
---
# Xcodeプロジェクトの移行{#migrate-an-xcode-project}

Tuist</LocalizedLink>を使用して新しいプロジェクトを<LocalizedLink href="/guides/features/projects/adoption/new-project">作成</LocalizedLink>する場合を除き、その場合はすべてが自動的に設定されますが、それ以外の場合はTuistのプリミティブを使用してXcodeプロジェクトを定義する必要があります。この作業がどれほど面倒かは、プロジェクトの複雑さによって異なります。

ご存知の通り、Xcodeプロジェクトは時間の経過とともに複雑で整理しづらくなることがあります。ディレクトリ構造と一致しないグループ、複数のターゲット間で共有されているファイル、存在しないファイルを指すファイル参照などがその一例です。こうした複雑さが蓄積されることで、プロジェクトを確実に移行できるコマンドを提供することが難しくなっています。

さらに、手動での移行作業は、プロジェクトを整理し、簡素化する絶好の機会となります。プロジェクトの開発者たちが感謝するだけでなく、Xcodeも処理やインデックス作成が高速化されます。Tuistを完全に導入すれば、プロジェクトが常に一貫した定義で維持され、シンプルさが保たれるようになります。

その作業を円滑に進めるため、ユーザーから寄せられたフィードバックをもとに、いくつかのガイドラインをご案内します。

## プロジェクトのスケルトンを作成する{#create-project-scaffold}

まず、以下のTuistファイルを使用して、プロジェクトの骨組みを作成してください：

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

`Project.swift` はプロジェクトを定義するマニフェストファイルであり、`Package.swift`
は依存関係を定義するマニフェストファイルです。`Tuist.swift` ファイルでは、プロジェクト固有の Tuist 設定を定義できます。

::: tip PROJECT NAME WITH -TUIST SUFFIX
<!-- -->
既存のXcodeプロジェクトとの競合を防ぐため、プロジェクト名に「`-Tuist`
」という接尾辞を追加することを推奨します。プロジェクトのTuistへの移行が完了したら、この接尾辞を削除しても構いません。
<!-- -->
:::

## CIでTuistプロジェクトをビルドおよびテストする{#build-and-test-the-tuist-project-in-ci}

各変更の移行が正しく行われるようにするため、マニフェストファイルからTuistによって生成されたプロジェクトをビルドおよびテストするように、継続的インテグレーションを拡張することをお勧めします：

```bash
tuist install
tuist generate
xcodebuild build {xcodebuild flags} # or tuist test
```

## プロジェクトのビルド設定を、` 、.xcconfig、` ファイルに抽出してください{#extract-the-project-build-settings-into-xcconfig-files}

プロジェクトからビルド設定を`.xcconfig`
ファイルに抽出することで、プロジェクトを軽量化し、移行を容易にします。以下のコマンドを使用して、プロジェクトからビルド設定を`.xcconfig`
ファイルに抽出できます：


```bash
mkdir -p xcconfigs/
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -x xcconfigs/MyApp-Project.xcconfig
```

次に、`のProject.swift` ファイルを更新し、先ほど作成した` の.xcconfig` ファイルを参照するように設定します：

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

次に、継続的インテグレーションパイプラインを拡張し、以下のコマンドを実行して、ビルド設定の変更が` の.xcconfigおよび`
ファイルに直接反映されるようにします：

```bash
tuist migration check-empty-settings -p Project.xcodeproj
```

## パッケージの依存関係を抽出する{#extract-package-dependencies}

プロジェクトの依存関係をすべて、`にあるTuist/Package.swift` ファイルに抽出してください：

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
特定のパッケージの製品タイプを上書きするには、`のPackageSettings` 構造体内の`productTypes`
辞書にそのパッケージを追加します。デフォルトでは、Tuistはすべてのパッケージを静的フレームワークとみなします。
<!-- -->
:::


## 移行順序を決定する{#determine-the-migration-order}

ターゲットは、依存関係が最も多いものから少ないものへと移行することを推奨します。以下のコマンドを使用すると、依存関係の数順に並べ替えてプロジェクトのターゲット一覧を表示できます：

```bash
tuist migration list-targets -p Project.xcodeproj
```

リストの上からターゲットの移行を開始してください。上にあるものほど依存度が高いためです。


## 移行対象{#migrate-targets}

ターゲットは1つずつ移行してください。変更内容をマージする前にレビューとテストが行われるよう、ターゲットごとにプルリクエストを作成することを推奨します。

### ターゲットのビルド設定を、` 、.xcconfig、` ファイルに抽出してください{#extract-the-target-build-settings-into-xcconfig-files}

プロジェクトのビルド設定と同様に、ターゲットのビルド設定を`.xcconfig`
ファイルに抽出することで、ターゲットを軽量化し、移行を容易にします。以下のコマンドを使用して、ターゲットからビルド設定を`.xcconfig`
ファイルに抽出できます:

```bash
tuist migration settings-to-xcconfig -p MyApp.xcodeproj -t TargetX -x xcconfigs/TargetX.xcconfig
```

### `プロジェクトのProject.swift` ファイルでターゲットを定義してください{#define-the-target-in-the-projectswift-file}

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
ターゲットに関連付けられたテストターゲットがある場合は、`Project.swift` ファイルでも、同様の手順を繰り返して定義する必要があります。
<!-- -->
:::

### 移行先の検証{#validate-the-target-migration}

`、tuist generate` 、`、xcodebuild build` の順に実行してプロジェクトがビルドされることを確認し、`、tuist test`
を実行してテストが成功することを確認してください。さらに、[xcdiff](https://github.com/bloomberg/xcdiff)
を使用して生成された Xcode プロジェクトと既存のプロジェクトを比較し、変更内容が正しいことを確認することもできます。

### 繰り返し{#repeat}

すべてのターゲットが完全に移行されるまで、この手順を繰り返してください。完了したら、CIおよびCDパイプラインを更新し、`tuist generate`
、続いて`xcodebuild build` 、そして`tuist test` を使用してプロジェクトをビルドおよびテストすることをお勧めします。

## トラブルシューティング{#troubleshooting}

### ファイルが見つからないことによるコンパイルエラー。{#compilation-errors-due-to-missing-files}

Xcodeプロジェクトのターゲットに関連付けられたファイルが、そのターゲットを表すファイルシステム上のディレクトリにすべて含まれていない場合、プロジェクトがコンパイルできなくなる可能性があります。Tuistでプロジェクトを生成した後のファイル一覧が、Xcodeプロジェクト内のファイル一覧と一致していることを確認し、この機会にファイル構造をターゲット構造に合わせて整えてください。
