---
{
  "title": "テストインサイト",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "Tuist Test Insights を使用して、Xcode、Gradle、Bazel、Elixir、Rust、Once プロジェクト内の不安定なテストや低速なテストを特定します。"
}
---
# テストインサイト {#test-insights}

Test Insights を使用して、遅いテストの特定、不安定なテストの追跡、失敗した CI 実行の迅速な理解により、テストスイートの健全性を監視します。現在、Xcode、Gradle、Bazel、Elixir、Rust、Once をサポートしています。利用可能な結果とタイミングはランナーによって異なります。サポートされているビルドシステムでテストがどのコードを実行するかを追跡するには、<.localized_link href="/guides/features/test-code-coverage">コードカバレッジ</.localized_link>を参照してください。[遅いテスト](https://tuist.dev/solutions/slow-tests)および[不安定なテスト](https://tuist.dev/solutions/flaky-tests)に関するガイダンスについては、ソリューションガイドを参照してください。

<.home_cards>
  <.home_card
    title="Xcode"
    details="スキームのポストアクションと Tuist CLI を使用して Xcode テストの分析を追跡します。"
    link="/guides/features/test-insights/xcode"
/>
  <.home_card
    title="Gradle"
    details="Tuist Gradle プラグインを使用して Gradle テストの分析を追跡します。"
    link="/guides/features/test-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="tuist bazel test を介してテストを実行することで Bazel テストの分析を追跡します。"
    link="/guides/features/test-insights/bazel"
/>
  <.home_card
    title="Elixir"
    details="Tuist Hex パッケージを使用して Elixir プロジェクトのテストを追跡します。"
    link="/guides/features/test-insights/elixir"
/>
  <.home_card
    title="Rust"
    details="通常のテストコマンドを使用して Cargo テストの結果、スイートの実行時間、および doctests を追跡します。"
    link="/guides/features/test-insights/rust"
/>
  <.home_card
    title="Once"
    details="Once のネイティブ統合を介して、報告されたテストターゲット、スイート、ケース、失敗、および再試行回数を追跡します。"
    link="/guides/features/test-insights/once"
/>
</.home_cards>
