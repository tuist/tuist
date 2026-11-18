---
{
  "title": "Tuistとは？",
  "description": "Tuistは、エンジニアリングチームとそのコーディングエージェント向けのビルドプラットフォームです。Xcode、Gradle、Bazel、Elixir、Rustのビルドおよびテストワークフローをサポートしています。Rustのサポートは現在カナリア版でのみ利用可能です。機能はツールチェーンによって異なり、Rustのコンパイルキャッシュは実験的なものです。"
}
---

# チームとコーディングエージェントのためのビルドプラットフォーム

**Tuistは、エンジニアリングチームとそのコーディングエージェント向けのビルドプラットフォームです。** Xcode、Gradle、Bazel、Elixir、Rustにおけるビルドおよびテストのワークフローをサポートしており、Onceのサポートはカナリア版で提供されています。既存のビルドシステムを置き換えるのではなく、それらと連携して動作します。利用可能な機能はツールチェーンによって異なります。Rustプロジェクトでは、doctest、flaky testの検出、実験的なコンパイルキャッシュを含むCargoのビルドおよびテストのインサイトを利用できます。Onceは、共有キャッシュ、ビルドおよびテストのインサイト、シャーディング、サポートされているアプリケーションのプレビューのためにネイティブに接続します。

お使いのビルドシステムに合わせて、<.localized_link href="/guides/get-started">Getting Startedのパス</.localized_link>のいずれかに従ってください。OnceはTuist CLIなしで直接接続します。その他のパスでは、インストールすべきTuistのツールについて説明しています。

<br/>

<.home_cards>
  <.home_card
    title="キャッシュ"
    details="チーム全体およびCI間でビルド成果物を共有します。Xcodeのコンパイルキャッシュ、Tuistのモジュールキャッシュ、Gradleのビルドキャッシュ、Bazelのリモートキャッシュ、Elixirの依存関係キャッシュ、Rustの実験的なコンパイルキャッシュ、そしてOnceの共有アクションキャッシュに対応しています。"
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/cache"
/>
  <.home_card
    title="ビルド＆テストのインサイト"
    details="Xcode、Gradle、Bazel、Elixir、Rust、およびOnceのプロジェクトにおいて、ビルドとテストの所要時間、失敗、flakiness、回帰を追跡します。"
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/build-insights"
/>
  <.home_card
    title="選択的テスト"
    details="生成されたXcodeプロジェクトの変更の影響を受けたテストのみを実行し、数秒でフィードバックを得られます。"
    link="/guides/features/selective-testing"
/>
  <.home_card
    title="ランナー"
    details="管理されたmacOSおよびLinuxランナー上でCIを実行し、開発者マシンが使用するものと同じキャッシュに近い環境を提供します。"
    link="/guides/features/runners"
/>
  <.home_card
    title="プレビュー"
    details="URLを使ってアプリを即座に共有できます。ストアのレビュー待ちや複雑な設定は不要です。"
    link="/guides/features/previews"
/>
  <.home_card
    title="生成されたプロジェクト"
    details="SwiftでXcodeプロジェクトを定義し、一貫して生成します。マージ競合を解消し、モジュールキャッシュを活用できます。"
    link="/guides/features/projects"
/>
  <.home_card
    title="パッケージレジストリ"
    details="Tuistのキャッシュネットワーク backed なレジストリにより、Swiftパッケージの解決を数分ではなく数秒で行います。"
    link="/guides/features/package-registries/swift"
/>
  <.home_card
    title="バンドルサイズ"
    details="アプリを軽量に保つための分析を行い、ユーザーのダウンロード速度を向上させ、ストアのガイドラインをクリアします。"
    link="/guides/features/bundle-insights"
/>
</.home_cards>

## 大規模なリリースを行うチームから信頼されています

**[Trendyol](https://www.trendyol.com/)、[Etsy](https://www.etsy.com/)、[Bumble](https://bumble.com/)、[Monzo](https://monzo.com/)、[Bending Spoons](https://bendingspoons.com/)、およびその他100社以上の企業のチーム**が、iOSおよびAndroidのコードベース全体でTuistを使用してより迅速にリリースを行っています。
