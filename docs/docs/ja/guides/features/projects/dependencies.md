---
{
  "title": "Dependencies",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to declare dependencies in your Tuist project."
}
---
# 依存関係 {#dependencies}

プロジェクトが大きくなると、コードを共有し、境界を定義し、ビルド時間を改善するために、複数のターゲットに分割するのが一般的である。複数のターゲットとは、**依存関係グラフ**
を形成する、ターゲット間の依存関係を定義することを意味する。

## XcodeProjでコード化されたグラフ{#xcodeprojcodified-graphs}

Xcode と XcodeProj
の設計のために、依存関係グラフのメンテナンスは、面倒でエラーが発生しやすい作業になることがあります。以下は、あなたが遭遇するかもしれない問題のいくつかの例です：

- Xcode
  のビルドシステムは、派生データの同じディレクトリにプロジェクトのすべての製品を出力するので、ターゲットは、インポートすべきではない製品をインポートできるかもしれません。コンパイルは、クリーンビルドがより一般的である
  CI で失敗するかもしれません。
- ターゲットの推移的動的依存関係は、`LD_RUNPATH_SEARCH_PATHS`
  ビルド設定の一部であるいずれかのディレクトリにコピーされる必要がある。そうしないと、ターゲットは実行時にそれらを見つけることができない。これは、グラフが小さいうちは考えやすく設定しやすいが、グラフが大きくなると問題になる。
- ターゲットが静的な[XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle)をリンクするとき、ターゲットはXcodeがバンドルを処理し、現在のプラットフォームとアーキテクチャのための正しいバイナリを抽出するために、追加のビルドフェーズを必要とします。このビルドフェーズは、自動的に追加されません。

上記はほんの一例に過ぎませんが、私たちが長年にわたって遭遇してきた例は他にもたくさんあります。依存関係グラフを維持し、その妥当性を保証するためにエンジニアのチームが必要だとしたらどうだろう。あるいは、さらに悪いことに、あなたがコントロールもカスタマイズもできないクローズドソースのビルドシステムによって、ビルド時に複雑さが解決されていたとします。聞き覚えがあるだろうか？これは、AppleがXcodeとXcodeProjで取ったアプローチであり、Swiftパッケージマネージャが受け継いだものです。

依存関係グラフは、**明示的であるべきであり、** 、**静的であるべきである、** そうであってこそ、**検証されたものであるべきであり、**
、**最適化されたものであるべきである、**
と私たちは強く信じている。Tuistを使えば、あなたは何が何に依存するかを記述することに集中し、残りは私たちが引き受ける。複雑さや実装の詳細は抽象化されます。

以下のセクションでは、プロジェクトで依存関係を宣言する方法を学びます。

::: tip GRAPH VALIDATION
<!-- -->
Tuistはプロジェクト生成時にグラフを検証し、サイクルがなく、すべての依存関係が有効であることを確認する。このおかげで、どのチームも依存関係グラフを壊す心配をすることなく、その進化に参加することができる。
<!-- -->
:::

## ローカルな依存関係{#local-dependencies}

ターゲットは、同じプロジェクトや異なるプロジェクトの他のターゲット、およびバイナリに依存することができます。`Target`
をインスタンス化するとき、`dependencies` 引数に以下のいずれかのオプションを渡すことができます：

- `ターゲット` ：同じプロジェクト内のターゲットとの依存関係を宣言します。
- `プロジェクト` ：別のプロジェクトのターゲットとの依存関係を宣言します。
- `フレームワーク` ：バイナリフレームワークとの依存関係を宣言する。
- `ライブラリ` ：バイナリライブラリとの依存関係を宣言する。
- `XCFramework` ：バイナリのXCFrameworkとの依存関係を宣言する。
- `SDK` ：システムSDKとの依存関係を宣言します。
- `XCTest` ：XCTestとの依存関係を宣言。

::: info DEPENDENCY CONDITIONS
<!-- -->
すべての依存関係タイプは、プラットフォームに基づいて依存関係を条件付きでリンクするために、`条件`
オプションを受け入れます。デフォルトでは、ターゲットがサポートするすべてのプラットフォームに対して依存関係をリンクします。
<!-- -->
:::

## 外部依存{#external-dependencies}

Tuistでは、プロジェクト内で外部依存関係を宣言することもできる。

### スイフト・パッケージ{#swift-packages}

Swift
Packagesは、あなたのプロジェクトで依存関係を宣言する私たちの推奨する方法です。あなたは、Xcodeのデフォルトの統合メカニズムを使用するか、TuistのXcodeProjベースの統合を使用してそれらを統合することができます。

#### TuistのXcodeProjベースの統合{#tuists-xcodeprojbased-integration}

Xcodeのデフォルトの統合は最も便利なものではあるが、中規模や大規模のプロジェクトに必要な柔軟性とコントロールに欠けている。これを克服するために、TuistはXcodeProjベースの統合を提供しており、XcodeProjのターゲットを使用してプロジェクトにSwift
Packagesを統合することができます。そのおかげで、統合をよりコントロールできるだけでなく、<LocalizedLink href="/guides/features/cache">キャッシュ</LocalizedLink>や<LocalizedLink href="/guides/features/test/selective-testing">選択的テスト実行</LocalizedLink>のようなワークフローと互換性を持たせることができます。

XcodeProjの統合は、新しいSwift
Packageの機能をサポートしたり、より多くのパッケージ構成を扱うために、より多くの時間がかかる可能性があります。しかし、Swift パッケージと
XcodeProj
ターゲット間のマッピングロジックは、オープンソースであり、コミュニティによって貢献することができます。これは、クローズドソースでAppleによって維持されているXcodeのデフォルトの統合とは対照的です。

外部の依存関係を追加するには、`Tuist/` の下か、プロジェクトのルートに`Package.swift` を作成する必要があります。

コードグループ
```swift [Tuist/Package.swift]
// swift-tools-version: 5.9
import PackageDescription

#if TUIST
    import ProjectDescription
    import ProjectDescriptionHelpers

    let packageSettings = PackageSettings(
        productTypes: [
            "Alamofire": .framework, // default is .staticFramework
        ]
    )

#endif

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/Alamofire/Alamofire", from: "5.0.0"),
    ],
    targets: [
        .binaryTarget(
            name: "Sentry",
            url: "https://github.com/getsentry/sentry-cocoa/releases/download/8.40.1/Sentry.xcframework.zip",
            checksum: "db928e6fdc30de1aa97200576d86d467880df710cf5eeb76af23997968d7b2c7"
        ),
    ]
)
```
<!-- -->
:::

::: tip PACKAGE SETTINGS
<!-- -->
`PackageSettings`
インスタンスをコンパイラディレクティブでラップすると、パッケージの統合方法を設定できます。例えば、上の例では、パッケージに使われるデフォルトのプロダクトタイプを上書きするために使われています。デフォルトでは、これは必要ありません。
<!-- -->
:::

> [!IMPORTANT] CUSTOM BUILD CONFIGURATIONS プロジェクトでカスタムビルド設定（標準の`Debug`
> と`Release` 以外の設定）を使用する場合は、`baseSettings` を使用して`PackageSettings`
> で指定する必要があります。外部依存関係は、正しくビルドするために、プロジェクトの設定を知る必要があります。例えば
> 
> ```swift
> #if TUIST
>     import ProjectDescription
> 
>     let packageSettings = PackageSettings(
>         productTypes: [:],
>         baseSettings: .settings(configurations: [
>             .debug(name: "Base"),
>             .release(name: "Production")
>         ])
>     )
> #endif
> ```
> 
> 詳しくは[#8345](https://github.com/tuist/tuist/issues/8345)を参照。

`Package.swift`
ファイルは、外部依存関係を宣言するためのインターフェースであり、それ以外のものではありません。そのため、パッケージではターゲットやプロダクトを定義しません。依存関係を定義したら、次のコマンドを実行して依存関係を解決し、`Tuist/Dependencies`
ディレクトリに引き込むことができます：

```bash
tuist install
# Resolving and fetching dependencies. {#resolving-and-fetching-dependencies}
# Installing Swift Package Manager dependencies. {#installing-swift-package-manager-dependencies}
```

お気づきかもしれませんが、私たちは[CocoaPods](https://cocoapods.org)のようなアプローチをとっています。これにより、依存関係を解決して更新するタイミングをユーザーがコントロールすることができ、プロジェクトでXcodeを開いてコンパイルする準備ができます。これは、AppleのSwiftパッケージマネージャとの統合によって提供される開発者の体験が、プロジェクトが成長するにつれて低下すると私たちが考えている領域です。

プロジェクトのターゲットから、`TargetDependency.external` 依存関係タイプを使用して、これらの依存関係を参照できます：

コードグループ
```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "App",
    organizationName: "tuist.io",
    targets: [
        .target(
            name: "App",
            destinations: [.iPhone],
            product: .app,
            bundleId: "dev.tuist.app",
            deploymentTargets: .iOS("13.0"),
            infoPlist: .default,
            sources: ["Targets/App/Sources/**"],
            dependencies: [
                .external(name: "Alamofire"), // [!code ++]
            ]
        ),
    ]
)
```
<!-- -->
:::

::: info NO SCHEMES GENERATED FOR EXTERNAL PACKAGES
<!-- -->
**schemes** は、スキームリストをきれいに保つために、Swift Package
プロジェクトでは自動的に作成されません。XcodeのUIから作成できます。
<!-- -->
:::

#### Xcodeのデフォルトの統合{#xcodes-default-integration}

Xcode のデフォルトの統合メカニズムを使用したい場合は、プロジェクトをインスタンス化するときに、リスト`パッケージ` を渡すことができます：

```swift
let project = Project(name: "MyProject", packages: [
    .remote(url: "https://github.com/krzyzanowskim/CryptoSwift", requirement: .exact("1.8.0"))
])
```

そしてターゲットから参照する：

```swift
let target = .target(name: "MyTarget", dependencies: [
    .package(product: "CryptoSwift", type: .runtime)
])
```

Swift マクロとビルドツールプラグインのために、それぞれ`.macro` と`.plugin` の型を使用する必要があります。

::: warning SPM Build Tool Plugins
<!-- -->
SPMビルドツールプラグインは、プロジェクトの依存関係にTuistの[XcodeProj-based
integration](#tuist-s-xcodeproj-based-integration)を使用する場合でも、[Xcodeのデフォルト統合](#xcode-s-default-integration)メカニズムを使用して宣言する必要があります。
<!-- -->
:::

SPMビルドツールプラグインの実用的なアプリケーションは、Xcodeの「ビルドツールプラグインの実行」ビルドフェーズ中にコードリンティングを実行することです。パッケージマニフェストでは、これは次のように定義されます：

```swift
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "Framework",
    products: [
        .library(name: "Framework", targets: ["Framework"]),
    ],
    dependencies: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", .upToNextMajor(from: "0.56.1")),
    ],
    targets: [
        .target(
            name: "Framework",
            plugins: [
                .plugin(name: "SwiftLint", package: "SwiftLintPlugin"),
            ]
        ),
    ]
)
```

ビルドツールプラグインをそのまま使用して Xcode プロジェクトを生成するには、プロジェクトマニフェストの`packages`
配列でパッケージを宣言し、`.plugin` タイプのパッケージをターゲットの依存関係に含める必要があります。

```swift
import ProjectDescription

let project = Project(
    name: "Framework",
    packages: [
        .remote(url: "https://github.com/SimplyDanny/SwiftLintPlugins", requirement: .upToNextMajor(from: "0.56.1")),
    ],
    targets: [
        .target(
            name: "Framework",
            dependencies: [
                .package(product: "SwiftLintBuildToolPlugin", type: .plugin),
            ]
        ),
    ]
)
```

### カルタゴ{#carthage}

Carthage](https://github.com/carthage/carthage) は`frameworks` または`xcframeworks`
を出力するので、`carthage update` を実行して`Carthage/Build` ディレクトリの依存関係を出力し、`.framework`
または`.xcframework` target
依存タイプを使用してターゲットで依存関係を宣言できます。プロジェクトを生成する前に実行できるスクリプトでこれをラップできます。

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

::: warning BUILD AND TEST
<!-- -->
`xcodebuild build` and`tuist test`
を使用してプロジェクトをビルドおよびテストする場合も同様に、ビルドまたはテストの前に`carthage update` コマンドを実行して、Carthage
で解決された依存関係が存在することを確認する必要があります。
<!-- -->
:::

### ココアポッズ{#cocoapods}

[CocoaPods](https://cocoapods.org)は、依存関係を統合するためにXcodeプロジェクトを期待します。Tuistを使用してプロジェクトを生成し、`pod
install`
を実行して、プロジェクトとPodsの依存関係を含むワークスペースを作成して依存関係を統合することができます。これを、プロジェクトを生成する前に実行できるスクリプトにまとめることができます。

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

::: 警告
<!-- -->
CocoaPodsの依存関係は、`build` や`test` のような、プロジェクトを生成した直後に`xcodebuild`
を実行するワークフローとは互換性がありません。また、フィンガープリントのロジックがPodsの依存関係を考慮しないため、バイナリキャッシュや選択的テストとも互換性がありません。
<!-- -->
:::

## 静的または動的{#static-or-dynamic}

フレームワークやライブラリは、静的にリンクすることも、動的にリンクすることもできる。**この選択は、アプリのサイズや起動時間**
などに大きな影響を与える。その重要性にもかかわらず、この決定はあまり考慮されずに行われることが多い。

**一般的な経験則**
高速な起動時間を実現するために、リリースビルドではできるだけ多くのものを静的にリンクし、高速な反復時間を実現するために、デバッグビルドではできるだけ多くのものを動的にリンクしたい。

プロジェクトグラフで静的リンクと動的リンクの間を変更することの課題は、変更がグラフ全体に連鎖的な影響を及ぼすため、Xcodeでは些細なことではありません（例えば、ライブラリはリソースを含むことができず、静的フレームワークは埋め込まれる必要はありません）。Appleは、Swift
Package Managerの静的リンクと動的リンクの自動決定や、[Mergeable
Libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)のようなコンパイル時のソリューションで問題を解決しようとしました。しかし、これはコンパイルグラフに新しい動的変数を追加し、非決定性の新しいソースを追加し、コンパイルグラフに依存する
Swift プレビューのようないくつかの機能が信頼できなくなる可能性があります。

幸運なことに、Tuistは静的と動的の間の変更に関連する複雑さを概念的に圧縮し、リンクタイプ間で標準的な<LocalizedLink href="/guides/features/projects/synthesized-files#bundle-accessors">バンドルアクセサ</LocalizedLink>を合成します。環境変数による動的設定と組み合わせることで、呼び出し時にリンクタイプを渡し、マニフェストでその値を使用してターゲットのプロダクトタイプを設定することができます。

```swift
// Use the value returned by this function to set the product type of your targets.
func productType() -> Product {
    if case let .string(linking) = Environment.linking {
        return linking == "static" ? .staticFramework : .framework
    } else {
        return .framework
    }
}
```

Tuist<LocalizedLink href="/guides/features/projects/cost-of-convenience">はそのコスト</LocalizedLink>のため、暗黙の設定による利便性をデフォルトにしないことに注意してください。これが意味するのは、結果のバイナリが正しいことを保証するために、リンクタイプや、[`-ObjC`
リンカフラグ](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184)のような時に必要となる追加のビルド設定をあなたが設定することに依存しているということです。したがって、私たちのスタンスは、正しい判断を下すためのリソースを、通常はドキュメントの形で提供することです。

::: tip EXAMPLE: THE COMPOSABLE ARCHITECTURE
<!-- -->
多くのプロジェクトが統合しているSwiftパッケージは、[The Composable
Architecture](https://github.com/pointfreeco/swift-composable-architecture)です。詳細は[このセクション](#the-composable-architecture)を参照してください。
<!-- -->
:::

### シナリオ{#scenarios}

リンクを完全に静的または動的に設定することが、実行不可能であったり、良い考えで
ないシナリオもある。以下は、スタティック・リンクとダイナミック・リンクを混在させる必要があるシナリオの非網羅的なリストである：

- **拡張機能を持つアプリ：**
  アプリとその拡張機能はコードを共有する必要があるため、それらのターゲットをダイナミックにする必要があるかもしれない。そうしないと、アプリとエクステンションの両方で同じコードが重複することになり、バイナリ・サイズが大きくなってしまう。
- **コンパイル済みの外部依存関係：**
  静的または動的なコンパイル済みバイナリが提供されることがある。静的バイナリは、動的フレームワークやライブラリにラップして動的にリンクすることができます。

グラフに変更を加える際、Tuistはグラフを分析し、「静的副作用」を検出した場合には警告を表示する。この警告は、動的ターゲットを介して静的ターゲットに過渡的に依存するターゲットを静的にリンクすることで発生する可能性のある問題を特定するためのものです。これらの副作用は、しばしばバイナリサイズの増大や、最悪の場合にはランタイムクラッシュとして現れます。

## トラブルシューティング{#troubleshooting}

### Objective-Cの依存関係{#objectivec-dependencies}

Objective-Cの依存関係を統合する場合、[Apple Technical Q&A
QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html)に詳述されているように、実行時のクラッシュを回避するために、コンシューマターゲットに特定のフラグを含める必要がある場合があります。

ビルドシステムとTuistはフラグが必要かどうかを推測する方法がなく、フラグは潜在的に望ましくない副作用を伴うので、Tuistはこれらのフラグのどれかを自動的に適用しません。また、Swiftパッケージマネージャは`-ObjC`
が`.unsafeFlag` を介して含まれるとみなすので、ほとんどのパッケージは必要なときにデフォルトのリンク設定の一部としてこれを含めることができません。

Objective-Cの依存関係（または内部Objective-Cターゲット）の消費者は、`-ObjC` または`-force_load`
フラグを適用する必要があります。このフラグは、`OTHER_LDFLAGS` を消費ターゲットに設定することによって設定されます。

### Firebaseとその他のGoogleライブラリ{#firebase-other-google-libraries}

Googleのオープンソースライブラリは、強力ではあるが、その構築方法において非標準的なアーキテクチャやテクニックを使用していることが多いため、Tuistに統合するのが難しい場合がある。

FirebaseとGoogleの他のアップルプラットフォームライブラリを統合するために必要なヒントをいくつか紹介しよう：

#### `-ObjC` が`OTHER_LDFLAGS に追加されていることを確認する。` {#ensure-objc-is-added-to-other_ldflags}

Googleのライブラリの多くはObjective-Cで書かれている。このため、消費するターゲットは`OTHER_LDFLAGS` ビルド設定に`-ObjC`
タグを含める必要があります。これは`.xcconfig` ファイルで設定するか、Tuist
マニフェスト内のターゲットの設定で手動で指定することができます。例を挙げよう：

```swift
Target.target(
    ...
    settings: .settings(
        base: ["OTHER_LDFLAGS": "$(inherited) -ObjC"]
    )
    ...
)
```

詳細は上記の[Objective-Cの依存関係](#objective-c-dependencies)のセクションを参照してください。

#### `FBLPromises` の商品タイプをダイナミックフレームワークに設定する。{#set-the-product-type-for-fblpromises-to-dynamic-framework}

Googleのライブラリの中には、`FBLPromises` に依存しているものがあります。`FBLPromises`
、以下のようなクラッシュが発生することがあります：

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

`Package.swift` ファイルの`FBLPromises` の product type を`.framework`
に明示的に設定すると問題が解決するはずです：

```swift [Tuist/Package.swift]
// swift-tools-version: 5.10

import PackageDescription

#if TUIST
import ProjectDescription
import ProjectDescriptionHelpers

let packageSettings = PackageSettings(
    productTypes: [
        "FBLPromises": .framework,
    ]
)
#endif

let package = Package(
...
```

### コンポーザブル・アーキテクチャー{#the-composable-architecture}

ここ](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184)と[トラブルシューティングのセクション](#troubleshooting)で説明したように、パッケージを静的にリンクする場合、`OTHER_LDFLAGS`
ビルド設定を`$(inherited) -ObjC`
に設定する必要があります。これはTuistのデフォルトのリンクタイプです。あるいは、パッケージのプロダクト・タイプをダイナミックにオーバーライドすることもできる。静的にリンクする場合、テストとアプリのターゲットは通常問題なく動作しますが、SwiftUIのプレビューは壊れます。これはすべてを動的にリンクすることで解決できます。下の例では、[Sharing](https://github.com/pointfreeco/swift-sharing)も依存関係として追加されています。これは、The
Composable
Architectureと一緒に使われることが多く、独自の[設定の落とし穴](https://github.com/pointfreeco/swift-sharing/issues/150#issuecomment-2797107032)があるからです。

以下の設定は、すべてを動的にリンクします - アプリ+テストターゲットとSwiftUIプレビューが動作するように。

::: tip STATIC OR DYNAMIC
<!-- -->
ダイナミック・リンクは必ずしも推奨されません。詳細は[静的か動的か](#static-or-dynamic)のセクションを参照。この例では、簡単にするために、すべての依存関係を無条件で動的にリンクしています。
<!-- -->
:::

```swift [Tuist/Package.swift]
// swift-tools-version: 6.0
import PackageDescription

#if TUIST
import enum ProjectDescription.Environment
import struct ProjectDescription.PackageSettings

let packageSettings = PackageSettings(
    productTypes: [
        "CasePaths": .framework,
        "CasePathsCore": .framework,
        "Clocks": .framework,
        "CombineSchedulers": .framework,
        "ComposableArchitecture": .framework,
        "ConcurrencyExtras": .framework,
        "CustomDump": .framework,
        "Dependencies": .framework,
        "DependenciesTestSupport": .framework,
        "IdentifiedCollections": .framework,
        "InternalCollectionsUtilities": .framework,
        "IssueReporting": .framework,
        "IssueReportingPackageSupport": .framework,
        "IssueReportingTestSupport": .framework,
        "OrderedCollections": .framework,
        "Perception": .framework,
        "PerceptionCore": .framework,
        "Sharing": .framework,
        "SnapshotTesting": .framework,
        "SwiftNavigation": .framework,
        "SwiftUINavigation": .framework,
        "UIKitNavigation": .framework,
        "XCTestDynamicOverlay": .framework
    ],
    targetSettings: [
        "ComposableArchitecture": .settings(base: [
            "OTHER_SWIFT_FLAGS": ["-module-alias", "Sharing=SwiftSharing"]
        ]),
        "Sharing": .settings(base: [
            "PRODUCT_NAME": "SwiftSharing",
            "OTHER_SWIFT_FLAGS": ["-module-alias", "Sharing=SwiftSharing"]
        ])
    ]
)
#endif
```

::: 警告
<!-- -->
`import Sharing` の代わりに`import SwiftSharing` をしなければならない。
<!-- -->
:::

### `.swiftmodule から漏れる推移的静的依存関係` {#transitive-static-dependencies-leaking-through-swiftmodule}

動的なフレームワークやライブラリーが`import StaticSwiftModule`
を通して静的なものに依存する場合、そのシンボルは動的なフレームワークやライブラリーの`.swiftmodule`
に含まれ、<LocalizedLink href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1">コンパイルに失敗</LocalizedLink>する可能性があります。これを防ぐには、<LocalizedLink href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`internal
import`</LocalizedLink>を使用して静的依存関係をインポートする必要があります：

```swift
internal import StaticModule
```

::: info
<!-- -->
インポートのアクセスレベルは、Swift 6に含まれています。Swift の古いバージョンを使用している場合は、代わりに
<LocalizedLink href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_implementationOnly`</LocalizedLink>
を使用する必要があります：
<!-- -->
:::

```swift
@_implementationOnly import StaticModule
```
