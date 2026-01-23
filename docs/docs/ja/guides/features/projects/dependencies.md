---
{
  "title": "Dependencies",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn how to declare dependencies in your Tuist project."
}
---
# 依存関係 {#dependencies}

プロジェクトが拡大すると、コードの共有、境界の定義、ビルド時間の改善のために複数のターゲットに分割することが一般的です。複数のターゲットを定義すると、**依存関係グラフ**
が形成され、外部依存関係も含まれる場合があります。

## XcodeProj-コード化されたグラフ{#xcodeprojcodified-graphs}

XcodeおよびXcodeProjの設計上、依存関係グラフの維持は煩雑でエラーが発生しやすい作業です。以下に遭遇する可能性のある問題の例を示します：

- Xcodeのビルドシステムはプロジェクトの全成果物を派生データ内の同一ディレクトリに出力するため、ターゲットが本来インポートすべきでない成果物をインポートできる可能性があります。クリーンビルドが頻繁に行われるCI環境や、異なる構成が使用される後の段階でコンパイルが失敗する恐れがあります。
- ターゲットの推移的動的依存関係は、`LD_RUNPATH_SEARCH_PATHS`
  のビルド設定に含まれるいずれかのディレクトリにコピーする必要があります。そうしないと、ターゲットは実行時にそれらを見つけられません。グラフが小さい場合は考えやすく設定も簡単ですが、グラフが大きくなるにつれて問題になります。
- ターゲットが静的な[XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle)をリンクする場合、Xcodeがバンドルを処理し、現在のプラットフォームとアーキテクチャに適したバイナリを抽出するために、ターゲットに追加のビルドフェーズが必要です。このビルドフェーズは自動で追加されず、追加を忘れがちです。

上記はほんの一例ですが、長年にわたり遭遇した事例は数多くあります。エンジニアチームに依存関係グラフの維持管理と有効性の保証を要求すると想像してみてください。さらに悪いことに、その複雑な処理がビルド時にクローズドソースのビルドシステムによって解決され、制御やカスタマイズが不可能だとします。聞き覚えがありませんか？これはAppleがXcodeとXcodeProjで採用した手法であり、Swift
Package Managerが継承したものです。

依存関係グラフは明示的であるべきだと強く信じています。**** ** ** なぜなら、そうして初めて検証可能（**）** 最適化可能（**）**
となるからです。Tuistを使えば、何が何に依存するかを記述することに集中でき、残りは我々が処理します。複雑な実装の詳細は抽象化され、ユーザーから隠蔽されます。

以下のセクションでは、プロジェクトで依存関係を宣言する方法について学びます。

::: tip GRAPH VALIDATION
<!-- -->
Tuistはプロジェクト生成時にグラフを検証し、循環が存在せず全ての依存関係が有効であることを保証します。これにより、どのチームも依存関係グラフを壊す心配なく、その進化に貢献できます。
<!-- -->
:::

## ローカル依存関係{#local-dependencies}

ターゲットは、同一プロジェクト内および異なるプロジェクト内の他のターゲットやバイナリに依存できます。`ターゲット` をインスタンス化する際、`依存関係`
引数に以下のいずれかのオプションを指定できます：

- `ターゲット`: 同じプロジェクト内のターゲットとの依存関係を宣言します。
- `プロジェクト` ：別のプロジェクト内のターゲットに対する依存関係を宣言します。
- `フレームワーク`: バイナリフレームワークとの依存関係を宣言します。
- `ライブラリ ``` : バイナリライブラリへの依存関係を宣言します。
- `XCFramework`: バイナリ XCFramework との依存関係を宣言します。
- `SDK`: システム SDK との依存関係を宣言します。
- `XCTest`: XCTest との依存関係を宣言します。

::: info DEPENDENCY CONDITIONS
<!-- -->
すべての依存関係タイプは、プラットフォームに基づいて依存関係を条件付きでリンクする`condition`
オプションを受け入れます。デフォルトでは、ターゲットがサポートするすべてのプラットフォームに対して依存関係をリンクします。
<!-- -->
:::

## 外部依存関係{#external-dependencies}

Tuistでは、プロジェクト内で外部依存関係を宣言することも可能です。

### Swift Packages{#swift-packages}

Swiftパッケージは、プロジェクトで依存関係を宣言する推奨方法です。Xcodeのデフォルト統合機能、またはTuistのXcodeProjベース統合を使用して統合できます。

#### TuistのXcodeProjベースの統合{#tuists-xcodeprojbased-integration}

Xcodeのデフォルト統合は最も便利ですが、中規模・大規模プロジェクトに必要な柔軟性と制御性に欠けます。これを克服するため、TuistはXcodeProjベースの統合を提供し、XcodeProjのターゲットを使用してSwiftパッケージをプロジェクトに統合できます。
これにより、統合に対する制御性を高められるだけでなく、<LocalizedLink href="/guides/features/cache">キャッシュ</LocalizedLink>や<LocalizedLink href="/guides/features/test/selective-testing">選択的テスト実行</LocalizedLink>といったワークフローとの互換性も実現しています。

XcodeProjの統合は、新しいSwift Package機能のサポートやより多くのパッケージ構成の処理に時間がかかる傾向があります。ただし、Swift
PackageとXcodeProjターゲット間のマッピングロジックはオープンソースであり、コミュニティによる貢献が可能です。これは、クローズドソースでAppleによって管理されているXcodeのデフォルト統合とは対照的です。

外部依存関係を追加するには、`パッケージを作成する必要があります。Package.swift` は、`Tuist/`
ディレクトリ内か、プロジェクトのルートディレクトリに配置してください。

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
`パッケージ設定`
インスタンスをコンパイラディレクティブでラップすることで、パッケージの統合方法を設定できます。例えば上記の例では、パッケージに使用されるデフォルトの製品タイプを上書きするために使用されています。通常はこれを使用する必要はありません。
<!-- -->
:::

> [!IMPORTANT] カスタムビルド構成プロジェクトでカスタムビルド構成（標準の`Debug` および`Release`
> 以外の構成）を使用する場合、`PackageSettings` で`baseSettings`
> を使用してそれらを指定する必要があります。外部依存関係は、正しくビルドするためにプロジェクトの構成を認識する必要があります。例：
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
> 詳細は[#8345](https://github.com/tuist/tuist/issues/8345)を参照してください。

`Package.swift`
ファイルは、外部依存関係を宣言するためのインターフェースに過ぎません。そのため、このパッケージではターゲットやプロダクトを定義しません。依存関係を定義したら、次のコマンドを実行して依存関係を解決し、`Tuist/Dependencies`
ディレクトリに依存関係を取り込みます:

```bash
tuist install
# Resolving and fetching dependencies. {#resolving-and-fetching-dependencies}
# Installing Swift Package Manager dependencies. {#installing-swift-package-manager-dependencies}
```

お気づきかもしれませんが、依存関係の解決を専用のコマンドとして扱う点で、[CocoaPods](https://cocoapods.org)と同様のアプローチを採用しています。これにより、ユーザーは依存関係の解決・更新のタイミングを制御でき、プロジェクト内のXcodeを開いてコンパイル準備を整えることが可能になります。
プロジェクトが拡大するにつれ、AppleのSwift Package Manager統合による開発者体験が時間とともに劣化する領域だと私たちは考えています。

プロジェクトターゲットから、`TargetDependency.external` 依存関係タイプを使用してそれらの依存関係を参照できます:

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
Swift Packageプロジェクトでは、スキームリストを整理するため、**スキーム（** ）は自動生成されません。XcodeのUIから作成できます。
<!-- -->
:::

#### Xcodeのデフォルト統合{#xcodes-default-integration}

Xcodeのデフォルト統合機能を使用する場合は、プロジェクトインスタンス化時にリストを`パッケージ` に渡せます：

```swift
let project = Project(name: "MyProject", packages: [
    .remote(url: "https://github.com/krzyzanowskim/CryptoSwift", requirement: .exact("1.8.0"))
])
```

そして、ターゲットからそれらを参照してください：

```swift
let target = .target(name: "MyTarget", dependencies: [
    .package(product: "CryptoSwift", type: .runtime)
])
```

Swiftマクロおよびビルドツールプラグインについては、それぞれ以下の型を使用する必要があります：`.macro` ` .plugin`

::: warning SPM Build Tool Plugins
<!-- -->
SPMビルドツールプラグインは、プロジェクト依存関係にTuistの[XcodeProjベースの統合](#tuist-s-xcodeproj-based-integration)を使用している場合でも、[Xcodeのデフォルト統合](#xcode-s-default-integration)メカニズムを使用して宣言する必要があります。
<!-- -->
:::

SPMビルドツールプラグインの実用的な応用例として、Xcodeの「ビルドツールプラグインの実行」ビルドフェーズ中にコードのリンティングを実行することが挙げられる。パッケージマニフェストでは以下のように定義される：

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

ビルドツールプラグインを保持したXcodeプロジェクトを生成するには、プロジェクトマニフェストの```パッケージ`
配列でパッケージを宣言し、ターゲットの依存関係に``.plugin`` タイプのパッケージを含める必要があります。

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

[Carthage](https://github.com/carthage/carthage) は`frameworks` または`xcframeworks`
を出力するため、`carthage update` を実行して依存関係を`Carthage/Build` ディレクトリに出力し、`.framework`
または`.xcframework`
ターゲット依存関係タイプを使用してターゲット内で依存関係を宣言できます。プロジェクト生成前に実行できるスクリプトにこれを組み込むことも可能です。

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

::: warning BUILD AND TEST
<!-- -->
プロジェクトをビルドおよびテストする場合、`xcodebuild build` および`tuist test`
を実行します。同様に、ビルドまたはテスト前に`carthage update`
コマンドを実行し、Carthageで解決された依存関係が存在することを確認する必要があります。
<!-- -->
:::

### CocoaPods{#cocoapods}

[CocoaPods](https://cocoapods.org) は依存関係を統合するために Xcode プロジェクトを必要とします。Tuist
を使用してプロジェクトを生成し、その後`pod install` を実行して、プロジェクトと Pods
依存関係を含むワークスペースを作成し、依存関係を統合できます。プロジェクト生成前に実行できるスクリプトにこれを組み込むことも可能です。

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

::: 警告
<!-- -->
CocoaPodsの依存関係は、プロジェクト生成直後に`xcodebuild` を実行するワークフロー（例：`build` や`test`
）と互換性がありません。また、フィンガープリンティングロジックがPods依存関係を考慮していないため、バイナリキャッシュや選択的テストとも互換性がありません。
<!-- -->
:::

## 静的または動的{#static-or-dynamic}

フレームワークやライブラリは静的リンクまたは動的リンクで接続でき、**アプリサイズや起動時間などの側面に重大な影響を及ぼす選択である**
。その重要性にもかかわらず、この決定はしばしば十分な検討なしに行われる。

**の一般的な指針**
は、リリースビルドでは起動時間を短縮するため可能な限り多くのものを静的リンクし、デバッグビルドでは反復処理を高速化するため可能な限り多くのものを動的リンクすることです。

プロジェクトグラフにおける静的リンクと動的リンクの切り替えが課題となるのは、Xcodeでは変更がグラフ全体に連鎖効果をもたらすため（例：ライブラリはリソースを含められない、静的フレームワークは埋め込み不要）容易ではないからです。
Appleはこの問題を、Swift Package Managerの静的/動的リンク自動判別や[Mergeable
Libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)といったコンパイル時ソリューションで解決しようと試みました。しかしこれによりコンパイルグラフに新たな動的変数が追加され、非決定性の新たな要因が生じ、コンパイルグラフに依存するSwift
Previewsなどの機能が不安定化する可能性があります。

幸いなことに、Tuistは静的と動的の切り替えに伴う複雑さを概念的に圧縮し、リンクタイプを問わず標準的な<LocalizedLink href="/guides/features/projects/synthesized-files#bundle-accessors">バンドルアクセサ</LocalizedLink>を合成します。<LocalizedLink href="/guides/features/projects/dynamic-configuration">環境変数による動的設定</LocalizedLink>と組み合わせることで、呼び出し時にリンクタイプを渡すことができ、マニフェスト内の値を使用してターゲットのプロダクトタイプを設定できます。

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

Tuist
<LocalizedLink href="/guides/features/projects/cost-of-convenience">は、そのコスト</LocalizedLink>のため、暗黙の設定による便宜性をデフォルトとしていません。これは、結果のバイナリが正しいことを保証するために、リンカーフラグ[`-ObjC`
](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184)など、リンキングタイプや追加のビルド設定をユーザーが設定する必要があることを意味します。したがって、私たちが取る姿勢は、適切な判断を下すためのリソース（通常はドキュメントの形で）を提供することです。

::: tip EXAMPLE: THE COMPOSABLE ARCHITECTURE
<!-- -->
多くのプロジェクトが統合しているSwiftパッケージは[The Composable
Architecture](https://github.com/pointfreeco/swift-composable-architecture)です。詳細は[このセクション](#the-composable-architecture)を参照してください。
<!-- -->
:::

### シナリオ{#scenarios}

リンク設定を完全に静的または動的に統一することが不可能な、あるいは適切でないシナリオがいくつか存在します。以下は、静的リンクと動的リンクを混在させる必要がある可能性のあるシナリオの非網羅的なリストです：

- **拡張機能付きアプリ:**
  アプリとその拡張機能はコードを共有する必要があるため、これらのターゲットを動的に設定する必要があるかもしれません。そうしないと、アプリと拡張機能の両方に同じコードが重複して存在し、バイナリサイズが増大する結果となります。
- **事前コンパイル済み外部依存関係:**
  事前コンパイル済みのバイナリ（静的または動的）が提供される場合があります。静的バイナリは、動的フレームワークやライブラリでラップされ、動的にリンクされることがあります。

グラフに変更を加える際、Tuistはそれを解析し、「静的副作用」を検出した場合に警告を表示します。この警告は、動的ターゲットを介して静的ターゲットに推移的に依存するターゲットを静的にリンクすることで生じる可能性のある問題を特定するのに役立ちます。これらの副作用は、バイナリサイズの増加として現れることが多く、最悪の場合、ランタイムクラッシュを引き起こす可能性があります。

## トラブルシューティング{#troubleshooting}

### Objective-C 依存関係{#objectivec-dependencies}

Objective-C依存関係を統合する際、[Apple Technical Q&A
QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html)で詳述されているように、実行時クラッシュを回避するために、消費側ターゲットに特定のフラグを含める必要がある場合があります。

ビルドシステムとTuistはフラグの必要性を判断する手段を持たず、またフラグには望ましくない副作用の可能性があるため、Tuistはこれらのフラグを自動的に適用しません。さらにSwift
Package Managerは`-ObjC` を` 経由で包含されたものと見なすため、`
ほとんどのパッケージは必要な場合でもデフォルトのリンク設定の一部として含めることができません。

Objective-C 依存関係（または内部 Objective-C ターゲット）を利用するコンシューマーは、必要に応じて`-ObjC`
または`-force_load` フラグを適用してください。これには、利用するターゲットで`OTHER_LDFLAGS` を設定します。

### Firebase およびその他の Google ライブラリ{#firebase-other-google-libraries}

Googleのオープンソースライブラリは強力ですが、構築方法において非標準的なアーキテクチャや技術を使用していることが多いため、Tuistへの統合が困難な場合があります。

FirebaseおよびGoogleのその他のAppleプラットフォーム向けライブラリを統合する際に必要となる可能性のあるヒントをいくつか紹介します：

#### `-ObjC` を`の OTHER_LDFLAGS に追加してください` {#ensure-objc-is-added-to-other_ldflags}

`
Googleのライブラリの多くはObjective-Cで記述されています。このため、利用するターゲットでは`のOTHER_LDFLAGS設定に``-ObjC`（``
`）を含める必要があります。これは``.xcconfig`（`` `）ファイルで設定するか、Tuistマニフェスト内のターゲット設定で手動指定できます。例：

```swift
Target.target(
    ...
    settings: .settings(
        base: ["OTHER_LDFLAGS": "$(inherited) -ObjC"]
    )
    ...
)
```

詳細は上記の[Objective-C 依存関係](#objective-c-dependencies)セクションを参照してください。

#### `の製品タイプをFBLPromises` に設定し、動的フレームワークとして設定してください{#set-the-product-type-for-fblpromises-to-dynamic-framework}

特定のGoogleライブラリは、Googleの別のライブラリである`FBLPromises` に依存しています。`FBLPromises`
に関するクラッシュが発生する場合があり、以下のような内容になります：

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

`` 内のPackage.swiftファイルで、 のFBLPromises（ ）のプロダクトタイプを明示的に .framework（
）に設定すれば、問題は解決するはずです：`` ``

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

### コンポーザブルアーキテクチャ{#the-composable-architecture}

[こちら](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184)および[トラブルシューティングセクション](#troubleshooting)に記載の通り、パッケージを静的リンクする場合（Tuistのデフォルトリンクタイプ）、`のOTHER_LDFLAGS設定を`
から`$(inherited)-ObjC` に変更する必要があります。あるいは、パッケージのプロダクトタイプを動的リンクに上書きすることも可能です。
静的リンク時には、testおよびappターゲットは通常問題なく動作しますが、SwiftUIプレビューは機能しません。これはすべてを動的にリンクすることで解決できます。以下の例では、The
Composable
Architectureと併用されることが多く、独自の[設定上の落とし穴](https://github.com/pointfreeco/swift-sharing/issues/150#issuecomment-2797107032)があるため、[Sharing](https://github.com/pointfreeco/swift-sharing)も依存関係として追加されています。

以下の設定により、すべてが動的にリンクされます。つまり、app + testターゲットとSwiftUIプレビューが機能します。

::: tip STATIC OR DYNAMIC
<!-- -->
動的リンクは常に推奨されるわけではありません。詳細は[静的または動的](#static-or-dynamic)のセクションを参照してください。この例では、簡略化のため全ての依存関係を条件なしで動的にリンクしています。
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
`import Sharing` の代わりに、`import SwiftSharing` を使用する必要があります。
<!-- -->
:::

### `.swiftmoduleを介して漏れる推移的静的依存関係` {#transitive-static-dependencies-leaking-through-swiftmodule}

動的フレームワークまたはライブラリが`import StaticSwiftModule`
を通じて静的フレームワークに依存する場合、シンボルは動的フレームワークまたはライブラリの`.swiftmodule`
に含まれ、<LocalizedLink href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1">コンパイルが失敗する</LocalizedLink>可能性があります。これを防ぐには、静的依存関係を<LocalizedLink href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`internal
import`</LocalizedLink>: のようにインポートする必要があります。

```swift
internal import StaticModule
```

::: info
<!-- -->
インポート時のアクセスレベルはSwift
6で導入されました。古いバージョンのSwiftを使用している場合は、代わりに<LocalizedLink href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_implementationOnly`</LocalizedLink>を使用する必要があります：
<!-- -->
:::

```swift
@_implementationOnly import StaticModule
```
