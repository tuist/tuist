---
{
  "title": "モジュラーアーキテクチャ (TMA)",
  "titleTemplate": ":title · プロジェクト · 機能 · ガイド · Tuist",
  "description": "モジュラーアーキテクチャ (TMA) と、それを使用してプロジェクトを構造化する方法について学びます。"
}
---
# モジュラーアーキテクチャ（TMA）{#the-modular-architecture-tma}

TMAは、スケーラビリティを確保し、ビルドとテストのサイクルを最適化し、チーム内で良いプラクティスを維持できるようにアプリケーションを構造化するアーキテクチャアプローチです。その核となる考え方は、明確で簡潔なAPIを使って相互接続された独立した機能を作成することでアプリを構築することです。

これらのガイドラインでは、アーキテクチャの原則を紹介し、アプリケーションの機能を異なるレイヤーで識別・整理する方法を説明します。また、このアーキテクチャを採用する場合に役立つヒント、ツール、アドバイスも紹介します。

> [!NOTE]
> **µFeatures**
>
> このアーキテクチャは以前「µFeatures」として知られていました。その目的と背後にある原則をより適切に反映するため、「The Modular Architecture（TMA）」に名称を変更しました。


## コア原則 {#core-principle}

開発者は、メインアプリとは独立して、UIプレビュー、コード補完、デバッグなどのXcode機能が確実に動作することを保証しながら、機能を**迅速にビルド、テスト、試行**できるべきです。

## モジュールとは {#what-is-a-module}

モジュールはアプリケーションの機能を表し、以下の5つのターゲット（ここでターゲットはXcodeターゲットを指します）の組み合わせです：

- **ソース：** 機能のソースコード（Swift、Objective-C、C++、JavaScriptなど）とそのリソース（画像、フォント、ストーリーボード、xibファイル）を含みます。
- **インターフェース：** 機能のパブリックインターフェースとモデルを含むコンパニオンターゲットです。
- **テスト：** 機能のユニットテストと統合テストを含みます。
- **Testing：** テストやサンプルアプリで使用できるテストデータを提供します。また、後述するように他の機能で使用できるモジュールのクラスやプロトコルのモックも提供します。
- **Example：** 開発者が特定の条件（異なる言語、画面サイズ、設定）で機能を試すために使用できるサンプルアプリを含みます。

ターゲットには命名規則に従うことを推奨しており、TuistのDSLのおかげでプロジェクト内でこれを強制できます。

| ターゲット | 依存関係 | 内容 |
| ---- | ---- | ---- |
| `Feature` | `FeatureInterface` | ソースコードとリソース |
| `FeatureInterface` | - | パブリックインターフェースとモデル |
| `FeatureTests` | `Feature`, `FeatureTesting` | ユニットテストと統合テスト |
| `FeatureTesting` | `FeatureInterface` | テストデータとモック |
| `FeatureExample` | `FeatureTesting`, `Feature` | サンプルアプリ |

> [!TIP]
> **UIプレビュー**
>
> `Feature`はUIプレビューを有効にするためにDevelopment Assetとして`FeatureTesting`を使用できます


> [!WARNING]
> **テストターゲットの代わりにコンパイラディレクティブを使用**
>
> あるいは、`Debug`用にコンパイルする際にコンパイラディレクティブを使用して、`Feature`または`FeatureInterface`ターゲットにテストデータとモックを含めることもできます。グラフは簡素化されますが、アプリの実行には不要なコードまでコンパイルすることになります。


## なぜモジュールなのか {#why-a-module}

### 明確で簡潔なAPI {#clear-and-concise-apis}

すべてのアプリソースコードが同じターゲットにある場合、コード内に暗黙的な依存関係が生じやすく、いわゆるスパゲッティコードになりがちです。すべてが強く結合され、状態が予測不能になることもあり、新しい変更を導入するのが悪夢になります。独立したターゲットで機能を定義する場合、機能実装の一部としてパブリックAPIを設計する必要があります。何を公開すべきか、機能をどのように消費すべきか、何を非公開のままにするかを決定する必要があります。機能の利用者がどのように機能を使用するかをより制御でき、安全なAPIを設計することで良いプラクティスを強制できます。

### 小さなモジュール {#small-modules}

[分割統治](https://en.wikipedia.org/wiki/Divide_and_conquer)。小さなモジュールで作業することで、より集中でき、機能を孤立させてテスト・試行できます。さらに、開発サイクルははるかに高速になります。必要なコンポーネントのみを選択的にコンパイルするためです。アプリ全体のコンパイルは、機能をアプリに統合する必要のある作業の最終段階でのみ必要です。

### 再利用性 {#reusability}

フレームワークやライブラリを使用して、アプリ間や拡張機能などの他の製品間でコードを再利用することが推奨されます。モジュールを構築することで、その再利用は非常に簡単になります。既存のモジュールを組み合わせ、_（必要に応じて）_ プラットフォーム固有のUIレイヤーを追加するだけで、iMessage拡張機能、Today Extension、watchOSアプリケーションを構築できます。

## 依存関係 {#dependencies}

モジュールが別のモジュールに依存する場合、そのインターフェースターゲットに対して依存関係を宣言します。これには二つの利点があります。一つは、あるモジュールの実装が別のモジュールの実装と結合されるのを防ぎます。もう一つは、クリーンビルドが高速化されることです。自機能の実装と、直接および推移的な依存関係のインターフェースのみをコンパイルすればよいからです。このアプローチは、SwiftRockの[Interface Modulesを使用してiOSビルド時間を短縮](https://swiftrocks.com/reducing-ios-build-times-by-using-interface-targets)というアイデアに触発されています。

インターフェースへの依存は、実行時に実装のグラフを構築し、それを必要とするモジュールに依存性注入することをアプリに要求します。TMAはこの方法について特定の立場を取りませんが、ビルド時の間接参照を追加しない依存性注入ソリューションやパターン、あるいはこの目的のために設計されていないプラットフォームAPIを使用しないソリューションの使用を推奨します。

## 製品タイプ {#product-types}

モジュールを構築する際、ターゲットに対して**ライブラリとフレームワーク**、および**静的リンクと動的リンク**から選択できます。Tuistなしでは、依存関係グラフを手動で設定する必要があるため、この決定はやや複雑になります。しかし、Tuist Projectsのおかげで、これはもはや問題ではありません。

開発中は動的ライブラリまたはフレームワークを使用し、<.localized_link href="/guides/features/projects/synthesized-files#bundle-accessors">バンドルアクセサ</.localized_link>を使用して、バンドルアクセスロジックをターゲットのライブラリまたはフレームワークの性質から分離することを推奨します。これはコンパイル時間の短縮と、[SwiftUIプレビュー](https://developer.apple.com/documentation/swiftui/previews-in-xcode)が確実に動作することを保証するために重要です。そして、リリースビルドではアプリの起動を高速化するために静的ライブラリまたはフレームワークを使用します。<.localized_link href="/guides/features/projects/dynamic-configuration#configuration-through-environment-variables">動的設定</.localized_link>を活用して、生成時に製品タイプを変更できます：

```bash
# You'll have to read the value of the variable from the manifest {#youll-have-to-read-the-value-of-the-variable-from-the-manifest}
# and use it to change the linking type {#and-use-it-to-change-the-linking-type}
TUIST_PRODUCT_TYPE=static-library tuist generate
```

```swift
// You can place this in your manifest files or helpers
// and use the returned value when instantiating targets.
func productType() -> Product {
    if case let .string(productType) = Environment.productType {
        return productType == "static-library" ? .staticLibrary : .framework
    } else {
        return .framework
    }
}
```


> [!WARNING]
> **マージ可能なライブラリ**
>
> Appleは、静的ライブラリと動的ライブラリの切り替えの手間を軽減するために[マージ可能なライブラリ](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)を導入しました。しかし、これはビルド時の非決定性をもたらし、ビルドの再現性を損ない、最適化を困難にするため、使用は推奨しません。


## コード {#code}

TMAはモジュールのコードアーキテクチャやパターンについて特定の立場を取りません。ただし、経験に基づいたいくつかのヒントを共有します：

- **コンパイラの活用は素晴らしいことです。** コンパイラへの依存が行き過ぎると生産性が低下し、プレビューなどのXcode機能の動作が不安定になる可能性があります。コンパイラを使用して良いプラクティスを強制し、早期にエラーを検出することを推奨しますが、コードの可読性や保守性を損なうほどには行わないでください。
- **Swiftマクロは慎重に使用してください。** 非常に強力ですが、コードの可読性や保守性を低下させる可能性があります。
- **プラットフォームと言語を受け入れ、抽象化しないでください。** 複雑な抽象化レイヤーを作成しようとすると、逆効果になる可能性があります。プラットフォームと言語は、追加の抽象化レイヤーなしでも優れたアプリを構築するのに十分な力を持っています。良いプログラミングおよびデザインパターンを参考にして機能を実装してください。


## リソース {#resources}

- [µFeaturesの構築](https://speakerdeck.com/pepibumur/building-ufeatures)
- [フレームワーク指向プログラミング](https://speakerdeck.com/pepibumur/framework-oriented-programming-mobilization-dot-pl)
- [フレームワークとSwiftへの旅](https://speakerdeck.com/pepibumur/a-journey-into-frameworks-and-swift)
- [iOSでの開発速度を向上させるためのフレームワーク活用 - パート1](https://developers.soundcloud.com/blog/leveraging-frameworks-to-speed-up-our-development-on-ios-part-1)
- [ライブラリ指向プログラミング](https://academy.realm.io/posts/justin-spahr-summers-library-oriented-programming/)
- [モダンなフレームワークの構築](https://developer.apple.com/videos/play/wwdc2014/416/)
- [xcconfigファイルの非公式ガイド](https://pewpewthespells.com/blog/xcconfig_guide.html)
- [静的ライブラリと動的ライブラリ](https://pewpewthespells.com/blog/static_and_dynamic_libraries.html)
