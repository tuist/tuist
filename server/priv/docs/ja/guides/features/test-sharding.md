---
{
  "title": "テストシャーディング",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "Tuist Test Sharding を使用して、複数の CI ランナーにテストを分散し、テストスイートの高速化を実現します。"
}
---
# テストシャーディング {#test-sharding}

最新のCIホストはマルチコア環境を提供し、ある程度のテスト並列化を可能にします。しかし、同時に実行できるシミュレータの数に制限がある場合や、テストスイートが単一のマシンでは処理しきれない場合など、単一ホストの能力を超える必要があるシナリオがあります。

そのような場合には、複数のCIランナーにテストを分散させ、結果を集約して統合されたビューとして表示するシステムが必要です。これを実現するのがテストシャーディングです。

Tuistは過去のテスト実行時間データを使用し、[ビンパッキングアルゴリズム](https://en.wikipedia.org/wiki/Bin_packing_problem)を用いてシャード間の負荷をインテリジェントに分散させるため、各ランナーはほぼ同時に処理を終了します。すべてのシャードからの結果は<.localized_link href="/guides/features/test-insights">Test Insights</.localized_link>で自動的に集約され、すべてのシャードにわたるテストスイートの統合されたビューを提供します。シャーディングは壁時計時間を短縮しますが、マシンの実行時間は増加する可能性があります。[Slow tests](https://tuist.dev/solutions/slow-tests)および[CI costs](https://tuist.dev/solutions/ci-costs)では、この2つのバランスをどう取るかについて説明しています。

<.home_cards>
  <.home_card
    title="Xcode"
    details="Xcodeテストを並列CIランナー間でシャーディングします。"
    link="/guides/features/test-sharding/xcode"
/>
  <.home_card
    title="Generated projects"
    details="Tuistが生成したプロジェクトのテストを並列CIランナー間でシャーディングします。"
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
  <.home_card
    title="Struo"
    details="検出されたStruoのテストバッチを、ホスティングプランと結果の統合機能を利用してCIワーカー間で分散します。"
    link="/guides/features/test-sharding/struo"
/>
</.home_cards>
