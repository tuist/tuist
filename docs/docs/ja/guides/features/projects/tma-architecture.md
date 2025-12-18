---
{
  "title": "The Modular Architecture (TMA)",
  "titleTemplate": ":title · Projects · Features · Guides · Tuist",
  "description": "Learn about The Modular Architecture (TMA) and how to structure your projects using it."
}
---
# モジュラー・アーキテクチャ（TMA）{#the-modular-architecture-tma}。

TMAは、スケーラビリティを可能にし、ビルドとテストのサイクルを最適化し、チーム内のグッドプラクティスを保証するために、Apple
OSアプリケーションを構造化するアーキテクチャアプローチです。その中核となる考え方は、明確で簡潔なAPIを使用して相互接続された独立した機能を構築することで、アプリケーションを構築することです。

このガイドラインでは、アーキテクチャの原則を紹介し、アプリケーションの機能を特定し、さまざまなレイヤーに整理するのに役立ちます。また、このアーキテクチャを使うことを決めた場合のヒントやツール、アドバイスも紹介します。

::情報 μFEATURES
<!-- -->
このアーキテクチャは、以前はμFeaturesとして知られていました。私たちは、その目的と背後にある原則をよりよく反映させるため、これをモジュラー・アーキテクチャー（TMA）と改名しました。
<!-- -->
:::

## コア・プリンシプル{#core-principle}。

開発者は、**、ビルド、テスト、**
、メインアプリから独立して、UIプレビュー、コード補完、デバッグのようなXcodeの機能が確実に動作することを保証しながら、それらの機能を高速に試すことができるはずです。

## モジュールとは何か {#what-is-a-module}。

モジュールは、アプリケーションの機能を表し、以下の 5 つのターゲットの組み合わせです（ここで、ターゲットは Xcode のターゲットを指します）：

- **ソース：**
  機能のソースコード（Swift、Objective-C、C++、JavaScript...）とそのリソース（画像、フォント、ストーリーボード、xibs）が含まれています。
- **インターフェイス：** 機能のパブリック・インターフェースとモデルを含むコンパニオン・ターゲット。
- **テスト：** 機能のユニットテストと統合テストが含まれます。
- **テスト：**
  テストやサンプルアプリで使えるテストデータを提供する。また、後で説明するように、モジュール・クラスや他の機能で使用できるプロトコルのモックも提供します。
- **例：** 開発者が特定の条件下（異なる言語、画面サイズ、設定）で機能を試すために使用できるサンプルアプリが含まれています。

TuistのDSLのおかげでプロジェクトで強制できることだが、ターゲットの命名規則に従うことをお勧めする。

| ターゲット        | 依存関係                       | 内容                 |
| ------------ | -------------------------- | ------------------ |
| `特徴`         | `機能インターフェース`               | ソースコードとリソース        |
| `機能インターフェース` | -                          | パブリック・インターフェースとモデル |
| `フィーチャーテスト`  | `フィーチャー`,`フィーチャー・テスト`      | 単体テストと統合テスト        |
| `フィーチャー・テスト` | `機能インターフェース`               | データとモックのテスト        |
| `機能例`        | `FeatureTesting`,`Feature` | アプリ例               |

UI プレビュー
<!-- -->
`Feature` ` FeatureTesting` を開発アセットとして使用し、UIのプレビューが可能。
<!-- -->
:::

テスト・ターゲットの代わりにコンパイラの指示を警告する。
<!-- -->
あるいは、`Debug` 用にコンパイルする際に、`Feature` または`FeatureInterface`
ターゲットにテスト・データとモックを含めるコンパイラ・ディレクティブを使用することもできます。グラフは単純化されますが、アプリの実行には必要のないコードをコンパイルすることになります。
<!-- -->
:::

## なぜモジュールなのか {#why-a-module}

### 明確で簡潔なAPI {#clear-and-concise-apis}。

すべてのアプリのソースコードが同じターゲットにある場合、コードに暗黙の依存関係を構築するのは非常に簡単で、よく知られたスパゲッティ・コードになってしまう。すべてが強く結合され、状態は時に予測不可能になり、新しい変更の導入は悪夢となる。独立したターゲットで機能を定義する場合、機能実装の一部としてパブリックAPIを設計する必要がある。何をパブリックにするか、どのように機能を消費させるか、何をプライベートのままにするかを決める必要がある。私たちは、クライアントがどのようにその機能を使うかをよりコントロールしやすくなり、安全なAPIを設計することで、グッドプラクティスを実施することができる。

### スモール・モジュール {#small-modules}

[分割統治](https://en.wikipedia.org/wiki/Divide_and_conquer)。小さなモジュールで作業することで、より集中することができ、機能を分離してテストしたり試したりすることができる。さらに、機能を動作させるために必要なコンポーネントだけをコンパイルするという、より選択的なコンパイルが可能になるため、開発サイクルははるかに速くなる。アプリ全体のコンパイルが必要になるのは、機能をアプリに統合する必要がある作業の最後の最後だけです。

### 再利用性 {#reusability}

フレームワークやライブラリを使うことで、アプリやエクステンションのような他の製品間でコードを再利用することが奨励されている。モジュールをビルドすることで、それらを再利用するのはとても簡単だ。既存のモジュールを組み合わせ、_
（必要な場合）_
プラットフォーム固有のUIレイヤーを追加するだけで、iMessageエクステンション、Todayエクステンション、watchOSアプリケーションを構築できる。

## 依存関係 {#dependencies}

モジュールが他のモジュールに依存するとき、そのモジュールはインターフェイスのターゲットに対して依存関係を宣言する。この利点は2つある。モジュールの実装が他のモジュールの実装に結合されるのを防ぎ、クリーンビルドをスピードアップします。このアプローチは、SwiftRockの[Reducing
iOS Build Times by using Interface
Modules](https://swiftrocks.com/reducing-ios-build-times-by-using-interface-targets)のアイデアにインスパイアされています。

インターフェースに依存する場合、アプリは実行時に実装のグラフを構築し、それを必要とするモジュールに依存性注入する必要がある。TMAは、この方法には口を出さないが、依存性注入のソリューションやパターン、あるいはビルド時の間接処理を追加しないソリューションや、この目的のために設計されていないプラットフォームAPIを使用するソリューションを使用することを推奨する。

## 製品タイプ {#product-types}

モジュールをビルドするとき、**ライブラリとフレームワーク** 、**スタティック・リンクとダイナミック・リンク**
のどちらかをターゲットに選ぶことができる。Tuistがなければ、依存関係グラフを手動で設定する必要があるため、この決定を行うのは少し複雑です。しかし、Tuist
Projectsのおかげで、これはもはや問題ではない。

バンドルアクセスロジックをターゲットのライブラリやフレームワークの性質から切り離すために<LocalizedLink href="/guides/features/projects/synthesized-files#bundle-accessors">バンドルアクセサ</LocalizedLink>を使用して、開発中に動的なライブラリやフレームワークを使用することをお勧めします。これは高速なコンパイル時間と[SwiftUIプレビュー](https://developer.apple.com/documentation/swiftui/previews-in-xcode)が確実に動作するためのキーです。そして、アプリが高速に起動することを保証するために、リリースビルドのための静的なライブラリまたはフレームワーク。生成時に製品の種類を変更するために<LocalizedLink href="/guides/features/projects/dynamic-configuration#configuration-through-environment-variables">動的設定</LocalizedLink>を活用することができます：

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


:::警告 マージブル・ライブラリー
<!-- -->
Appleは、[mergeable
libraries](https://developer.apple.com/documentation/xcode/configuring-your-project-to-use-mergeable-libraries)を導入することで、スタティック・ライブラリとダイナミック・ライブラリの切り替えの煩雑さを軽減しようとしました。しかし、これはビルド時に非決定性をもたらし、ビルドを再現不可能にし、最適化しにくくするので、私たちはこれを使うことを推奨しません。
<!-- -->
:::

## コード {#code}

TMAは、あなたのモジュールのコード・アーキテクチャやパターンについて意見を述べることはありません。しかし、私たちの経験に基づいたいくつかのヒントを共有したいと思います：

- **コンパイラを活用することは素晴らしいことです。**
  コンパイラを過度に活用することは、非生産的に終わるかもしれませんし、プレビューのようないくつかのXcodeの機能が信頼性なく動作する原因になるかもしれません。私たちは、グッドプラクティスを強制し、エラーを早期に発見するためにコンパイラを使用することを推奨しますが、コードを読みにくくし、保守しにくくするほどではありません。
- **Swiftマクロは控えめに使いましょう。** マクロは非常に強力ですが、コードを読みにくくし、保守しにくくします。
- **プラットフォームと言語を受け入れ、抽象化してはいけない。**
  精巧な抽象化レイヤーを考え出そうとすると、逆効果に終わるかもしれない。プラットフォームと言語は、抽象化レイヤーを追加することなく、優れたアプリを構築するのに十分強力です。優れたプログラミング・パターンやデザイン・パターンを参考にして、機能を構築しよう。

## リソース {#resources}

- [建物μ特徴](https://speakerdeck.com/pepibumur/building-ufeatures)。
- [フレームワーク指向プログラミング](https://speakerdeck.com/pepibumur/framework-oriented-programming-mobilization-dot-pl)。
- [フレームワークとスウィフトへの旅](https://speakerdeck.com/pepibumur/a-journey-into-frameworks-and-swift)。
- [iOSでの開発をスピードアップするフレームワークの活用 -
  前編](https://developers.soundcloud.com/blog/leveraging-frameworks-to-speed-up-our-development-on-ios-part-1)。
- [ライブラリ指向プログラミング](https://academy.realm.io/posts/justin-spahr-summers-library-oriented-programming/)。
- [モダンなフレームワークの構築](https://developer.apple.com/videos/play/wwdc2014/416/)
- [xcconfigファイル非公式ガイド](https://pewpewthespells.com/blog/xcconfig_guide.html)。
- [静的ライブラリと動的ライブラリ](https://pewpewthespells.com/blog/static_and_dynamic_libraries.html)。
