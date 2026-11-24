---
{
  "title": "Tuistとは？",
  "description": "Tuistは、エンジニアリングチームとそのコーディングエージェント向けのビルドプラットフォームです。Xcode、Gradle、Bazel、Elixir、Rustにおけるビルドおよびテストワークフローをサポートします（Rustのサポートは現在カナリア版）。機能はツールチェーンによって異なり、Rustのコンパイルキャッシュは実験的なものです。"
}
---

# チームとコーディングエージェントのためのビルドプラットフォーム

**Tuistは、エンジニアリングチームとそのコーディングエージェントのためのビルドプラットフォームです。** Xcode、Gradle、Bazel、Elixir、Rustのビルドおよびテストワークフローをサポートしており、Onceのサポートはcanary版で利用可能です。既存のビルドシステムを置き換えるのではなく、それらと連携して動作します。利用可能な機能はツールチェーンによって異なります。Rustプロジェクトでは、doctest、flaky testの検出、実験的なコンパイルキャッシュを含むCargoのビルドおよびテストインサイトを利用できます。Onceは、共有キャッシュ、ビルドおよびテストインサイト、シャーディング、サポート対象のアプリケーションプレビューのためにネイティブに接続します。

お使いのビルドシステムに合わせて、<.localized_link href="/guides/get-started">はじめ方のガイド</.localized_link>のいずれかに従ってください。OnceはTuist CLIなしで直接接続します。その他のガイドでは、インストールすべきTuistツールについて説明しています。

<br/>

<.home_cards>
  <.home_card
    title="キャッシュ"
    details="チームやCI間でビルド成果物を共有します。Xcodeのコンパイルキャッシュ、Tuistのモジュールキャッシュ、Gradleのビルドキャッシュ、Bazelのリモートキャッシュ、Elixirの依存関係キャッシュ、Rustの実験的なコンパイルキャッシュ、およびOnceの共有アクションキャッシュに対応しています。"
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/cache"
/>
  <.home_card
    title="ビルド＆テストインサイト"
    details="Xcode、Gradle、Bazel、Elixir、Rust、Onceのプロジェクト全体で、ビルドとテストの所要時間、失敗、flakiness、回帰を追跡します。"
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/build-insights"
/>
  <.home_card
    title="選択的テスト"
    details="生成されたXcodeプロジェクトで変更のないテストターゲットをスキップし、個々のXCTest/XCUITestを選択するための早期アクセス対応カバレッジ戦略を提供します。"
    link="/guides/features/selective-testing"
/>
  <.home_card
    title="ランナー"
    details="管理されたmacOSおよびLinuxランナー上でCIを実行し、開発者マシンが使用するものと同じキャッシュに近い環境を利用できます。"
    link="/guides/features/runners"
/>
  <.home_card
    title="プレビュー"
    details="URLを介して、サポート対象のモバイルアプリ、macOSアプリ、およびmacOS/Linuxコマンドラインツールを共有します。ビルド、署名、および受信者の互換性に関する要件が適用されます。"
    link="/guides/features/previews"
/>
  <.home_card
    title="生成されたプロジェクト"
    details="SwiftでXcodeプロジェクトを記述し、一貫して生成します。プロジェクトファイルの競合を減らし、モジュールキャッシュを活用できます。"
    link="/guides/features/projects"
/>
  <.home_card
    title="パッケージレジストリ"
    details="Gitリポジトリをクローンする代わりに、レジストリプロトコルを介してサポート対象のSwiftパッケージを取得します。"
    link="/guides/features/package-registries/swift"
/>
  <.home_card
    title="バンドルサイズ"
    details="サポート対象のAppleおよびAndroidバンドルサイズの推移を追跡し、サイズ増大の原因を調査します。"
    link="/guides/features/bundle-insights"
/>
</.home_cards>

## 大規模なリリースを行うチームから信頼されています

チームが導入したワークフローと報告された結果については、[顧客事例](https://tuist.dev/customers)をご覧ください。
