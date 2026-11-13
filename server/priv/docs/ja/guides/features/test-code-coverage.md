---
{
  "title": "コードカバレッジ",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "テスト実行から各ファイルとコミットの行カバレッジを追跡します。"
}
---
# コードカバレッジ {#code-coverage}

コードカバレッジは、テストがコードのどの行を実行したかを示します。Tuist は各テスト実行のカバレッジをアップロードし、コミットごとの実行結果をファイル単位およびプロジェクト全体で集約して 1 つの数値にまとめるため、ダッシュボード上でコミットを追跡しながら確認できます。

<.home_cards>
  <.home_card
    title="Xcode"
    details="tuist xcodebuild test でテストした Xcode プロジェクトのコードカバレッジをアップロードします。"
    link="/guides/features/test-code-coverage/xcode"
/>
  <.home_card
    title="生成されたプロジェクト"
    details="tuist test、バイナリキャッシュ、選択的テストを使用して、Tuist が生成したプロジェクトのコードカバレッジを測定します。"
    link="/guides/features/test-code-coverage/generated-xcode-project"
/>
  <.home_card
    title="Elixir"
    details="mix test --cover でテストした Elixir プロジェクトの行カバレッジをアップロードします。"
    link="/guides/features/test-code-coverage/elixir"
/>
  <.home_card
    title="Rust"
    details="cargo test でテストした Rust プロジェクトの行カバレッジをアップロードします。"
    link="/guides/features/test-code-coverage/rust"
/>
</.home_cards>
