---
{
  "title": "テストシャーディング",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "Tuist Test Sharding を使用して複数の CI ランナーにテストを分散し、テストスイートの高速化を実現します。"
}
---
# テストシャーディング {#test-sharding}

最新のCIホストはマルチコア環境を提供し、ある程度のテスト並列化を可能にします。しかし、単一のホストでは対応できないシナリオもあります。例えば、同時に実行できるシミュレーターの数に制限がある場合や、テストスイートが単一のマシンの処理能力を超えてしまった場合などです。

そのような場合には、複数のCIランナーにテストを分散させ、結果を統合されたビューに集約するシステムが必要です。これを実現するのがテストシャーディングです。

Tuistは過去のテスト実行時間データを用いて[ビンパッキングアルゴリズム](https://en.wikipedia.org/wiki/Bin_packing_problem)によりシャード間の負荷をインテリジェントに分散し、各ランナーがほぼ同時に完了するように調整します。すべてのシャードからの結果は<.localized_link href="/guides/features/test-insights">Test Insights</.localized_link>で自動的に集約され、すべてのシャードにわたるテストスイートの統合されたビューを提供します。シャーディングは実経過時間を短縮しますが、マシン時間は増加する可能性があります。[Slow tests](https://tuist.dev/solutions/slow-tests)と[CI costs](https://tuist.dev/solutions/ci-costs)では、この2つの要素をどのように权衡すべきかを説明しています。

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
  <.home_card
    title="Struo"
    details="検出されたStruoのテストバッチを、ホスティングプランを使用してCIワーカー間で分散し、結果を統合します。"
    link="/guides/features/test-sharding/struo"
/>
</.home_cards>
