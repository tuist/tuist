---
{
  "title": "テストインサイト",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "Tuist Test Insights を使用して、Xcode、Gradle、Bazel、Elixir、Rust、Once プロジェクト内の不安定なテストや低速なテストを特定します。"
}
---
# テストインサイト {#test-insights}

Test Insights を使って、遅いテストの特定、不安定なテストの追跡、失敗した CI 実行の迅速な把握により、テストスイートの健全性を監視します。現在は Xcode、Gradle、Bazel、Elixir、Rust、Once に対応しています。利用可能な結果と計測値はランナーによって異なります。サポートされているビルドシステムでテストがどのコードを実行しているかを確認するには、<.localized_link href="/guides/features/test-code-coverage">コードカバレッジ</.localized_link>を参照してください。[遅いテスト](https://tuist.dev/solutions/slow-tests)や[不安定なテスト](https://tuist.dev/solutions/flaky-tests)に関するガイダンスについては、ソリューションガイドをご覧ください。

<.home_cards>
  <.home_card
    title="Xcode"
    details="スキームのポストアクションと Tuist CLI を使って Xcode のテスト分析を追跡します。"
    link="/guides/features/test-insights/xcode"
/>
  <.home_card
    title="Gradle"
    details="Tuist Gradle プラグインを使って Gradle のテスト分析を追跡します。"
    link="/guides/features/test-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="tuist bazel test でテストを実行して Bazel のテスト分析を追跡します。"
    link="/guides/features/test-insights/bazel"
/>
  <.home_card
    title="Elixir"
    details="Tuist Hex パッケージを使って Elixir プロジェクトのテストを追跡します。"
    link="/guides/features/test-insights/elixir"
/>
  <.home_card
    title="Rust"
    details="通常のテストコマンドを使って Cargo テストの結果、スイートの実行時間、および doctest を追跡します。"
    link="/guides/features/test-insights/rust"
/>
  <.home_card
    title="Once"
    details="Once のネイティブ統合を通じて、報告されたテストターゲット、スイート、ケース、失敗、再試行回数を追跡します。"
    link="/guides/features/test-insights/once"
/>
</.home_cards>
