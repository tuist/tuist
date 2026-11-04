---
{
  "title": "テストインサイト",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "Tuist Test Insights を使用して、Xcode、Gradle、Bazel、Elixir、Rust プロジェクト内の不安定なテストや低速なテストを特定します。"
}
---
# テストインサイト {#test-insights}

Test Insights を使って、低速なテストの特定、不安定なテストの追跡、失敗した CI 実行の迅速な把握により、テストスイートの健全性を監視します。現在、Xcode、Gradle、Bazel、Elixir、Rust をサポートしています。テストがどのコードを実行しているかを追跡するには、<.localized_link href="/guides/features/test-code-coverage">コードカバレッジ</.localized_link>をご覧ください。

<.home_cards>
  <.home_card
    title="Xcode"
    details="スキームのポストアクションと Tuist CLI を使用して、Xcode のテスト分析を追跡します。"
    link="/guides/features/test-insights/xcode"
/>
  <.home_card
    title="Gradle"
    details="Tuist Gradle プラグインを使用して、Gradle のテスト分析を追跡します。"
    link="/guides/features/test-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="tuist bazel test を介してテストを実行することで、Bazel のテスト分析を追跡します。"
    link="/guides/features/test-insights/bazel"
/>
  <.home_card
    title="Elixir"
    details="Tuist Hex パッケージを使用して、Elixir プロジェクトのテストを追跡します。"
    link="/guides/features/test-insights/elixir"
/>
  <.home_card
    title="Rust"
    details="通常のテストコマンドを使用して、Cargo テストの結果、スイートの実行時間、および doctest を追跡します。"
    link="/guides/features/test-insights/rust"
/>
</.home_cards>
