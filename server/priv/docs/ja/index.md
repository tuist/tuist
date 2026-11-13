---
{
  "title": "Tuistとは？",
  "description": "Tuistは、エンジニアリングチームとそのコーディングエージェント向けのビルドプラットフォームです。Xcode、Gradle、Bazel、Elixir、Rustのビルドおよびテストワークフローをサポートしています。Rustのサポートは現在カナリア版でのみ利用可能です。機能はツールチェーンによって異なり、Rustのコンパイルキャッシュは実験的なものです。"
}
---

# チームとコーディングエージェントのためのビルドプラットフォーム

**Tuistは、エンジニアリングチームとそのコーディングエージェントのためのビルドプラットフォームです。** Xcode、Gradle、Bazel、Elixir、Rustのビルドおよびテストワークフローをサポートしており、Onceのサポートはカナリア版で利用可能です。既存のビルドシステムを置き換えるのではなく、それらと連携して動作します。利用可能な機能はツールチェーンによって異なります。Rustプロジェクトでは、doctest、不安定なテストの検出、実験的なコンパイルキャッシュを含むCargoのビルドおよびテストインサイトを利用できます。Onceは、共有キャッシュ、ビルドおよびテストインサイト、シャーディング、サポートされているアプリケーションプレビューのためにネイティブに接続します。

お使いのビルドシステムに合わせて、<.localized_link href="/guides/get-started">スタートガイド</.localized_link>のいずれかのパスに従ってください。OnceはTuist CLIなしで直接接続します。その他のパスでは、インストールすべきTuistツールについて説明しています。

<br/>

<.home_cards>
  <.home_card
    title="キャッシュ"
    details="チームやCI間でビルド成果物を共有します。Xcodeのコンパイルキャッシュ、Tuistのモジュールキャッシュ、Gradleのビルドキャッシュ、Bazelのリモートキャッシュ、Elixirの依存関係キャッシュ、Rustの実験的なコンパイルキャッシュ、Onceの共有アクションキャッシュに対応しています。"
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/cache"
/>
  <.home_card
    title="ビルド＆テストインサイト"
    details="Xcode、Gradle、Bazel、Elixir、Rust、Onceのプロジェクト全体で、ビルドおよびテストの所要時間、失敗、不安定性、回帰を追跡します。"
    supported_for="apple,gradle,bazel,elixir,rust,once"
    link="/guides/features/build-insights"
/>
  <.home_card
    title="選択的テスト"
    details="生成されたXcodeプロジェクトで変更されていないテストターゲットをスキップし、個別のXCTest/XCUITest選択のための早期アクセスカバレッジ戦略を提供します。"
    link="/guides/features/selective-testing"
/>
  <.home_card
    title="ランナー"
    details="管理されたmacOSおよびLinuxランナーでCIを実行し、開発者マシンが使用するものと同じキャッシュに近い環境を利用します。"
    link="/guides/features/runners"
/>
  <.home_card
    title="プレビュー"
    details="サポートされているモバイルアプリ、macOSアプリ、macOS/LinuxコマンドラインツールをURL経由で共有します。ビルド、署名、受信者の互換性要件が適用されます。"
    link="/guides/features/previews"
/>
  <.home_card
    title="生成されたプロジェクト"
    details="SwiftでXcodeプロジェクトを定義し、一貫して生成します。プロジェクトファイルの競合を減らし、モジュールキャッシュを有効にします。"
    link="/guides/features/projects"
/>
  <.home_card
    title="パッケージレジストリ"
    details="Gitリポジトリをクローンする代わりに、レジストリプロトコルを通じてサポートされているSwiftパッケージを取得します。"
    link="/guides/features/package-registries/swift"
/>
  <.home_card
    title="バンドルサイズ"
    details="サポートされているAppleおよびAndroidのバンドルサイズを経時的に追跡し、サイズ増大の原因を調査します。"
    link="/guides/features/bundle-insights"
/>
</.home_cards>

## 大規模なリリースを行うチームから信頼されています

チームが導入したワークフローと報告された結果については、[顧客事例](https://tuist.dev/customers)をご覧ください。
