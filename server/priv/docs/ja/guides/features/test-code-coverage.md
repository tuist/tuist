---
{
  "title": "コードカバレッジ",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "テスト実行から各ファイルとコミットの行カバレッジを追跡します。"
}
---
# コードカバレッジ {#code-coverage}

コードカバレッジは、テストが実行したコードの行を示します。Tuist は各テスト実行のカバレッジをアップロードし、コミットごとの実行をファイル単位およびプロジェクト全体で集約して 1 つの数値にまとめます。これにより、ダッシュボード上でコミットごとに推移を追跡できます。

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
</.home_cards>
