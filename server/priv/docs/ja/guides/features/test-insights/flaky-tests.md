---
{
  "title": "Flaky Tests",
  "titleTemplate": ":title · Test Insights · Features · Guides · Tuist",
  "description": "Automatically detect and track flaky tests in your CI pipelines."
}
---
# 不安定なテスト {#flaky-tests}

不安定なテストとは、同じコードで複数回実行した際に異なる結果（合格または不合格）を返すテストのことです。これらはテストスイートへの信頼を損ない、誤った失敗の調査に開発者の時間を浪費させます。Tuist は不安定なテストを自動的に検出し、経時的な追跡を支援します。

<.home_cards>
  <.home_card
    title="Xcode"
    details="tuist xcodebuild test を使用して、Xcode プロジェクト内の不安定なテストを検出、管理、隔離します。"
    link="/guides/features/test-insights/flaky-tests/xcode"
/>
  <.home_card
    title="生成されたプロジェクト"
    details="tuist test を使用して、Tuist が生成したプロジェクト内の不安定なテストを検出、管理、隔離します。"
    link="/guides/features/test-insights/flaky-tests/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Gradle プロジェクト内の不安定なテストを検出し、管理します。"
    link="/guides/features/test-insights/flaky-tests/gradle"
/>
  <.home_card
    title="Bazel"
    details="tuist bazel test を使用して、不安定な Bazel テストケースを検出、ミュート、スキップします。"
    link="/guides/features/test-insights/flaky-tests/bazel"
/>
  <.home_card
    title="Elixir"
    details="テストの再試行機能を使用して、Elixir プロジェクト内の不安定なテストを検出し、管理します。"
    link="/guides/features/test-insights/flaky-tests/elixir"
/>
  <.home_card
    title="Rust"
    details="CI 実行全体の結果を使用して、不安定な Cargo テストを検出し、調査します。"
    link="/guides/features/test-insights/flaky-tests/rust"
/>
</.home_cards>
