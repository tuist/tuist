---
{
  "title": "Tuistとは？",
  "description": "Tuistは、エンジニアリングチームとそのコーディングエージェント向けビルドプラットフォームです。Xcode、Gradle、Bazel、Elixir、Rustのビルドおよびテストワークフローをサポートします（Struoのサポートはカナリア版）。機能はツールチェーンによって異なり、Rustのコンパイルキャッシュは実験的な機能です。"
}
---

# チームとコーディングエージェントのためのビルドプラットフォーム

**Tuistは、エンジニアリングチームとそのコーディングエージェント向けビルドプラットフォームです。** Xcode、Gradle、Bazel、Elixir、Rustにおけるビルドおよびテストワークフローをサポートしており、Struoのサポートはカナリー版で提供されています。既存のビルドシステムを置き換えるのではなく、それらと連携して動作します。利用可能な機能はツールチェーンによって異なります。Rustプロジェクトでは、doctest、flaky testの検出、実験的なコンパイルキャッシュを含むCargoのビルドおよびテストインサイトを利用できます。Struoは、共有キャッシュ、ビルドおよびテストインサイト、シャーディング、サポート対象アプリケーションのプレビューのためにネイティブに接続します。

お使いのビルドシステムに合わせて<.localized_link href="/guides/get-started">はじめ方のガイド</.localized_link>のいずれかを選択してください。StruoはTuist CLIなしで直接接続します。その他のガイドでは、インストールすべきTuistツールについて説明しています。

<br/>

<.home_cards>
  <.home_card
    title="キャッシュ"
    details="チームとCI間でビルド成果物を共有します。Xcodeのコンパイルキャッシュ、Tuistのモジュールキャッシュ、Gradleのビルドキャッシュ、Bazelのリモートキャッシュ、Elixirの依存関係キャッシュ、Rustの実験的コンパイルキャッシュ、Struoの共有アクションキャッシュに対応しています。"
    supported_for="apple,gradle,bazel,elixir,rust,struo"
    link="/guides/features/cache"
/>
  <.home_card
    title="ビルド・テストインサイト"
    details="Xcode、Gradle、Bazel、Elixir、Rust、Struoプロジェクト全体で、ビルドおよびテストの所要時間、失敗、flakiness、回帰を追跡します。"
    supported_for="apple,gradle,bazel,elixir,rust,struo"
    link="/guides/features/build-insights"
/>
  <.home_card
    title="選択的テスト"
    details="生成されたXcodeプロジェクトにおいて変更のないテストターゲットをスキップし、個々のXCTest/XCUITestの選択に対する早期アクセスのカバレッジ戦略を提供します。"
    link="/guides/features/selective-testing"
/>
  <.home_card
    title="ランナー"
    details="管理されたmacOSおよびLinuxランナー上でCIを実行し、開発者マシンが使用するものと同じキャッシュに近接して利用できます。"
    link="/guides/features/runners"
/>
  <.home_card
    title="プレビュー"
    details="サポート対象のモバイルアプリ、macOSアプリ、macOS/LinuxコマンドラインツールをURL経由で共有します。ビルド、署名、受信側の互換性に関する要件が適用されます。"
    link="/guides/features/previews"
/>
  <.home_card
    title="生成プロジェクト"
    details="SwiftでXcodeプロジェクトを定義し、一貫して生成します。プロジェクトファイルの競合を減らし、モジュールキャッシュを活用できます。"
    link="/guides/features/projects"
/>
  <.home_card
    title="パッケージレジストリ"
    details="Gitリポジトリのクローンではなく、レジストリプロトコルを通じてサポート対象のSwiftパッケージを取得します。"
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
