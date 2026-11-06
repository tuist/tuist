---
{
  "title": "不安定なテスト",
  "titleTemplate": ":title · テストインサイト · 機能 · ガイド · Tuist",
  "description": "CIパイプライン内の不安定なテストを自動的に検出・追跡します。"
}
---
# 不安定なテスト {#flaky-tests}

不安定なテストとは、同じコードで複数回実行したときに結果（合格または不合格）が異なるテストです。テストスイートへの信頼を損ない、誤った失敗の調査に開発者の時間を浪費させます。Tuist は不安定なテストを自動的に検出し、経時的に追跡できるよう支援します。

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
    details="Gradle プロジェクト内の不安定なテストを検出および管理します。"
    link="/guides/features/test-insights/flaky-tests/gradle"
/>
  <.home_card
    title="Bazel"
    details="tuist bazel test を使用して、不安定な Bazel テストケースを検出し、ミュートおよびスキップします。"
    link="/guides/features/test-insights/flaky-tests/bazel"
/>
  <.home_card
    title="Elixir"
    details="テスト再試行により、Elixir プロジェクト内の不安定なテストを検出および管理します。"
    link="/guides/features/test-insights/flaky-tests/elixir"
/>
  <.home_card
    title="Rust"
    details="CI 実行全体での結果を使用して、不安定な Cargo テストを検出し、調査します。"
    link="/guides/features/test-insights/flaky-tests/rust"
/>
</.home_cards>
