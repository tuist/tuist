---
{
  "title": "依存関係",
  "titleTemplate": ":title · プロジェクト · 機能 · ガイド · Tuist",
  "description": "Tuistプロジェクトで依存関係を宣言する方法を学びます。"
}
---
# 依存関係 {#dependencies}

プロジェクトが大きくなると、コードの共有、境界の定義、ビルド時間の短縮のために、複数のターゲットに分割するのが一般的です。複数のターゲットがあるということは、それらの間に依存関係を定義して**依存グラフ**を形成することを意味し、外部の依存関係も含まれる場合があります。

## XcodeProjでコード化されたグラフ {#xcodeprojcodified-graphs}

XcodeおよびXcodeProjの設計上、依存グラフの維持は面倒でエラーが発生しやすい作業になり得ます。遭遇する可能性のある問題の例をいくつか挙げます。

- Xcodeのビルドシステムはプロジェクトのすべての生成物をDerived Data内の同じディレクトリに出力するため、ターゲットが本来インポートすべきではない生成物をインポートできてしまう可能性があります。クリーンビルドがより一般的なCI環境や、後ほど異なる構成を使用した際に、コンパイルが失敗する場合があります。
- ターゲットの推移的な動的依存関係は、`LD_RUNPATH_SEARCH_PATHS`ビルド設定に含まれるいずれかのディレクトリにコピーする必要があります。そうしないと、ターゲットは実行時にそれらを見つけられません。グラフが小さい場合は考慮や設定が容易ですが、グラフが大きくなるにつれて問題となります。
- ターゲットが静的な[XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle)をリンクする場合、Xcodeがバンドルを処理し、現在のプラットフォームとアーキテクチャに適したバイナリを抽出するための追加のビルドフェーズが必要です。このビルドフェーズは自動的に追加されず、追加し忘れることがよくあります。

上記はいくつかの例にすぎませんが、長年の間に遭遇した問題はさらに多くあります。依存グラフを維持し、その妥当性を確保するためにエンジニアチームが必要だと想像してみてください。さらに悪いことに、制御やカスタマイズができないクローズドソースのビルドシステムによって、ビルド時に複雑さが解決されるとしたらどうでしょうか。聞き覚えがありますか？これはAppleがXcodeとXcodeProjで採用し、Swift Package Managerが継承したアプローチです。

私たちは、依存グラフは**明示的**かつ**静的**であるべきだと強く信じています。そうして初めて、それを**検証**および**最適化**できるからです。Tuistでは、何が何に依存しているかを記述することに集中すれば、残りは私たちが処理します。複雑さや実装の詳細は抽象化され、意識する必要がありません。

以下のセクションでは、プロジェクトで依存関係を宣言する方法を学びます。

> [!TIP]
> **グラフの検証**
>
> Tuistはプロジェクトを生成する際にグラフを検証し、循環がなく、すべての依存関係が有効であることを確認します。これにより、どのチームも依存グラフを壊すことを心配せずに、その進化に参加できます。


## ローカル依存関係 {#local-dependencies}

ターゲットは、同じプロジェクト内や異なるプロジェクト内の他のターゲット、およびバイナリに依存できます。`Target`をインスタンス化する際、`dependencies`引数に以下のいずれかのオプションを渡すことができます。

- `Target`: 同じプロジェクト内のターゲットとの依存関係を宣言します。
- `Project`: 異なるプロジェクト内のターゲットとの依存関係を宣言します。
- `Framework`: バイナリフレームワークとの依存関係を宣言します。
- `Library`: バイナリライブラリとの依存関係を宣言します。
- `XCFramework`: バイナリXCFrameworkとの依存関係を宣言します。
- `SDK`: システムSDKとの依存関係を宣言します。
- `XCTest`: XCTestとの依存関係を宣言します。
- `Macro`: 同じプロジェクト内で定義されたSwiftマクロターゲットとの依存関係を宣言します（[Swift Macros](#swift-macros)を参照）。

> [!NOTE]
> **依存条件**
>
> すべての依存関係タイプは、プラットフォームに基づいて依存関係を条件付きでリンクするための`condition`オプションを受け入れます。デフォルトでは、ターゲットがサポートするすべてのプラットフォームに対して依存関係をリンクします。


## 外部依存関係 {#external-dependencies}

Tuistでは、プロジェクトで外部依存関係を宣言することもできます。

### Swift Packages {#swift-packages}

Swift Packagesは、プロジェクトで依存関係を宣言するための推奨方法です。TuistはSwift Package Managerを使用してそれらを解決します。ローカルパッケージによるモジュール化とTuistプロジェクトの比較については、[Swift Package Manager vs Tuist](https://tuist.dev/compare/swift-package-manager)を参照してください。Xcodeのデフォルトの統合メカニズムを使用するか、TuistのXcodeProjベースの統合を使用して統合できます。

#### TuistのXcodeProjベースの統合 {#tuists-xcodeprojbased-integration}

Xcodeのデフォルトの統合は最も便利ですが、中規模および大規模プロジェクトに必要な柔軟性と制御性に欠けます。これを克服するため、TuistはXcodeProjのターゲットを使用してSwift Packagesをプロジェクトに統合できる、XcodeProjベースの統合を提供しています。これにより、統合に対するより大きな制御を提供できるだけでなく、<.localized_link href="/guides/features/cache">キャッシング</.localized_link>や<.localized_link href="/guides/features/selective-testing">選択的テスト実行</.localized_link>などのワークフローとも互換性を持たせることができます。

XcodeProjの統合は、新しいSwift Package機能のサポートや、より多くのパッケージ構成の処理に時間がかかる傾向があります。ただし、Swift PackagesとXcodeProjターゲット間のマッピングロジックはオープンソースであり、コミュニティから貢献できます。これは、クローズドソースでAppleによって維持されているXcodeのデフォルトの統合とは対照的です。

外部依存関係を追加するには、`Tuist/`の下またはプロジェクトのルートに`Package.swift`を作成する必要があります。

::: code-group
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

> [!TIP]
> **パッケージ設定**
>
> コンパイラディレクティブで囲まれた`PackageSettings`インスタンスを使用すると、パッケージの統合方法を構成できます。例えば、上記の例では、パッケージに使用されるデフォルトの製品タイプを上書きするために使用されています。デフォルトでは、これは必要ありません。また、`expectedSignatures`を通じてSwiftPMバイナリターゲットの期待される署名を設定するためにも使用できます。


### バイナリターゲットの署名

ローカルまたはリモートのSwiftパッケージがバイナリXCFrameworkターゲットを公開する場合、`PackageSettings.expectedSignatures`を使用して期待される署名を構成できます。

```swift
#if TUIST
    import ProjectDescription

    let packageSettings = PackageSettings(
        expectedSignatures: [
            "SelfSignedXCFramework": .selfSigned(
                fingerprint: "EF61C3C0339FC84805357AFEC2E0BB0E6A0D5EE64165B333F934BF9E282785BC"
            ),
        ]
    )
#endif
```

> [!IMPORTANT] CUSTOM BUILD CONFIGURATIONS
> プロジェクトがカスタムビルド構成（標準の`Debug`および`Release`以外の構成）を使用している場合、`baseSettings`を使用して`PackageSettings`でそれらを指定する必要があります。外部依存関係は、正しくビルドするためにプロジェクトの構成を知る必要があります。例:
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
> 詳細については、[#8345](https://github.com/tuist/tuist/issues/8345)を参照してください。

`Package.swift`ファイルは外部依存関係を宣言するためのインターフェースにすぎず、それ以上のものではありません。そのため、パッケージ内にターゲットや製品を定義しません。依存関係の定義が完了したら、次のコマンドを実行して依存関係を解決し、`Tuist/Dependencies`ディレクトリに取り込むことができます。

```bash
tuist install
# Resolving and fetching dependencies.
# Installing Swift Package Manager dependencies.
```

ご存知の方もいるかもしれませんが、私たちは[CocoaPods](https://cocoapods.org)と同様のアプローチを採用しており、依存関係の解決は独立したコマンドとして実行されます。これにより、ユーザーは依存関係をいつ解決および更新するかを制御でき、Xcodeでプロジェクトを開いた時点でコンパイル可能な状態にすることができます。私たちは、AppleのSwift Package Managerとの統合が提供する開発者体験は、プロジェクトの成長に伴って時間とともに低下すると考えています。

プロジェクトのターゲットから、`TargetDependency.external`依存関係タイプを使用してこれらの依存関係を参照できます。

::: code-group
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
                .external(name: "Alamofire"),
            ]
        ),
    ]
)
```
<!-- -->
:::

> [!NOTE]
> **外部パッケージ用のスキームは生成されません**
>
> スキームリストをクリーンに保つため、Swift Packageプロジェクト用の**スキーム**は自動的に作成されません。XcodeのUIを通じて作成できます。


#### Xcodeのデフォルトの統合 {#xcodes-default-integration}

Xcodeのデフォルトの統合メカニズムを使用したい場合は、プロジェクトをインスタンス化する際に`packages`リストを渡すことができます。

```swift
let project = Project(name: "MyProject", packages: [
    .package(url: "https://github.com/krzyzanowskim/CryptoSwift", .exact("1.8.0"))
])
```

そして、ターゲットからそれらを参照します。

```swift
let target: Target = .target(name: "MyTarget", destinations: .iOS, product: .framework, bundleId: "dev.tuist.MyTarget", dependencies: [
    .package(product: "CryptoSwift", type: .runtime)
])
```

Xcodeのデフォルトの統合を通じて外部Swift PackageからSwift MacroまたはBuild Tool Pluginを統合する場合、それぞれ`.macro`および`.plugin`タイプで宣言してください。マクロは[TuistのXcodeProjベースの統合](#tuists-xcodeprojbased-integration)を通じて消費することもでき、パッケージから消費するのではなく独自のマクロを定義したい場合は、[Swift Macros](#swift-macros)を参照してください。

> [!WARNING]
> **SPMビルドツールプラグイン**
>
> SPMビルドツールプラグインは、プロジェクトの依存関係にTuistの[XcodeProjベースの統合](#tuists-xcodeprojbased-integration)を使用している場合でも、[Xcodeのデフォルトの統合](#xcodes-default-integration)メカニズムを使用して宣言する必要があります。

SPMビルドツールプラグインは、XcodeとSwiftPMが実行して、ターゲットに対して実行すべき具体的なビルドコマンドを発見するためのSwiftプログラムです。これらのコマンドは、パッケージグラフ、ターゲットファイル、プラグインの作業ディレクトリ、解決されたプラグインツール、およびプラグインによって宣言された出力に依存する可能性があります。一部のプラグインは、同じターゲットビルドの一部となる必要があるファイルも生成します。

TuistのXcodeProjベースの統合は、マッピングが静的な場合（ライブラリ、バイナリ、実行可能ファイル、マクロなど）、パッケージ製品をネイティブなXcodeターゲットにマップします。ビルドツールプラグインには、XcodeのSwiftPM統合の外側で同等のネイティブXcodeプロジェクトプリミティブが存在しません。プラグインは最終的に実行可能ファイルを実行できますが、通常のスクリプトビルドフェーズからその実行可能ファイルを呼び出すことは、プラグインを実行することと同等ではありません。Tuistはまず、プラグインのSwiftコードを評価し、SwiftPMのプラグインコンテキストを再現し、コマンドを発見し、宣言された入力と出力をモデル化し、Xcodeがビルドを計画する前に生成されたファイルをターゲットグラフに追加する必要があります。

このため、`Tuist/Package.swift`でのみプラグインパッケージを宣言し、`.external(name:)`を通じて消費することはサポートされていません。サポートされている代替手段は、`Project.packages`でパッケージを宣言し、`.package(product:type: .plugin)`を使用してプラグイン製品を消費ターゲットに追加することです。これにより、プラグインはSwift Package製品の依存関係として生成されたXcodeプロジェクトに接続されたままとなり、XcodeとSwiftPMはネイティブなプラグインコンテキストでそれを実行できます。

トレードオフは、Xcodeがそのプラグイン統合を所有することです。

- Xcodeは、SwiftPM統合を通じてプラグインパッケージを解決およびビルドします。
- パッケージは、Tuistによって生成された外部ターゲットではなく、Swift Package参照として生成されたプロジェクトに表示されます。
- Tuistは、静的にマップされたパッケージ製品に対して提供できるのと同じレベルの制御、検証、キャッシング、および選択的テストの動作をプラグインに提供できません。
- CIおよびローカルビルドでは、これらのプラグインパッケージに対してXcodeのパッケージ解決を許可する必要があります。

これらの影響により、TuistプロジェクトでSPMビルドツールプラグインを使用することは一般的にお勧めしません。可能な場合は、ターゲットで宣言されたビルドフェーズスクリプトを使用するか、TuistまたはXcodeを呼び出す前に、生成されたXcodeプロジェクトの外側のスクリプトからツールを実行してください。

SPMビルドツールプラグインの実用的なアプリケーションは、Xcodeの「Run Build Tool Plug-ins」ビルドフェーズ中にコードリンティングを実行することです。ビルドツールプラグインをそのままにしてXcodeプロジェクトを生成するには、プロジェクトマニフェストの`packages`配列でパッケージを宣言し、ターゲットの依存関係にタイプ`.plugin`のパッケージを含めます。

```swift
import ProjectDescription

let project = Project(
    name: "Framework",
    packages: [
        .package(url: "https://github.com/SimplyDanny/SwiftLintPlugins", from: "0.56.1"),
    ],
    targets: [
        .target(
            name: "Framework",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.Framework",
            dependencies: [
                .package(product: "SwiftLintBuildToolPlugin", type: .plugin),
            ]
        ),
    ]
)
```

### Carthage {#carthage}

[Carthage](https://github.com/carthage/carthage)は`frameworks`または`xcframeworks`を出力するため、`carthage update`を実行して`Carthage/Build`ディレクトリに依存関係を出力し、`.framework`または`.xcframework`ターゲット依存関係タイプを使用してターゲット内の依存関係を宣言できます。これを、プロジェクトを生成する前に実行できるスクリプトにまとめることができます。

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

> [!WARNING]
> **ビルドとテスト**
>
> `xcodebuild build`および`tuist test`を通じてプロジェクトをビルドおよびテストする場合、同様に、ビルドまたはテストの前に`carthage update`コマンドを実行して、Carthageで解決された依存関係が存在することを確認する必要があります。


### CocoaPods {#cocoapods}

[CocoaPods](https://cocoapods.org)は、依存関係を統合するためにXcodeプロジェクトを必要とします。Tuistを使用してプロジェクトを生成し、その後`pod install`を実行して、プロジェクトとPodsの依存関係を含むワークスペースを作成することで依存関係を統合できます。これを、プロジェクトを生成する前に実行できるスクリプトにまとめることができます。

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

> [!WARNING]
> CocoaPodsの依存関係は、プロジェクト生成直後に`xcodebuild`を実行する`build`や`test`などのワークフローと互換性がありません。また、フィンガープリントロジックがPodsの依存関係を考慮しないため、バイナリキャッシングおよび選択的テストとも互換性がありません。


## Swift Macros {#swift-macros}

Tuistプロジェクトで[Swift Macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/)を扱う際には2つの異なるシナリオがあり、どちらの状況にあるかを明確にすることが重要です。

- **外部Swift Packageで定義されたマクロを消費する。** 両方の統合メカニズムがマクロをサポートしています。[TuistのXcodeProjベースの統合](#tuists-xcodeprojbased-integration)では、`Tuist/Package.swift`でパッケージを宣言し、`.external(name:)`で依存関係を設定します。Tuistはマクロ製品をネイティブターゲットにマップします。[Xcodeのデフォルトの統合](#xcodes-default-integration)では、`.package(product:type: .macro)`で依存関係を宣言します。ビルドツールプラグインとは異なり、マクロはXcodeのデフォルトの統合に限定されません。
- プロジェクトの一部として**独自のマクロを定義する**—例えば、モノレポ内の共有ライブラリなど。これには`Package.swift`は不要です。Tuistには第一級の`.macro`製品タイプがあるため、マニフェストでマクロターゲットを直接宣言できます。

### 独自のマクロの定義 {#defining-your-own-macro}

Swiftマクロはコンパイラプラグインであり、Swiftコンパイラがコンパイル時に読み込んで実行する実行可能ファイルです。Tuistはこれを`.macro`製品タイプでネイティブにモデル化します。AppleはXcodeプロジェクトでSwift Macroターゲットタイプを公開していませんが、Tuistはコマンドラインツールターゲットを生成し、マクロを使用するターゲットの依存関係として配線し、`-load-plugin-executable`フラグをSwiftコンパイラ設定に注入することでこれを有効にします。これらの接続処理はすべて自動で行われます。

一般的なマクロは2つのターゲットに分かれています。マクロを実装する**プラグイン**ターゲット（`product: .macro`）と、マクロのパブリックインターフェース（`@attached`/`@freestanding`宣言）を宣言し、`.macro(name:)`を介してプラグインに依存する**ライブラリ**ターゲットです。プラグインはビルドマシン上で実行されるため、そのターゲットはホスト専用（macOS）となります。

マクロの実装は[swift-syntax](https://github.com/swiftlang/swift-syntax)に依存しており、これは`Tuist/Package.swift`で通常の外部依存関係として宣言します。

```swift [Tuist/Package.swift]
// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "PackageName",
    dependencies: [
        .package(url: "https://github.com/swiftlang/swift-syntax", from: "600.0.0"),
    ]
)
```

その後、プロジェクトでマクロプラグインとライブラリターゲットを直接定義できます。

```swift [Project.swift]
import ProjectDescription

let project = Project(
    name: "MyLibrary",
    targets: [
        // The compiler plugin that implements the macro. macOS-only, since it
        // runs on the build machine at compile time.
        .target(
            name: "MyMacrosImplementation",
            destinations: [.mac],
            product: .macro,
            bundleId: "dev.tuist.MyMacrosImplementation",
            sources: ["Sources/MyMacrosImplementation/**"],
            dependencies: [
                .external(name: "SwiftSyntax"),
                .external(name: "SwiftSyntaxMacros"),
                .external(name: "SwiftCompilerPlugin"),
            ]
        ),
        // The library that exposes the macro declarations to consumers and
        // depends on the plugin via `.macro(name:)`.
        .target(
            name: "MyLibrary",
            destinations: .iOS,
            product: .framework,
            bundleId: "dev.tuist.MyLibrary",
            sources: ["Sources/MyLibrary/**"],
            dependencies: [
                .macro(name: "MyMacrosImplementation"),
            ]
        ),
    ]
)
```

`MyLibrary`をリンクする任意のターゲットでマクロを使用できるようになります。Tuistがプラグインを伝播させるため、コンパイラがそれを読み込めます。


## 静的または動的 {#static-or-dynamic}

フレームワークとライブラリは静的または動的にリンクでき、**この選択はアプリサイズや起動時間などに大きな影響を与えます**。その重要性にもかかわらず、この決定はあまり考慮されずに行われることがよくあります。

**一般的な経験則**としては、リリースビルドでは高速な起動時間を実現するために可能な限り多くのものを静的にリンクし、デバッグビルドでは高速な反復時間を実現するために可能な限り多くのものを動的にリンクすることです。

プロジェクトグラフ内で静的リンクと動的リンクの間を変更する際の課題は、Xcodeでは簡単ではないことです。変更がグラフ全体に連鎖的な影響を与えるためです（例：ライブラリはリソースを含められない、静的フレームワークは埋め込む必要がない）。Appleは、Swift Package Managerによる静的および動的リンクの自動決定や[Mergeable Libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)などのコンパイル時ソリューションでこの問題を解決しようとしました。しかし、これによりコンパイルグラフに新しい動的変数が追加され、非決定性の新たな原因が生じ、コンパイルグラフに依存するSwift Previewsなどの機能が不安定になる可能性があります。

幸い、Tuistは静的と動的の間の変更に関連する複雑さを概念的に圧縮し、リンクタイプ間で標準的な<.localized_link href="/guides/features/projects/synthesized-files#bundle-accessors">バンドルアクセサ</.localized_link>を合成します。<.localized_link href="/guides/features/projects/dynamic-configuration">環境変数による動的構成</.localized_link>と組み合わせることで、呼び出し時にリンクタイプを渡し、その値をマニフェストで使用してターゲットの製品タイプを設定できます。

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

Tuistは<.localized_link href="/guides/features/projects/cost-of-convenience">コストがかかるため、暗黙的な構成による利便性をデフォルトとしません</.localized_link>。これは、結果として得られるバイナリが正しいことを保証するために、リンクタイプと、場合によっては必要な追加のビルド設定（[`-ObjC`リンカーフラグ](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184)など）を設定することをユーザーに委ねていることを意味します。したがって、私たちが取る立場は、適切な判断を下すためのリソース（通常はドキュメントの形）を提供することです。

> [!TIP]
> **例：The Composable Architecture**
>
> 多くのプロジェクトが統合しているSwift Packageは[The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture)です。[このセクション](#the-composable-architecture)で詳細をご覧ください。


### シナリオ {#scenarios}

リンクを完全に静的または動的に設定することが現実的でない、あるいは適切でないシナリオがいくつかあります。以下は、静的リンクと動的リンクを混合する必要がある可能性のあるシナリオの網羅的ではないリストです。

- **拡張機能を持つアプリ：** アプリとその拡張機能はコードを共有する必要があるため、それらのターゲットを動的にする必要がある場合があります。そうしないと、アプリと拡張機能の両方で同じコードが複製され、バイナリサイズが増加します。
- **事前コンパイルされた外部依存関係：** 静的または動的な事前コンパイル済みバイナリが提供される場合があります。静的バイナリは、動的にリンクされるように動的フレームワークまたはライブラリでラップできます。

グラフに変更を加えると、Tuistはそれを分析し、「静的副作用」を検出した場合に警告を表示します。この警告は、動的ターゲットを介して静的ターゲットに推移的に依存するターゲットを静的にリンクすることによって生じる可能性のある問題を特定するのに役立ちます。これらの副作用は、バイナリサイズの増加や、最悪の場合にはランタイムクラッシュとして現れることがよくあります。

## トラブルシューティング {#troubleshooting}

### Objective-Cの依存関係 {#objectivec-dependencies}

Objective-Cの依存関係を統合する際、[Apple Technical Q&A QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html)で詳述されているように、ランタイムクラッシュを回避するために、消費側ターゲットに特定のフラグを含める必要がある場合があります。

ビルドシステムとTuistにはフラグが必要かどうかを推論する方法がなく、またフラグには望ましくない副作用が伴う可能性があるため、Tuistはこれらのフラグを自動的に適用しません。さらに、Swift Package Managerは`-ObjC`を`.unsafeFlag`を介して含まれるものと見なすため、ほとんどのパッケージは必要に応じてデフォルトのリンク設定の一部としてこれを含めることができません。

Objective-Cの依存関係の消費者（または内部Objective-Cターゲット）は、消費側ターゲットで`OTHER_LDFLAGS`を設定することで、必要に応じて`-ObjC`または`-force_load`フラグを適用する必要があります。

### Firebaseおよびその他のGoogleライブラリ {#firebase-other-google-libraries}

Googleのオープンソースライブラリは強力ですが、構築方法において非標準的なアーキテクチャと手法を使用することが多いため、Tuist内での統合が難しい場合があります。

FirebaseおよびGoogleの他のAppleプラットフォームライブラリを統合するために従う必要があるかもしれないいくつかのヒントを以下に示します。

#### `-ObjC`が`OTHER_LDFLAGS`に追加されていることを確認する {#ensure-objc-is-added-to-other_ldflags}

Googleのライブラリの多くはObjective-Cで記述されています。そのため、消費側ターゲットでは`OTHER_LDFLAGS`ビルド設定に`-ObjC`タグを含める必要があります。これは`.xcconfig`ファイルで設定するか、Tuistマニフェスト内のターゲット設定で手動で指定できます。例:

```swift
Target.target(
    ...
    settings: .settings(
        base: ["OTHER_LDFLAGS": "$(inherited) -ObjC"]
    )
    ...
)
```

詳細については、上記の[Objective-Cの依存関係](#objectivec-dependencies)セクションを参照してください。

#### `FBLPromises`のプロダクトタイプを動的フレームワークに設定する {#set-the-product-type-for-fblpromises-to-dynamic-framework}

特定のGoogleライブラリは、Googleのもう一つのライブラリである`FBLPromises`に依存しています。`FBLPromises`に関連するクラッシュが発生することがあり、以下のようなエラーが表示されます:

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

`Package.swift`ファイルで`FBLPromises`のプロダクトタイプを明示的に`.framework`に設定すると、この問題が解決します:

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

### The Composable Architecture {#the-composable-architecture}

[こちら](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184)および[トラブルシューティングセクション](#troubleshooting)で説明されているように、パッケージを静的にリンクする場合（Tuistのデフォルトのリンクタイプです）、`OTHER_LDFLAGS`ビルド設定を`$(inherited) -ObjC`に設定する必要があります。 alternatively 、パッケージのプロダクトタイプを動的にオーバーライドすることもできます。静的にリンクする場合、テストターゲットとアプリターゲットは通常問題なく動作しますが、SwiftUIプレビューは機能しません。これはすべてを動的にリンクすることで解決できます。以下の例では、The Composable Architectureと一緒に使用されることが多く、独自の[設定上の落とし穴](https://github.com/pointfreeco/swift-sharing/issues/150#issuecomment-2797107032)があるため、[Sharing](https://github.com/pointfreeco/swift-sharing)も依存関係として追加されています。

以下の設定ではすべてを動的にリンクするため、アプリ＋テストターゲットおよびSwiftUIプレビューが正常に動作します。

> [!TIP]
> **静的か動的か**
>
> 動的リンクが常に推奨されるわけではありません。詳細については[静的か動的か](#static-or-dynamic)セクションを参照してください。この例では、簡略化のため条件なしですべての依存関係を動的にリンクしています。


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

> [!WARNING]
> `import Sharing`の代わりに`import SwiftSharing`を使用する必要があります。


### `.swiftmodule`を通じて漏れ出す推移的な静的依存関係 {#transitive-static-dependencies-leaking-through-swiftmodule}

動的フレームワークまたはライブラリが`import StaticSwiftModule`を介して静的なモジュールに依存している場合、そのシンボルは動的フレームワークまたはライブラリの`.swiftmodule`に含まれ、<.localized_link href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1">コンパイル失敗の原因となる可能性</.localized_link>があります。これを防ぐには、<.localized_link href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`internal import`</.localized_link>を使用して静的依存関係をインポートする必要があります:

```swift
internal import StaticModule
```

> [!NOTE]
> インポート時のアクセスレベルはSwift 6で導入されました。それより古いバージョンのSwiftを使用している場合は、代わりに<.localized_link href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_implementationOnly`</.localized_link>を使用する必要があります:


```swift
@_implementationOnly import StaticModule
```

## 関連情報 {#related}

[monday.comがTuistでモジュラープロジェクトグラフを採用した方法](https://tuist.dev/customers/monday)を読み、依存関係が最も少ないターゲットから始めてください。
