---
{
  "title": "ビルドインサイト",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "Tuist Build Insights を使用して、Xcode、Gradle、Bazel、Elixir、Rust、Once プロジェクトのビルドパフォーマンスを追跡します。"
}
---
# ビルドインサイト {#build-insights}

ビルドインサイトを使用して、ローカルおよびCIのビルドパフォーマンスを追跡します。現在、Xcode、Gradle、Bazel、Elixir、Rust、Onceをサポートしています。ビルドの遅延や増大するCIコストを段階的に調査するには、[Slow builds](https://tuist.dev/solutions/slow-builds)および[CI costs](https://tuist.dev/solutions/ci-costs)をご覧ください。

<.home_cards>
  <.home_card
    title="Xcode"
    details="Tuistダッシュボードで、Xcodeスキームのポストアクションの実行時間、ビルド設定、ビルドメタデータを追跡します。"
    link="/guides/features/build-insights/xcode"
/>
  <.home_card
    title="生成されたプロジェクト"
    details="カスタムスキームを持つTuist生成プロジェクトでビルドインサイトを追跡します。"
    link="/guides/features/build-insights/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Tuist Gradleプラグインを使用して、Gradleタスクの実行時間とキャッシュの有効性を追跡します。"
    link="/guides/features/build-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="Build Event Protocolを通じて、Bazelコマンドの実行時間、キャッシュ合計、クリティカルパスの診断情報を追跡します。"
    link="/guides/features/build-insights/bazel"
/>
  <.home_card
    title="Elixir"
    details="Elixirプロジェクトのコンパイル時間、警告、ビルドを遅延させているファイルを追跡します。"
    link="/guides/features/build-insights/elixir"
/>
  <.home_card
    title="Rust"
    details="Tuist CLIを使用して、Cargoコマンドの実行時間、観測されたrustc呼び出し、コンパイラの診断情報を追跡します。"
    link="/guides/features/build-insights/rust"
/>
  <.home_card
    title="Once"
    details="実行をリアルタイムで追跡し、グラフアクション、実行時間、失敗、キャッシュの決定を検査します。"
    link="/guides/features/build-insights/once"
/>
</.home_cards>
