---
{
  "title": "ビルドインサイト",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "Tuist Build Insights で、Xcode、Gradle、Bazel、Elixir、Rust プロジェクトのビルドパフォーマンスを追跡します。"
}
---
# ビルドインサイト {#build-insights}

Build Insights を使用して、ローカルおよび CI ビルドのパフォーマンスを追跡します。現在、Xcode、Gradle、Bazel、Elixir、Rust に対応しています。

<.home_cards>
  <.home_card
    title="Xcode"
    details="Tuist ダッシュボードで Xcode スキームのポストアクションの実行時間、ビルド設定、ビルドメタデータを追跡します。"
    link="/guides/features/build-insights/xcode"
/>
  <.home_card
    title="生成されたプロジェクト"
    details="カスタムスキーマを使用して、Tuist で生成されたプロジェクトのビルドインサイトを追跡します。"
    link="/guides/features/build-insights/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Tuist Gradle プラグインを使用して、Gradle タスクの実行時間とキャッシュの有効性を追跡します。"
    link="/guides/features/build-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="Build Event Protocol を介して、Bazel コマンドの実行時間、キャッシュ合計、クリティカルパスの診断情報を追跡します。"
    link="/guides/features/build-insights/bazel"
/>
  <.home_card
    title="Elixir"
    details="Elixir プロジェクトのコンパイル時間、警告、ビルドを遅延させているファイルを追跡します。"
    link="/guides/features/build-insights/elixir"
/>
  <.home_card
    title="Rust"
    details="Tuist CLI を使用して、Cargo コマンドの実行時間、観測された rustc の呼び出し、コンパイラの診断情報を追跡します。"
    link="/guides/features/build-insights/rust"
/>
</.home_cards>
