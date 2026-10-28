---
{
  "title": "Test Sharding",
  "titleTemplate": ":title · Features · Guides · Tuist",
  "description": "Distribute tests across multiple CI runners to speed up your test suite with Tuist Test Sharding."
}
---
# テストシャーディング {#test-sharding}

最新のCIホストは、ある程度のテスト並列化を可能にするマルチコア環境を提供します。しかし、単一のホストでは対応しきれないシナリオもあります。例えば、同時に実行できるシミュレーターの数に制限がある場合や、テストスイートが単一のマシンのキャパシティを超えてしまった場合などです。

そのような場合には、複数のCIランナーにテストを分散させ、結果を統合ビューに集約するシステムが必要です。これを実現するのがテストシャーディングです。

Tuistは、[ビンパッキングアルゴリズム](https://en.wikipedia.org/wiki/Bin_packing_problem)を使用して過去のテスト実行時間データに基づき、シャード間の負荷をインテリジェントに分散させるため、各ランナーがほぼ同時に完了します。すべてのシャードからの結果は<.localized_link href="/guides/features/test-insights">Test Insights</.localized_link>で自動的に集約され、すべてのシャードにわたるテストスイートの統一されたビューを提供します。

<.home_cards>
  <.home_card
    title="Xcode"
    details="Xcodeのテストを並列CIランナー間でシャーディングします。"
    link="/guides/features/test-sharding/xcode"
/>
  <.home_card
    title="生成されたプロジェクト"
    details="Tuistで生成されたプロジェクトのテストを並列CIランナー間でシャーディングします。"
    link="/guides/features/test-sharding/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Gradleのテストを並列CIランナー間でシャーディングします。"
    link="/guides/features/test-sharding/gradle"
/>
  <.home_card
    title="Elixir"
    details="Elixirプロジェクトのテストを並列CIランナー間でシャーディングします。"
    link="/guides/features/test-sharding/elixir"
/>
  <.home_card
    title="Rust"
    details="通常のCargoテスト実行におけるテストシャーディングの利用可否を確認します。"
    link="/guides/features/test-sharding/rust"
/>
</.home_cards>
