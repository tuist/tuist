---
{
  "title": "依存関係",
  "titleTemplate": ":title · プロジェクト · 機能 · ガイド · Tuist",
  "description": "Tuist プロジェクトで依存関係を宣言する方法を学びます。"
}
---
# 依存関係 {#dependencies}

プロジェクトが大きくなると、コードの共有、境界の定義、ビルド時間の短縮のために複数のターゲットに分割するのが一般的です。複数のターゲットがある場合、それらの間に依存関係を定義して**依存関係グラフ**を形成します。このグラフには外部依存関係も含まれることがあります。

## XcodeProj で符号化されたグラフ {#xcodeprojcodified-graphs}

Xcode と XcodeProj の設計により、依存関係グラフの維持は煩雑でミスを招きやすい作業になりがちです。遭遇する可能性のある問題の例をいくつか挙げます。

- Xcode のビルドシステムはプロジェクトのすべての成果物を Derived Data 内の同じディレクトリに出力するため、ターゲットが本来インポートすべきでない成果物をインポートできてしまう場合があります。クリーンビルドが一般的な CI 環境や、後から異なる構成を使用する場合にコンパイルが失敗することがあります。
- ターゲットの推移的な動的依存関係は、`LD_RUNPATH_SEARCH_PATHS` ビルド設定に含まれるいずれかのディレクトリにコピーする必要があります。コピーされていないと、ランタイム時にターゲットがそれらを見つけられません。グラフが小さいうちは考えやすく設定も簡単ですが、グラフが大きくなるにつれて問題になります。
- ターゲットが静的な [XCFramework](https://developer.apple.com/documentation/xcode/creating-a-multi-platform-binary-framework-bundle) をリンクする場合、Xcode がバンドルを処理し、現在のプラットフォームとアーキテクチャに適したバイナリを抽出するために追加のビルドフェーズが必要です。このビルドフェーズは自動的に追加されないため、追加し忘れることがよくあります。

上記はいくつかの例にすぎませんが、長年の経験の中で他にも多くの問題に遭遇してきました。依存関係グラフを維持し、その正当性を確保するためにエンジニアチームが必要だと想像してみてください。さらに悪いことに、制御やカスタマイズができないクローズドソースのビルドシステムによって、複雑さがビルド時に解決される場合もあります。聞き覚えがありますか？これは Apple が Xcode と XcodeProj で採用し、Swift Package Manager が継承したアプローチです。

依存関係グラフは **明示的** かつ **静的** であるべきだと私たちは強く信じています。そうすることで初めて **検証** と **最適化** が可能になるからです。Tuist では、何が何に依存しているかを記述することに集中すれば、残りは Tuist が処理します。複雑さや実装の詳細は抽象化されています。

以下のセクションでは、プロジェクトで依存関係を宣言する方法を学びます。

> [!TIP]
> **グラフの検証**
>
> Tuist はプロジェクト生成時にグラフを検証し、循環がないこと、すべての依存関係が有効であることを確認します。これにより、どのチームでも依存関係グラフを壊すことを心配せずに進化に参加できます。


## ローカル依存関係 {#local-dependencies}

ターゲットは、同じプロジェクト内や別のプロジェクト内の他のターゲット、およびバイナリに依存できます。`Target` をインスタンス化する際、`dependencies` 引数に以下のいずれかのオプションを渡せます。

- `Target`: 同じプロジェクト内のターゲットとの依存関係を宣言します。
- `Project`: 別のプロジェクト内のターゲットとの依存関係を宣言します。
- `Framework`: バイナリフレームワークとの依存関係を宣言します。
- `Library`: バイナリライブラリとの依存関係を宣言します。
- `XCFramework`: バイナリ XCFramework との依存関係を宣言します。
- `SDK`: システム SDK との依存関係を宣言します。
- `XCTest`: XCTest との依存関係を宣言します。
- `Macro`: 同じプロジェクト内で定義された Swift マクロターゲットとの依存関係を宣言します（[Swift マクロ](#swift-macros) を参照）。

> [!NOTE]
> **依存条件**
>
> すべての依存関係タイプは `condition` オプションを受け付け、プラットフォームに基づいて依存関係を条件付きでリンクできます。デフォルトでは、ターゲットがサポートするすべてのプラットフォームに対して依存関係をリンクします。


## 外部依存関係 {#external-dependencies}

Tuist では、プロジェクトで外部依存関係を宣言することもできます。

### Swift Packages {#swift-packages}

Swift Packages は、プロジェクトで依存関係を宣言するための推奨方法です。Xcode のデフォルトの統合メカニズムを使用するか、Tuist の XcodeProj ベースの統合を使用して統合できます。

#### Tuist の XcodeProj ベースの統合 {#tuists-xcodeprojbased-integration}

Xcode のデフォルトの統合は最も便利ですが、中規模および大規模プロジェクトに必要な柔軟性と制御性に欠けます。これを克服するため、Tuist は XcodeProj のターゲットを使用して Swift Packages をプロジェクトに統合できる XcodeProj ベースの統合を提供します。これにより、統合に対する制御性を高めるだけでなく、<.localized_link href="/guides/features/cache">キャッシュ</.localized_link> や <.localized_link href="/guides/features/selective-testing">選択的テスト実行</.localized_link> などのワークフローとも互換性を持たせることができます。

XcodeProj の統合は、新しい Swift Package の機能に対応したり、より多くのパッケージ構成を処理したりするのに時間がかかる傾向があります。ただし、Swift Packages と XcodeProj ターゲット間のマッピングロジックはオープンソースであり、コミュニティによる貢献が可能です。これは、クローズドソースで Apple によって維持されている Xcode のデフォルトの統合とは対照的です。

外部依存関係を追加するには、`Tuist/` の下またはプロジェクトのルートに `Package.swift` を作成する必要があります。

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
> コンパイラディレクティブで囲まれた `PackageSettings` インスタンスを使用すると、パッケージの統合方法を構成できます。例えば、上記の例ではパッケージに使用されるデフォルトの製品タイプを上書きするために使用されています。通常は不要です。また、`expectedSignatures` を使用して SwiftPM バイナリターゲットの期待される署名を構成することもできます。


### バイナリターゲットの署名

ローカルまたはリモートの Swift パッケージがバイナリ XCFramework ターゲットを公開する場合、`PackageSettings.expectedSignatures` を使用して期待される署名を構成できます。

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
> プロジェクトが標準の `Debug` と `Release` 以外の独自のビルド構成を使用している場合は、`baseSettings` を使用して `PackageSettings` でそれらを指定する必要があります。外部依存関係は正しくビルドするためにプロジェクトの構成を知る必要があります。例:
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
> 詳細については [#8345](https://github.com/tuist/tuist/issues/8345) を参照してください。

`Package.swift` ファイルは外部依存関係を宣言するためのインターフェースにすぎません。そのため、パッケージ内にターゲットや製品を定義しません。依存関係の定義が完了したら、次のコマンドを実行して依存関係を解決し、`Tuist/Dependencies` ディレクトリに取得できます。

```bash
tuist install
# Resolving and fetching dependencies. {#resolving-and-fetching-dependencies}
# Installing Swift Package Manager dependencies. {#installing-swift-package-manager-dependencies}
```

お気づきかもしれませんが、私たちは [CocoaPods](https://cocoapods.org) と同様のアプローチを採用しており、依存関係の解決は独立したコマンドとして実行されます。これにより、ユーザーは依存関係をいつ解決・更新するかを制御でき、Xcode でプロジェクトを開いてすぐにコンパイルできる状態にできます。プロジェクトの規模が大きくなるにつれて、Apple の Swift Package Manager 統合が提供する開発者体験は低下していくと私たちは考えています。

プロジェクトのターゲットから、`TargetDependency.external` 依存関係タイプを使用してこれらの依存関係を参照できます。

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
                .external(name: "Alamofire"), // [!code ++]
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
> スキームリストを整理された状態に保つため、Swift Package プロジェクト用に **スキーム** は自動的に作成されません。Xcode の UI から作成することができます。


#### Xcode のデフォルトの統合 {#xcodes-default-integration}

Xcode のデフォルトの統合メカニズムを使用したい場合は、プロジェクトをインスタンス化する際に `packages` リストを渡すことができます。

```swift
let project = Project(name: "MyProject", packages: [
    .remote(url: "https://github.com/krzyzanowskim/CryptoSwift", requirement: .exact("1.8.0"))
])
```

そして、ターゲットからそれらを参照します。

```swift
let target = .target(name: "MyTarget", dependencies: [
    .package(product: "CryptoSwift", type: .runtime)
])
```

Xcode のデフォルトの統合を通じて外部 Swift Package から Swift Macro または Build Tool Plugin を統合する場合、それぞれ `.macro` および `.plugin` タイプで宣言してください。マクロは [Tuist の XcodeProj ベースの統合](#tuists-xcodeprojbased-integration) を通じて利用することもでき、パッケージから消費するのではなく独自に Swift マクロを定義したい場合は、[Swift Macros](#swift-macros) を参照してください。

> [!WARNING]
> **SPM ビルドツールプラグイン**
>
> SPM ビルドツールプラグインは、プロジェクトの依存関係に Tuist の [XcodeProj ベースの統合](#tuists-xcodeprojbased-integration) を使用している場合でも、[Xcode のデフォルトの統合](#xcodes-default-integration) メカニズムを使用して宣言する必要があります。

SPM ビルドツールプラグインは、ターゲットに対して実行すべき具体的なビルドコマンドを発見するために Xcode と SwiftPM が実行する Swift プログラムです。これらのコマンドは、パッケージグラフ、ターゲットファイル、プラグインの作業ディレクトリ、解決されたプラグインツール、およびプラグインによって宣言された出力に依存する可能性があります。一部のプラグインは、同じターゲットビルドの一部となる必要があるファイルも生成します。

Tuist の XcodeProj ベースの統合は、マッピングが静的である場合（ライブラリ、バイナリ、実行可能ファイル、マクロなど）、パッケージ製品をネイティブな Xcode ターゲットにマップします。ビルドツールプラグインには、Xcode の SwiftPM 統合の外側で同等のネイティブな Xcode プロジェクトプリミティブが存在しません。プラグインは最終的に実行可能ファイルを実行できますが、通常のスクリプトビルドフェーズからその実行可能ファイルを呼び出すことは、プラグインを実行することと同義ではありません。Tuist はまずプラグインの Swift コードを評価し、SwiftPM のプラグインコンテキストを再現してコマンドを発見し、宣言された入力と出力をモデル化し、生成されたファイルをターゲットグラフに追加してから、Xcode がビルドを計画する必要があります。

このため、`Tuist/Package.swift` でのみプラグインパッケージを宣言し、`.external(name:)` を通じて利用することはサポートされていません。サポートされている代替手段は、`Project.packages` でパッケージを宣言し、`.package(product:type: .plugin)` を使用してプラグイン製品を利用側のターゲットに追加することです。これにより、プラグインは Swift Package 製品の依存関係として生成された Xcode プロジェクトに接続されたままとなり、Xcode と SwiftPM はネイティブなプラグインコンテキストでそれを実行できます。

トレードオフとして、そのプラグイン統合は Xcode が管理します。

- Xcode はその SwiftPM 統合を通じてプラグインパッケージを解決およびビルドします。
- パッケージは、Tuist が生成した外部ターゲットではなく、Swift Package 参照として生成されたプロジェクトに表示されます。
- Tuist は、静的にマップされたパッケージ製品に対して提供できるようなレベルの制御、検証、キャッシング、および選択的テストの動作をプラグインに提供できません。
- CI およびローカルビルドでは、それらのプラグインパッケージに対して Xcode のパッケージ解決を許可する必要があります。

これらの影響があるため、Tuist プロジェクトで SPM ビルドツールプラグインを使用することは一般的にお勧めしません。可能な場合は、ターゲットで宣言されたビルドフェーズスクリプトを使用するか、Tuist または Xcode を呼び出す前に生成された Xcode プロジェクトの外にあるスクリプトからツールを実行してください。

SPM ビルドツールプラグインの実用的な用途の一つは、Xcode の「Run Build Tool Plug-ins」ビルドフェーズ中にコードリンティングを実行することです。ビルドツールプラグインを含んだ状態で Xcode プロジェクトを生成するには、プロジェクトマニフェストの `packages` 配列でパッケージを宣言し、ターゲットの依存関係にタイプ `.plugin` のパッケージを含めます。

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

### Carthage {#carthage}

[Carthage](https://github.com/carthage/carthage) は `frameworks` または `xcframeworks` を出力するため、`carthage update` を実行して `Carthage/Build` ディレクトリに依存関係を出力し、その後 `.framework` または `.xcframework` ターゲット依存関係タイプを使用してターゲット内の依存関係を宣言できます。これをプロジェクト生成前に実行するスクリプトにまとめることができます。

```bash
#!/usr/bin/env bash

carthage update
tuist generate
```

> [!WARNING]
> **ビルドとテスト**
>
> `xcodebuild build` および `tuist test` を介してプロジェクトをビルドおよびテストする場合も同様に、ビルドまたはテストの前に `carthage update` コマンドを実行して、Carthage で解決された依存関係が存在することを確認する必要があります。


### CocoaPods {#cocoapods}

[CocoaPods](https://cocoapods.org) は、依存関係を統合するために Xcode プロジェクトを必要とします。Tuist を使用してプロジェクトを生成し、その後 `pod install` を実行して、プロジェクトと Pods 依存関係を含むワークスペースを作成することで依存関係を統合できます。これをプロジェクト生成前に実行するスクリプトにまとめることができます。

```bash
#!/usr/bin/env bash

tuist generate
pod install
```

> [!WARNING]
> CocoaPods 依存関係は、プロジェクト生成直後に `xcodebuild` を実行する `build` や `test` などのワークフローとは互換性がありません。また、フィンガープリントロジックが Pods 依存関係を考慮しないため、バイナリキャッシングや選択的テストとも互換性がありません。


## Swift Macros {#swift-macros}

Tuist プロジェクトで [Swift Macros](https://docs.swift.org/swift-book/documentation/the-swift-programming-language/macros/) を扱う際には、2 つの異なるシナリオがあり、自分がどちらに該当するかを明確にすることが重要です。

- **外部 Swift Package で定義されたマクロを利用する。** 両方の統合メカニズムがマクロをサポートしています。[Tuist の XcodeProj ベースの統合](#tuists-xcodeprojbased-integration) では、`Tuist/Package.swift` でパッケージを宣言し、`.external(name:)` で依存関係を設定します。Tuist はマクロ製品をネイティブターゲットにマップします。[Xcode のデフォルトの統合](#xcodes-default-integration) では、`.package(product:type: .macro)` で依存関係を宣言します。ビルドツールプラグインとは異なり、マクロは Xcode のデフォルトの統合に限定されません。
- プロジェクトの一部として**独自のマクロを定義する**こと（例：モノレポ内の共有ライブラリ）。これには `Package.swift` は不要です。Tuist には第一級の `.macro` 製品タイプがあるため、マニフェストでマクロターゲットを直接宣言できます。

### 独自のマクロの定義 {#defining-your-own-macro}

Swift マクロはコンパイラプラグインであり、Swift コンパイラがコンパイル時に読み込んで実行する実行可能ファイルです。Tuist はこれを `.macro` 製品タイプでネイティブにモデル化します。Apple は Xcode プロジェクトで Swift Macro ターゲットタイプを公開していませんが、Tuist はコマンドラインツールターゲットを生成し、マクロを使用するターゲットの依存関係として配線し、Swift コンパイラ設定に `-load-plugin-executable` フラグを注入することでこれを有効にします。すべての接続処理は自動で行われます。

典型的なマクロは 2 つのターゲットに分かれます。マクロを実装する **プラグイン** ターゲット（`product: .macro`）と、マクロの公開インターフェース（`@attached`/`@freestanding` 宣言）を宣言し、`.macro(name:)` を介してプラグインに依存する **ライブラリ** ターゲットです。プラグインはビルドマシン上で実行されるため、そのターゲットはホスト専用（macOS）となります。

マクロの実装は [swift-syntax](https://github.com/swiftlang/swift-syntax) に依存しており、これを `Tuist/Package.swift` で通常の外部依存関係として宣言します。

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

`MyLibrary` をリンクする任意のターゲットは、現在マクロを使用できます。Tuist がプラグインを伝播させるため、コンパイラがそれを読み込むことができます。


## 静的または動的 {#static-or-dynamic}

フレームワークとライブラリは静的または動的にリンクでき、**この選択はアプリサイズや起動時間などに大きな影響を与えます**。その重要性にもかかわらず、この決定はあまり考慮されずに行われることがよくあります。

**一般的な経験則**としては、リリースビルドでは高速な起動時間を実現するために可能な限り多くのものを静的にリンクし、デバッグビルドでは高速な反復時間を実現するために可能な限り多くのものを動的にリンクすることです。

プロジェクトグラフ内で静的リンクと動的リンクの間を変更する際の課題は、Xcode では自明ではないことです。変更がグラフ全体に連鎖的な影響を与えるためです（例：ライブラリはリソースを含めることができず、静的フレームワークは埋め込む必要がありません）。Apple は、Swift Package Manager の静的および動的リンク間の自動決定や [Mergeable Libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries) などのコンパイル時ソリューションでこの問題を解決しようとしました。しかし、これはコンパイルグラフに新しい動的変数を追加し、非決定性の新たな原因を生み出し、コンパイルグラフに依存する Swift Previews などの一部の機能の信頼性を低下させる可能性があります。

幸いなことに、Tuist は静的と動的の間の変更に関連する複雑さを概念的に圧縮し、リンクタイプ間で標準化された <.localized_link href="/guides/features/projects/synthesized-files#bundle-accessors">バンドルアクセサ</.localized_link> を合成します。<.localized_link href="/guides/features/projects/dynamic-configuration">環境変数による動的構成</.localized_link> と組み合わせることで、呼び出し時にリンクタイプを渡し、その値をマニフェストで使用してターゲットの製品タイプを設定できます。

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

Tuist は <.localized_link href="/guides/features/projects/cost-of-convenience">コストがかかるため、暗黙的な構成による利便性をデフォルトとしません</.localized_link>。これは、結果として得られるバイナリが正しいことを保証するために、リンクタイプと、場合によっては必要な追加のビルド設定（[`-ObjC` リンカーフラグ](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184) など）を設定することをユーザーに委ねていることを意味します。したがって、私たちが取る立場は、適切な判断を下すためのリソース（通常はドキュメントの形）を提供することです。

> [!TIP]
> **例：The Composable Architecture**
>
> 多くのプロジェクトが統合している Swift Package は [The Composable Architecture](https://github.com/pointfreeco/swift-composable-architecture) です。詳細は [このセクション](#the-composable-architecture) を参照してください。


### シナリオ {#scenarios}

リンクを完全に静的または動的に設定することが現実的でない、あるいは適切でないシナリオがいくつかあります。以下は、静的リンクと動的リンクを混合する必要がある可能性のあるシナリオの網羅的でないリストです。

- **拡張機能を持つアプリ：** アプリとその拡張機能はコードを共有する必要があるため、それらのターゲットを動的にする必要がある場合があります。そうしないと、アプリと拡張機能の両方で同じコードが重複し、バイナリサイズが増大します。
- **事前コンパイルされた外部依存関係：** 場合によっては、静的または動的な事前コンパイル済みバイナリが提供されます。静的バイナリは、動的にリンクされるように動的フレームワークまたはライブラリでラップできます。

グラフに変更を加える際、Tuist はそれを分析し、「静的副作用」を検出した場合に警告を表示します。この警告は、動的ターゲットを介して静的ターゲットに推移的に依存するターゲットを静的にリンクすることで発生する可能性のある問題を特定するのに役立ちます。これらの副作用は、バイナリサイズの増大や、最悪の場合はランタイムクラッシュとして現れることがよくあります。

## トラブルシューティング {#troubleshooting}

### Objective-C 依存関係 {#objectivec-dependencies}

Objective-C 依存関係を統合する際、[Apple Technical Q&A QA1490](https://developer.apple.com/library/archive/qa/qa1490/_index.html) で詳述されているように、ランタイムクラッシュを回避するために、消費側ターゲットに特定のフラグを含める必要がある場合があります。

ビルドシステムと Tuist にはフラグが必要かどうかを推論する方法がなく、またフラグには望ましくない副作用が生じる可能性があるため、Tuist はこれらのフラグを自動的に適用しません。さらに、Swift Package Manager は `-ObjC` が `.unsafeFlag` を介して含まれるものと見なすため、ほとんどのパッケージは必要に応じてデフォルトのリンク設定の一部としてそれを含めることができません。

Objective-C 依存関係の消費者（または内部 Objective-C ターゲット）は、必要に応じて消費側ターゲットで `OTHER_LDFLAGS` を設定することで `-ObjC` または `-force_load` フラグを適用する必要があります。

### Firebase およびその他の Google ライブラリ {#firebase-other-google-libraries}

Google のオープンソースライブラリは強力ですが、構築方法において非標準的なアーキテクチャや手法を使用することが多いため、Tuist 内での統合が難しい場合があります。

Firebase と Google の他の Apple プラットフォーム向けライブラリを統合するために従う必要がある可能性のあるヒントをいくつか紹介します。

#### `-ObjC` が `OTHER_LDFLAGS` {#ensure-objc-is-added-to-other_ldflags} に追加されていることを確認する

Google のライブラリの多くは Objective-C で記述されています。そのため、消費側ターゲットでは `OTHER_LDFLAGS` ビルド設定に `-ObjC` タグを含める必要があります。これは `.xcconfig` ファイルで設定するか、Tuist マニフェスト内のターゲット設定で手動で指定できます。例:

```swift
Target.target(
    ...
    settings: .settings(
        base: ["OTHER_LDFLAGS": "$(inherited) -ObjC"]
    )
    ...
)
```

詳細については、上記の [Objective-C 依存関係](#objective-c-dependencies) セクションを参照してください。

#### `FBLPromises` の製品タイプを動的フレームワークに設定する {#set-the-product-type-for-fblpromises-to-dynamic-framework}

特定の Google ライブラリは、Google の別のライブラリである `FBLPromises` に依存しています。`FBLPromises` に関連するクラッシュが発生し、次のようなエラーが表示される場合があります。

```
NSInvalidArgumentException. Reason: -[FBLPromise HTTPBody]: unrecognized selector sent to instance 0x600000cb2640.
```

`Package.swift` ファイルで `FBLPromises` の製品タイプを明示的に `.framework` に設定すると、この問題を解決できます。

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

[こちら](https://github.com/pointfreeco/swift-composable-architecture/discussions/1657#discussioncomment-4119184) および [トラブルシューティングセクション](#troubleshooting) で説明されているように、パッケージを静的にリンクする場合（Tuist のデフォルトのリンクタイプです）、`OTHER_LDFLAGS` ビルド設定を `$(inherited) -ObjC` に設定する必要があります。 alternatively、パッケージの製品タイプを動的にオーバーライドすることもできます。静的にリンクする場合、テストおよびアプリターゲットは通常問題なく動作しますが、SwiftUI プレビューが機能しなくなります。これはすべてを動的にリンクすることで解決できます。以下の例では、The Composable Architecture と併用されることが多く、独自の [設定上の落とし穴](https://github.com/pointfreeco/swift-sharing/issues/150#issuecomment-2797107032) がある [Sharing](https://github.com/pointfreeco/swift-sharing) も依存関係として追加されています。

以下の構成ではすべてを動的にリンクするため、アプリおよびテストターゲットと SwiftUI プレビューが正常に動作します。

> [!TIP]
> **静的または動的**
>
> 動的リンクが常に推奨されるわけではありません。詳細については [静的または動的](#static-or-dynamic) セクションを参照してください。この例では、簡略化のため条件なしですべての依存関係を動的にリンクしています。


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
> `import Sharing` の代わりに `import SwiftSharing` を使用する必要があります。


### `.swiftmodule` を介して漏れ出す推移的な静的依存関係 {#transitive-static-dependencies-leaking-through-swiftmodule}

動的フレームワークまたはライブラリが `import StaticSwiftModule` を介して静的なモジュールに依存している場合、そのシンボルは動的フレームワークまたはライブラリの `.swiftmodule` に含まれ、<.localized_link href="https://forums.swift.org/t/compiling-a-dynamic-framework-with-a-statically-linked-library-creates-dependencies-in-swiftmodule-file/22708/1">コンパイル失敗の原因となる</.localized_link>可能性があります。これを防ぐには、<.localized_link href="https://github.com/swiftlang/swift-evolution/blob/main/proposals/0409-access-level-on-imports.md">`internal import`</.localized_link> を使用して静的依存関係をインポートする必要があります。

```swift
internal import StaticModule
```

> [!NOTE]
> インポート時のアクセスレベルは Swift 6 で導入されました。それより古いバージョンの Swift を使用している場合は、代わりに <.localized_link href="https://github.com/apple/swift/blob/main/docs/ReferenceGuides/UnderscoredAttributes.md#_implementationonly">`@_implementationOnly`</.localized_link> を使用する必要があります。


```swift
@_implementationOnly import StaticModule
```
