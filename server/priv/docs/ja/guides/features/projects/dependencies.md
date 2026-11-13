---
{
  "title": "依存関係",
  "titleTemplate": ":title · プロジェクト · 機能 · ガイド · Tuist",
  "description": "Tuist プロジェクトで依存関係を宣言する方法を学びます。"
}
---
# 依存関係 {#dependencies}

プロジェクトが大きくなると、コードの共有、境界の定義、ビルド時間の改善のために、複数のターゲットに分割するのが一般的です。複数のターゲットがあるということは、それらの間に依存関係を定義して**依存関係グラフ**を形成することを意味し、外部の依存関係も含む可能性があります。

## XcodeProjで符号化されたグラフ {#xcodeprojcodified-graphs}

XcodeおよびXcodeProjの設計上、依存関係グラフの維持は面倒でエラーが発生しやすい作業になり得ます。以下は、遭遇する可能性のある問題の例です。

- Xcodeのビルドシステムはプロジェクトのすべての製品をDerived Data内の同じディレクトリに出力するため、ターゲットが本来インポートすべきではない製品をインポートできてしまう可能性があります。クリーンビルドがより一般的なCI環境や、後ほど異なる構成を使用する場合に、コンパイルが失敗することがあります。
- ターゲットの推移的な動的依存関係は、`LD_RUNPATH_SEARCH_PATHS`ビルド設定に含まれるいずれかのディレクトリにコピーする必要があります。そうでないと、ターゲットは実行時にそれらを見つけることができません。グラフが小さい場合は考慮や設定が容易ですが、グラフが大きくなるにつれて問題となります。
- ターゲットが静的な[XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle)をリンクする場合、Xcodeがバンドルを処理し、現在のプラットフォームとアーキテクチャに適したバイナリを抽出するために、追加のビルドフェーズが必要です。このビルドフェーズは自動的に追加されず、追加し忘れることがよくあります。

上記はいくつかの例にすぎませんが、長年にわたって遭遇した問題はさらに多くあります。依存関係グラフを維持し、その有効性を確保するためにエンジニアチームが必要だと想像してみてください。さらに悪いことに、制御やカスタマイズができないクローズドソースのビルドシステムによって、ビルド時に複雑さが解決されるとしたらどうでしょうか。聞き覚えがありますか？これはAppleがXcodeおよびXcodeProjで採用し、Swift Package Managerが継承したアプローチです。

私たちは、依存関係グラフは**明示的**かつ**静的**であるべきだと強く信じています。そうすることで初めて、それを**検証**および**最適化**できるからです。Tuistでは、何が何に依存しているかを記述することに集中すれば、残りは私たちが処理します。複雑さや実装の詳細は抽象化されています。

以下のセクションでは、プロジェクトで依存関係を宣言する方法を学びます。

> [!TIP]
> **グラフの検証**
>
> Tuistは、プロジェクト生成時にグラフを検証し、循環がないこと、すべての依存関係が有効であることを確認します。これにより、どのチームでも依存関係グラフを破壊することを心配せずに進化させることができます。


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
> **依存関係の条件**
>
> すべての依存関係タイプは、プラットフォームに基づいて依存関係を条件付きでリンクするための`condition`オプションを受け入れます。デフォルトでは、ターゲットがサポートするすべてのプラットフォームに対して依存関係をリンクします。


## 外部依存関係 {#external-dependencies}

Tuistでは、プロジェクトで外部依存関係を宣言することもできます。

### Swift Packages {#swift-packages}

Swift Packagesは、プロジェクトで依存関係を宣言するための推奨方法です。Xcodeのデフォルトの統合メカニズムを使用するか、TuistのXcodeProjベースの統合を使用して統合できます。

#### TuistのXcodeProjベースの統合 {#tuists-xcodeprojbased-integration}

Xcodeのデフォルトの統合は最も便利ですが、中規模および大規模プロジェクトに必要な柔軟性と制御性に欠けます。これを克服するために、TuistはXcodeProjのターゲットを使用してSwift Packagesをプロジェクトに統合できるXcodeProjベースの統合を提供しています。これにより、統合に対するより大きな制御を提供できるだけでなく、<.localized_link href="/guides/features/cache">キャッシング</.localized_link>や<.localized_link href="/guides/features/selective-testing">選択的テスト実行</.localized_link>などのワークフローとの互換性も実現します。

XcodeProjの統合は、新しいSwift Package機能のサポートや、より多くのパッケージ構成の処理に時間がかかる傾向があります。ただし、Swift PackagesとXcodeProjターゲット間のマッピングロジックはオープンソースであり、コミュニティによる貢献が可能です。これは、クローズドソースでAppleによって維持されているXcodeのデフォルトの統合とは対照的です。

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
> コンパイラディレクティブで囲まれた`PackageSettings`インスタンスを使用すると、パッケージの統合方法を構成できます。例えば、上記の例では、パッケージに使用されるデフォルトの製品タイプを上書きするために使用されています。デフォルトでは、これは必要ありません。また、`expectedSignatures`を通じてSwiftPMバイナリターゲットの期待される署名を構成するためにも使用できます。


### バイナリターゲットの署名

ローカルまたはリモートのSwiftパッケージがバイナリXCFrameworkターゲットを公開している場合、`PackageSettings.expectedSignatures`を使用して期待される署名を構成できます。

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
> プロジェクトがカスタムビルド構成（標準の`Debug`および`Release`以外の構成）を使用している場合、`baseSettings`を使用して`PackageSettings`でそれらを指定する必要があります。外部依存関係は、正しくビルドするためにプロジェクトの構成を知る必要があります。例：
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

`Package.swift`ファイルは外部依存関係を宣言するためのインターフェースにすぎません。そのため、パッケージ内にターゲットや製品を定義しません。依存関係を定義したら、次のコマンドを実行して依存関係を解決し、`Tuist/Dependencies`ディレクトリに取得できます。

```bash
tuist install
# Resolving and fetching dependencies.
# Installing Swift Package Manager dependencies.
```

ご存知かもしれませんが、依存関係の解決を独立したコマンドとして実行する点は[CocoaPods](https://cocoapods.org)と似たアプローチです。これにより、ユーザーは依存関係の解決や更新のタイミングを制御でき、Xcodeでプロジェクトを開いた時点でコンパイル可能な状態にできます。プロジェクトの規模が大きくなるにつれて、AppleのSwift Package Manager統合が提供する開発者体験が低下していく領域だと私たちは考えています。

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
> スキームリストをクリーンに保つため、Swift Packageプロジェクトに対して**スキーム**は自動的に作成されません。XcodeのUIを通じて作成できます。


#### Xcodeのデフォルトの統合 {#xcodes-default-integration}

Xcodeのデフォルトの統合メカニズムを使用したい場合は、プロジェクトをインスタンス化する際に`packages`リストを渡します。

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

Xcodeのデフォルトの統合を通じて外部Swift PackageからSwift MacroまたはBuild Tool Pluginを統合する場合、それぞれ`.macro`および`.plugin`タイプで宣言してください。Macroは[TuistのXcodeProjベースの統合](#tuists-xcodeprojbased-integration)を通じて使用することもでき、パッケージから消費するのではなく独自のSwift Macroを定義したい場合は、[Swift Macros](#swift-macros)を参照してください。

> [!WARNING]
> **SPMビルドツールプラグイン**
>
> SPMビルドツールプラグインは、プロジェクトの依存関係にTuistの[XcodeProjベースの統合](#tuists-xcodeprojbased-integration)を使用している場合でも、[Xcodeのデフォルトの統合](#xcodes-default-integration)メカニズムを使用して宣言する必要があります。

SPMビルドツールプラグインは、XcodeとSwiftPMが実行して、ターゲットで実行すべき具体的なビルドコマンドを発見するためのSwiftプログラムです。これらのコマンドは、パッケージグラフ、ターゲットファイル、プラグインの作業ディレクトリ、解決されたプラグインツール、およびプラグインによって宣言された出力に依存する可能性があります。一部のプラグインは、同じターゲットビルドの一部となる必要があるファイルも生成します。

TuistのXcodeProjベースの統合は、マッピングが静的な場合（ライブラリ、バイナリ、実行ファイル、マクロなど）、パッケージ製品をネイティブなXcodeターゲットにマップします。ビルドツールプラグインには、XcodeのSwiftPM統合以外に同等のネイティブなXcodeプロジェクトプリミティブが存在しません。プラグインは最終的に実行可能ファイルを実行できますが、通常のスクリプトビルドフェーズからその実行可能ファイルを呼び出すことは、プラグインを実行することと同等ではありません。TuistはまずプラグインのSwiftコードを評価し、SwiftPMのプラグインコンテキストを再現し、コマンドを発見し、宣言された入力と出力をモデル化し、Xcodeがビルドを計画する前に生成されたファイルをターゲットグラフに追加する必要があります。

このため、`Tuist/Package.swift`でのみプラグインパッケージを宣言し、`.external(name:)`を通じて消費することはサポートされていません。サポートされている代替手段は、`Project.packages`でパッケージを宣言し、`.package(product:type: .plugin)`を使用してプラグイン製品を消費側ターゲットに追加することです。これにより、プラグインはSwift Package製品の依存関係として生成されたXcodeプロジェクトに接続されたままとなり、XcodeとSwiftPMはネイティブなプラグインコンテキストでそれを実行できます。

トレードオフとして、Xcodeがそのプラグイン統合を所有することになります。

- Xcodeは、SwiftPM統合を通じてプラグインパッケージを解決およびビルドします。
- パッケージは、Tuistによって生成された外部ターゲットではなく、Swift Package参照として生成されたプロジェクトに表示されます。
- Tuistは、静的にマップされたパッケージ製品に対して提供できるのと同じレベルの制御、検証、キャッシング、および選択的テストの動作をプラグインに提供できません。
- CIおよびローカルビルドでは、それらのプラグインパッケージに対してXcodeのパッケージ解決を許可する必要があります。

これらの影響のため、TuistプロジェクトでSPMビルドツールプラグインを使用することは一般的にお勧めしません。可能な場合は、ターゲットで宣言されたビルドフェーズスクリプトを使用するか、TuistまたはXcodeを呼び出す前に、生成されたXcodeプロジェクトの外にあるスクリプトからツールを実行してください。

SPMビルドツールプラグインの実用的な用途の一つは、Xcodeの「Run Build Tool Plug-ins」ビルドフェーズ中にコードリンティングを実行することです。ビルドツールプラグインをそのままにしてXcodeプロジェクトを生成するには、プロジェクトマニフェストの`packages`配列でパッケージを宣言し、ターゲットの依存関係にタイプ`.plugin`のパッケージを含めます。

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

[Carthage](https://github.com/carthage/carthage)は`frameworks`または`xcframeworks`を出力するため、`carthage update`を実行して`Carthage/Build`ディレクトリに依存関係を出力し、その後`.framework`または`.xcframework`ターゲット依存関係タイプを使用してターゲット内の依存関係を宣言できます。これを、プロジェクトを生成する前に実行できるスクリプトにまとめることができます。

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

> [!WARNING]
> **ビルドとテスト**
>
> `xcodebuild build`および`tuist test`を通じてプロジェクトをビルドおよびテストする場合も同様に、ビルドまたはテストの前に`carthage update`コマンドを実行して、Carthageで解決された依存関係が存在することを確認する必要があります。


### CocoaPods {#cocoapods}

[CocoaPods](https://cocoapods.org)は、依存関係を統合するためにXcodeプロジェクトを必要とします。Tuistを使用してプロジェクトを生成し、その後`pod install`を実行して、プロジェクトとPodsの依存関係を含むワークスペースを作成することで依存関係を統合できます。これを、プロジェクトを生成する前に実行できるスクリプトにまとめることができます。

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

> [!WARNING]
> CocoaPodsの依存関係は、プロジェクト生成直後に`xcodebuild`を実行する`build`や`test`などのワークフローと互換性がありません。また、フィンガープリントロジックがPodsの依存関係を考慮しないため、バイナリキャッシングや選択的テストとも互換性がありません。


## Swift Macros {#swift-macros}

Tuistプロジェクトで[Swift Macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/)を扱う際には、2つの異なるシナリオがあり、自分がどちらの状況にいるかを明確にすることが重要です。

- **外部Swift Packageで定義されたマクロを使用する。** どちらの統合メカニズムもマクロをサポートしています。[TuistのXcodeProjベースの統合](#tuists-xcodeprojbased-integration)では、`Tuist/Package.swift`でパッケージを宣言し、`.external(name:)`で依存します。Tuistはマクロ製品をネイティブターゲットにマップします。[Xcodeのデフォルトの統合](#xcodes-default-integration)では、`.package(product:type: .macro)`で依存関係を宣言します。ビルドツールプラグインとは異なり、マクロはXcodeのデフォルトの統合に限定されません。
- プロジェクトの一部として**独自のマクロを定義する**—例えば、モノレポ内の共有ライブラリ内など。これには`Package.swift`は不要です。Tuistには第一級クラスの`.macro`製品タイプがあるため、マニフェストでマクロターゲットを直接宣言できます。

### 独自のマクロを定義する {#defining-your-own-macro}

Swiftマクロはコンパイラプラグインであり、Swiftコンパイラがコンパイル時に読み込んで実行する実行可能ファイルです。Tuistはこれを`.macro`製品タイプでネイティブにモデル化します。AppleはXcodeプロジェクトでSwift Macroターゲットタイプを公開していませんが、Tuistはコマンドラインツールターゲットを生成し、マクロを使用するターゲットの依存関係として配線し、Swiftコンパイラ設定に`-load-plugin-executable`フラグを注入することでこれを有効にします。これらの基盤整備はすべて自動的に行われます。

典型的なマクロは2つのターゲットに分かれます。マクロを実装する**プラグイン**ターゲット（`product: .macro`）と、マクロのパブリックインターフェース（`@attached`/`@freestanding`宣言）を宣言し、`.macro(name:)`を通じてプラグインに依存する**ライブラリ**ターゲットです。プラグインはビルドマシン上で実行されるため、そのターゲットはホストのみ（macOS）となります。

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

その後、プロジェクト内でマクロプラグインとライブラリターゲットを直接定義できます。

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

`MyLibrary`をリンクする任意のターゲットは、現在マクロを使用できます。Tuistはプラグインを伝播させ、コンパイラがそれを読み込めるようにします。


## 静的または動的 {#static-or-dynamic}

フレームワークとライブラリは静的または動的にリンクでき、**この選択はアプリサイズや起動時間などに大きな影響を与えます**。その重要性にもかかわらず、この決定はあまり考慮されずに行われることがよくあります。

**一般的な経験則**としては、リリースビルドでは高速な起動時間を実現するために可能な限り多くのものを静的にリンクし、デバッグビルドでは高速な反復時間を実現するために可能な限り多くのものを動的にリンクすることです。

プロジェクトグラフ内で静的リンクと動的リンクの間を変更する際の課題は、Xcodeでは自明ではないことです。変更がグラフ全体に連鎖的な影響を与えるためです（例：ライブラリはリソースを含められない、静的フレームワークは埋め込む必要がない）。Appleは、Swift Package Managerによる静的リンクと動的リンクの自動選択や[Mergeable Libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)などのコンパイル時ソリューションでこの問題を解決しようとしました。しかし、これによりコンパイルグラフに新しい動的変数が追加され、非決定性の新たな原因が生じ、コンパイルグラフに依存するSwift Previewsなどの機能が不安定になる可能性があります。

幸い、Tuistは静的と動的の間の変更に関連する複雑さを概念的に圧縮し、リンクタイプ間で標準化された<.localized_link href="/guides/features/projects/synthesized-files#bundle-accessors">バンドルアクセサ</.localized_link>を合成します。<.localized_link href="/guides/features/projects/dynamic-configuration">環境変数による動的構成</.localized_link>と組み合わせることで、呼び出し時にリンクタイプを渡し、その値をマニフェストで使用してターゲットの製品タイプを設定できます。

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

Tuistは<.localized_link href="/guides/features/projects/cost-of-convenience">コストがかかるため、暗黙的な構成による利便性をデフォルトとしません</.localized_link>。これは、結果として得られるバイナリが正しいことを保証するために、リンクタイプと、場合によっては必要な追加のビルド設定（[`-ObjC`リンカーフラグ](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184)など）を設定することに依存していることを意味します。したがって、私たちが取る立場は、適切な判断を下すためのリソース（通常はドキュメントの形）を提供することです。

> [!TIP]
> **例：The Composable Architecture**
>
> 多くのプロジェクトが統合しているSwift Packageは[The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture)です。詳細は[このセクション](#the-composable-architecture)をご覧ください。


### シナリオ {#scenarios}

リンクを完全に静的または動的に設定することが現実的ではない、あるいは適切ではないシナリオがいくつかあります。以下は、静的リンクと動的リンクを混合する必要がある可能性のあるシナリオの網羅的でないリストです。

- **拡張機能を持つアプリ：** アプリとその拡張機能はコードを共有する必要があるため、それらのターゲットを動的にする必要がある場合があります。そうしないと、アプリと拡張機能の両方で同じコードが重複し、バイナリサイズが増大します。
- **事前コンパイルされた外部依存関係：** 場合によっては、静的または動的な事前コンパイル済みバイナリが提供されます。静的バイナリは、動的にリンクされるように動的フレームワークまたはライブラリでラップできます。

グラフに変更を加える際、Tuistはそれを分析し、「静的サイドエフェクト」を検出すると警告を表示します。この警告は、動的ターゲットを介して静的ターゲットに推移的に依存するターゲットを静的にリンクすることから生じる可能性のある問題を特定するのに役立ちます。これらのサイドエフェクトは、バイナリサイズの増大として現れることが多く、最悪の場合、ランタイムクラッシュを引き起こします。

## トラブルシューティング {#troubleshooting}

### Objective-C依存関係 {#objectivec-dependencies}

Objective-C依存関係を統合する際、[Apple Technical Q&A QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html)で詳述されているように、ランタイムクラッシュを回避するために、消費側ターゲットに特定のフラグを含める必要がある場合があります。

ビルドシステムとTuistには、フラグが必要かどうかを推論する方法がなく、フラグには望ましくない副作用が伴う可能性があるため、Tuistはこれらのフラグを自動的に適用しません。また、Swift Package Managerは`-ObjC`を`.unsafeFlag`経由で含まれるものと見なすため、ほとんどのパッケージは必要に応じてデフォルトのリンク設定の一部としてこれを含めることができません。

Objective-C依存関係の消費者（または内部Objective-Cターゲット）は、必要に応じて消費側ターゲットで`OTHER_LDFLAGS`を設定することで、`-ObjC`または`-force_load`フラグを適用する必要があります。

### Firebaseおよびその他のGoogleライブラリ {#firebase-other-google-libraries}

Googleのオープンソースライブラリは強力ですが、構築方法において非標準的なアーキテクチャや手法を使用することが多いため、Tuist内での統合が難しい場合があります。

FirebaseおよびGoogleの他のAppleプラットフォームライブラリを統合するために従う必要があるかもしれないヒントをいくつか紹介します。

#### `-ObjC`が`OTHER_LDFLAGS`に追加されていることを確認する {#ensure-objc-is-added-to-other_ldflags}

Googleのライブラリの多くはObjective-Cで記述されています。そのため、消費側ターゲットはすべて、その`OTHER_LDFLAGS`ビルド設定に`-ObjC`タグを含める必要があります。これは`.xcconfig`ファイルで設定するか、Tuistマニフェスト内のターゲット設定で手動で指定できます。例:

```swift
Target.target(
    ...
    settings: .settings(
        base: ["OTHER_LDFLAGS": "$(inherited) -ObjC"]
    )
    ...
)
```

詳細については、上記の[Objective-C依存関係](#objectivec-dependencies)セクションを参照してください。

#### `FBLPromises`のプロダクトタイプをダイナミックフレームワークに設定する {#set-the-product-type-for-fblpromises-to-dynamic-framework}

特定のGoogleライブラリは、Googleのもう一つのライブラリである`FBLPromises`に依存しています。`FBLPromises`に関するクラッシュが発生し、次のようなエラーメッセージが表示される場合があります:

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

`Package.swift`ファイルで`FBLPromises`のプロダクトタイプを明示的に`.framework`に設定すると、この問題が解決されます:

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

[こちら](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184)および[トラブルシューティングセクション](#troubleshooting)で説明されているように、パッケージを静的にリンクする場合（Tuistのデフォルトのリンクタイプです）、`OTHER_LDFLAGS`ビルド設定を`$(inherited) -ObjC`に設定する必要があります。 alternatively、パッケージのプロダクトタイプを動的にオーバーライドすることもできます。静的にリンクする場合、テストおよびアプリターゲットは通常問題なく動作しますが、SwiftUIプレビューは機能しません。これは、すべてを動的にリンクすることで解決できます。以下の例では、[Sharing](https://github.com/pointfreeco/swift-sharing)も依存関係として追加されています。これはThe Composable Architectureと一緒に使用されることが多く、独自の[設定上の落とし穴](https://github.com/pointfreeco/swift-sharing/issues/150#issuecomment-2797107032)があるためです。

以下の設定ではすべてを動的にリンクするため、アプリ＋テストターゲットとSwiftUIプレビューが正常に動作します。

> [!TIP]
> **静的か動的か**
>
> 動的リンクは常に推奨されるわけではありません。詳細については、[静的か動的か](#static-or-dynamic)セクションを参照してください。この例では、簡略化のため、すべての依存関係を条件なしで動的にリンクしています。


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
> `import Sharing`の代わりに、`import SwiftSharing`を使用する必要があります。


### `.swiftmodule`を通じて漏れ出す推移的な静的依存関係 {#transitive-static-dependencies-leaking-through-swiftmodule}

動的フレームワークまたはライブラリが`import StaticSwiftModule`を介して静的なモジュールに依存している場合、シンボルは動的フレームワークまたはライブラリの`.swiftmodule`に含まれ、<.localized_link href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1">コンパイル失敗の原因となる可能性があります</.localized_link>。これを防ぐには、<.localized_link href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`internal import`</.localized_link>を使用して静的依存関係をインポートする必要があります:

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
