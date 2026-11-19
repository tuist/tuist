---
{
  "title": "モジュラーアーキテクチャ（TMA）",
  "titleTemplate": ":title · プロジェクト · 機能 · ガイド · Tuist",
  "description": "モジュラーアーキテクチャ（TMA）と、それを用いたプロジェクトの構造化方法について学びます。"
}
---
# モジュラーアーキテクチャ（TMA）{#the-modular-architecture-tma}

TMA は、スケーラビリティを実現し、ビルドとテストのサイクルを最適化し、チーム内で適切なプラクティスを確立するためにアプリケーションを構造化するアーキテクチャアプローチです。その核となる考え方は、明確で簡潔な API で相互接続された独立した機能を作成することでアプリを構築することです。

これらのガイドラインではアーキテクチャの原則を紹介し、アプリケーションの機能を異なるレイヤーで識別・整理する方法を示します。また、このアーキテクチャを採用する場合に役立つヒント、ツール、アドバイスも紹介します。

> [!NOTE]
> **µFeatures**
>
> このアーキテクチャは以前 µFeatures と呼ばれていました。その目的と背後にある原則をより適切に反映するため、The Modular Architecture（TMA）に名称を変更しました。


## コア原則 {#core-principle}

開発者は、UI プレビュー、コード補完、デバッグなどの Xcode 機能が確実に動作することを保証しながら、メインアプリとは独立して自分の機能を迅速に**ビルド、テスト、試行**できるべきです。

## モジュールとは {#what-is-a-module}

モジュールはアプリケーションの機能を表し、以下の 5 つのターゲットの組み合わせです（ここで「ターゲット」は Xcode ターゲットを指します）。

- **ソース:** 機能のソースコード（Swift、Objective-C、C++、JavaScript...）とそのリソース（画像、フォント、ストーリーボード、xib）を含みます。
- **インターフェース:** 機能のパブリックインターフェースとモデルを含むコンパニオンターゲットです。
- **テスト:** 機能のユニットテストおよび統合テストを含みます。
- **Testing:** テストやサンプルアプリで使用できるテストデータを提供します。また、後述するように他の機能で使用できるモジュールのクラスやプロトコルのモックも提供します。
- **Example:** 開発者が特定の条件（異なる言語、画面サイズ、設定など）で機能を試すために使用できるサンプルアプリを含みます。

ターゲットには命名規則に従うことを推奨しており、Tuist の DSL を活用すればプロジェクト内でこれを強制できます。

| ターゲット | 依存関係 | 内容 |
| ---- | ---- | ---- |
| `Feature` | `FeatureInterface` | ソースコードとリソース |
| `FeatureInterface` | - | パブリックインターフェースとモデル |
| `FeatureTests` | `Feature`, `FeatureTesting` | ユニットテストおよび統合テスト |
| `FeatureTesting` | `FeatureInterface` | テストデータとモック |
| `FeatureExample` | `FeatureTesting`, `Feature` | サンプルアプリ |

> [!TIP]
> **UI プレビュー**
>
> `Feature` は UI プレビューを有効にするため、`FeatureTesting` を Development Asset として使用できます


> [!WARNING]
> **テストターゲットの代わりにコンパイラディレクティブを使用する**
>
> 別の方法として、`Debug` 向けにコンパイルする際にコンパイラディレクティブを使用して、`Feature` または `FeatureInterface` ターゲットにテストデータやモックを含めることができます。グラフは簡素化されますが、アプリの実行には不要なコードまでコンパイルすることになります。


## なぜモジュールなのか {#why-a-module}

### 明確で簡潔な API {#clear-and-concise-apis}

すべてのアプリソースコードが同じターゲットにある場合、コード内に暗黙的な依存関係が生じやすく、いわゆるスパゲッティコードになりがちです。すべてが強く結合され、状態が予測不可能になることもあり、新しい変更を導入するのが困難になります。独立したターゲットで機能を定義する場合、機能の実装の一環としてパブリック API を設計する必要があります。何を公開すべきか、機能をどのように利用してもらうか、何を非公開にするかを決定します。機能の利用者にどのように機能を使ってほしいかをより制御でき、安全な API を設計することで適切なプラクティスを強制できます。

### 小さなモジュール {#small-modules}

[分割統治](https://en.wikipedia.org/wiki/Divide_and_conquer)。小さなモジュールで作業することで、焦点を絞り、機能を孤立させてテスト・試行できます。さらに、機能の動作に必要なコンポーネントのみを選択的にコンパイルするため、開発サイクルが大幅に高速化します。アプリ全体のコンパイルが必要なのは、機能をアプリに統合する必要がある作業の最終段階のみです。

### 再利用性 {#reusability}

フレームワークやライブラリを使用して、アプリ間や拡張機能などの他の製品間でコードを再利用することが推奨されます。モジュールを構築することで、その再利用は非常に簡単になります。既存のモジュールを組み合わせ、_（必要に応じて）_ プラットフォーム固有の UI レイヤーを追加するだけで、iMessage 拡張機能、Today Extension、または watchOS アプリケーションを構築できます。

## 依存関係 {#dependencies}

あるモジュールが別のモジュールに依存する場合、そのインターフェースターゲットに対して依存関係を宣言します。これには二つの利点があります。一つは、あるモジュールの実装が別のモジュールの実装と結合されるのを防ぎます。もう一つは、クリーンビルドが高速化することです。これは、自機能の実装と、直接および推移的な依存関係のインターフェースのみをコンパイルすればよいためです。このアプローチは、SwiftRock の[Interface Modules を使用して iOS ビルド時間を短縮する](https://swiftrocks.com/reducing-ios-build-times-by-using-interface-targets)というアイデアに触発されています。

インターフェースへの依存は、アプリが実行時に実装のグラフを構築し、それを必要とするモジュールに依存注入することを要求します。TMA はその方法について特定の立場を取りませんが、ビルド時間の間接性を追加しない依存注入ソリューションやパターン、あるいはこの目的のために設計されていないプラットフォーム API を使用しないソリューションの使用を推奨します。

## プロダクトタイプ {#product-types}

モジュールを構築する際、ターゲットに対して**ライブラリとフレームワーク**、および**静的リンクと動的リンク**から選択できます。Tuist なしでは、依存関係グラフを手動で設定する必要があるため、この決定は少し複雑になります。しかし、Tuist Projects のおかげで、これはもはや問題ではありません。

開発中は動的ライブラリまたはフレームワークを使用し、<.localized_link href="/guides/features/projects/synthesized-files#bundle-accessors">バンドルアクセサ</.localized_link>を活用して、ターゲットがライブラリかフレームワークかという性質からバンドルアクセスロジックを分離することを推奨します。これはコンパイル時間の高速化と、[SwiftUI プレビュー](https://developer.apple.com/documentation/swiftui/previews-in-xcode)が確実に動作することを保証するために重要です。そして、リリースビルドではアプリの起動を高速化するため、静的ライブラリまたはフレームワークを使用します。<.localized_link href="/guides/features/projects/dynamic-configuration#configuration-through-environment-variables">動的構成</.localized_link>を活用して、生成時にプロダクトタイプを変更できます。

```bash
# You'll have to read the value of the variable from the manifest
# and use it to change the linking type
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
> Apple は、静的ライブラリと動的ライブラリの切り替えの手間を軽減するために[マージ可能なライブラリ](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)を導入しました。しかし、これはビルド時の非決定性をもたらし、ビルドの再現性を損ない最適化を難しくするため、使用は推奨しません。


## コード {#code}

TMA はモジュールのコードアーキテクチャやパターンについて特定の立場を取りません。ただし、経験に基づいたいくつかのヒントを紹介します。

- **コンパイラの活用は素晴らしい。** コンパイラに過度に依存すると生産性が低下し、プレビューなどの Xcode 機能が不安定になる可能性があります。コンパイラを使用して優れたプラクティスを強制し、早期にエラーを検出することを推奨しますが、コードの可読性と保守性を損なうほどではありません。
- **Swift マクロは控えめに使用する。** 非常に強力ですが、コードの可読性と保守性を低下させる可能性があります。
- **プラットフォームと言語を受け入れ、抽象化しない。** 複雑な抽象化レイヤーを作成しようとすると、逆効果になる可能性があります。プラットフォームと言語は、追加の抽象化レイヤーなしで優れたアプリを構築するのに十分な強力さを持っています。機能の構築には、優れたプログラミングおよびデザインパターンを参考にしてください。


## リソース {#resources}

- [µFeatures の構築](https://speakerdeck.com/pepibumur/building-ufeatures)
- [フレームワーク指向プログラミング](https://speakerdeck.com/pepibumur/framework-oriented-programming-mobilization-dot-pl)
- [フレームワークと Swift への旅](https://speakerdeck.com/pepibumur/a-journey-into-frameworks-and-swift)
- [iOS での開発を加速するためのフレームワーク活用 - パート 1](https://developers.soundcloud.com/blog/leveraging-frameworks-to-speed-up-our-development-on-ios-part-1)
- [ライブラリ指向プログラミング](https://academy.realm.io/posts/justin-spahr-summers-library-oriented-programming/)
- [モダンなフレームワークの構築](https://developer.apple.com/videos/play/wwdc2014/416/)
- [xcconfig ファイルの非公式ガイド](https://pewpewthespells.com/blog/xcconfig_guide.html)
- [静的ライブラリと動的ライブラリ](https://pewpewthespells.com/blog/static_and_dynamic_libraries.html)
