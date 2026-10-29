---
{
  "title": "Elixir テストシャーディング",
  "titleTemplate": ":title · テストシャーディング · 機能 · ガイド · Tuist",
  "description": "Tuist Test Sharding を使用して、Elixir プロジェクトのテストを複数の CI ランナーに分散します。"
}
---
# Elixir テストのシャーディング {#elixir-test-sharding}

Tuist Hex パッケージには、Elixir プロジェクトのテストをシャーディングするための組み込みサポートが含まれています。Tuist サーバーを使用して、過去のタイミングデータに基づいてバランスの取れたシャードプランを作成し、プロジェクトを一度コンパイルすることで、すべてのランナーがすぐにテストの実行に移れるようにします。

> [!IMPORTANT] REQUIREMENTS
> - CI シャードジョブを設定する前に、<.localized_link href="/guides/get-started/elixir-project">共有 Elixir セットアップ</.localized_link>を完了してください

## 仕組み {#how-it-works}

テストのシャーディングは、2段階のワークフローに従います：

1. **ビルドフェーズ：** Tuist はテスト用にプロジェクトをコンパイルし、テストファイルを列挙して、サーバー上で**シャードプラン**を作成します。サーバーは過去30日間のテストタイミングデータを使用して、各シャードの実行時間がほぼ同じになるようにテストを分散させます。ビルドフェーズではビルドをアップロードし、CI システムが並列ランナーを生成するために使用する**シャードマトリックス**を出力します。
2. **テストフェーズ：** 各 CI ランナーは**シャードインデックス**を受け取り、ビルドをダウンロードして、そのシャードに割り当てられたテストのみを実行します。

テストはファイル単位で分散されます。ファイル内のすべてのテストは同じシャードで実行されます。Tuist がまだ認識していないテストには推定値が適用されるため、プロジェクトの最初のプランは後続のプランほどバランスが取れていません。

## ビルドフェーズ {#build-phase}

`tuist.test.build`タスクを使用してテストシャードを準備します：

```sh
MIX_ENV=test mix compile --warnings-as-errors
MIX_ENV=test mix tuist.test.build --shard-max 5
```

シャーディングタスクを呼び出す前に、共有セットアップによってインストールされたエイリアスを通じてコンパイルを行います。クリーンなチェックアウト状態では、Mix が `tuist.test.build` を検出している間に依存関係をコンパイルすることがあり、その時点で Tuist の依存関係キャッシュがそれらを復元する機会がありません。明示的なコンパイルは、シャーディングタスクと同じテスト環境で実行されます。

このタスクは以下を行います：
1. テスト環境でプロジェクトをコンパイルします
2. 過去のタイミングデータを使用して Tuist サーバー上にシャードプランを作成します
3. シャードが再度コンパイルしないようビルドをアップロードします
4. CI システム用のシャードマトリックスを出力します

### ビルドオプション {#build-options}

| オプション | 説明 |
|--------|-------------|
| `--shard-max <N>` | シャードの最大数（デフォルト: 2） |
| `--shard-min <N>` | シャードの最小数 |
| `--shard-total <N>` | 範囲ではなく、正確なシャード数 |
| `--shard-max-duration <MS>` | シャードあたりの目標最大期間（ミリ秒） |
| `--shard-reference <REF>` | シャードがプランを見つけるための名前 |
| `--no-upload` | ビルドをアップロードせずにシャードをプランニングします。各シャードは独自にコンパイルを行います |

その他の引数はすべて `mix compile` に転送されます。

シャード参照は CI 環境変数（`GITHUB_RUN_ID`、`CI_PIPELINE_ID`、`CIRCLE_WORKFLOW_ID`、`BUILDKITE_BUILD_ID`）から自動的に導出されるか、`TUIST_SHARD_REFERENCE` 環境変数を通じて明示的に設定できます。これらのプロバイダー以外では、ビルドフェーズと1回のパイプライン実行のシャードが共有する値に設定する必要があります。GitHub Actions では、参照には実行試行も含まれます。失敗したジョブのみを再実行する場合、シャードジョブで新しい参照を導出するのではなく、元のビルドジョブの参照を渡してください。

## テストフェーズ {#test-phase}

`TUIST_SHARD_INDEX` が設定されている場合、パッケージはサーバーからシャード割り当てを取得し、ビルドをダウンロードして、コンパイルせずに割り当てられたテストファイルのみを実行します。クリーンなランナーでは、タスクを呼び出す前に SDK をブートストラップし、そのパスを読み込んでください：

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.compile tuist_ex --include-children + deps.loadpaths --no-compile --no-deps-check + tuist.test
```

Mix のワーカープロセスで SDK をコンパイルしても、親プロセスでは読み込まれません。明示的な `deps.loadpaths` ステップにより、ビルドをダウンロードする前に残りの依存関係がコンパイルされるのを防ぎます。この単一コマンド形式は、プロジェクトのテスト準備エイリアスを維持します。セットアップコマンドがコンパイルを引き起こす場合は、以下の別個のセットアップ手順を使用してください。

渡すテストファイルやディレクトリによってシャードがさらに絞り込まれます。シャード内にあり、かつ選択範囲内にあるファイルのみが実行されます。テストのないシャードは正常に終了します。

すべてのシャードの結果はダッシュボード上に単一のテスト実行として表示され、**シャード**セクションで各シャードにかかった時間が示されます。

テストの前にセットアップを実行する必要がある場合は、アプリケーションを起動せずにまずビルドをダウンロードしてください：

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.compile tuist_ex --include-children + deps.loadpaths --no-compile --no-deps-check + tuist.test --prepare-only
```

コンパイルを無効にした別プロセスでセットアップを実行します。例えば、Ecto プロジェクトでは以下を使用してデータベースを作成および移行できます：

```sh
MIX_ENV=test mix run --no-start --no-compile --no-deps-check -e 'Mix.Tasks.Ecto.Create.run([]); Mix.Tasks.Ecto.Migrate.run([])'
```

その他のプロジェクト固有の準備はこのフェーズで行ってください。ブートストラップ作業を行う前に、コンパイルエイリアスも `--no-compile` を尊重する必要があります。Mix はリストエイリアスの最後のタスクにのみフラグを転送するため、以前の無条件の `deps.compile` は依然として実行されます。<.localized_link href="/guides/features/cache/elixir-advanced#manual-compile-integration">マニュアルコンパイル統合</.localized_link>のガード付きエイリアスを参照してください。

その後、シャードを実行する前にコンパイルなしで復元された SDK を読み込みます。これにより、ソースがダウンロードされたビルドよりも新しい場合、タスク検出がパス依存関係をコンパイルするのも防止します：

```sh
MIX_ENV=test TUIST_SHARD_INDEX=0 mix do deps.loadpaths --no-compile --no-deps-check + tuist.test --no-download
```

両方のコマンドには同じシャード参照が必要です。`--prepare-only` はアップロードされたビルドを必要とし、準備されたアプリケーション成果物がない場合 `--no-download` は失敗します。`--no-download` はプロジェクトのテスト準備エイリアスを明示的にスキップし（再試行時も含む）、セットアップステップをスキップした際に通知を表示します。通常の実行では、`--no-compile --no-deps-check` を転送してもエイリアスは維持されます。データベース移行を別プロセスで行うことで、移行回帰テストがそれらのモジュール自体を読み込む際のモジュール再定義警告も回避できます。

異なる環境をテストする際は、`--scheme clickhouse-current` や `--scheme clickhouse-floor` のような安定した `--scheme` ラベルを渡してください。異なるラベルの結果は、同じ構成の不安定な再実行として扱われません。

### シャードに必要なもの {#what-the-shards-need}

アップロードされたビルドは `_build/test` ディレクトリです。各シャードランナーには依然として以下が必要です：
- ビルドフェーズと同じチェックアウト
- 同じ Elixir および Erlang/OTP バージョン
- `mix deps.get` からの依存関係ソース

アンブレラプロジェクトのルートからのシャーディングはまだサポートされていません。そのアプリケーションの1つ内で両方のフェーズを実行してください。

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

### 他のプロバイダー {#other-providers}

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
