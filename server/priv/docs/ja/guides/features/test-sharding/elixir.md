---
{
  "title": "Elixir テストシャーディング",
  "titleTemplate": ":title · テストシャーディング · 機能 · ガイド · Tuist",
  "description": "Tuist Test Sharding を使用して、Elixir プロジェクトのテストを複数の CI ランナーに分散します。"
}
---
# Elixir テストのシャーディング {#elixir-test-sharding}

Tuist Hex パッケージには、Elixir プロジェクトのテストをシャーディングするための組み込みサポートが含まれています。Tuist サーバーを使用して過去のタイミングデータに基づいてバランスの取れたシャーディングプランを作成し、プロジェクトを一度コンパイルすることで、各ランナーがすぐにテストを実行できるようにします。

> [!IMPORTANT]
> **要件**
>
> - CI シャードジョブを設定する前に、<.localized_link href="/guides/get-started/elixir-project">共有 Elixir セットアップ</.localized_link>を完了してください

## 仕組み {#how-it-works}

テストのシャーディングは 2 段階のワークフローに従います。

1. **ビルドフェーズ:** Tuist はテスト用にプロジェクトをコンパイルし、テストファイルを列挙して、サーバー上で**シャーディングプラン**を作成します。サーバーは過去 30 日間のテストタイミング履歴データを使用して、各シャードの実行時間が概ね均等になるようにテストを分散します。ビルドフェーズではビルド成果物をアップロードし、CI システムが並列ランナーを生成するために使用する**シャードマトリックス**を出力します。
2. **テストフェーズ:** 各 CI ランナーは**シャードインデックス**を受け取り、ビルド成果物をダウンロードして、そのシャードに割り当てられたテストのみを実行します。

> [!NOTE]
> 登録済みの Tuist Linux ランナーでは、シャードビルドでローカルアーティファクトストレージを使用できます。このようなビルドを利用するすべてのシャードは、同じサイトの登録済みランナーで実行する必要があります。ワークフローを他のランナーに移行する場合は、ローカルストレージを無効にしてビルドを再実行してください。

テストはファイル単位で分散されます。あるファイル内のすべてのテストは同じシャードで実行されます。Tuist がまだ認識していないテストには推定値が適用されるため、プロジェクトの最初のプランは後続のプランほどバランスが取れていません。

## ビルドフェーズ {#build-phase}

`tuist.test.build`タスクを使用してテストシャードを準備します。

```sh
MIX_ENV=test mix compile --warnings-as-errors
MIX_ENV=test mix tuist.test.build --shard-max 5
```

シャーディングタスクを呼び出す前に、共有セットアップによってインストールされたエイリアス経由でコンパイルしてください。クリーンなチェックアウト状態では、Tuist の依存関係キャッシュが復元する機会を得る前に、Mix が`tuist.test.build`を検出しながら依存関係をコンパイルすることがあります。明示的なコンパイルは、シャーディングタスクと同じテスト環境で実行されます。

このタスクは次のことを行います。
1. テスト環境でプロジェクトをコンパイルします
2. 過去のタイミングデータを使用して Tuist サーバー上にシャーディングプランを作成します
3. シャードが再度コンパイルしないようビルド成果物をアップロードします
4. CI システム用のシャードマトリックスを出力します

### ビルドオプション {#build-options}

| オプション | 説明 |
|--------|-------------|
| `--shard-max <N>` | 最大シャード数（デフォルト: 2） |
| `--shard-min <N>` | 最小シャード数 |
| `--shard-total <N>` | 範囲ではなく正確なシャード数 |
| `--shard-max-duration <MS>` | シャードあたりの目標最大時間（ミリ秒） |
| `--shard-reference <REF>` | シャードがプランを検索するための名前 |
| `--no-upload` | ビルド成果物をアップロードせずにシャードを計画します。各シャードは各自でコンパイルします |

その他の引数はすべて`mix compile`に転送されます。

シャード参照は CI 環境変数（`GITHUB_RUN_ID`、`CI_PIPELINE_ID`、`CIRCLE_WORKFLOW_ID`、`BUILDKITE_BUILD_ID`）から自動的に導出されるか、`TUIST_SHARD_REFERENCE`環境変数を通じて明示的に設定できます。これらのプロバイダー以外では、ビルドフェーズと同一パイプライン実行のシャードが共有する値に設定する必要があります。GitHub Actions では、参照には実行試行も含まれます。失敗したジョブのみを再実行する場合、シャードジョブで新しい参照を導出するのではなく、元のビルドジョブの参照を渡してください。

## テストフェーズ {#test-phase}

`TUIST_SHARD_INDEX`が設定されている場合、パッケージはサーバーからシャード割り当てを取得し、ビルド成果物をダウンロードして、コンパイルせずに割り当てられたテストファイルのみを実行します。クリーンなランナーでは、タスクを呼び出す前に SDK をブートストラップし、そのパスを読み込んでください。

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.compile tuist_ex --include-children + deps.loadpaths --no-compile --no-deps-check + tuist.test
```

Mix のワーカープロセスで SDK をコンパイルしても、親プロセスには読み込まれません。明示的な`deps.loadpaths`ステップにより、ビルド成果物をダウンロードする前に残りの依存関係をコンパイルしてしまうタスク検出を防ぎます。この単一コマンド形式は、プロジェクトのテスト準備エイリアスを維持します。セットアップコマンドがコンパイルを引き起こす場合は、以下の別個のセットアップ手順を使用してください。

渡されたテストファイルやディレクトリにより、シャードはさらに絞り込まれます。シャードに含まれ、かつ選択範囲にも含まれるファイルのみが実行されます。テストがないシャードは正常に終了します。

すべてのシャードの結果はダッシュボード上で単一のテスト実行として集約され、**シャード**セクションで各シャードの実行時間が表示されます。

テストの前にセットアップを実行する必要がある場合は、アプリケーションを起動せずにまずビルド成果物をダウンロードしてください。

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.compile tuist_ex --include-children + deps.loadpaths --no-compile --no-deps-check + tuist.test --prepare-only
```

コンパイルを無効にした別プロセスでセットアップを実行します。例えば、Ecto プロジェクトでは以下のようにデータベースを作成およびマイグレーションできます。

```sh
MIX_ENV=test mix run --no-start --no-compile --no-deps-check -e 'Mix.Tasks.Ecto.Create.run([]); Mix.Tasks.Ecto.Migrate.run([])'
```

その他のプロジェクト固有の準備はこのフェーズで行ってください。ブートストラップ作業を行う前に、コンパイルエイリアスも`--no-compile`を尊重する必要があります。Mix はリストエイリアスの最後のタスクにのみフラグを転送するため、それより前の無条件の`deps.compile`は依然として実行されます。<.localized_link href="/guides/features/cache/elixir-advanced#manual-compile-integration">手動コンパイル統合</.localized_link>のガード付きエイリアスを参照してください。

その後、シャードを実行する前に、コンパイルせずに復元された SDK を読み込みます。これにより、ソースがダウンロードされたビルド成果物よりも新しい場合、タスク検出がパス依存関係をコンパイルすることも防ぎます。

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.loadpaths --no-compile --no-deps-check + tuist.test --no-download
```

両方のコマンドは同じシャード参照が必要です。`--prepare-only`はアップロードされたビルド成果物を必要とし、準備されたアプリケーションアーティファクトが存在しない場合、`--no-download`は失敗します。`--no-download`はプロジェクトのテスト準備エイリアスを明示的にスキップし（再試行時も含む）、セットアップステップをスキップした際に通知を表示します。通常の実行では、`--no-compile --no-deps-check`を転送した場合でもエイリアスは保持されます。データベースマイグレーションを別プロセスで行うことで、マイグレーション回帰テストがそれらのモジュール自身を読み込む際のモジュール再定義警告も回避できます。

異なる環境をテストする際は、安定した`--scheme`ラベル（例：`--scheme clickhouse-current`または`--scheme clickhouse-floor`）を渡してください。異なるラベルの結果は、同じ構成の不安定な再実行としては扱われません。

### シャードに必要なもの {#what-the-shards-need}

アップロードされるビルド成果物は `_build/test` ディレクトリです。各シャードランナーには引き続き以下が必要です：
- ビルドフェーズと同じチェックアウト
- 同じ Elixir および Erlang/OTP バージョン
- `mix deps.get` による依存関係のソース

アンブレラプロジェクトのルートからのシャーディングはまだサポートされていません。そのアプリケーションのいずれかの中で両方のフェーズを実行してください。

## 継続的インテグレーション {#continuous-integration}

### GitHub Actions {#github-actions}

GitHub Actions では、ビルドフェーズがシャードインデックスをステップの `matrix` 出力に書き込みます。マトリクス戦略を使用してシャードを並列実行します：

```yaml
name: Tests
on: [pull_request]

env:
  MIX_ENV: test
  TUIST_TOKEN: ${{ secrets.TUIST_TOKEN }}

jobs:
  build:
    name: Build test shards
    runs-on: ubuntu-latest
    outputs:
      matrix: ${{ steps.build.outputs.matrix }}
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '27'
      - run: mix deps.get
      - run: mix compile --warnings-as-errors
      - id: build
        run: mix tuist.test.build --shard-max 5

  test:
    name: "Shard #${{ matrix.shard }}"
    needs: build
    runs-on: ubuntu-latest
    strategy:
      fail-fast: false
      matrix:
        shard: ${{ fromJson(needs.build.outputs.matrix).shard }}
    env:
      TUIST_SHARD_INDEX: ${{ matrix.shard }}
    steps:
      - uses: actions/checkout@v4
      - uses: erlef/setup-beam@v1
        with:
          elixir-version: '1.18'
          otp-version: '27'
      - run: mix deps.get
      - run: mix do deps.compile tuist_ex --include-children + deps.loadpaths --no-compile --no-deps-check + tuist.test --prepare-only
      # Ecto example: keep all project-specific test preparation here.
      # The project's compile alias must honor --no-compile (see above).
      - run: mix run --no-start --no-compile --no-deps-check -e 'Mix.Tasks.Ecto.Create.run([]); Mix.Tasks.Ecto.Migrate.run([])'
      - run: mix do deps.loadpaths --no-compile --no-deps-check + tuist.test --no-download
```

### その他のプロバイダー {#other-providers}

GitHub Actions 以外では、ビルドフェーズがプランを `.tuist-shard-matrix.json` に書き込みます：

```json
{
  "reference": "gitlab-1234",
  "shard_count": 2,
  "shards": [
    {
      "index": 0,
      "test_targets": ["MyApp.AccountsTest", "MyApp.CheckoutTest"],
      "estimated_duration_ms": 41000
    },
    {
      "index": 1,
      "test_targets": ["MyAppWeb.PageControllerTest"],
      "estimated_duration_ms": 39500
    }
  ]
}
```

`shard_count` を使用して並列ジョブを設定し、各ジョブに `0` から `shard_count - 1` までの `TUIST_SHARD_INDEX` を割り当ててください。Tuist が参照を導出しないプロバイダーでは、すべてのジョブに同じ `TUIST_SHARD_REFERENCE` も与えてください。
