---
{
  "title": "ビルドインサイト",
  "titleTemplate": ":title · 機能 · ガイド · Tuist",
  "description": "Tuist Build Insights で、Xcode、Gradle、Bazel、Elixir、Rust、Struo プロジェクトのビルドパフォーマンスを追跡します。"
}
---
# ビルドインサイト {#build-insights}

ビルドインサイトを使用して、ローカルおよび CI のビルドパフォーマンスを追跡します。現在、Xcode、Gradle、Bazel、Elixir、Rust、Struo をサポートしています。ビルドの遅延や増大する CI コストを段階的に調査するには、[Slow builds](https://tuist.dev/solutions/slow-builds) および [CI costs](https://tuist.dev/solutions/ci-costs) を参照してください。

<.home_cards>
  <.home_card
    title="Xcode"
    details="Tuist ダッシュボードで、Xcode スキームのポストアクションのタイミング、ビルド設定、ビルドメタデータを追跡します。"
    link="/guides/features/build-insights/xcode"
/>
  <.home_card
    title="生成されたプロジェクト"
    details="カスタムスキームを使用した Tuist 生成プロジェクトでビルドインサイトを追跡します。"
    link="/guides/features/build-insights/generated-xcode-project"
/>
  <.home_card
    title="Gradle"
    details="Tuist Gradle プラグインを使用して、Gradle タスクのタイミングとキャッシュの有効性を追跡します。"
    link="/guides/features/build-insights/gradle"
/>
  <.home_card
    title="Bazel"
    details="Build Event Protocol を介して、Bazel コマンドの実行時間、キャッシュの合計、クリティカルパスの診断情報を追跡します。"
    link="/guides/features/build-insights/bazel"
/>
  <.home_card
    title="Elixir"
    details="Elixir プロジェクトのコンパイル時間、警告、ビルドを遅延させているファイルを追跡します。"
    link="/guides/features/build-insights/elixir"
/>
  <.home_card
    title="Rust"
    details="Tuist CLI を使用して、Cargo コマンドの実行時間、観測された rustc の呼び出し、コンパイラの診断情報を追跡します。"
    link="/guides/features/build-insights/rust"
/>
  <.home_card
    title="Struo"
    details="実行をリアルタイムで追跡し、グラフのアクション、所要時間、失敗、キャッシュの決定事項を検査します。"
    link="/guides/features/build-insights/struo"
/>
</.home_cards>
