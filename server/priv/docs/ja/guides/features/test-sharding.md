---
{
  "title": "テストシャーディング",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "Tuistのテストシャーディング機能を使用して、複数のCIランナーにテストを分散し、テストスイートの実行時間を短縮します。"
}
---
# テストシャーディング {#test-sharding}

最新のCIホストはマルチコア環境を提供し、ある程度のテスト並列化を可能にします。しかし、単一のホストでは対応できないシナリオが存在します。例えば、同時に実行できるシミュレータの数に制限がある場合や、テストスイートが単一のマシンでは処理しきれないほど大規模になった場合などです。

そのような場合、複数のCIランナーにテストを分散させ、結果を統合されたビューに集約するシステムが必要です。これを実現するのがテストシャーディングです。

Tuistは過去のテスト実行時間データを使用し、[ビンパッキングアルゴリズム](https://en.wikipedia.org/wiki/Bin_packing_problem)を用いてシャード間の負荷をインテリジェントに分散させるため、各ランナーがほぼ同時に終了します。すべてのシャードからの結果は<.localized_link href="/guides/features/test-insights">Test Insights</.localized_link>で自動的に集約され、すべてのシャードにわたるテストスイートの統合されたビューを提供します。

<.home_cards>
  <.home_card
    title="Xcode"
    details="Xcodeテストを並列CIランナー間でシャーディングします。"
    link="/guides/features/test-sharding/xcode"
/>
  <.home_card
    title="生成されたプロジェクト"
    details="Tuistで生成されたプロジェクトのテストを並列CIランナー間でシャーディングします。"
    link="/guides/features/test-sharding/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Gradleテストを並列CIランナー間でシャーディングします。"
    link="/guides/features/test-sharding/gradle"
/>
  <.home_card
    title="Elixir"
    details="Elixirプロジェクトのテストを並列CIランナー間でシャーディングします。"
    link="/guides/features/test-sharding/elixir"
/>
  <.home_card
    title="Rust"
    details="Cargoのテストターゲットを並列CIワーカー間で分散します。"
    link="/guides/features/test-sharding/rust"
/>
</.home_cards>
