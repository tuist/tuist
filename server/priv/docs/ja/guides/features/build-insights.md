---
{
  "title": "ビルドインサイト",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "Tuist Build Insights を使用して、Xcode、Gradle、Bazel、Elixir、Rust、Once プロジェクトのビルドパフォーマンスを追跡します。"
}
---
# ビルドインサイト {#build-insights}

ビルドインサイトを使用して、ローカルおよびCIでのビルドパフォーマンスを追跡します。現在、Xcode、Gradle、Bazel、Elixir、Rust、Onceをサポートしています。

<.home_cards>
  <.home_card
    title="Xcode"
    details="Tuistダッシュボードで、Xcodeスキームのポストアクションのタイミング、ビルド設定、ビルドメタデータを追跡します。"
    link="/guides/features/build-insights/xcode"
/>
  <.home_card
    title="生成されたプロジェクト"
    details="カスタムスキームを使用したTuist生成プロジェクトでビルドインサイトを追跡します。"
    link="/guides/features/build-insights/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Tuist Gradleプラグインを使用して、Gradleタスクのタイミングとキャッシュの有効性を追跡します。"
    link="/guides/features/build-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="Build Event Protocolを通じて、Bazelコマンドの実行時間、キャッシュの合計、クリティカルパスの診断情報を追跡します。"
    link="/guides/features/build-insights/bazel"
/>
  <.home_card
    title="Elixir"
    details="Elixirプロジェクトのコンパイル時間、警告、ビルドを遅延させているファイルを追跡します。"
    link="/guides/features/build-insights/elixir"
/>
  <.home_card
    title="Rust"
    details="Tuist CLIを使用して、Cargoコマンドの実行時間、観測されたrustcの呼び出し、コンパイラの診断情報を追跡します。"
    link="/guides/features/build-insights/rust"
/>
  <.home_card
    title="Once"
    details="実行をリアルタイムで追跡し、グラフアクション、実行時間、失敗、キャッシュの決定事項を検査します。"
    link="/guides/features/build-insights/once"
/>
</.home_cards>
